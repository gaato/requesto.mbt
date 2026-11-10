///|
/// The `User-Agent` a client sends unless told otherwise.
let user_agent : String = "requesto/0.2.3"

///|
/// How long one exchange may take, in milliseconds, unless told otherwise.
let default_timeout : Int32 = 30_000

///|
/// The largest buffered body the default transport accepts, unless told
/// otherwise: 64 MiB, counted after decompression.
let default_max_body_bytes : Int32 = 67_108_864

///|
/// The default transport's own deadline. The client applies `timeout` on its
/// clock, so the transport's only has to stay out of the way of any timeout
/// a call asks for.
let transport_ceiling_ms : Int32 = 2_147_483_647

///|
/// Defaults shared by the calls made through it, and the transport and clock
/// they use. Call `close` when done, to drop the default transport's idle
/// connections.
pub struct Client {
  priv base_url : String?
  priv headers : @http.Headers
  priv params : Array[(String, String)]
  priv timeout : Int32
  /// `None` to derive it from `timeout` and `retry`; `Some(None)` for no
  /// bound.
  priv total_timeout : Int32??
  priv max_body_bytes : Int32?
  priv steps : Array[Step]
  priv follow_redirects : Bool
  priv max_redirects : Int32
  priv jar : CookieJar?
  priv retry : Retry
  priv auth : Step?
  priv random : () -> Double
  priv transport : &@http.Transport
  priv clock : &@clock.Clock
  priv owned : @adapter.AsyncTransport?
}

///|
/// Creates a client.
///
/// - `base_url`: prefixed to relative URLs; a call's URL is appended to it
///   with one `/`, so `"/users"` and `"users"` both land under its path.
/// - `headers`: sent with every call, after `User-Agent: requesto/<version>`,
///   which a `User-Agent` here replaces.
/// - `params`: query parameters added to every call.
/// - `auth`: sets `Authorization` on calls that do not set it themselves.
/// - `timeout`: milliseconds one exchange may take, 30 s by default: up to
///   the whole response, or for a streamed one up to its head and then each
///   read of its body.
/// - `total_timeout`: milliseconds a whole call may take, its redirects,
///   retries and the waits between them included, up to the whole response
///   or a streamed one's head. Unset, it is `max_retries + 2` times the
///   call's `timeout`: one for each send `retry` allows and one for the
///   waits and redirects between them, 2.5 minutes by default. Raising
///   `timeout` raises it too, and a single send's own `timeout` always runs
///   out first; `None` lifts it.
/// - `max_body_bytes`: the largest body buffered, 64 MiB by default, counted
///   after decoding; `None` lifts it. The default transport applies it to
///   each call; `Response::read` applies it to a streamed body.
/// - `steps`: links of the chain around the transport, the first outermost;
///   they see the call's first request and its final response, before
///   redirects, retries and `auth`.
/// - `retry`: when a call is sent again, `Retry::new()` by default: up to 3
///   retries of idempotent methods on 408, 429, 500, 502, 503, 504 and
///   transport failures, of any method when nothing was sent;
///   `Retry::none()` turns it off.
/// - `follow_redirects`: follows 301, 302, 303, 307 and 308 responses, at
///   most `max_redirects` (10) in a row, as gaato/http's `follow_redirects`
///   does: 303, and 301 or 302 after `POST`, turn into `GET` without the
///   body; `Authorization`, `Cookie` and `Proxy-Authorization` are dropped
///   when the origin changes; `https` to `http` is refused. On by default;
///   each call can turn it off or on. On JS, `fetch` follows redirects
///   before the client sees them.
/// - `cookies`: by default the client keeps cookies in a jar of its own on
///   its clock (`Client::cookies`), at most 50 per domain and 3000 in all,
///   applied on every redirect hop. `Jar(jar)` uses `jar` instead, `Off`
///   keeps none.
/// - `transport`: replaces the default `AsyncTransport` of gaato/http-async.
/// - `clock`: measures `timeout` and `elapsed`, and waits between retries.
/// - `random`: values in `[0, 1)` for retry jitter, Digest client nonces and
///   multipart boundaries; host randomness by default.
///
/// These configure the default transport and are ignored with `transport`:
///
/// - `connect_timeout`, `write_timeout`, `read_timeout`, `pool_timeout`:
///   milliseconds for making a connection, sending the request, waiting for
///   each read of the response, and waiting for a free connection. Unset,
///   only `timeout` applies.
/// - `max_connections`, `max_connections_per_origin`: open connections in
///   all and to one origin; a call beyond them waits for one to be free.
///   Unset, gaato/http-async's defaults apply.
/// - `max_idle_per_origin`: connections kept open between calls, per origin.
/// - `proxy`: an `http://` or `https://` proxy URL, credentials optional,
///   for every call. Without it, `trust_env` (on by default) reads
///   `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY`.
///
/// ```mbt check
/// test {
///   let client = @requesto.Client::new(
///     base_url="https://api.example.com/v1",
///     headers=[("Accept", "application/json")],
///     auth=Bearer("token"),
///   )
///   client.close()
/// }
/// ```
pub fn Client::new(
  base_url? : String,
  headers~ : Array[(String, String)] = [],
  params~ : Array[(String, String)] = [],
  auth? : Auth,
  timeout~ : Int32 = default_timeout,
  total_timeout? : Int32?,
  max_body_bytes~ : Int32? = Some(default_max_body_bytes),
  steps~ : Array[Step] = [],
  follow_redirects~ : Bool = true,
  max_redirects~ : Int32 = default_max_redirects,
  cookies? : Cookies,
  retry~ : Retry = Retry::new(),
  transport? : &@http.Transport,
  clock? : &@clock.Clock,
  random? : () -> Double,
  connect_timeout? : Int32,
  write_timeout? : Int32,
  read_timeout? : Int32,
  pool_timeout? : Int32,
  max_connections? : Int32,
  max_connections_per_origin? : Int32,
  max_idle_per_origin? : Int32,
  proxy? : String,
  trust_env~ : Bool = true,
) -> Client {
  let defaults = @http.Headers::from_array([("user-agent", user_agent)])
  let random = random.unwrap_or(@random.default_random)
  let (transport, owned) = match transport {
    Some(transport) => (transport, None)
    None => {
      let transport = @adapter.AsyncTransport::new(
        timeout_ms=transport_ceiling_ms,
        connect_timeout_ms?=connect_timeout,
        write_timeout_ms?=write_timeout,
        read_timeout_ms?=read_timeout,
        pool_timeout_ms?=pool_timeout,
        max_connections?,
        max_connections_per_origin?,
        max_idle_per_origin?,
        max_body_bytes?,
        proxy?,
        trust_env~,
      )
      (transport as &@http.Transport, Some(transport))
    }
  }
  let clock = clock.unwrap_or_else(() => @adapter.AsyncClock::new())
  {
    base_url,
    headers: merge_headers(defaults, headers),
    params: [..params],
    timeout,
    total_timeout,
    max_body_bytes,
    steps: [..steps],
    retry,
    auth: auth.map(auth => auth_step(auth, random)),
    random,
    follow_redirects,
    max_redirects,
    jar: cookie_jar(cookies, clock),
    transport,
    clock,
    owned,
  }
}

