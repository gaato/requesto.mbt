///|
/// Answers with the request's method, its Content-Type and its body.
fn echo_app(req : @mttp.Request) -> @mttp.Response {
  let content_type = req.headers.get("content-type").unwrap_or("")
  let body = @utf8.decode_lossy(req.body.as_bytes().unwrap_or(b""))
  @mttp.Response::new(
    200,
    body=Bytes(@utf8.encode("\{req.meth} \{content_type}\n\{body}")),
  )
}

///|
async test "every verb sends its method, and the body verbs their body" {
  let c = @requesto.Client::new(
    base_url="https://api.test",
    transport=@requesto.MockTransport::new(req => echo_app(req)),
  )
  defer c.close()
  assert_eq(c.get("x").text(), "GET \n")
  assert_eq(c.head("x").status_code, 200)
  assert_eq(c.options("x").text(), "OPTIONS \n")
  assert_eq(c.delete("x").text(), "DELETE \n")
  assert_eq(c.post("x", text="a").text(), "POST text/plain; charset=utf-8\na")
  // Raw bytes carry no Content-Type, as in httpx2.
  assert_eq(c.put("x", content=b"b").text(), "PUT \nb")
  assert_eq(
    c.patch("x", data=[("k", "v w")]).text(),
    "PATCH application/x-www-form-urlencoded\nk=v+w",
  )
  assert_eq(c.request("PURGE", "x").text(), "PURGE \n")
}

///|
async test "files sends a multipart body with data as its text fields" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => echo_app(req)),
  )
  defer c.close()
  let text = c
    .post("https://api.test/upload", data=[("note", "hi")], files=[
      @requesto.Part::file("doc", "a.txt", "text/plain", b"hello"),
    ])
    .text()
  assert_true(text.has_prefix("POST multipart/form-data; boundary=requesto-"))
  assert_true(text.contains("name=\"note\"\r\n\r\nhi\r\n"))
  assert_true(
    text.contains(
      "name=\"doc\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n",
    ),
  )
}

///|
/// A Digest-protected resource: a 401 with a challenge until the request
/// carries a Digest answer for user "u".
fn digest_app(req : @mttp.Request) -> @mttp.Response {
  match req.headers.get("authorization") {
    Some(auth) if auth.has_prefix("Digest ") && auth.contains("username=\"u\"") =>
      @mttp.Response::new(200, body=Bytes(b"in"))
    _ =>
      @mttp.Response::new(
        401,
        headers=@mttp.Headers::of([
          (
            "www-authenticate", "Digest realm=\"r\", nonce=\"n0\", qop=\"auth\", algorithm=SHA-256",
          ),
        ]),
      )
  }
}

///|
async test "Digest answers a challenge, per client and per call" {
  let c = @requesto.Client::new(
    base_url="https://a.test",
    auth=Digest("u", "p"),
    transport=@requesto.MockTransport::new(req => digest_app(req)),
  )
  defer c.close()
  assert_eq(c.get("secret").text(), "in")
  let plain = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => digest_app(req)),
  )
  defer plain.close()
  assert_eq(plain.get("https://a.test/secret").status_code, 401)
  assert_eq(
    plain.get("https://a.test/secret", auth=Digest("u", "p")).text(),
    "in",
  )
}

///|
async test "Digest credentials are not answered after a redirect to another origin" {
  let c = @requesto.Client::new(
    auth=Digest("u", "p"),
    follow_redirects=true,
    transport=@requesto.MockTransport::new(req => {
      if req.url.has_prefix("https://a.test/") {
        @mttp.Response::new(
          302,
          headers=@mttp.Headers::of([("location", "https://b.test/secret")]),
        )
      } else {
        digest_app(req)
      }
    }),
  )
  defer c.close()
  let r = c.get("https://a.test/start")
  assert_eq(r.url, "https://b.test/secret")
  assert_eq(r.status_code, 401)
}

///|
async test "each_event hands server-sent events to a callback" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(_ => {
      @mttp.Response::new(
        200,
        headers=@mttp.Headers::of([("content-type", "text/event-stream")]),
        body=Bytes(b"data: one\n\nevent: tick\ndata: two\n\n"),
      )
    }),
  )
  defer c.close()
  let seen : Array[String] = []
  c.stream("GET", "https://api.test/events", async fn(r) {
    r.each_event(event => seen.push("\{event.event}:\{event.data}"))
  })
  assert_eq(seen, ["message:one", "tick:two"])
}

