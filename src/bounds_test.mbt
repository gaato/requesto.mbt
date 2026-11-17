///|
/// A body of `n` bytes for any request.
fn sized(n : Int32) -> @requesto.MockTransport {
  @requesto.MockTransport::new(_ => {
    @mttp.Response::new(200, body=Bytes(Bytes::make(n, b'x')))
  })
}

///|
async test "a buffered body holds max_body_bytes and refuses one more" {
  let fits = @requesto.Client::new(max_body_bytes=10, transport=sized(10))
  defer fits.close()
  assert_eq(fits.get("https://api.test/").content.length(), 10)
  let over = @requesto.Client::new(max_body_bytes=10, transport=sized(11))
  defer over.close()
  let failed = error_of(() => over.get("https://api.test/"))
  guard failed is Some(TooLarge(_, limit~)) else { fail("expected TooLarge") }
  assert_eq(limit, 10)
}

///|
async test "read holds max_body_bytes of a streamed body and refuses one more" {
  let fits = @requesto.Client::new(max_body_bytes=10, transport=sized(10))
  defer fits.close()
  let body = fits.stream("GET", "https://api.test/", async fn(r) { r.read() })
  assert_eq(body.length(), 10)
  let over = @requesto.Client::new(max_body_bytes=10, transport=sized(11))
  defer over.close()
  let failed = over.stream("GET", "https://api.test/", async fn(r) {
    error_of(() => r.read())
  })
  assert_true(failed is Some(TooLarge(_, ..)))
}

///|
async test "each_line holds max_line_bytes of a line and refuses one more" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(_ => {
      @mttp.Response::new(200, body=Bytes(b"1234\n12345\nnever"))
    }),
  )
  defer c.close()
  let lines : Array[String] = []
  let failed = c.stream("GET", "https://api.test/", async fn(r) {
    any_error_of(() => r.each_line(line => lines.push(line), max_line_bytes=4))
  })
  assert_eq(lines, ["1234"])
  guard failed is Some(@requesto.TooLarge(_, limit~)) else {
    fail("expected TooLarge")
  }
  assert_eq(limit, 4)
}

///|
async test "each_event holds max_event_bytes of an event and refuses one more" {
  let c = @requesto.Client::new(
    transport=@requesto.MockTransport::new(_ => {
      @mttp.Response::new(
        200,
        body=Bytes(b"data: 1234\n\ndata: 123456789\n\ndata: never\n\n"),
      )
    }),
  )
  defer c.close()
  let seen : Array[String] = []
  let failed = c.stream("GET", "https://api.test/", async fn(r) {
    any_error_of(() => r.each_event(e => seen.push(e.data), max_event_bytes=12))
  })
  assert_eq(seen, ["1234"])
  assert_true(failed is Some(@requesto.TooLarge(_, ..)))
}

///|
/// `/hop/<n>` redirects to `/hop/<n - 1>`; `/hop/0` answers.
fn hops(req : @mttp.Request) -> @mttp.Response {
  // One digit is enough for these tests.
  let n = req.url[req.url.length() - 1].to_int() - '0'.to_int()
  if n == 0 {
    @mttp.Response::new(200)
  } else {
    @mttp.Response::new(
      302,
      headers=@mttp.Headers::of([("location", "/hop/\{n - 1}")]),
    )
  }
}

///|
async test "follow_redirects follows max_redirects hops and refuses one more" {
  let c = @requesto.Client::new(
    base_url="https://api.test",
    follow_redirects=true,
    max_redirects=3,
    transport=@requesto.MockTransport::new(req => hops(req)),
  )
  defer c.close()
  let r = c.get("hop/3")
  assert_eq(r.status_code, 200)
  assert_eq(r.history.length(), 3)
  let failed = error_of(() => c.get("hop/4"))
  assert_true(failed is Some(TooManyRedirects(_)))
}

///|
async test "total_timeout ends a call that is still running, on virtual time" {
  let clock = @runtime.VirtualClock(start_ms=0L)
  let slow : &@mttp.Backend = @mttp_core_client.from_fn((_, _) => {
    clock.sleep(1_000_000)
    @mttp.Response::new(200)
  })
  let c = @requesto.Client::new(transport=slow, clock~, total_timeout=1000)
  defer c.close()
  let result : Ref[@requesto.HTTPError??] = Ref(None)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      result.val = Some(error_of(() => c.get("https://api.test/")))
    })
    clock.settle(until=() => clock.next_deadline() == Some(1000L))
    assert_true(clock.advance_to_next())
    clock.settle(until=() => result.val is Some(_))
  })
  guard result.val is Some(Some(TotalTimeout(_) as e)) else {
    fail("expected TotalTimeout")
  }
  assert_true(e.is_timeout())
}
