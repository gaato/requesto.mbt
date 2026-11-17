# Migrating from requesto 0.2 to 0.3

requesto 0.3 is rebuilt on [mttp](https://github.com/gaato/mttp) and follows
httpx2's names and defaults. It runs on `moonbitlang/core/async`, where 0.2
ran on `moonbitlang/async`; a program cannot use both runtimes, so move the
whole program at once. core/async is experimental: each package that imports
it needs `options("allow-experimental-packages": ["moonbitlang/core/async"])`
in its `moon.pkg`, and the event loop starts with `@mttp.run` or an
`async fn main`.

## Names

| 0.2 | 0.3 |
|---|---|
| `response.status` | `response.status_code` |
| `RequestoError` | `HTTPError` |
| `Timeout(phase=Dial, ..)`, `Timeout(phase=Body, ..)`, … | `ConnectTimeout`, `ReadTimeout`, `WriteTimeout`, `PoolTimeout` |
| `TotalTimeout(..)` | `TotalTimeout(_)` |
| `Network(phase~, ..)` | `ConnectError`, `ReadError`, `WriteError` |
| `Protocol(..)` | `ProtocolError`, or `TooLarge` for a body over `max_body_bytes` |
| `Proxy(..)` | `ProxyError(_, status~)` |
| `TooManyRedirects(..)` | `TooManyRedirects(_)`; a https-to-http redirect is `RedirectRefused` |
| `InvalidURL(..)`, `InvalidRequest(..)`, `UnsupportedProtocol(..)` | `InvalidRequest(_)` |
| `StreamConsumed(..)` | `StreamClosed(_)` |
| `Decoding(..)` | `DecodingError(message)` |
| `Status(response~, ..)` | `HTTPStatusError(response)` |
| `is_timeout()`, `is_transport_error()` | the same, plus `is_network_error()` and `is_request_error()` |
| `timeout=30_000` | `timeout=Timeout::new(Some(30_000))`, or one phase: `Timeout::new(Some(5_000), read=Some(30_000))` |
| `retry=Retry::new(..)`, `Retry::none()` | `retry=@mttp.RetryPolicy::conservative()`, the default `RetryPolicy::none()` |
| `cookies=Jar(jar)`, `cookies=Off` | `cookie_jar=jar` (an `@mttp.CookieJar`), `cookies=false`; `cookies=true`, the default, gives the client a jar of its own |
| `steps=[..]`, `on_request`, `on_response` | `event_hooks=EventHooks::new(request=[..], response=[..])`, or a `transport` that wraps another `@mttp.Backend` |
| `transport=MockTransport::new(f)` | `transport=MockTransport::new(handler)`, where `handler` has the type of an mttp server handler |
| `clock=` | `clock=` and `timer=`, such as `@runtime.VirtualClock` from `gaato/mttp/runtime` |
| `Client::stream(.., response => ..)` | `Client::stream(.., async fn(response) { .. })`, with a `StreamResponse` |
| `response.each_chunk(f)` | `response.each_bytes(f)` |
| `Client::sse(..)`, `sse(..)` | `client.stream(.., async fn(r) { r.each_event(f) })` |
| `max_connections=`, `max_idle_per_origin=` | `limits=Limits::new(max_connections=.., max_keepalive_connections=..)` |
| `connect_timeout=`, `read_timeout=`, … | the phases of `Timeout` |
| `proxy=` | `proxy=`; `trust_env=` keeps its meaning |
| `files=[Part::..]`, `auth=Digest(..)` | the same |

## Defaults that differ

- **Redirects are not followed** unless `follow_redirects=true` is set on
  the client or the call; 0.2 followed up to 10. Up to 20 are followed when
  asked.
- **Nothing is retried** unless `retry=` is set; 0.2 retried idempotent
  requests on transient failures by default (`max_retries` 3).
- **Timeouts are per phase**: 5 s each for connecting, reading, writing and
  waiting for a connection. 0.2 bounded each exchange at 30 s and the whole
  call at `(max_retries + 2) × timeout`; 0.3 has no whole-call deadline
  unless `total_timeout` sets one.
- **Lines** read with `each_line` are bounded at 1 MiB by default (0.2:
  16 MiB); pass `max_line_bytes=` for longer ones.
- **Event streams** have no separate idle timeout: each read is bounded by
  the read timeout (5 s by default). Raise `Timeout`'s `read` for a stream
  whose keep-alives come less often.
- **Raw `content=` bytes** are sent without a `Content-Type`, as in httpx2.
