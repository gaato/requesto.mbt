///|
test "join_url appends to the base URL unless the URL is absolute" {
  let cases : Array[(String?, String, String)] = [
    (None, "https://a.test/x", "https://a.test/x"),
    (None, "users", "users"),
    (Some("https://a.test/v1"), "users", "https://a.test/v1/users"),
    (Some("https://a.test/v1/"), "/users", "https://a.test/v1/users"),
    (Some("https://a.test/v1//"), "//users/42", "https://a.test/v1/users/42"),
    (Some("https://a.test/v1"), "", "https://a.test/v1"),
    (Some("https://a.test/v1/"), "/", "https://a.test/v1"),
    (Some("https://a.test/v1"), "?page=2", "https://a.test/v1?page=2"),
    (Some("https://a.test/v1"), "http://b.test/y", "http://b.test/y"),
    (Some("https://a.test/v1"), "ftp://b.test/y", "ftp://b.test/y"),
    (Some("https://a.test"), "users:42", "https://a.test/users:42"),
    (Some("https://a.test/v1?key=x"), "users", "https://a.test/v1/users?key=x"),
    (
      Some("https://a.test/v1/?key=x"),
      "users?page=2",
      "https://a.test/v1/users?key=x&page=2",
    ),
    (
      Some("https://a.test/v1?"),
      "users?page=2",
      "https://a.test/v1/users?page=2",
    ),
    (Some("https://a.test/v1?key=x"), "users?", "https://a.test/v1/users?key=x"),
    (Some("https://a.test/v1#top"), "users", "https://a.test/v1/users"),
    (Some("https://a.test/v1?key=x#top"), "", "https://a.test/v1?key=x"),
    (Some("https://a.test/v1"), "users#frag", "https://a.test/v1/users"),
    (
      Some("https://a.test/v1?key=x"),
      "users#frag",
      "https://a.test/v1/users?key=x",
    ),
  ]
  for case in cases {
    let (base, url, expected) = case
    assert_eq(
      join_url(base, url),
      expected,
      msg="\{base.unwrap_or("-")} + \{url}",
    )
  }
}

///|
test "scheme_length accepts RFC 3986 schemes before ://" {
  let cases : Array[(String, Int32?)] = [
    ("https://a.test", Some(5)),
    ("HTTP://a.test", Some(4)),
    ("svn+ssh://a.test", Some(7)),
    ("a1.-+://x", Some(5)),
    ("://a.test", None),
    ("1http://a.test", None),
    ("ht tp://a.test", None),
    ("users/http://a.test", None),
    ("users", None),
    ("mailto:a@b.test", None),
  ]
  for case in cases {
    assert_eq(scheme_length(case.0), case.1, msg=case.0)
  }
}

///|
test "merge_params lets the call's names replace the client's" {
  let cases : Array[
    (Array[(String, String)], Array[(String, String)], Array[(String, String)]),
  ] = [
    ([], [], []),
    ([("a", "1")], [], [("a", "1")]),
    ([], [("a", "1")], [("a", "1")]),
    ([("a", "1"), ("b", "2")], [("b", "3")], [("a", "1"), ("b", "3")]),
    (
      [("a", "1"), ("a", "2"), ("c", "0")],
      [("a", "9"), ("a", "8")],
      [("c", "0"), ("a", "9"), ("a", "8")],
    ),
  ]
  for case in cases {
    assert_eq(merge_params(case.0, case.1), case.2)
  }
}

