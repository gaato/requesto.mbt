///|
/// The default `User-Agent`, naming this module's version.
let user_agent : String = "requesto/0.3.1"

///|
/// The default bound on a buffered body, after decompression.
let default_max_body_bytes : Int32 = 64 * 1024 * 1024

///|
/// The default number of redirects `follow_redirects` follows, as httpx2's.
let default_max_redirects : Int32 = 20

///|
/// The default time limit of each phase, as httpx2's.
let default_phase_timeout_ms : Int32 = 5000

///|
/// Per-phase time limits in milliseconds, as httpx2's `Timeout`. `None`
/// means no limit for that phase.
pub(all) struct Timeout {
  /// Connecting, TLS included.
  connect : Int32?
  /// The response's head, and each read of its body.
  read : Int32?
  /// Writing the request.
  write : Int32?
  /// Waiting for a free connection.
  pool : Int32?
}

///|
/// `Timeout::new(Some(5000))` limits every phase to 5 s; name a phase to set
/// it apart, as in httpx2's `Timeout(10.0, connect=5.0)`.
pub fn Timeout::new(
  all : Int32?,
  connect~ : Int32? = all,
  read~ : Int32? = all,
  write~ : Int32? = all,
  pool~ : Int32? = all,
) -> Timeout {
  { connect, read, write, pool, }
}

///|
/// Connection pool limits, as httpx2's `Limits`: at most `max_connections`
/// open (`None` for no limit), at most `max_keepalive_connections` idle, each
/// idle one closed after `keepalive_expiry` milliseconds.
pub(all) struct Limits {
  max_connections : Int32?
  max_keepalive_connections : Int32
  keepalive_expiry : Int32
}

///|
/// httpx2's defaults: 100 connections, 20 kept alive, for 5 s.
pub fn Limits::new(
  max_connections~ : Int32? = Some(100),
  max_keepalive_connections~ : Int32 = 20,
  keepalive_expiry~ : Int32 = 5000,
) -> Limits {
  { max_connections, max_keepalive_connections, keepalive_expiry, }
}

///|
/// httpx2's `event_hooks`: functions that see each request before it is
/// sent and each response before it is returned. A hook that raises fails
/// the call. Hooks are plain functions, as on httpx2's sync `Client`, so a
/// lambda can be written without annotations.
pub struct EventHooks {
  request : Array[(@mttp.Request) -> Unit raise HTTPError]
  response : Array[(Response) -> Unit raise HTTPError]
}

///|
/// Hooks run in order: `request` before each send, `response` after it.
pub fn EventHooks::new(
  request~ : Array[(@mttp.Request) -> Unit raise HTTPError] = [],
  response~ : Array[(Response) -> Unit raise HTTPError] = [],
) -> EventHooks {
  { request, response, }
}

///|
/// httpx2's `MockTransport`: a transport that calls a handler instead of the
/// network. The handler has the type of an mttp server handler, so an app
/// served with `@server.serve` can be passed here and called without a
/// socket (what httpx2's `ASGITransport` does).
pub struct MockTransport {
  priv backend : &@mttp.Backend
}

///|
/// A transport that answers every request with `handler`.
pub fn MockTransport::new(handler : @mttp.Handler) -> MockTransport {
  { backend: @client.from_handler(handler), }
}

///|
/// `send` and `close` as methods of `MockTransport`.
pub extend MockTransport with @mttp_core.Backend::{close, send}

///|
/// Calls the handler with the request.
pub impl @mttp.Backend for MockTransport with fn send(self, request, options) {
  self.backend.send(request, options)
}

///|
/// Closes the handler's backend.
pub impl @mttp.Backend for MockTransport with fn close(self) {
  self.backend.close()
}

///|
/// An mttp client plus the defaults requesto adds on top.
pub struct Client {
  priv inner : @mttp.Client
  priv clock : &@rt.Clock
  priv base_url : String
  priv auth : Auth?
  priv params : Array[(String, String)]
  priv follow_redirects : Bool
  priv max_body_bytes : Int32
  priv hooks : EventHooks
}

///|
/// The network backend's settings for a client's options. `getenv` reads the
/// proxy variables when `trust_env` holds and no `proxy` is given.
fn network_config(
  timeout : Timeout,
  limits : Limits,
  proxy : String?,
  trust_env : Bool,
  getenv : (String) -> String?,
) -> @h1client.ClientConfig {
  {
    ..@h1client.ClientConfig::default(),
    pool_timeout_ms: timeout.pool,
    connect_timeout_ms: timeout.connect,
    write_timeout_ms: timeout.write,
    read_timeout_ms: timeout.read,
    max_connections: limits.max_connections,
    max_idle_connections: limits.max_keepalive_connections,
    idle_max_ms: limits.keepalive_expiry,
    proxy: match proxy {
      Some(url) => @h1client.ProxyConfig::fixed(url)
      None if trust_env => @h1client.ProxyConfig::from_env(getenv)
      None => @h1client.ProxyConfig::none()
    },
  }
}

