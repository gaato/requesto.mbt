///|
/// A mock transport that records each request and answers 200 with `body`.
fn recorder(
  sent : Array[@requesto.Request],
  status~ : Int32 = 200,
  headers~ : Array[(String, String)] = [],
  body~ : Bytes = b"",
) -> @requesto.MockTransport {
  @requesto.MockTransport::new(request => {
    sent.push(request)
    { status, headers: @http.Headers::from_array(headers), body, }
  })
}

///|
async test "a call merges the client's defaults with its own arguments" {
  let sent = []
  let client = @requesto.Client::new(
    base_url="https://api.test/v1",
    headers=[("Accept", "application/json"), ("X-Team", "a")],
    params=[("key", "k"), ("lang", "en")],
    transport=recorder(sent),
  )
  let _ = client.get(
    "/users/42?fields=id#top",
    params=[("lang", "ja"), ("expand", "teams")],
    headers=[("x-team", "b"), ("X-Extra", "1")],
  )
  let request = sent[0]
  assert_eq(request.http_method, "GET")
  assert_eq(
    request.url,
    "https://api.test/v1/users/42?fields=id&key=k&lang=ja&expand=teams",
  )
  assert_eq(request.headers.iter().collect(), [
    ("user-agent", "requesto/0.2.3"),
    ("accept", "application/json"),
    ("x-team", "b"),
    ("x-extra", "1"),
  ])
  assert_eq(request.body, Bytes(b""))
}

///|
async test "client headers replace the default User-Agent" {
  let sent = []
  let client = @requesto.Client::new(
    headers=[("User-Agent", "mine/1")],
    transport=recorder(sent),
  )
  let _ = client.get("https://a.test/")
  assert_eq(sent[0].headers.get_all("user-agent"), ["mine/1"])
}

///|
async test "auth sets Authorization unless the call sets it" {
  let sent = []
  let cases : Array[(@requesto.Auth, Array[(String, String)], String)] = [
    (Bearer("t"), [], "Bearer t"),
    (Basic(username="u", password="p"), [], "Basic dTpw"),
    (
      Basic(username="Aladdin", password="open sesame"),
      [],
      "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==",
    ),
    (Basic(username="é", password=""), [], "Basic w6k6"),
    (Bearer("t"), [("Authorization", "Token x")], "Token x"),
  ]
  for case in cases {
    let client = @requesto.Client::new(auth=case.0, transport=recorder(sent))
    let _ = client.get("https://a.test/", headers=case.1)
    assert_eq(sent.last().unwrap().headers.get_all("authorization"), [case.2])
  }
}

///|
async test "each body kind reaches the transport with its Content-Type" {
  let sent = []
  let client = @requesto.Client::new(transport=recorder(sent))
  let _ = client.post("https://a.test/", json={ "a": [1, 2] })
  let _ = client.put("https://a.test/", data=[("q", "a b")])
  let _ = client.patch("https://a.test/", text="hé")
  let _ = client.request("DELETE", "https://a.test/", content=b"\x01")
  let parts = [@requesto.Part::text("a", "1")]
  let _ = client.post("https://a.test/", files=parts)
  let _ = client.post("https://a.test/")
  let expected : Array[(String, String?, Bytes?)] = [
    ("POST", Some("application/json"), Some(b"{\"a\":[1,2]}")),
    ("PUT", Some("application/x-www-form-urlencoded"), Some(b"q=a%20b")),
    ("PATCH", Some("text/plain; charset=utf-8"), Some(b"h\xc3\xa9")),
    ("DELETE", None, Some(b"\x01")),
    ("POST", Some("multipart/form-data"), None),
    ("POST", None, Some(b"")),
  ]
  for i, case in expected {
    let request = sent[i]
    assert_eq(request.http_method, case.0, msg="request \{i}")
    let content_type = request.headers
      .get("content-type")
      .map(value => value.split(";").next().unwrap().to_owned())
    let expected_type = case.1.map(value => {
      value.split(";").next().unwrap().to_owned()
    })
    assert_eq(content_type, expected_type, msg="request \{i}")
    if case.2 is Some(body) {
      assert_eq(request.body, Bytes(body), msg="request \{i}")
    }
  }
  let multipart = sent[4]
  let content_type = multipart.headers.get("content-type").unwrap()
  let boundary = content_type.split("boundary=").collect()[1].to_owned()
  assert_eq(multipart.body, Bytes(@multipart.encode(parts, boundary).1))
}

