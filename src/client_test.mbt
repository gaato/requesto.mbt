///|
/// A tiny mttp server app: the same function could be passed to
/// `@server.serve`. The tests call it through `MockTransport`, with no socket.
fn app(req : @mttp.Request) -> @mttp.Response noraise {
  let url = req.url
  let json_headers = @mttp_core.Headers::of([
    ("content-type", "application/json"),
  ])
  if url.contains("/json") {
    @mttp_core.Response::new(
      200,
      headers=json_headers,
      body=Bytes(b"{\"id\":42,\"name\":\"okayu\"}"),
    )
  } else if url.contains("/old") {
    @mttp_core.Response::new(
      302,
      headers=@mttp_core.Headers::of([("location", "https://api.test/json")]),
    )
  } else if url.contains("/echo") {
    let auth = req.headers.get("authorization").unwrap_or("")
    let body = req.body.as_bytes().unwrap_or(b"")
    let echoed : Json = {
      "url": Json::string(url),
      "auth": Json::string(auth),
      "body": Json::string(@utf8.decode_lossy(body)),
    }
    @mttp_core.Response::new(
      200,
      headers=json_headers,
      body=Bytes(@utf8.encode(echoed.stringify())),
    )
  } else if url.contains("/lines") {
    @mttp_core.Response::new(200, body=Bytes(b"a\nb\r\nc"))
  } else {
    @mttp_core.Response::new(404, body=Bytes(b"no such page"))
  }
}

///|
#derive(FromJson, Debug, Eq)
struct User {
  id : Int32
  name : String
}

///|
/// The error a call raised, or `None` if it returned.
async fn[T] error_of(
  f : async () -> T raise @requesto.HTTPError,
) -> @requesto.HTTPError? {
  try {
    f() |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
/// The error a call that runs the caller's code raised, or `None`.
async fn[T] any_error_of(f : async () -> T) -> Error? {
  try {
    f() |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
fn client(follow_redirects~ : Bool = false) -> @requesto.Client {
  @requesto.Client::new(
    base_url="https://api.test",
    auth=Bearer("t0k3n"),
    params=[("v", "2")],
    follow_redirects~,
    transport=@requesto.MockTransport::new(req => app(req)),
  )
}

///|
async test "get, raise_for_status and json_as chain as in httpx2" {
  let c = client()
  defer c.close()
  let user : User = c.get("json").raise_for_status().json_as()
  debug_inspect(user, content="{ id: 42, name: \"okayu\" }")
}

///|
async test "a 404 is a value until raise_for_status" {
  let c = client()
  defer c.close()
  let r = c.get("nope")
  assert_eq(r.status_code, 404)
  assert_true(r.is_client_error())
  assert_eq(r.text(), "no such page")
  let raised = error_of(() => r.raise_for_status())
  guard raised is Some(HTTPStatusError(failed)) else {
    fail("expected HTTPStatusError")
  }
  assert_eq(failed.status_code, 404)
}

///|
async test "redirects are not followed unless asked, per client or per call" {
  let c = client()
  defer c.close()
  let r = c.get("old")
  assert_eq(r.status_code, 302)
  assert_true(r.is_redirect())
  let followed = c.get("old", follow_redirects=true)
  assert_eq(followed.status_code, 200)
  assert_eq(followed.url, "https://api.test/json")
  assert_eq(followed.history.length(), 1)
  let c2 = client(follow_redirects=true)
  defer c2.close()
  assert_eq(c2.get("old").status_code, 200)
}

///|
async test "client params, call params, auth and a JSON body reach the app" {
  let c = client()
  defer c.close()
  let echoed = c.post("echo", params=[("q", "1")], json={ "a": 1 }).json()
  debug_inspect(
    echoed,
    content=(
      #|Object(
      #|  {
      #|    "url": String("https://api.test/echo?v=2&q=1"),
      #|    "auth": String("Bearer t0k3n"),
      #|    "body": String("{\"a\":1}"),
      #|  },
      #|)
    ),
  )
  // auth= on one call replaces the client's.
  let basic = c.get("echo", auth=Basic("u", "p")).json()
  guard basic is Object(obj) && obj.get("auth") is Some(String(header)) else {
    fail("no auth")
  }
  assert_eq(header, "Basic dTpw")
}

///|
async test "event hooks see the request and the response" {
  let seen : Array[String] = []
  let c = @requesto.Client::new(
    base_url="https://api.test",
    transport=@requesto.MockTransport::new(req => app(req)),
    event_hooks=@requesto.EventHooks::new(
      request=[req => seen.push("-> \{req.url}")],
      response=[
        res => {
          seen.push("<- \{res.status_code}")
          // httpx2's idiom: make every call raise on an error status.
          res.raise_for_status() |> ignore
        },
      ],
    ),
  )
  defer c.close()
  c.get("json") |> ignore
  let failed = error_of(() => c.get("nope"))
  assert_true(failed is Some(HTTPStatusError(_)))
  assert_eq(seen, [
    "-> https://api.test/json", "<- 200", "-> https://api.test/nope", "<- 404",
  ])
}

///|
async test "stream hands lines to a callback and closes after it" {
  let c = client()
  defer c.close()
  let lines : Array[String] = []
  let status = c.stream("GET", "lines", async fn(response) {
    response.raise_for_status() |> ignore
    response.each_line(line => lines.push(line))
    response.status_code
  })
  assert_eq(status, 200)
  assert_eq(lines, ["a", "b", "c"])
}

///|
async test "transport failures become httpx2-named variants keeping mttp's error" {
  let refused : &@mttp.Backend = @mttp_core_client.from_fn((_, _) => {
    raise @mttp_core.TransportError(
      kind=Connect,
      phase=Dial,
      detail="connection refused",
    )
  })
  let c = @requesto.Client::new(transport=refused)
  defer c.close()
  let result = error_of(() => c.get("https://api.test/"))
  guard result is Some(ConnectError(inner) as e) else {
    fail("expected ConnectError")
  }
  assert_true(e.is_transport_error())
  assert_false(e.is_timeout())
  assert_eq(inner.message(), "Connect during Dial: connection refused")
}

///|
async test "a header value mttp refuses fails before sending as InvalidRequest" {
  let c = @requesto.Client::new()
  defer c.close()
  let result = error_of(() => {
    c.get("https://example.invalid/", headers=[("x-note", " padded ")])
  })
  guard result is Some(InvalidRequest(inner)) else {
    fail("expected InvalidRequest")
  }
  let @mttp_core.TransportError(phase~, ..) = inner
  assert_eq(phase, Pool)
}