///|
async test "each_bytes, read and raise_for_status on a streamed response" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => {
      if req.url.contains("missing") {
        @mttp.Response::new(404)
      } else {
        @mttp.Response::new(200, body=Bytes(b"abc"))
      }
    }),
  )
  defer c.close()
  let read = c.stream("GET", "https://api.test/", async fn(r) { r.read() })
  assert_eq(read, b"abc")
  let total = Ref(0)
  c.stream("GET", "https://api.test/", async fn(r) {
    r.each_bytes(chunk => total.val += chunk.length())
  })
  assert_eq(total.val, 3)
  let failed = c.stream("GET", "https://api.test/missing", async fn(r) {
    error_of(() => r.raise_for_status())
  })
  guard failed is Some(HTTPStatusError(response)) else {
    fail("expected HTTPStatusError")
  }
  assert_eq(response.status_code, 404)
  assert_eq(response.request.url, "https://api.test/missing")
}

///|
async test "the client keeps cookies across calls, and cookies=false drops them" {
  let handler = (req : @mttp.Request) => {
    if req.url.contains("/set") {
      @mttp.Response::new(
        200,
        headers=@mttp.Headers::of([("set-cookie", "session=s1; Path=/")]),
      )
    } else {
      @mttp.Response::new(
        200,
        body=Bytes(@utf8.encode(req.headers.get("cookie").unwrap_or("-"))),
      )
    }
  }
  let kept = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => handler(req)),
  )
  defer kept.close()
  kept.get("https://api.test/set") |> ignore
  assert_eq(kept.get("https://api.test/check").text(), "session=s1")
  let dropped = @requesto.Client::new(
    cookies=false,
    transport=@requesto.MockTransport::new(req => handler(req)),
  )
  defer dropped.close()
  dropped.get("https://api.test/set") |> ignore
  assert_eq(dropped.get("https://api.test/check").text(), "-")
}

///|
async test "status predicates and reason phrases" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => {
      let status = if req.url.contains("teapot") { 418 } else { 599 }
      @mttp.Response::new(status)
    }),
  )
  defer c.close()
  let teapot = c.get("https://api.test/teapot")
  assert_true(teapot.is_client_error() && teapot.is_error())
  assert_false(teapot.is_success() || teapot.is_redirect())
  assert_eq(teapot.reason_phrase(), "I'm a teapot")
  let odd = c.get("https://api.test/odd")
  assert_true(odd.is_server_error())
  assert_eq(odd.reason_phrase(), "")
}

///|
async test "json and json_as raise DecodingError for a body that does not fit" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => {
      let body = if req.url.contains("broken") { b"{" } else { b"[1]" }
      @mttp.Response::new(200, body=Bytes(body))
    }),
  )
  defer c.close()
  assert_true(
    error_of(() => c.get("https://api.test/broken").json())
    is Some(DecodingError(_)),
  )
  let mismatch = error_of(() => {
    let user : User = c.get("https://api.test/list").json_as()
    user
  })
  assert_true(mismatch is Some(DecodingError(_)))
}

///|
async test "the top-level functions send through a client of their own" {
  // A header value mttp refuses fails before any connection is made, so
  // each function is exercised without a network.
  let bad = [("x-note", " padded ")]
  let url = "https://example.invalid/"
  let calls : Array[async () -> Unit raise @requesto.HTTPError] = [
    () => @requesto.get(url, headers=bad) |> ignore,
    () => @requesto.head(url, headers=bad) |> ignore,
    () => @requesto.options(url, headers=bad) |> ignore,
    () => @requesto.delete(url, headers=bad) |> ignore,
    () => @requesto.post(url, headers=bad, text="a") |> ignore,
    () => @requesto.put(url, headers=bad, content=b"a") |> ignore,
    () => @requesto.patch(url, headers=bad, json={ "a": 1 }) |> ignore,
    () => @requesto.request("PURGE", url, headers=bad) |> ignore,
  ]
  for call in calls {
    assert_true(error_of(call) is Some(InvalidRequest(_)))
  }
  let streamed = any_error_of(() => {
    @requesto.stream("GET", url, r => r.status_code, headers=bad)
  })
  assert_true(streamed is Some(@requesto.InvalidRequest(_)))
}