///|
/// Drops the default transport's idle connections. A transport passed to
/// `Client::new` is left to its owner.
pub fn Client::close(self : Client) -> Unit {
  if self.owned is Some(transport) {
    transport.close()
  }
}

///|
/// The client's cookie jar, or `None` with `cookies=Off`.
///
/// ```mbt check
/// test {
///   let client = @requesto.Client::new()
///   assert_eq(client.cookies().map(jar => jar.length()), Some(0))
///   client.close()
/// }
/// ```
pub fn Client::cookies(self : Client) -> CookieJar? {
  self.jar
}

///|
/// Sends a request and returns its response, whatever its status.
///
/// - `url` is joined to `base_url`, then parsed and normalised as `Url`
///   does; one that is not an absolute `http` or `https` URL is refused
///   before anything is sent. Credentials in it (`user:pass@`) are taken
///   out of the URL and sent as Basic `Authorization`, in place of the
///   client's `auth`, unless the call sets `Authorization` itself.
/// - `params` are added to the URL's query, after the client's; a name given
///   here replaces the client's parameters of that name.
/// - `headers` replace the client's headers of the same names.
/// - At most one body: `content` (bytes, no `Content-Type`), `text`
///   (`text/plain; charset=utf-8`), `data` (a URL-encoded form), `files`
///   (`multipart/form-data`), `json` (compact `application/json`) or
///   `body_stream` (sent as it is read, with `Content-Length` when
///   `body_length` gives it and chunked otherwise). A `Content-Type` in the
///   headers wins over the implied one. A body that streams, including
///   files made with `Part::file_stream`, is sent at most once: retries and
///   redirects that would send it again stop instead.
/// - `timeout`, `total_timeout` and `retry` replace the client's for this
///   call. A call that sets `timeout` but not `total_timeout`, on a client
///   that sets none, derives its total from its own `timeout`. When the
///   total runs out, the call raises `TotalTimeout`; a retry whose wait
///   would not fit in what is left is not waited for, and the last response
///   is returned or the last failure raised.
/// - `follow_redirects` replaces the client's for this call. The response
///   carries the redirects followed in `history` and the final URL in `url`.
pub async fn Client::request(
  self : Client,
  http_method : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
) -> Response raise RequestoError {
  let request = self.build(
    http_method,
    url,
    params,
    headers,
    select_body(
      content?,
      text?,
      data?,
      files?,
      json?,
      body_stream?,
      body_length?,
    ),
  )
  let timeout = timeout.unwrap_or(self.timeout)
  let retry = retry.unwrap_or(self.retry)
  let total = self.total_budget(total_timeout, timeout, retry)
  self.within_total(request, total, deadline => {
    run_steps(
      self.chain(request, retry, follow_redirects, deadline),
      request => self.exchange(request, timeout, stream=false),
      request,
    )
  })
}