///|
test "build adds parameters after the existing query and drops the fragment" {
  let client = Client::new(
    transport=MockTransport::new(_ => {
      raise @http.HttpError::Protocol("not sent")
    }),
  )
  let cases : Array[(String, Array[(String, String)], String)] = [
    ("https://a.test/x", [], "https://a.test/x"),
    ("https://a.test/x", [("q", "1")], "https://a.test/x?q=1"),
    ("https://a.test/x?a=1", [("q", "1")], "https://a.test/x?a=1&q=1"),
    ("https://a.test/x?a=1", [("a", "2")], "https://a.test/x?a=1&a=2"),
    ("https://a.test/x?", [("q", "1")], "https://a.test/x?q=1"),
    ("https://a.test/x?a=1&", [("q", "1")], "https://a.test/x?a=1&q=1"),
    ("https://a.test/x#top", [], "https://a.test/x"),
    ("https://a.test/x?a=1#top", [("q", "1")], "https://a.test/x?a=1&q=1"),
    ("https://a.test/x?#top", [], "https://a.test/x?"),
    (
      "https://a.test/x",
      [("a b", "c&d=e"), ("é", "/?#")],
      "https://a.test/x?a%20b=c%26d%3De&%C3%A9=%2F%3F%23",
    ),
    ("https://a.test/x", [("q", "1"), ("r", "")], "https://a.test/x?q=1&r="),
  ]
  for case in cases {
    let request = client.build("GET", case.0, case.1, [], Empty)
    assert_eq(request.url, case.2, msg=case.0)
  }
}

///|
test "build normalises the URL it sends" {
  let client = Client::new(
    transport=MockTransport::new(_ => {
      raise @http.HttpError::Protocol("not sent")
    }),
  )
  let cases : Array[(String, String)] = [
    ("HTTPS://Example.COM:443/a/./b/../c", "https://example.com/a/c"),
    ("http://a.test:80/", "http://a.test/"),
    ("http://a.test:8080/", "http://a.test:8080/"),
    ("http://a.test?x", "http://a.test?x"),
    ("http://[::1]/", "http://[::1]/"),
    ("http://[2001:DB8:0:0:0:0:0:1]:8080/x", "http://[2001:db8::1]:8080/x"),
    ("https://user:p%40ss@a.test/x", "https://a.test/x"),
    ("https://us\u{e9}r@a.test/", "https://a.test/"),
    ("https://a.test/caf\u{e9}?q=\u{e9}", "https://a.test/caf%C3%A9?q=%C3%A9"),
    ("https://a.test/a%20b?c%26d", "https://a.test/a%20b?c%26d"),
    ("https://a.test/{x}|\"<>", "https://a.test/%7Bx%7D|%22%3C%3E"),
    ("https://a.test/x#a%20b", "https://a.test/x"),
    ("https://a.test/x#", "https://a.test/x"),
  ]
  for case in cases {
    let request = client.build("GET", case.0, [], [], Empty)
    assert_eq(request.url, case.1, msg=case.0)
  }
  // Userinfo leaves the URL as Basic auth, decoded: "user:p@ss", "usér:".
  let auth = ["https://user:p%40ss@a.test/x", "https://us\u{e9}r@a.test/"].map(url => {
    client.build("GET", url, [], [], Empty).headers.get("authorization")
  })
  assert_eq(auth, [Some("Basic dXNlcjpwQHNz"), Some("Basic dXPDqXI6")])
}

///|
test "parse_url accepts absolute HTTP URLs with a host" {
  let cases : Array[(String, String)] = [
    ("https://a.test", "ok"),
    ("HTTP://a.test:8080/x?y#z", "ok"),
    ("http://a.test?x", "ok"),
    ("http://[::1]/", "ok"),
    ("ftp://a.test/", "unsupported"),
    ("ws://a.test/", "unsupported"),
    ("users/42", "invalid: not an absolute URL"),
    ("", "invalid: not an absolute URL"),
    ("http:/a.test", "invalid: not an absolute URL"),
    ("https://", "invalid: no host"),
    ("https:///x", "invalid: no host"),
    ("https://?q", "invalid: no host"),
    ("https://#f", "invalid: no host"),
    ("https://a.test/a b", "invalid: contains a space or control character"),
    ("https://a.test/\n", "invalid: contains a space or control character"),
    ("https://a.test/\u{7f}", "invalid: contains a space or control character"),
    ("http://[::1/", "invalid: IP literal without a closing bracket"),
    ("http://[fe80::1%25eth0]/", "invalid: IP literal is not IPv6"),
    ("http://[v1.x]/", "invalid: IP literal is not IPv6"),
    ("http://[::1]x/", "invalid: unexpected character after an IP literal"),
    ("http://a.test:99999/", "invalid: port exceeds 65535"),
    ("http://a.test:8o/", "invalid: port is not a number"),
    ("http://a.test:/", "ok"),
    ("http://user@/", "invalid: no host"),
    (
      "http://ex\u{e4}mple.test/", "invalid: non-ASCII host; pass its IDNA (xn--) form",
    ),
    ("http://a_b.test/", "ok"),
    ("http://a%41.test/", "invalid: host contains \"%\""),
  ]
  for case in cases {
    let (url, expected) = case
    let actual = try parse_url(url) catch {
      UnsupportedProtocol(url=u) => {
        assert_eq(u, url)
        "unsupported"
      }
      InvalidURL(url=u, message~) => {
        assert_eq(u, url)
        "invalid: \{message}"
      }
      error => "unexpected \{error}"
    } noraise {
      _ => "ok"
    }
    assert_eq(actual, expected, msg=url)
  }
}

