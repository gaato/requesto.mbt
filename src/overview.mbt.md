# gaato/requesto

HTTP calls for MoonBit written the way httpx2 (and requests) users write
them: verb functions, a client with defaults, responses as values,
`raise_for_status()`, streaming in a scope, event hooks and a mock transport.
Underneath it is [gaato/mttp](https://mooncakes.io/docs/gaato/mttp), which
does the HTTP; requesto only adds the surface and its defaults.

The name is "request" as Japanese speakers tend to say it: リクエスト,
*rikuesuto*.

> **Status**: unofficial and experimental. While the version is 0.x, a minor
> release may contain breaking changes; the
> [changelog](https://github.com/gaato/requesto.mbt/blob/main/CHANGELOG.md)
> lists each one with a migration note.

## Install

```sh
moon add gaato/requesto
```

requesto runs on `moonbitlang/core/async`, which is experimental: a package
that imports it needs
`options("allow-experimental-packages": ["moonbitlang/core/async"])` in its
`moon.pkg`. Start the event loop with `@mttp.run` or an `async fn main`.

## Usage

```mbt check
///|
#derive(FromJson)
struct Account {
  id : Int32
  name : String
}

///|
pub async fn example() -> Unit raise @requesto.HTTPError {
  let client = @requesto.Client::new(
    base_url="https://api.example.com/v1",
    headers=[("Accept", "application/json")],
    auth=Bearer("token"),
  )
  defer client.close()
  let user : Account = client
    .get("users/42", params=[("expand", "teams")])
    .raise_for_status()
    .json_as()
  println("user \{user.id}: \{user.name}")
  client.post("users", json={ "name": user.name }) |> ignore
}
```

A response is a value whatever its status. `raise_for_status()` raises
`HTTPStatusError` for anything outside 200–299 and otherwise returns the
response, so calls chain. Every failure is an `HTTPError`; its variants are
httpx2's exception names (`ConnectTimeout`, `ReadTimeout`, `ConnectError`,
`TooManyRedirects`, `HTTPStatusError`, …), with `is_timeout()` and
`is_transport_error()` in place of the class tree, and `mttp()` returns the
`@mttp.TransportError` underneath.

### Bodies and auth

Each call takes one body: `content=` bytes, `text=`, `data=` as a form,
`json=`, or `files=` with `data=` as the text fields of a multipart body.
`auth=` takes `Basic(user, password)`, `Bearer(token)` or
`Digest(user, password)`, on the client or on one call. A Digest challenge
is answered only for the origin the request was built for, never after a
redirect to another.

```mbt check
///|
pub async fn upload(
  client : @requesto.Client,
) -> Unit raise @requesto.HTTPError {
  client
  .post(
    "reports",
    data=[("title", "weekly")],
    files=[@requesto.Part::file("file", "week.csv", "text/csv", b"a,b\n")],
    auth=Digest("user", "password"),
  )
  .raise_for_status()
  |> ignore
}
```

### Streaming

`client.stream` passes a response whose body is still on the connection to a
function, and closes it when the function returns. Read it whole with
`read()`, or piece by piece with `each_bytes`, `each_line` or, for
server-sent events, `each_event`:

```mbt check
///|
pub async fn follow(client : @requesto.Client) -> Unit {
  client.stream("GET", "events", async fn(response) {
    response.raise_for_status() |> ignore
    response.each_event(event => println("\{event.event}: \{event.data}"))
  })
}
```

A line longer than 1 MiB or an event longer than 16 MiB raises `TooLarge`
(`max_line_bytes=`, `max_event_bytes=` change it).

### Tracing

`trace=` on a call, httpx2's `trace` extension, is called with each point
an attempt reaches on the connection: `Dialed(addr~)`, `TlsDone`,
`Pooled(reused~)`, `Written` and `FirstByte`, for every attempt, redirects
included. The native and wasm network reports them; the JS host's fetch
reports none.

```mbt check
///|
pub async fn timed(client : @requesto.Client) -> Unit raise @requesto.HTTPError {
  client.get("status", trace=event => println(@debug.to_string(event)))
  |> ignore
}
```

### Testing without a network

`MockTransport::new` takes a handler of the same type an mttp server serves,
so a client can call your app directly, as httpx2's `ASGITransport` does:

```mbt check
///|
fn hello_app(_ : @mttp.Request) -> @mttp.Response {
  @mttp.Response::new(200, body=Bytes(b"hello"))
}

///|
async test "the app answers" {
  let client = @requesto.Client::new(
    transport=@requesto.MockTransport::new(req => hello_app(req)),
  )
  defer client.close()
  assert_eq(client.get("https://app.test/").text(), "hello")
}
```

## Coming from httpx2

| httpx2 | requesto |
|---|---|
| `httpx2.get(url, params=..., headers=...)` | `@requesto.get(url, params=[...], headers=[...])` |
| `httpx2.Client(base_url=..., auth=...)` | `@requesto.Client::new(base_url=..., auth=Bearer(...))` |
| `content=b"..."` / `content="..."` | `content=b"..."` / `text="..."` |
| `r.status_code`, `r.text`, `r.json()` | `r.status_code`, `r.text()`, `r.json()`, or `r.json_as()` into a type |
| `with client.stream(...) as r:` | `client.stream(..., async fn(r) { ... })` |
| `r.iter_bytes()`, `r.iter_lines()` | `r.each_bytes(f)`, `r.each_line(f)` |
| `httpx_sse`'s `iter_sse()` | `r.each_event(f)` |
| `files={"file": ("a.csv", data, "text/csv")}` | `files=[Part::file("file", "a.csv", "text/csv", data)]` |
| `auth=("user", "pw")`, `DigestAuth("user", "pw")` | `auth=Basic("user", "pw")`, `auth=Digest("user", "pw")` |
| `Limits(max_connections=100)` | `limits=Limits::new(max_connections=Some(100))` |
| `proxy="http://..."`, `trust_env=False` | `proxy="http://..."`, `trust_env=false` |
| `verify=False`, `verify="ca.pem"` | `trust=Insecure`, `trust=PemFile("ca.pem")` |
| `Timeout(10.0, connect=5.0)` | `Timeout::new(Some(10_000), connect=Some(5_000))` (milliseconds) |
| `event_hooks={"request": [...], "response": [...]}` | `event_hooks=EventHooks::new(request=[...], response=[...])` |
| `extensions={"trace": log}` | `trace=event => ...` |
| `MockTransport(handler)` | `MockTransport::new(handler)` |
| `except httpx2.HTTPError` | `catch { e => ... }` on `HTTPError` |

`HTTPError` and `status_code` keep httpx2's spelling rather than MoonBit's
usual `HttpError` and mttp's `status`, so names can be guessed from httpx2.

## Defaults

The same as httpx2's: redirects are not followed (`follow_redirects=true` on
the client or one call follows up to 20), nothing is retried (`retry=` takes
an `@mttp.RetryPolicy`), each phase — connect, read, write, pool — has 5 s,
the pool holds up to 100 connections and keeps 20 idle for 5 s, the client
keeps cookies in a jar of its own (`cookie_jar=` shares one), proxies come
from `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY`, and there is no deadline for
the whole call (`total_timeout=` sets one). On JavaScript the host's `fetch` handles connections, proxies and
TLS itself.

One difference: a buffered body is limited to 64 MiB after decompression
(`max_body_bytes=`), and a larger one fails with `TooLarge` instead of
filling memory. Read larger bodies with `stream`.

Text is decoded as UTF-8, with malformed sequences replaced by U+FFFD; read
`content` for other encodings. Raw `content=` bytes are sent without a
`Content-Type`, as in httpx2.

## Using mttp alongside

Types that need no sugar are mttp's own: `@mttp.Request`, `@mttp.Response`,
`@mttp.Headers`, `@mttp.RetryPolicy`, `&@mttp.Backend`. `client.mttp()`
returns the mttp client underneath, and `build_request` gives the
`@mttp.Request` a call would send. Typed endpoints, routers, OpenAPI and
servers are mttp's; use it directly for those.

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/requesto.mbt/blob/main/LICENSE).
