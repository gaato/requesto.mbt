# Migrating from requesto to mttp

requesto is no longer developed. Its replacement is a set of modules from
[gaato/mttp](https://github.com/gaato/mttp):

- `gaato/mttp`: the client (`gaato/mttp/client`), with retries, rate limits,
  redirects, cookies, multipart, SSE and typed response readers.
- `gaato/http-async`: the network backend (`AsyncBackend`), clocks and timers
  on `moonbitlang/core/async`.
- `gaato/http`: the shared types (`Request`, `Response`, `Headers`, `Url`,
  `TransportError`) and the `Backend` trait.
- `gaato/mttp_digest`: Digest authentication, if you used it.

requesto runs on `moonbitlang/async`; the replacement runs on
`moonbitlang/core/async`. A program cannot use both runtimes, so move the
whole program at once. core/async is experimental: each package that imports
it needs `options("allow-experimental-packages": ["moonbitlang/core/async"])`
in its `moon.pkg`.

## A minimal client

```moonbit
let client = @client.Client::new(
  @backend.AsyncBackend::new(),   // gaato/http-async/backend
  @runtime.AsyncClock::new(),     // gaato/http-async/runtime
  timeout_ms=30_000,
  timer=@runtime.ClockTimer::new(),
)
defer client.close()
let reply = @client.get("https://example.com/").send(client)
match reply.body {
  Ok(text) => println(text)
  Err(failure) => println("HTTP \{failure.head().status}")
}
```

## Feature map

| requesto | Replacement |
|---|---|
| Top-level verbs (`get`, `post`, …) | `@client.get(url)` / `@client.post(url)` / `@client.request(@http.Request::new(...))`, sent with `.send(client)` |
| `Client` with defaults | `@client.Client::new(backend, clock, base_url?, headers?, timeout_ms?, ...)` |
| Base URL, query, headers | `base_url~` and `headers~` on the client; `@http.Request::query`, `.header` on a request |
| Basic and Bearer auth | `@http.Request::basic` / `bearer`, or `RequestPlan::bearer` |
| Bytes, text, JSON and form bodies | `@http.Request::body_bytes`, `body_text`, `body_json`, `body_form` |
| Multipart and file uploads | `gaato/mttp/multipart` (`body`, `encode_body`) |
| Streaming uploads | `@http.Request::body_stream`; `RequestPlan::body_fn` supplies a fresh body for each retry |
| Response as a value, `raise_for_status()` | A reply's `body` is a `Result`: `Ok` for an accepted status, `Err(ResponseFailure)` otherwise. Choose the reader with `.response(...)`: `as_string`, `as_bytes`, `as_json`, `as_json_value`, `as_form`, `ignore_body` |
| Streaming responses | `as_stream`; the stream is valid only inside its callback |
| SSE and lines | `as_sse` / `as_lines`; set `read_idle_ms` explicitly |
| Redirects and history | `@client.FollowRedirects::new(backend)`; the final URL and the hops are the reply attributes `final_url` and `redirect_history` |
| Cookie jar | `@cookies.Cookies::new(backend, @cookie.CookieJar::new(clock))` |
| Digest authentication | `gaato/mttp_digest`: `DigestScheme::new(backend, user, password, origin~, random~)` |
| Retries | `retry~ : @client.RetryPolicy` (`default`, `conservative`, `none`, `from_rule`) |
| Per-attempt and total timeouts | `timeout_ms~` and `total_ms~` on the client; a total deadline needs `timer~` |
| Body size limits | `max_body_bytes~` on the client or a request; `AsyncBackend::new(config~)` bounds the bytes on the wire |
| Proxies and connection limits | `AsyncBackend::new(config~ : @h1client.ClientConfig)`; on JS the host's `fetch` handles them |
| TLS trust | `AsyncBackend::new(trust~ : @http_async.Trust)` |
| Steps and hooks | Wrap a backend with `@client.from_fn`; observe attempts with `observer~` |
| Mock transport | `@testing.BackendStub` (`gaato/mttp/testing`), or `@client.from_handler` |
| Virtual clock | `@runtime.VirtualClock` |
| `RequestoError` | `@http.TransportError` for the connection and protocol, `ResponseFailure` for a rejected status or an unreadable body |

## Defaults that differ

- **Retries and cookies are off unless you add them.** requesto retried and
  kept cookies by default. Pass `retry~` and wrap the backend in `Cookies`
  when you want them.
- **Redirects are a wrapper.** Use
  `Client::new(FollowRedirects::new(Cookies::new(AsyncBackend::new(), jar)), clock, ...)`
  for requesto's behaviour. A retry starts the whole request again,
  including any redirects it followed, where requesto retried each hop.
- **requesto's derived total timeout is gone.** requesto defaulted the total
  budget to `(max_retries + 2) × timeout`. Set `total_ms~` yourself.
- **Body limits are explicit.** The client reads at most 64 MiB of a body by
  default, counted after decompression.
- **Text is decoded lossily.** `as_string` replaces malformed UTF-8 with
  U+FFFD. Read `as_bytes` and decode it yourself if you need to reject it.
- **There are no `elapsed` or `retries` fields on a response.** Use
  `observer~`, which receives every attempt with its duration and decision.