///|
test "merge_headers replaces every value of a name the overrides use" {
  let base = @http.Headers::from_array([
    ("User-Agent", "a"),
    ("Accept", "x"),
    ("Accept", "y"),
    ("X-Keep", "1"),
  ])
  let cases : Array[(Array[(String, String)], Array[(String, String)])] = [
    (
      [],
      [("user-agent", "a"), ("accept", "x"), ("accept", "y"), ("x-keep", "1")],
    ),
    ([("ACCEPT", "z")], [("user-agent", "a"), ("x-keep", "1"), ("accept", "z")]),
    (
      [("X-New", "1"), ("x-new", "2"), ("User-Agent", "b")],
      [
        ("accept", "x"),
        ("accept", "y"),
        ("x-keep", "1"),
        ("x-new", "1"),
        ("x-new", "2"),
        ("user-agent", "b"),
      ],
    ),
  ]
  for case in cases {
    let merged = merge_headers(base, case.0)
    assert_eq(merged.iter().collect(), case.1)
  }
  assert_eq(base.length(), 4, msg="the base is not changed")
}

///|
test "userinfo splits at the first colon and is percent-decoded" {
  let cases : Array[(String, (String, String))] = [
    ("user:pass", ("user", "pass")),
    ("user", ("user", "")),
    ("user:", ("user", "")),
    (":pass", ("", "pass")),
    ("u:p:q", ("u", "p:q")),
    ("a%40b:p%3Aq", ("a@b", "p:q")),
    ("%E3%81%82:%F0%9F%94%91", ("あ", "🔑")),
    ("100%:%zz%4", ("100%", "%zz%4")),
    ("%ff:x", ("\u{fffd}", "x")),
    ("%E3:x", ("\u{fffd}", "x")),
    ("u%E3%81:%E3%81%82%E3", ("u\u{fffd}", "あ\u{fffd}")),
    ("u%2:p%2", ("u%2", "p%2")),
    ("%E3%2:%2%41", ("\u{fffd}%2", "%2A")),
  ]
  for case in cases {
    assert_eq(split_userinfo(case.0), case.1, msg=case.0)
  }
}

///|
test "userinfo is taken out of a URL that has it" {
  let cases : Array[(String, String?, String)] = [
    ("https://u:p@a.test/x?q", Some("u:p"), "https://a.test/x?q"),
    ("http://u@[::1]:8080/", Some("u"), "http://[::1]:8080/"),
    ("https://a.test/u:p@x", None, "https://a.test/u:p@x"),
    ("https://a.test/", Some("u:p"), "https://a.test/"),
  ]
  for case in cases {
    assert_eq(without_userinfo(case.0, case.1), case.2, msg=case.0)
  }
}

///|
test "redact_url hides the userinfo of the authority only" {
  let cases : Array[(String, String)] = [
    ("https://u:p@a.test/x", "https://<redacted>@a.test/x"),
    ("https://u:p@a.test", "https://<redacted>@a.test"),
    ("https://u@p@a.test/x?y@z", "https://<redacted>@a.test/x?y@z"),
    ("https://a.test/x@y", "https://a.test/x@y"),
    ("https://a.test?u@v", "https://a.test?u@v"),
    ("not a url", "not a url"),
    ("//u:p@a.test/", "//<redacted>@a.test/"),
  ]
  for case in cases {
    assert_eq(redact_url(case.0), case.1, msg=case.0)
  }
}
