///|
test "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" {
  assert_eq(default_phase_timeout_ms, 5000)
  assert_eq(default_max_redirects, 20)
  assert_eq(default_max_body_bytes, 64 * 1024 * 1024)
  assert_eq(default_max_line_bytes, 1024 * 1024)
  assert_eq(default_max_event_bytes, 16 * 1024 * 1024)
  assert_eq(user_agent, "requesto/\{version}")
  let config = network_config(
    Timeout::new(Some(default_phase_timeout_ms)),
    Limits::new(),
    None,
    false,
    _ => None,
  )
  assert_eq(config.connect_timeout_ms, Some(5000))
  assert_eq(config.read_timeout_ms, Some(5000))
  assert_eq(config.write_timeout_ms, Some(5000))
  assert_eq(config.pool_timeout_ms, Some(5000))
  assert_eq(config.max_connections, Some(100))
  assert_eq(config.max_idle_connections, 20)
  assert_eq(config.idle_max_ms, 5000)
  assert_eq(config.proxy, @h1client.ProxyConfig::none())
  let c = Client::new()
  defer c.close()
  assert_eq(c.max_body_bytes, default_max_body_bytes)
  assert_false(c.follow_redirects)
}

///|
test "Timeout::new sets one phase apart, and proxies come from proxy or the environment" {
  let config = network_config(
    Timeout::new(Some(10_000), connect=Some(5_000), pool=None),
    Limits::new(max_connections=None),
    None,
    true,
    name => {
      if name == "HTTPS_PROXY" {
        Some("http://proxy.test:3128")
      } else {
        None
      }
    },
  )
  assert_eq(config.connect_timeout_ms, Some(5000))
  assert_eq(config.read_timeout_ms, Some(10_000))
  assert_eq(config.pool_timeout_ms, None)
  assert_eq(config.max_connections, None)
  assert_eq(
    config.proxy,
    @h1client.ProxyConfig::from_env(name => {
      if name == "HTTPS_PROXY" {
        Some("http://proxy.test:3128")
      } else {
        None
      }
    }),
  )
  let fixed = network_config(
    Timeout::new(None),
    Limits::new(),
    Some("http://p.test:8080"),
    true,
    _ => Some("http://ignored.test"),
  )
  assert_eq(fixed.proxy, @h1client.ProxyConfig::fixed("http://p.test:8080"))
  assert_eq(fixed.read_timeout_ms, None)
}

///|
test "a client keeps max_digest_sessions Digest sessions and drops the oldest" {
  let layer = DigestLayer::new(
    @client.from_handler(_ => @mttp.Response::new(200)),
  )
  for i in 0..<(max_digest_sessions + 1) {
    layer.session(("https://h\{i}.test", "u", "p")) |> ignore
  }
  assert_eq(layer.sessions.length(), max_digest_sessions)
  assert_false(layer.sessions.contains(("https://h0.test", "u", "p")))
  assert_true(
    layer.sessions.contains(("https://h\{max_digest_sessions}.test", "u", "p")),
  )
}

///|
test "origin_of keeps scheme, host and port, and refuses a relative URL" {
  assert_eq(origin_of("https://a.test/x?y"), "https://a.test")
  assert_eq(origin_of("http://a.test:8080/x"), "http://a.test:8080")
  let refused = try {
    origin_of("/relative") |> ignore
    false
  } catch {
    InvalidRequest(_) => true
    _ => false
  }
  assert_true(refused)
}

///|
test "is_informational and the reason phrase of a 1xx" {
  let r = sample_response(103)
  assert_true(r.is_informational())
  assert_eq(r.reason_phrase(), "Early Hints")
}

///|
/// A buffered response with `status` and no body.
fn sample_response(status : Int32) -> Response {
  {
    status_code: status,
    headers: @mttp_core.Headers::empty(),
    url: "https://api.test/",
    content: b"",
    request: {
      meth: Get,
      url: "https://api.test/",
      headers: @mttp_core.Headers::empty(),
    },
    history: [],
    elapsed: 0,
  }
}

///|
test "every registered status has its reason phrase" {
  let registered = [
    100, 101, 102, 103, 200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301,
    302, 303, 304, 305, 307, 308, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409,
    410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 425, 426, 428,
    429, 431, 451, 500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511,
  ]
  for status in registered {
    assert_true(reason_phrase(status) != "", msg="no phrase for \{status}")
  }
  assert_eq(reason_phrase(200), "OK")
  assert_eq(reason_phrase(404), "Not Found")
  assert_eq(reason_phrase(306), "")
  assert_eq(sample_response(503).reason_phrase(), "Service Unavailable")
}

///|
test "origin_of refuses a URL it cannot parse" {
  let refused = try {
    origin_of("http://[::1") |> ignore
    false
  } catch {
    InvalidRequest(_) => true
    _ => false
  }
  assert_true(refused)
}
