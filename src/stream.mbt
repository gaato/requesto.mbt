///|
/// The default bound on one line read by `StreamResponse::each_line`.
let default_max_line_bytes : Int32 = 1024 * 1024

///|
/// The default bound on one event read by `StreamResponse::each_event`.
let default_max_event_bytes : Int32 = 16 * 1024 * 1024

///|
/// A response whose body is still on the connection. It is valid only inside
/// the function passed to `stream`, and is closed when that function returns.
pub struct StreamResponse {
  /// The status code.
  status_code : Int32
  /// The response headers.
  headers : @mttp.Headers
  /// The URL of the request.
  url : String
  /// The request as it was sent.
  request : @mttp_core.RequestHead
  priv body : &@mttp.BodyStream
  priv max_body_bytes : Int32
}

///|
/// Whether the status is 200..=299.
pub fn StreamResponse::is_success(self : StreamResponse) -> Bool {
  self.status_code >= 200 && self.status_code < 300
}

///|
/// Raises `HTTPStatusError` outside 200..=299, carrying the head and an
/// empty body (the body stays unread); otherwise returns the response.
pub fn StreamResponse::raise_for_status(
  self : StreamResponse,
) -> StreamResponse raise HTTPError {
  guard self.is_success() else {
    raise HTTPStatusError({
      status_code: self.status_code,
      headers: self.headers,
      url: self.url,
      content: b"",
      request: self.request,
      history: [],
      elapsed: 0,
    })
  }
  self
}

///|
/// Reads the rest of the body, up to the client's `max_body_bytes`; a longer
/// body raises `TooLarge`.
pub async fn StreamResponse::read(
  self : StreamResponse,
) -> Bytes raise HTTPError {
  lift(() => @mttp.read_bounded(self.body, self.max_body_bytes))
}

///|
/// httpx2's `iter_bytes`: calls `f` with each chunk as it arrives. Errors
/// from `f` come out unchanged.
pub async fn StreamResponse::each_bytes(
  self : StreamResponse,
  f : async (Bytes) -> Unit,
) -> Unit {
  while lift(() => self.body.read_some()) is Some(chunk) {
    f(chunk)
  }
}

///|
/// httpx2's `iter_lines`: calls `f` with each line, without its `\n` or
/// `\r\n`, decoded as UTF-8 with malformed sequences replaced. A line longer
/// than `max_line_bytes` (1 MiB by default) closes the body and raises
/// `TooLarge` after the lines before it.
pub async fn StreamResponse::each_line(
  self : StreamResponse,
  f : async (String) -> Unit,
  max_line_bytes~ : Int32 = default_max_line_bytes,
) -> Unit {
  let pending = Buffer()
  async fn flush() {
    let bytes = pending.to_bytes()
    pending.reset()
    let n = bytes.length()
    let end = if n > 0 && bytes[n - 1] == b'\r' { n - 1 } else { n }
    f(@utf8.decode_lossy(bytes[0:end]))
  }

  self.each_bytes(chunk => {
    for b in chunk {
      if b == b'\n' {
        flush()
      } else if pending.length() >= max_line_bytes {
        self.body.close()
        raise TooLarge(
          local_error(
            TooLarge(limit=max_line_bytes),
            Body,
            "a line passed \{max_line_bytes} bytes",
          ),
          limit=max_line_bytes,
        )
      } else {
        pending.write_byte(b)
      }
    }
  })
  if pending.length() > 0 {
    flush()
  }
}

///|
/// Calls `f` with each server-sent event as it arrives (what httpx-sse's
/// `iter_sse` does). An event longer than `max_event_bytes` (16 MiB by
/// default) closes the body and raises `TooLarge`.
pub async fn StreamResponse::each_event(
  self : StreamResponse,
  f : async (SseEvent) -> Unit,
  max_event_bytes~ : Int32 = default_max_event_bytes,
) -> Unit {
  let reader = @sse.SseReader::new(self.body, max_event_bytes~)
  lift_any(() => reader.each(f))
}