///|
/// Sends a request like `request` and calls `f` with the response while its
/// body is still on the connection, then closes it, whether `f` read it or
/// not. Steps see the response before `f`; every response the call opened,
/// including ones a step dropped or raised over, is closed when it ends.
/// The redirect responses in `history` are closed unread before the next
/// request goes out: they keep their status, headers and URL, not their
/// bodies.
///
/// ```mbt check
/// async test {
///   let client = @requesto.Client::new(
///     transport=@requesto.MockTransport::new(_ => {
///       status: 200,
///       headers: @http.Headers::new(),
///       body: b"line one",
///     }),
///   )
///   let size = client.stream("GET", "https://example.com/export", response => {
///     let mut size = 0
///     response.each_chunk(chunk => size += chunk.length())
///     size
///   })
///   assert_eq(size, 8)
/// }
/// ```
pub async fn[T] Client::stream(
  self : Client,
  http_method : String,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  content? : Bytes,
  text? : String,
  data? : Array[(String, String)],
  files? : Array[Part],
  json? : Json,
  body_stream? : &@http.BodyStream,
  body_length? : Int64,
  timeout? : Int32,
  total_timeout? : Int32?,
  follow_redirects? : Bool,
  retry? : Retry,
  f : async (Response) -> T,
) -> T {
  let request = self.build(
    http_method,
    url,
    params,
    headers,
    select_body(
      content?,
      text?,
      data?,
      files?,
      json?,
      body_stream?,
      body_length?,
    ),
  )
  let timeout = timeout.unwrap_or(self.timeout)
  let retry = retry.unwrap_or(self.retry)
  let total = self.total_budget(total_timeout, timeout, retry)
  // Every response opened during the call is closed when it ends, so a
  // step that raises after `next`, or drops a response it replaced, cannot
  // leave a connection behind.
  let opened : Array[Response] = []
  defer opened.each(response => response.close())
  // The total covers the response's head; reading the body is bounded per
  // read instead, as `f` may read for as long as the stream lasts.
  let response = self.within_total(request, total, deadline => {
    run_steps(
      self.chain(request, retry, follow_redirects, deadline),
      request => {
        let response = self.exchange(request, timeout, stream=true)
        opened.push(response)
        response
      },
      request,
    )
  })
  f(response)
}

///|
/// The milliseconds a call may take in all, or `None` for no bound: the
/// call's `total_timeout`, else the client's, else `max_retries + 2`
/// exchanges of the call's `timeout`: one per send, and one for the waits
/// and redirects between them, so that a call sent once times out on its
/// own `timeout`, with its phase, before the total.
fn Client::total_budget(
  self : Client,
  total_timeout : Int32??,
  timeout : Int32,
  retry : Retry,
) -> Int32? {
  let set = if total_timeout is Some(_) {
    total_timeout
  } else {
    self.total_timeout
  }
  match set {
    Some(total) => total
    None => {
      let ms = (retry.max_retries.to_int64() + 2L) * timeout.to_int64()
      Some(if ms > max_int32 { transport_ceiling_ms } else { ms.to_int() })
    }
  }
}

///|
/// `Int32` max, as an `Int64`.
let max_int32 : Int64 = 2_147_483_647L

