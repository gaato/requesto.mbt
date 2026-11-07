///|
test "status predicates split the status classes" {
  // informational, success, redirect, client error, server error, error
  let cases : Array[(Int32, (Bool, Bool, Bool, Bool, Bool, Bool))] = [
    (99, (false, false, false, false, false, false)),
    (100, (true, false, false, false, false, false)),
    (199, (true, false, false, false, false, false)),
    (200, (false, true, false, false, false, false)),
    (299, (false, true, false, false, false, false)),
    (300, (false, false, true, false, false, false)),
    (399, (false, false, true, false, false, false)),
    (400, (false, false, false, true, false, true)),
    (499, (false, false, false, true, false, true)),
    (500, (false, false, false, false, true, true)),
    (599, (false, false, false, false, true, true)),
    (600, (false, false, false, false, false, false)),
  ]
  for case in cases {
    let response = sample_response(case.0)
    assert_eq(
      (
        response.is_informational(),
        response.is_success(),
        response.is_redirect(),
        response.is_client_error(),
        response.is_server_error(),
        response.is_error(),
      ),
      case.1,
      msg="status \{case.0}",
    )
  }
}

///|
test "raise_for_status returns 2xx responses and raises for every other status" {
  let cases : Array[(Int32, Bool)] = [
    (100, false),
    (101, false),
    (200, true),
    (201, true),
    (204, true),
    (299, true),
    (301, false),
    (304, false),
    (404, false),
    (500, false),
    (600, false),
  ]
  for case in cases {
    let (status, returned) = case
    let response = sample_response(status)
    let outcome = try response.raise_for_status() catch {
      Status(request~, response=r) => {
        assert_true(physical_equal(request, response.request))
        assert_true(physical_equal(r, response))
        false
      }
      error => fail("unexpected \{error}")
    } noraise {
      r => {
        assert_true(physical_equal(r, response))
        true
      }
    }
    assert_eq(outcome, returned, msg="status \{status}")
  }
}

///|
fn with_content(content : Bytes) -> Response {
  Response::new(200, sample_request(), content~)
}

///|
test "text decodes UTF-8 leniently" {
  let cases : Array[(Bytes, String)] = [
    (b"", ""),
    (b"h\xc3\xa9llo", "héllo"),
    (b"a\xffb", "a\u{fffd}b"),
  ]
  for case in cases {
    assert_eq(with_content(case.0).text(), case.1)
  }
}

///|
#derive(Eq, Debug, FromJson)
priv struct Point {
  x : Int32
  y : Int32
}

///|
test "json and json_as decode the body or raise Decoding" {
  assert_eq(with_content(b"{\"x\":1,\"y\":2}").json(), { "x": 1, "y": 2 })
  let point : Point = with_content(b"{\"x\":1,\"y\":2}").json_as()
  assert_eq(point, { x: 1, y: 2, })
  let failures : Array[(Bytes, String)] = [
    (b"\xff", "the body is not valid UTF-8"),
    (b"{", "parse"),
    (b"{\"x\":1}", "convert"),
  ]
  for case in failures {
    let message = try {
      let _ : Point = with_content(case.0).json_as()
      "decoded"
    } catch {
      Decoding(message~) => message
      error => "unexpected \{error}"
    }
    match case.1 {
      "parse" =>
        assert_true(
          message != "decoded" && message != "the body is not valid UTF-8",
          msg=message,
        )
      "convert" => assert_true(message.contains("y"), msg=message)
      expected => assert_eq(message, expected)
    }
  }
}
