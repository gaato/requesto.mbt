///|
/// A response with its body read. Every status is an ordinary response;
/// `raise_for_status` turns the ones outside 200..=299 into an error.
pub struct Response {
  /// The status code.
  status_code : Int32
  /// The response headers.
  headers : @mttp.Headers
  /// The URL the response came from, after any redirects.
  url : String
  /// The body, decompressed.
  content : Bytes
  /// The request as it was first sent.
  request : @mttp_core.RequestHead
  /// The redirects followed on the way here, oldest first.
  history : Array[@client.RedirectHop]
  /// Milliseconds from sending to having the whole body, on the client's
  /// clock.
  elapsed : Int64
}

///|
/// Whether the status is 100..=199.
pub fn Response::is_informational(self : Response) -> Bool {
  self.status_code >= 100 && self.status_code < 200
}

///|
/// Whether the status is 200..=299.
pub fn Response::is_success(self : Response) -> Bool {
  self.status_code >= 200 && self.status_code < 300
}

///|
/// Whether the status is a redirect (301, 302, 303, 307 or 308) with a
/// `Location` to follow.
pub fn Response::is_redirect(self : Response) -> Bool {
  self.status_code is (301 | 302 | 303 | 307 | 308) &&
  self.headers.contains("location")
}

///|
/// Whether the status is 400..=499.
pub fn Response::is_client_error(self : Response) -> Bool {
  self.status_code >= 400 && self.status_code < 500
}

///|
/// Whether the status is 500..=599, as in httpx2. `raise_for_status` also
/// raises for 600..=999, which mttp accepts as server failures.
pub fn Response::is_server_error(self : Response) -> Bool {
  self.status_code >= 500 && self.status_code < 600
}

///|
/// Whether the status is 400..=599.
pub fn Response::is_error(self : Response) -> Bool {
  self.status_code >= 400 && self.status_code < 600
}

///|
/// The standard reason phrase for the status, or `""` for one without.
pub fn Response::reason_phrase(self : Response) -> String {
  reason_phrase(self.status_code)
}

///|
/// Raises `HTTPStatusError` for any status outside 200..=299, as httpx2
/// does; otherwise returns the response so calls can chain.
pub fn Response::raise_for_status(self : Response) -> Response raise HTTPError {
  guard self.is_success() else { raise HTTPStatusError(self) }
  self
}

///|
/// The body as UTF-8, malformed sequences replaced with U+FFFD.
pub fn Response::text(self : Response) -> String {
  @utf8.decode_lossy(self.content)
}

///|
/// The body parsed as JSON; `DecodingError` if it is not JSON.
pub fn Response::json(self : Response) -> Json raise HTTPError {
  @json.parse(self.text()) catch {
    e => raise DecodingError(e.to_string())
  }
}

///|
/// The body decoded from JSON into `T`; `DecodingError` if it does not fit.
pub fn[T : @json.FromJson] Response::json_as(
  self : Response,
) -> T raise HTTPError {
  let value = self.json()
  @json.from_json(value) catch {
    e => raise DecodingError(e.to_string())
  }
}

///|
/// The reason phrases of RFC 9110 and the common extensions httpx2 lists.
fn reason_phrase(status : Int32) -> String {
  match status {
    100 => "Continue"
    101 => "Switching Protocols"
    102 => "Processing"
    103 => "Early Hints"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    207 => "Multi-Status"
    208 => "Already Reported"
    226 => "IM Used"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    402 => "Payment Required"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    407 => "Proxy Authentication Required"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Content Too Large"
    414 => "URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    417 => "Expectation Failed"
    418 => "I'm a teapot"
    421 => "Misdirected Request"
    422 => "Unprocessable Content"
    423 => "Locked"
    424 => "Failed Dependency"
    425 => "Too Early"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    451 => "Unavailable For Legal Reasons"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    506 => "Variant Also Negotiates"
    507 => "Insufficient Storage"
    508 => "Loop Detected"
    510 => "Not Extended"
    511 => "Network Authentication Required"
    _ => ""
  }
}
