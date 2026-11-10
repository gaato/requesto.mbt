///|
test "defaults: 30 s per exchange, 64 MiB per buffered body, a versioned User-Agent" {
  assert_eq(default_timeout, 30_000)
  assert_eq(default_max_body_bytes, 64 * 1024 * 1024)
  assert_eq(user_agent, "requesto/0.2.3")
  let client = Client::new()
  assert_eq(client.timeout, 30_000)
  assert_true(client.total_timeout is None, msg="derived per call")
  assert_eq(client.total_budget(None, 30_000, Retry::new()), Some(150_000))
  assert_eq(client.total_budget(None, 30_000, Retry::none()), Some(60_000))
  assert_eq(client.total_budget(None, 600_000, Retry::new()), Some(3_000_000))
  assert_eq(
    client.total_budget(None, transport_ceiling_ms, Retry::new()),
    Some(transport_ceiling_ms),
    msg="capped at Int32 max",
  )
  assert_eq(client.total_budget(Some(None), 30_000, Retry::new()), None)
  assert_eq(default_idle_timeout, 300_000)
  assert_true(client.owned is Some(_))
  assert_eq(client.headers.get("user-agent"), Some(user_agent))
  client.close()
}

///|
test "check_method accepts HTTP tokens" {
  let cases : Array[(String, Bool)] = [
    ("GET", true),
    ("get", true),
    ("M-SEARCH", true),
    ("X!#$%&'*+.^_`|~9", true),
    ("", false),
    ("GE T", false),
    ("GET\r\n", false),
    ("GÉT", false),
    ("(GET)", false),
  ]
  for case in cases {
    let accepted = try check_method(case.0) catch {
      InvalidRequest(message~) => {
        assert_eq(message, "invalid method: \{case.0}")
        false
      }
      error => fail("unexpected \{error}")
    } noraise {
      _ => true
    }
    assert_eq(accepted, case.1, msg=case.0)
  }
}

///|
test "build: an explicit Content-Type wins over the body's" {
  let transport = MockTransport::new(_ => {
    raise @http.HttpError::Protocol("not sent")
  })
  let client = Client::new(transport~, headers=[("X-Client", "1")])
  let cases : Array[(Array[(String, String)], String?)] = [
    ([], Some("application/json")),
    (
      [("content-type", "application/vnd.api+json")],
      Some("application/vnd.api+json"),
    ),
  ]
  for case in cases {
    let request = client.build(
      "post",
      "https://a.test/x",
      [],
      case.0,
      JsonValue(Json::null()),
    )
    assert_eq(request.http_method, "POST")
    assert_eq(request.headers.get("content-type"), case.1)
    assert_eq(request.headers.get_all("content-type").length(), 1)
    assert_eq(request.body, Bytes(b"null"))
  }
  let client = Client::new(transport~, headers=[("Content-Type", "text/csv")])
  let request = client.build("POST", "https://a.test/x", [], [], Text("a,b"))
  assert_eq(request.headers.get("content-type"), Some("text/csv"))
}

///|
test "Auth debug output redacts secrets" {
  assert_eq(
    @debug.to_string(Basic(username="u", password="p")),
    "Basic(username=\"u\", password=<redacted>)",
  )
  assert_eq(@debug.to_string(Bearer("t")), "Bearer(<redacted>)")
  assert_eq(
    @debug.to_string(Digest(username="u", password="p")),
    "Digest(username=\"u\", password=<redacted>)",
  )
}
