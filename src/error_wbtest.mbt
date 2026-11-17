///|
/// A transport failure of `kind` in `phase`.
fn failure(kind : @mttp_core.Kind, phase : @mttp_core.Phase) -> HTTPError {
  from_mttp(local_error(kind, phase, "detail"))
}

///|
test "from_mttp names each kind and phase as httpx2 would" {
  let names = [
    (failure(Timeout(ms=1), Pool), "PoolTimeout"),
    (failure(Timeout(ms=1), Dial), "ConnectTimeout"),
    (failure(Timeout(ms=1), Write), "WriteTimeout"),
    (failure(Timeout(ms=1), Head), "ReadTimeout"),
    (failure(Timeout(ms=1), Body), "ReadTimeout"),
    (failure(Timeout(ms=1), Unknown), "TotalTimeout"),
    (failure(Connect, Dial), "ConnectError"),
    (failure(Network, Pool), "ConnectError"),
    (failure(Refused, Dial), "ConnectError"),
    (failure(Closed, Write), "WriteError"),
    (failure(IncompleteClose, Body), "ReadError"),
    (failure(Network, Head), "ReadError"),
    (failure(Protocol, Head), "ProtocolError"),
    (failure(Proxy(status=407), Dial), "ProxyError"),
    (failure(TooLarge(limit=9), Body), "TooLarge"),
    (failure(TooManyRedirects(max=2), Unknown), "TooManyRedirects"),
    (failure(RedirectRefused, Unknown), "RedirectRefused"),
    (failure(Invalid, Pool), "InvalidRequest"),
    (failure(Unreplayable, Write), "StreamClosed"),
  ]
  for pair in names {
    let (error, name) = pair
    let got = match error {
      PoolTimeout(_) => "PoolTimeout"
      ConnectTimeout(_) => "ConnectTimeout"
      WriteTimeout(_) => "WriteTimeout"
      ReadTimeout(_) => "ReadTimeout"
      TotalTimeout(_) => "TotalTimeout"
      ConnectError(_) => "ConnectError"
      WriteError(_) => "WriteError"
      ReadError(_) => "ReadError"
      ProtocolError(_) => "ProtocolError"
      ProxyError(_, status~) => if status == 407 { "ProxyError" } else { "?" }
      TooLarge(_, limit~) => if limit == 9 { "TooLarge" } else { "?" }
      TooManyRedirects(_) => "TooManyRedirects"
      RedirectRefused(_) => "RedirectRefused"
      InvalidRequest(_) => "InvalidRequest"
      StreamClosed(_) => "StreamClosed"
      _ => "?"
    }
    assert_eq(got, name)
    assert_true(error.is_transport_error() && error.is_request_error())
    assert_eq(error.mttp().map(e => e.message().contains("detail")), Some(true))
  }
}

///|
test "the predicates follow httpx2's class tree" {
  assert_true(failure(Timeout(ms=1), Head).is_timeout())
  assert_false(failure(Timeout(ms=1), Head).is_network_error())
  assert_true(failure(Network, Body).is_network_error())
  assert_true(failure(Connect, Dial).is_network_error())
  assert_true(failure(Closed, Write).is_network_error())
  assert_false(failure(Protocol, Head).is_network_error())
  let status = HTTPStatusError(sample_response(500))
  assert_false(status.is_request_error() || status.is_transport_error())
  assert_true(status.mttp() is None)
  let decoding : HTTPError = DecodingError("bad")
  assert_true(decoding.is_request_error())
  assert_false(decoding.is_transport_error() || decoding.is_timeout())
  assert_true(decoding.mttp() is None)
}

///|
test "an error prints its mttp diagnostic, or its status and URL" {
  inspect(failure(Protocol, Head), content="Protocol during Head: detail")
  inspect(
    HTTPStatusError(sample_response(503)),
    content="HTTPStatusError: 503 for https://api.test/",
  )
  inspect(
    (DecodingError("no JSON") : HTTPError),
    content="DecodingError: no JSON",
  )
}

///|
async test "lift names an mttp failure that is not a TransportError" {
  let raised = try {
    lift(() => (fail("budget spent") : Unit))
    None
  } catch {
    TransportError(e) => Some(e.message())
    _ => None
  }
  guard raised is Some(message) else { fail("expected TransportError") }
  assert_true(message.contains("budget spent"))
}
