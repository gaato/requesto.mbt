///|
/// One suberror for every failure. The variants are httpx2's exception
/// classes that can occur here, and the predicates stand in for its class
/// tree. Transport variants keep the `@mttp.TransportError` they came from.
pub(all) suberror HTTPError {
  /// Connecting took longer than `Timeout.connect`.
  ConnectTimeout(@mttp.TransportError)
  /// The response's head or the next bytes of its body took longer than
  /// `Timeout.read`.
  ReadTimeout(@mttp.TransportError)
  /// Writing the request took longer than `Timeout.write`.
  WriteTimeout(@mttp.TransportError)
  /// Waiting for a free connection took longer than `Timeout.pool`.
  PoolTimeout(@mttp.TransportError)
  /// The whole-call deadline (`total_timeout`) ran out.
  TotalTimeout(@mttp.TransportError)
  /// The connection could not be made, or broke before the request was sent.
  ConnectError(@mttp.TransportError)
  /// The connection broke while the response was read.
  ReadError(@mttp.TransportError)
  /// The connection broke while the request was written.
  WriteError(@mttp.TransportError)
  /// The peer broke HTTP (httpx2's `RemoteProtocolError`).
  ProtocolError(@mttp.TransportError)
  /// A proxy refused the tunnel with `status`.
  ProxyError(@mttp.TransportError, status~ : Int32)
  /// More redirects than `max_redirects`.
  TooManyRedirects(@mttp.TransportError)
  /// A redirect from https to http, which mttp refuses; httpx2 follows it.
  RedirectRefused(@mttp.TransportError)
  /// The body passed `max_body_bytes`, or a line or event passed its limit;
  /// httpx2 has no such limits.
  TooLarge(@mttp.TransportError, limit~ : Int32)
  /// The request could not be sent as built: a bad URL, a header value mttp
  /// refuses, or a multipart body that cannot be encoded (httpx2's
  /// `InvalidURL` and `LocalProtocolError`).
  InvalidRequest(@mttp.TransportError)
  /// A streamed request body cannot be sent again for a redirect or a retry
  /// (httpx2's `StreamConsumed`).
  StreamClosed(@mttp.TransportError)
  /// A failure from mttp that no other variant names: a transport failure
  /// of a newer kind, or a refusal from mttp's client (a spent retry budget,
  /// say), whose message is then the detail of an `Unknown`-phase error.
  TransportError(@mttp.TransportError)
  /// `raise_for_status` on a status outside 200..=299.
  HTTPStatusError(Response)
  /// The body is not what the caller asked to decode it as.
  DecodingError(String)
}

///|
/// The variant's mttp diagnostic, or the status and URL.
pub impl Show for HTTPError with fn output(self, logger) {
  match self {
    HTTPStatusError(r) =>
      logger.write_string("HTTPStatusError: \{r.status_code} for \{r.url}")
    DecodingError(m) => logger.write_string("DecodingError: \{m}")
    _ =>
      match self.mttp() {
        Some(e) => logger.write_string(e.message())
        None => logger.write_string("HTTPError")
      }
  }
}

///|
/// `to_string` and `output` as methods of `HTTPError`.
pub extend HTTPError with Show::{to_string, output}

///|
/// The mttp error a transport variant came from.
pub fn HTTPError::mttp(self : HTTPError) -> @mttp.TransportError? {
  match self {
    ConnectTimeout(e)
    | ReadTimeout(e)
    | WriteTimeout(e)
    | PoolTimeout(e)
    | TotalTimeout(e)
    | ConnectError(e)
    | ReadError(e)
    | WriteError(e)
    | ProtocolError(e)
    | ProxyError(e, ..)
    | TooManyRedirects(e)
    | RedirectRefused(e)
    | TooLarge(e, ..)
    | InvalidRequest(e)
    | StreamClosed(e)
    | TransportError(e) => Some(e)
    HTTPStatusError(_) | DecodingError(_) => None
  }
}

///|
/// Whether a time limit ran out: a phase timeout or `total_timeout`.
pub fn HTTPError::is_timeout(self : HTTPError) -> Bool {
  self
  is (ConnectTimeout(_)
  | ReadTimeout(_)
  | WriteTimeout(_)
  | PoolTimeout(_)
  | TotalTimeout(_))
}

///|
/// httpx2's `NetworkError` branch: the connection could not be made or broke.
pub fn HTTPError::is_network_error(self : HTTPError) -> Bool {
  self is (ConnectError(_) | ReadError(_) | WriteError(_))
}

///|
/// httpx2's `TransportError` branch: anything that went wrong on the wire.
pub fn HTTPError::is_transport_error(self : HTTPError) -> Bool {
  self.mttp() is Some(_)
}

///|
/// httpx2's `RequestError` branch: every failure except `HTTPStatusError`.
pub fn HTTPError::is_request_error(self : HTTPError) -> Bool {
  !(self is HTTPStatusError(_))
}

///|
/// The variant httpx2 would raise for an mttp transport failure.
fn from_mttp(e : @mttp.TransportError) -> HTTPError {
  let @mttp_core.TransportError(kind~, phase~, ..) = e
  match (kind, phase) {
    (Timeout(..), Pool) => PoolTimeout(e)
    (Timeout(..), Dial) => ConnectTimeout(e)
    (Timeout(..), Write) => WriteTimeout(e)
    (Timeout(..), Head | Body) => ReadTimeout(e)
    (Timeout(..), _) => TotalTimeout(e)
    (Connect, _) => ConnectError(e)
    (Network | Closed | IncompleteClose | Refused, Pool | Dial) =>
      ConnectError(e)
    (Network | Closed | IncompleteClose | Refused, Write) => WriteError(e)
    (Network | Closed | IncompleteClose | Refused, _) => ReadError(e)
    (Protocol, _) => ProtocolError(e)
    (Proxy(status~), _) => ProxyError(e, status~)
    (TooLarge(limit~), _) => TooLarge(e, limit~)
    (TooManyRedirects(..), _) => TooManyRedirects(e)
    (RedirectRefused, _) => RedirectRefused(e)
    (Invalid, _) => InvalidRequest(e)
    (Unreplayable, _) => StreamClosed(e)
    _ => TransportError(e)
  }
}

///|
/// An mttp error for a failure requesto finds itself.
fn local_error(
  kind : @mttp_core.Kind,
  phase : @mttp_core.Phase,
  detail : String,
) -> @mttp.TransportError {
  @mttp_core.TransportError(kind~, phase~, detail~)
}

///|
/// Runs an mttp call, turning its transport failures into `HTTPError`.
async fn[T] lift(f : async () -> T) -> T raise HTTPError {
  f() catch {
    @mttp_core.TransportError(..) as e => raise from_mttp(e)
    e => raise TransportError(local_error(Network, Unknown, e.to_string()))
  }
}

///|
/// As `lift`, but errors other than mttp's pass through unchanged, for calls
/// that run the caller's own code.
async fn[T] lift_any(f : async () -> T) -> T {
  f() catch {
    @mttp_core.TransportError(..) as e => raise from_mttp(e)
    e => raise e
  }
}