///|
async test "client headers, mttp(), stream hooks and errors from the caller's code" {
  let seen : Array[String] = []
  let c = @requesto.Client::new(
    headers=[("x-client", "1")],
    event_hooks=@requesto.EventHooks::new(request=[req => seen.push(req.url)]),
    transport=@requesto.MockTransport::new(req => {
      @mttp.Response::new(
        200,
        body=Bytes(@utf8.encode(req.headers.get("x-client").unwrap_or("-"))),
      )
    }),
  )
  defer c.close()
  assert_eq(c.get("https://api.test/a").text(), "1")
  // The mttp client underneath sends with the same defaults.
  let reply = c.mttp().send(@mttp.get("https://api.test/b"))
  assert_eq(reply.body, Ok("1"))
  let own = any_error_of(() => {
    c.stream("GET", "https://api.test/c", _ => (fail("mine") : Unit))
  })
  guard own is Some(Failure(message)) else { fail("expected the Failure") }
  assert_true(message.contains("mine"))
  assert_eq(seen, ["https://api.test/a", "https://api.test/c"])
}

///|
async test "a multipart part mttp cannot encode fails as InvalidRequest" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => echo_app(req)),
  )
  defer c.close()
  let failed = error_of(() => {
    c.post("https://api.test/upload", files=[
      @requesto.Part::file("doc", "a.txt", "text/plain\r\nx: y", b"v"),
    ])
  })
  assert_true(failed is Some(InvalidRequest(_)))
}

///|
async test "cookie_jar shares one jar between clients" {
  let jar = @mttp.CookieJar::new(@mttp.clock())
  let handler = (req : @mttp.Request) => {
    if req.url.contains("/set") {
      @mttp.Response::new(
        200,
        headers=@mttp.Headers::of([("set-cookie", "shared=1; Path=/")]),
      )
    } else {
      @mttp.Response::new(
        200,
        body=Bytes(@utf8.encode(req.headers.get("cookie").unwrap_or("-"))),
      )
    }
  }
  let first = @requesto.Client::new(
    cookie_jar=jar,
    transport=@requesto.MockTransport::new(req => handler(req)),
  )
  defer first.close()
  let second = @requesto.Client::new(
    cookie_jar=jar,
    transport=@requesto.MockTransport::new(req => handler(req)),
  )
  defer second.close()
  first.get("https://api.test/set") |> ignore
  assert_eq(second.get("https://api.test/check").text(), "shared=1")
}

///|
/// Plays a network backend: reports a dial and the later phases of each
/// exchange to the request's `on_phase`, and redirects `/old` to `/new`.
fn phase_app(req : @mttp.Request) -> @mttp.Response {
  if req.attributes.get(@mttp.on_phase) is Some(report) {
    report(Dialed(addr="api.test:443"))
    report(Pooled(reused=false))
    report(Written)
    report(FirstByte)
  }
  if req.url.has_suffix("/old") {
    @mttp.Response::new(
      302,
      headers=@mttp.Headers::of([("location", "https://api.test/new")]),
    )
  } else {
    @mttp.Response::new(200, body=Bytes(b"ok"))
  }
}

///|
async test "trace sees each attempt's phases, across a redirect" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => phase_app(req)),
  )
  defer c.close()
  let seen : Array[@requesto.PhaseEvent] = []
  let r = c.get("https://api.test/old", follow_redirects=true, trace=event => {
    seen.push(event)
  })
  assert_eq(r.text(), "ok")
  let one : Array[@requesto.PhaseEvent] = [
    Dialed(addr="api.test:443"),
    Pooled(reused=false),
    Written,
    FirstByte,
  ]
  assert_eq(seen, [..one, ..one])
  // A call without trace carries no callback.
  seen.clear()
  c.get("https://api.test/new") |> ignore
  assert_eq(seen.length(), 0)
  // A streamed call traces the same way.
  c.stream("GET", "https://api.test/new", trace=event => seen.push(event), async fn(
    response,
  ) {
    assert_eq(response.read(), b"ok")
  })
  assert_eq(seen, one)
}