///|
async test "invalid calls raise the matching error and send nothing" {
  let sent = []
  let client = @requesto.Client::new(transport=recorder(sent))
  let based = @requesto.Client::new(
    base_url="https://a.test",
    transport=recorder(sent),
  )
  let calls : Array[
    (async () -> @requesto.Response raise @requesto.RequestoError, String),
  ] = [
    (
      () => client.post("https://a.test/", text="a", json=Json::null()),
      "InvalidRequest",
    ),
    (() => client.get("users/42"), "InvalidURL"),
    (() => based.get("ftp://b.test/"), "UnsupportedProtocol"),
    (() => client.get("https://"), "InvalidURL"),
    (() => client.request("GE T", "https://a.test/"), "InvalidRequest"),
  ]
  for call in calls {
    let outcome = try (call.0)() catch {
      InvalidRequest(..) => "InvalidRequest"
      InvalidURL(..) => "InvalidURL"
      UnsupportedProtocol(..) => "UnsupportedProtocol"
      error => "unexpected \{error}"
    } noraise {
      _ => "sent"
    }
    assert_eq(outcome, call.1)
  }
  assert_eq(sent.length(), 0)
}

///|
async test "verb shortcuts send their methods" {
  let sent = []
  let client = @requesto.Client::new(transport=recorder(sent))
  let url = "https://a.test/"
  let _ = client.get(url)
  let _ = client.head(url)
  let _ = client.options(url)
  let _ = client.delete(url)
  let _ = client.post(url)
  let _ = client.put(url)
  let _ = client.patch(url)
  let _ = client.request("purge", url)
  assert_eq(sent.map(request => request.http_method), [
    "GET", "HEAD", "OPTIONS", "DELETE", "POST", "PUT", "PATCH", "PURGE",
  ])
}

///|
async test "a response carries the status, headers, body, URL and request" {
  let sent = []
  let client = @requesto.Client::new(
    transport=recorder(
      sent,
      status=404,
      headers=[("Content-Type", "application/json")],
      body=b"{\"error\":\"missing\"}",
    ),
  )
  let response = client.get("https://a.test/x", params=[("q", "1")])
  assert_eq(response.status, 404)
  assert_eq(response.headers.get("content-type"), Some("application/json"))
  assert_eq(response.content(), b"{\"error\":\"missing\"}")
  assert_eq(response.json(), { "error": "missing" })
  assert_eq(response.url, "https://a.test/x?q=1")
  assert_true(physical_equal(response.request, sent[0]))
  assert_true(response.is_client_error())
  let status = try response.raise_for_status() catch {
    Status(response~, ..) => response.status
    error => fail("unexpected \{error}")
  } noraise {
    _ => fail("404 passed raise_for_status")
  }
  assert_eq(status, 404)
}

///|
async test "steps run in order around the transport" {
  let log = []
  let step = (name : String) => {
    (request : @requesto.Request, next : @requesto.Next) => {
      log.push("\{name} in")
      request.headers.append("x-step", name)
      let response = next(request)
      log.push("\{name} out \{response.status}")
      response
    }
  }
  let client = @requesto.Client::new(
    auth=Bearer("t"),
    steps=[
      @requesto.on_request(request => {
        log.push(
          "on_request \{request.headers.get("authorization").unwrap_or("-")}",
        )
      }),
      step("a"),
      step("b"),
      @requesto.on_response(response => {
        log.push(
          "on_response \{response.request.headers.get_all("x-step").join(",")}",
        )
      }),
    ],
    transport=@requesto.MockTransport::new(request => {
      log.push(
        "transport \{request.headers.get("authorization").unwrap_or("-")}",
      )
      { status: 204, headers: @http.Headers::new(), body: b"", }
    }),
  )
  let _ = client.get("https://a.test/")
  assert_eq(log, [
    "on_request -", "a in", "b in", "transport Bearer t", "on_response a,b", "b out 204",
    "a out 204",
  ])
}

