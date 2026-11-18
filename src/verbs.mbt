///|
/// A GET request; see `Client::request`.
pub async fn Client::get(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  self.request("GET", url, params~, headers~, auth?, trace?, follow_redirects~)
}

///|
/// A HEAD request; see `Client::request`.
pub async fn Client::head(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  self.request("HEAD", url, params~, headers~, auth?, trace?, follow_redirects~)
}

///|
/// A OPTIONS request; see `Client::request`.
pub async fn Client::options(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  self.request(
    "OPTIONS",
    url,
    params~,
    headers~,
    auth?,
    trace?,
    follow_redirects~,
  )
}

///|
/// A DELETE request; see `Client::request`.
pub async fn Client::delete(
  self : Client,
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = self.follow_redirects,
) -> Response raise HTTPError {
  self.request(
    "DELETE",
    url,
    params~,
    headers~,
    auth?,
    trace?,
    follow_redirects~,
  )
}

///|
/// A POST request with an optional body; see `Client::request`.
pub async fn Client::post(
  self : Client,
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
  self.request(
    "POST",
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
    follow_redirects~,
  )
}

///|
/// A PUT request with an optional body; see `Client::request`.
pub async fn Client::put(
  self : Client,
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
  self.request(
    "PUT",
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
    follow_redirects~,
  )
}

///|
/// A PATCH request with an optional body; see `Client::request`.
pub async fn Client::patch(
  self : Client,
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
  self.request(
    "PATCH",
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
    follow_redirects~,
  )
}

///|
/// One GET request on a client made and closed for this call, as
/// `httpx2.get`.
pub async fn get(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request("GET", url, params~, headers~, auth?, trace?)
}

///|
/// One HEAD request on a client made and closed for this call, as
/// `httpx2.head`.
pub async fn head(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request("HEAD", url, params~, headers~, auth?, trace?)
}

///|
/// One OPTIONS request on a client made and closed for this call, as
/// `httpx2.options`.
pub async fn options(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request("OPTIONS", url, params~, headers~, auth?, trace?)
}

///|
/// One DELETE request on a client made and closed for this call, as
/// `httpx2.delete`.
pub async fn delete(
  url : String,
  params~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  auth? : Auth,
  trace? : (PhaseEvent) -> Unit,
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request("DELETE", url, params~, headers~, auth?, trace?)
}

///|
/// One POST request on a client made and closed for this call, as
/// `httpx2.post`.
pub async fn post(
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
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request(
    "POST",
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
}

///|
/// One PUT request on a client made and closed for this call, as
/// `httpx2.put`.
pub async fn put(
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
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request(
    "PUT",
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
}

///|
/// One PATCH request on a client made and closed for this call, as
/// `httpx2.patch`.
pub async fn patch(
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
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request(
    "PATCH",
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
}

///|
/// One request on a client made and closed for this call, as
/// `httpx2.request`.
pub async fn request(
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
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> Response raise HTTPError {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.request(
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
}

///|
/// One streamed request on a client made and closed for this call, as
/// `httpx2.stream`; see `Client::stream`.
pub async fn[T] stream(
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
  follow_redirects~ : Bool = false,
  timeout~ : Timeout = Timeout::new(Some(default_phase_timeout_ms)),
) -> T {
  let client = Client::new(timeout~, follow_redirects~)
  defer client.close()
  client.stream(
    verb,
    url,
    f,
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
}

///|
/// A part of a multipart body, for `files`: `Part::file(name, filename,
/// content_type, bytes)` or `Part::text(name, value)`.
pub using @multipart {type Part}

///|
/// A server-sent event, as `StreamResponse::each_event` passes it.
pub using @sse {type SseEvent}

///|
/// A point one attempt reached on the connection, as `trace=` passes it
/// (httpx2's `trace` extension): `Dialed(addr~)`, `TlsDone`,
/// `Pooled(reused~)`, `Written` and `FirstByte`, in that order and each at
/// most once per attempt. The native and wasm network reports them; the JS
/// host's fetch and a `MockTransport` report none.
pub using @mttp_core {type PhaseEvent}
