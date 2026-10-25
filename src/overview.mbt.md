# gaato/requesto

An async HTTP client for MoonBit: verb functions, a client with defaults, body
encoders, and responses as values. It runs on the native, JavaScript and
moonrun Wasm backends.

The name is "request" as Japanese speakers tend to say it: リクエスト,
*rikuesuto*.

> **Status**: unofficial and experimental. While the version is 0.x, a minor
> release may contain breaking changes; the
> [changelog](https://github.com/gaato/requesto.mbt/blob/main/CHANGELOG.md)
> lists each one with a migration note.

> **Unreleased deprecation notice:** new HTTP work is moving to
> [mttp](https://github.com/gaato/mttp). The replacement is being validated in
> local workspaces and has not been published by this change. Existing
> requesto releases remain usable. See the
> [migration guide](https://github.com/gaato/requesto.mbt/blob/main/MIGRATION.md)
> for API and default-behavior differences before switching.

## Install

```sh
moon add gaato/requesto
```

## Usage

Make a client with the defaults every call shares, then call verbs on it. A
response is a value whatever its status; `raise_for_status()` turns a non-2xx
one into an error.

```mbt check
///|
struct User {
  id : Int32
  name : String
} derive(FromJson)

///|
pub async fn example() -> Unit {
  let client = @requesto.Client::new(
    base_url="https://api.example.com/v1",
    headers=[("Accept", "application/json")],
    auth=Bearer("token"),
  )
  defer client.close()
  let user : User = client
    .get("users/42", params=[("expand", "teams")])
    .raise_for_status()
    .json_as()
  println("user \{user.id}: \{user.name}")
  client.post("users", json={ "name": user.name }) |> ignore
  println(@requesto.get("https://example.com/").text())
}
```

## What it does

- `get`, `post`, `put`, `patch`, `delete`, `head`, `options` and `request`, on
  a `Client` or as top-level functions.
- Client defaults: `base_url` (always appended to), `headers`, `params`
  (merged into any query already in the URL), `auth` (`Basic`, `Bearer`,
  `Digest`), `timeout`, `retry`.
- One body per call: `content` (bytes), `text`, `data` (form), `files`
  (multipart, `@requesto.Part`), `json` or `body_stream`.
- A response is a value whatever its status; `raise_for_status()` turns
  non-2xx into `RequestoError::Status`.
- Retries: idempotent methods on 408, 429, 500, 502, 503, 504 and transport
  failures, any method when nothing was sent; `Retry-After` is honoured, else
  backoff with jitter. A wait the client will not make returns the response
  as it is; `response.retries` counts the sends after the first.
  `retry=Retry::none()` turns retries off.
- Redirects are followed, credentials dropped across origins, never `https`
  to `http`, with `history`; `follow_redirects=false` per client or call.
- Cookies are kept per client in an RFC 6265 jar, `client.cookies()`;
  `cookies=Jar(jar)` shares one, `cookies=Off` keeps none.
- Streaming both ways: `stream` hands over the response while its body is
  still arriving (`read_some`, `each_chunk`, `each_line`); `body_stream` and
  `Part::file_stream` send a body as it is read.
- Server-sent events: `client.sse("GET", url, event => ...)`, or `each_event`
  on a streamed response.
- URLs are checked and normalised before sending; `@requesto.Url` takes
  response URLs apart and resolves links.
- `proxy` (or `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`) and connection limits
  (`max_connections`, `max_connections_per_origin`).
- `steps`, links of the chain around the transport, with `on_request` and
  `on_response` hooks.

On JavaScript, `fetch` follows redirects before the client sees them, and in
browsers handles cookies itself.

## Limits and timeouts

Every call is bounded by default. Each limit below can be changed: on the
client, and `timeout`, `total_timeout`, `retry` and the stream limits per
call too. The doc comments of `Client::new`, `Retry::new`, `Client::sse`
and `Response::each_line` describe them. Times are in milliseconds.

- `timeout`: 30 s per exchange (one send and its buffered response).
- `total_timeout`: `max_retries + 2` exchanges' worth (150 s by default) for a
  whole call with its redirects and retries; `None` lifts it.
- `connect_timeout`, `write_timeout`, `read_timeout`, `pool_timeout`: unset by
  default, so only `timeout` applies.
- `max_body_bytes`: 64 MiB per buffered body; `None` lifts it.
- `max_event_bytes` and `max_line_bytes`: 16 MiB per server-sent event or line.
- `idle_timeout` on `sse`: 5 minutes for the next bytes after the head.
- `max_redirects`: 10 in a row.
- `Retry::new`: 3 retries, `Retry-After` honoured up to 60 s
  (`max_retry_after`).

A timeout raises `RequestoError::Timeout` or `RequestoError::TotalTimeout`; a
body over its limit raises `RequestoError::Protocol`.

## Testing

Swap the transport for a `MockTransport`, and the clock for `VirtualClock`
from `gaato/http-async/mock`, so tests need no sockets and no real sleeps:

```mbt check
///|
async test "a client answered by a mock transport" {
  let client = @requesto.Client::new(
    base_url="https://api.example.com/v1",
    transport=@requesto.MockTransport::new(request => {
      status: 200,
      headers: @http.Headers::new(),
      body: b"hello from \{request.url}",
    }),
  )
  defer client.close()
  let response = client.get("users/42").raise_for_status()
  assert_eq(response.text(), "hello from https://api.example.com/v1/users/42")
}
```

## Coming from

| | requests / httpx | axios / ky | Req | gaato/requesto |
|---|---|---|---|---|
| Call | `httpx.get(url, params=...)` | `ky.get(url, {searchParams})` | `Req.get!(url, params: ...)` | `@requesto.get(url, params=[...])` |
| Client | `httpx.Client(base_url=...)` | `axios.create({baseURL})` | `Req.new(base_url: ...)` | `@requesto.Client::new(base_url=...)` |
| JSON body | `json=...` | `json: ...` (ky) | `json: ...` | `json=...` |
| Non-2xx | value, `raise_for_status()` | throws | value | value, `raise_for_status()` |
| Read JSON | `.json()` | `.json()` / `data` | `.body` | `.json()`, `.json_as()` |
| Redirects | `follow_redirects=`, `.history` | `maxRedirects` / `redirect` | `redirect:`, `max_redirects:` | `follow_redirects=`, `max_redirects=`, `.history` |
| Cookies | `client.cookies` | the browser's | — | `client.cookies()`, `cookies=Jar(jar)` |
| Streaming | `client.stream(...)`, `iter_lines()` | `responseType: 'stream'` | `into: fun` | `client.stream(...)`, `each_line` |
| SSE | `httpx_sse.connect_sse` | `EventSource` | — | `client.sse(...)`, `each_event` |
| Timeouts | `httpx.Timeout(connect=...)` | `timeout`, `totalTimeout` (ky) | `receive_timeout:` | `timeout=`, `total_timeout=`, `connect_timeout=`, ... |
| Proxy | `proxy=` | `proxy` (axios) | `connect_options:` | `proxy=`, `trust_env` |
| Hooks | `event_hooks` | interceptors / hooks | steps | `steps=[on_request(...), ...]` |
| Retries | `HTTPAdapter(max_retries=Retry(...))` (off) | `retry` (ky, on) | `retry: :safe_transient` (on) | `retry=Retry::new(...)` (on) |
| Digest | `HTTPDigestAuth` / `DigestAuth` | — | — | `auth=Digest(username=u, password=p)` |
| Mock | `httpx.MockTransport` | — | `Req.Test` | `@requesto.MockTransport` |

## Links

- [Changelog](https://github.com/gaato/requesto.mbt/blob/main/CHANGELOG.md)
- [Repository](https://github.com/gaato/requesto.mbt)
- [Resource bounds](https://github.com/gaato/requesto.mbt/blob/main/RESOURCE_BOUNDS.md):
  every limit a client enforces, and what happens past it

## License

Apache-2.0. See
[LICENSE](https://github.com/gaato/requesto.mbt/blob/main/LICENSE).