///|
/// httpx2's defaults: redirects not followed, no retries, 5 s per phase,
/// cookies kept, no deadline for the whole call, proxies from the
/// environment. mttp adds one bound httpx2 lacks: buffered bodies are
/// limited to `max_body_bytes` (64 MiB).
///
/// - `total_timeout` (milliseconds) opts in to a deadline for the whole
///   call, redirects and retries included. Without it a stalled connection
///   still fails on its phase timeout; only a slow transfer that keeps
///   making progress runs on, as in httpx2.
/// - `cookies` gives the client a jar of its own; `cookie_jar` shares one
///   the caller made, with `@mttp.CookieJar::new`, between clients.
/// - `retry` takes an `@mttp.RetryPolicy`, such as
///   `RetryPolicy::conservative()`.
/// - `proxy` sends every request through one proxy; otherwise, when
///   `trust_env` holds, `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY` choose.
/// - `trust` is httpx2's `verify`: `System` roots, a `PemFile`, or
///   `Insecure`.
/// - `transport` replaces the network, for a `MockTransport` or any
///   `@mttp.Backend`; `timeout`'s phases, `limits`, `proxy`, `trust_env` and
///   `trust` configure only the network backend and are ignored then.
/// - `clock` and `timer` replace the real ones, for tests on virtual time.
pub fn Client::new(
  base_url? : String,
  headers~ : Array[(String, String)] = [],
  params~ : Array[(String, String)] = [],
  cookies~ : Bool = true,
  cookie_jar? : @mttp.CookieJar,
  auth? : Auth,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
  follow_redirects~ : Bool = false,
  max_redirects~ : Int32 = default_max_redirects,
  retry~ : @mttp.RetryPolicy = @mttp.RetryPolicy::none(),
  max_body_bytes~ : Int32 = default_max_body_bytes,
  total_timeout? : Int32,
  event_hooks~ : EventHooks = EventHooks::new(),
  limits~ : Limits = Limits::new(),
  proxy? : String,
  trust_env~ : Bool = true,
  trust~ : @mttp.Trust = System,
  transport? : &@mttp.Backend,
  clock? : &@rt.Clock,
  timer? : &@rt.Timer,
) -> Client {
  let mut h = @mttp_core.Headers::empty()
  for pair in headers {
    h = h.add(pair.0, pair.1)
  }
  if !h.contains("user-agent") {
    h = h.add("User-Agent", user_agent)
  }
  let clock = clock.unwrap_or_else(@mttp.clock)
  let timer = timer.unwrap_or_else(() => @runtime.ClockTimer::new(clock~))
  let jar = match cookie_jar {
    Some(jar) => Some(jar)
    None if cookies => Some(@mttp.CookieJar::new(clock))
    None => None
  }
  let backend = match transport {
    Some(backend) => backend
    None =>
      @mttp.backend(
        trust~,
        config=network_config(
          timeout, limits, proxy, trust_env, @env.get_env_var,
        ),
      )
  }
  // `@mttp.client` always sets an attempt deadline (30 s) and a total one
  // (120 s), so build the Client directly: httpx2 bounds phases, not calls.
  // The base URL is joined in `build_request`, as httpx2 does, so hooks and
  // built requests see the URL that is sent.
  let inner = @client.Client::new(
    DigestLayer::new(backend),
    clock,
    headers=h,
    max_body_bytes~,
    // A streamed body's reads get the read timeout, as in httpx2.
    read_idle_ms?=timeout.read,
    timer~,
    retry~,
    // Redirects are enabled underneath and turned on per request, so that
    // `follow_redirects=true` on one call works on a client that does not.
    redirect={ ..@mttp.RedirectConfig::default(), max_redirects, },
    cookies?=jar,
    total_ms?=total_timeout,
  )
  {
    inner,
    clock,
    base_url: base_url.unwrap_or(""),
    auth,
    params,
    follow_redirects,
    max_body_bytes,
    hooks: event_hooks,
  }
}

///|
/// The mttp client underneath, for a call requesto does not cover.
pub fn Client::mttp(self : Client) -> @mttp.Client {
  self.inner
}

///|
/// Closes the client's connections.
pub fn Client::close(self : Client) -> Unit {
  self.inner.close()
}

///|
/// A multipart boundary, random where the platform has a random source.
fn multipart_boundary(clock : &@rt.Clock) -> String {
  let seed = match random_unit() {
    Some(r) => (r * 9007199254740992.0).to_uint64()
    None => clock.now_unix_ms().reinterpret_as_uint64()
  }
  "requesto-\{seed.to_string(radix=16)}"
}

