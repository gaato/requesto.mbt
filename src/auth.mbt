///|
/// Credentials for a client's requests, or for one request.
pub(all) enum Auth {
  /// HTTP Basic: `user:password`, UTF-8 and base64-encoded.
  Basic(String, String)
  /// `Authorization: Bearer <token>`.
  Bearer(String)
  /// HTTP Digest (RFC 7616): a 401 with a Digest challenge from the
  /// request's origin is answered once, and the nonce is reused on later
  /// calls to that origin. Redirects to another origin are not answered.
  Digest(String, String)
}

///|
/// The most Digest sessions (origin and credentials) a client keeps; the
/// oldest is forgotten first.
let max_digest_sessions : Int32 = 16

///|
/// Marks a request that Digest credentials answer: the origin it was built
/// for, the user and the password.
let digest_credentials : @mttp_core.AttributeKey[(String, String, String)] = @mttp_core.AttributeKey::new(
  "requesto.digest",
)

///|
/// Puts `auth` on a request: a header for Basic and Bearer, a mark the
/// client's Digest layer reads for Digest.
fn apply_auth(
  req : @mttp.Request,
  auth : Auth,
) -> @mttp.Request raise HTTPError {
  match auth {
    Basic(user, password) => req.basic(user, password)
    Bearer(token) => req.bearer(token)
    Digest(user, password) => {
      let origin = origin_of(req.url)
      {
        ..req,
        attributes: req.attributes.put(
          digest_credentials,
          (origin, user, password),
        ),
      }
    }
  }
}

///|
/// `scheme://host[:port]` of an absolute URL.
fn origin_of(url : String) -> String raise HTTPError {
  let parsed = @mttp_core.Url::parse(url) catch {
    e =>
      raise InvalidRequest(local_error(Invalid, Pool, "bad URL \{url}: \{e}"))
  }
  guard parsed is { scheme: Some(scheme), host: Some(host), .. } else {
    raise InvalidRequest(
      local_error(Invalid, Pool, "Digest needs an absolute URL, not \{url}"),
    )
  }
  match parsed.port {
    Some(port) => "\{scheme}://\{host}:\{port}"
    None => "\{scheme}://\{host}"
  }
}

///|
/// A value in [0, 1) from the platform's random source, for Digest cnonces
/// and multipart boundaries; `None` where the platform has none.
fn random_unit() -> Double? {
  guard @env.rand(7) is Some(bytes) && bytes.length() == 7 else { return None }
  let mut n = 0UL
  for b in bytes {
    n = (n << 8) | b.to_uint64()
  }
  // 53 bits of the 56 drawn, scaled into [0, 1).
  Some((n >> 3).to_double() / 9007199254740992.0)
}

///|
/// The client's Digest layer: requests marked with `digest_credentials` go
/// through mttp_digest's `DigestScheme` for their origin and credentials,
/// the rest straight to the backend underneath. Redirects run outside this
/// layer, so each hop is checked against the origin the request was built
/// for, and a hop to another origin is never answered.
priv struct DigestLayer {
  inner : &@mttp.Backend
  sessions : Map[(String, String, String), @mttp_digest.DigestScheme]
}

///|
fn DigestLayer::new(inner : &@mttp.Backend) -> DigestLayer {
  { inner, sessions: {}, }
}

///|
/// The session for `key`, made on first use; the oldest is dropped when
/// `max_digest_sessions` are held.
fn DigestLayer::session(
  self : DigestLayer,
  key : (String, String, String),
) -> @mttp_digest.DigestScheme raise @mttp.TransportError {
  match self.sessions.get(key) {
    Some(scheme) => scheme
    None => {
      while self.sessions.length() >= max_digest_sessions {
        guard self.sessions.keys().head() is Some(oldest) else { break }
        // Not closed: closing a scheme closes the backend it shares.
        self.sessions.remove(oldest)
      }
      guard random_unit() is Some(_) else {
        raise local_error(
          Invalid,
          Pool,
          "Digest needs a random source for its cnonces, and this platform has none",
        )
      }
      let (origin, user, password) = key
      let scheme = @mttp_digest.DigestScheme::new(
        self.inner,
        user,
        password,
        origin~,
        random=() => random_unit().unwrap_or(0.5),
      )
      self.sessions.set(key, scheme)
      scheme
    }
  }
}

///|
impl @mttp.Backend for DigestLayer with fn send(self, request, options) {
  match request.attributes.get(digest_credentials) {
    None => self.inner.send(request, options)
    Some(key) => self.session(key).send(request, options)
  }
}

///|
impl @mttp.Backend for DigestLayer with fn close(self) {
  self.sessions.clear()
  self.inner.close()
}