///|
/// Runs `f` within `total` milliseconds on the client's clock, raising
/// `TotalTimeout` for `request` when they run out; `f` gets the deadline,
/// in milliseconds on that clock, or `None` without a bound.
async fn[T] Client::within_total(
  self : Client,
  request : Request,
  total : Int32?,
  f : async (Int64?) -> T raise RequestoError,
) -> T raise RequestoError {
  guard total is Some(ms) else { return f(None) }
  let deadline = self.clock.now_unix_ms() + ms.to_int64()
  let outcome = @adapter.with_timeout_opt(self.clock, ms, () => {
    try f(Some(deadline)) catch {
      error => Err(error)
    } noraise {
      value => Ok(value)
    }
  }) catch {
    error => raise map_transport_error(error, request)
  }
  match outcome {
    Some(Ok(value)) => value
    Some(Err(error)) => raise error
    None => raise TotalTimeout(request~, timeout=ms)
  }
}

///|
/// The chain of one call, outermost first: the client's steps, the
/// redirect step unless `follow_redirects` is off, then for each hop the
/// retry step, `auth` and the cookie step. Retries and auth run per hop, as
/// in requests and Req: a hop is resent on its own, so a request already
/// answered with a redirect is never sent again, and auth answers each hop
/// with its own method and URI, but only on the origin of `request`.
fn Client::chain(
  self : Client,
  request : Request,
  retry : Retry,
  follow_redirects : Bool?,
  deadline : Int64?,
) -> Array[Step] {
  let chain = [..self.steps]
  if follow_redirects.unwrap_or(self.follow_redirects) {
    chain.push(redirect_step(self.max_redirects))
  }
  chain.push(retry_step(retry, self.clock, self.random, deadline))
  if self.auth is Some(auth) {
    chain.push(same_origin_only(request.url, auth))
  }
  if self.jar is Some(jar) {
    chain.push(cookie_step(jar))
  }
  chain
}

///|
/// The request a call describes, before the steps.
fn Client::build(
  self : Client,
  http_method : String,
  url : String,
  params : Array[(String, String)],
  headers : Array[(String, String)],
  body : Body,
) -> Request raise RequestoError {
  check_method(http_method)
  let parsed = parse_url(join_url(self.base_url, url))
  let url = without_userinfo(
    parsed
    .without_fragment()
    .append_query_params(merge_params(self.params, params))
    .to_string(),
    parsed.userinfo,
  )
  let headers = merge_headers(self.headers, headers)
  if parsed.userinfo is Some(userinfo) && !headers.contains("authorization") {
    let (username, password) = split_userinfo(userinfo)
    headers.set("authorization", basic_value(username, password))
  }
  let (content_type, body) = body.encode(random=self.random)
  if content_type is Some(value) && !headers.contains("content-type") {
    headers.set("content-type", value)
  }
  { http_method: http_method.to_upper(), url, headers, body, }
}

///|
/// Raises unless `http_method` is an HTTP token.
fn check_method(http_method : String) -> Unit raise RequestoError {
  if http_method.is_empty() || !http_method.iter().all(is_tchar) {
    raise InvalidRequest(message="invalid method: \{http_method}")
  }
}

///|
/// The last link: one exchange with the transport, within `timeout` on the
/// client's clock. A streamed exchange ends at the response head and leaves
/// the body on the connection.
async fn Client::exchange(
  self : Client,
  request : Request,
  timeout : Int32,
  stream~ : Bool,
) -> Response raise RequestoError {
  let started = self.clock.now_unix_ms()
  let received = @adapter.with_timeout_opt(self.clock, timeout, () => {
    if stream {
      let (head, body) = self.transport.send_stream(request)
      (head.status, head.headers, Open(body, started=false))
    } else {
      let response = self.transport.send(request)
      (
        response.status,
        response.headers,
        Buffered(response.body, delivered=false),
      )
    }
  }) catch {
    error => raise map_transport_error(error, request)
  }
  guard received is Some((status, headers, state)) else {
    raise Timeout(request~, phase=Unknown, timeout~)
  }
  {
    status,
    headers,
    url: request.url,
    request,
    history: [],
    elapsed: (self.clock.now_unix_ms() - started).to_int(),
    retries: 0,
    body: {
      state,
      closed: false,
      max_bytes: self.max_body_bytes,
      clock: self.clock,
      timeout: Some(timeout),
    },
  }
}