///|
/// httpx2's `build_request`: the `@mttp.Request` a call would send, with the
/// client's base URL, query parameters and auth applied. One body argument
/// is used, in this order: `content`, `text`, `files` (with `data` as its
/// text fields), `data` (as a form), `json`. `trace` is called with each
/// `PhaseEvent` of each attempt, redirects and retries included, as httpx2's
/// `trace` extension is.
pub fn Client::build_request(
  self : Client,
  verb : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
) -> @mttp.Request raise HTTPError {
  let full = if self.base_url == "" {
    url
  } else {
    @mttp_core.join_url(self.base_url, url)
  }
  let mut req = @mttp_core.Request::new(@mttp_core.Method::parse(verb), full)
  for pair in self.params {
    req = req.query(pair.0, pair.1)
  }
  for pair in params {
    req = req.query(pair.0, pair.1)
  }
  for pair in headers {
    req = req.header(pair.0, pair.1)
  }
  match (if auth is Some(_) { auth } else { self.auth }) {
    Some(auth) => req = apply_auth(req, auth)
    None => ()
  }
  if trace is Some(trace) {
    req = { ..req, attributes: req.attributes.put(@mttp_core.on_phase, trace), }
  }
  match (content, text, files, data, json) {
    (Some(b), _, _, _, _) => req = req.body_bytes(b)
    (_, Some(s), _, _, _) => req = req.body_text(s)
    (_, _, Some(files), fields, _) => {
      let parts = fields
        .unwrap_or([])
        .map(pair => @multipart.Part::text(pair.0, pair.1))
      parts.append(files)
      req = @multipart.body(req, parts, boundary=multipart_boundary(self.clock)) catch {
        e =>
          raise InvalidRequest(
            local_error(Invalid, Pool, "multipart body: \{@debug.to_string(e)}"),
          )
      }
    }
    (_, _, _, Some(form), _) => req = req.body_form(form)
    (_, _, _, _, Some(j)) => req = req.body_json(j)
    _ => ()
  }
  req
}

///|
/// httpx2's `send`: sends a built request and reads its whole body.
pub async fn Client::send(
  self : Client,
  req : @mttp.Request,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  for hook in self.hooks.request {
    hook(req)
  }
  let started = self.clock.now_unix_ms()
  let reply = lift(() => {
    @mttp.request(req)
    .response(@mttp.as_bytes().any_status())
    .follow_redirects(follow_redirects)
    .send(self.inner)
  })
  let content = match reply.body {
    Ok(bytes) => bytes
    // any_status sends every status through Ok and as_bytes cannot fail to
    // decode; keep whatever bytes an Err carries.
    Err(UnexpectedStatus(_, body~)) | Err(Deserialization(_, body~, ..)) => body
    Err(_) => b""
  }
  let response : Response = {
    status_code: reply.status,
    headers: reply.headers,
    url: reply.attributes.get(@client.final_url).unwrap_or(reply.request.url),
    content,
    request: reply.request,
    history: reply.attributes.get(@client.redirect_history).unwrap_or([]),
    elapsed: self.clock.now_unix_ms() - started,
  }
  for hook in self.hooks.response {
    hook(response)
  }
  response
}

///|
/// Sends one request and reads its whole body, whatever the status. The
/// body arguments are those of `build_request`.
pub async fn Client::request(
  self : Client,
  verb : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  let req = self.build_request(
    verb,
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    auth?,
    trace?,
  )
  self.send(req, follow_redirects~)
}

///|
/// httpx2's `with client.stream(...) as response:`. The response is valid
/// only inside `f` and is closed when `f` returns; errors from `f` come out
/// unchanged. Request hooks run; response hooks do not, since the body is
/// not read.
pub async fn[T] Client::stream(
  self : Client,
  verb : String,
  url : String,
  f : async (StreamResponse) -> T,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> T {
  let req = self.build_request(
    verb,
    url,
    params~,
    headers~,
    content?,
    text?,
    data?,
    files?,
    json?,
    auth?,
    trace?,
  )
  for hook in self.hooks.request {
    hook(req)
  }
  let max_body_bytes = self.max_body_bytes
  let reply = lift_any(() => {
    @mttp.request(req)
    .response(
      @client.as_stream(async fn(head, body) {
        f({
          status_code: head.status,
          headers: head.headers,
          url: req.url,
          request: req.head(),
          body,
          max_body_bytes,
        })
      }).any_status(),
    )
    .follow_redirects(follow_redirects)
    .send(self.inner)
  })
  match reply.body {
    Ok(value) => value
    // any_status sends every status to the function.
    Err(failure) => raise DecodingError(failure.to_string())
  }
}