///|
async test "a step can stop the call or send it twice" {
  let sent = []
  let refuse : @requesto.Step = (_, _) => {
    raise InvalidRequest(message="refused")
  }
  let client = @requesto.Client::new(steps=[refuse], transport=recorder(sent))
  let outcome = try client.get("https://a.test/") catch {
    InvalidRequest(message~) => message
    error => "unexpected \{error}"
  } noraise {
    _ => "sent"
  }
  assert_eq(outcome, "refused")
  assert_eq(sent.length(), 0)
  let twice : @requesto.Step = (request, next) => {
    let _ = next(request)
    next(request)
  }
  let client = @requesto.Client::new(steps=[twice], transport=recorder(sent))
  let _ = client.get("https://a.test/")
  assert_eq(sent.length(), 2)
}

///|
async test "hooks can raise, as raise_for_status does" {
  let client = @requesto.Client::new(
    steps=[
      @requesto.on_response(response => ignore(response.raise_for_status())),
    ],
    transport=recorder([], status=500),
    retry=@requesto.Retry::none(),
  )
  let outcome = try client.get("https://a.test/") catch {
    Status(response~, ..) => response.status
    error => fail("unexpected \{error}")
  } noraise {
    _ => 0
  }
  assert_eq(outcome, 500)
}

///|
async test "transport failures surface as error variants carrying the request" {
  let cases : Array[(@http.HttpError, String)] = [
    (Connect("refused"), "Network Dial refused"),
    (Timeout(phase=Head, ms=250), "Timeout Head 250"),
    (Network(phase=Write, message="reset"), "Network Write reset"),
    (Proxy(status=502, message="Bad Gateway"), "Proxy 502 Bad Gateway"),
    (
      Protocol("response body exceeds 10 bytes"),
      "Protocol response body exceeds 10 bytes",
    ),
  ]
  for case in cases {
    let client = @requesto.Client::new(
      transport=@requesto.MockTransport::new(_ => raise case.0),
      retry=@requesto.Retry::none(),
    )
    let outcome = try client.get("https://a.test/x") catch {
      Network(request~, phase~, message~) if request.url == "https://a.test/x" =>
        "Network \{@debug.to_string(phase)} \{message}"
      Timeout(request~, phase~, timeout~) if request.url == "https://a.test/x" =>
        "Timeout \{@debug.to_string(phase)} \{timeout}"
      Proxy(request~, status~, message~) if request.url == "https://a.test/x" =>
        "Proxy \{status} \{message}"
      Protocol(request~, message~) if request.url == "https://a.test/x" =>
        "Protocol \{message}"
      error => "unexpected \{error}"
    } noraise {
      _ => "sent"
    }
    assert_eq(outcome, case.1)
  }
}

///|
async test "credentials in a URL become Basic auth and leave the URL" {
  let sent : Array[@requesto.Request] = []
  let transport = @requesto.MockTransport::new(request => {
    sent.push(request)
    { status: 200, headers: @http.Headers::new(), body: b"", }
  })
  let client = @requesto.Client::new(transport~, auth=Bearer("client-token"))
  ignore(client.get("https://us%40er:p%3Ass@a.test/x"))
  ignore(
    client.get("https://u:p@a.test/y", headers=[("Authorization", "Token t")]),
  )
  ignore(client.get("https://a.test/z"))
  let based = @requesto.Client::new(
    transport~,
    base_url="https://u:p@a.test/v1",
  )
  ignore(based.get("items"))
  assert_eq(sent.map(r => r.url), [
    "https://a.test/x", "https://a.test/y", "https://a.test/z", "https://a.test/v1/items",
  ])
  assert_eq(sent.map(r => r.headers.get("authorization")), [
    Some("Basic dXNAZXI6cDpzcw=="),
    Some("Token t"),
    Some("Bearer client-token"),
    Some("Basic dTpw"),
  ])
}

///|
async test "error messages never show credentials from a URL" {
  let client = @requesto.Client::new(
    transport=@requesto.MockTransport::new(_ => {
      raise @http.HttpError::Connect("no")
    }),
    retry=@requesto.Retry::none(),
  )
  let messages = []
  for
    url in [
      "https://user:secret@a.test:99999/", "ftp://user:secret@a.test/", "https://user:secret@a.test/",
    ] {
    let message = try client.get(url) catch {
      error => error.to_string() + " " + @debug.to_string(error)
    } noraise {
      _ => "sent"
    }
    messages.push(message)
    assert_false(message.contains("secret"), msg=message)
  }
  assert_true(messages[0].contains("<redacted>@a.test"), msg=messages[0])
}
