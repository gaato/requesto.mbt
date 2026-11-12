# Migrating from requesto to mttp

requesto is no longer developed. Its replacement is
[gaato/mttp](https://github.com/gaato/mttp), a family of two modules:

- [`gaato/mttp`](https://mooncakes.io/docs/gaato/mttp): the module an
  application adds. It runs on `moonbitlang/core/async` and re-exports the
  types (`Request`, `Response`, `Body`, `Headers`, `Method`, `Url`,
  `TransportError`, `Backend`), the client (`client()`, `get`, `post`,
  `request`, the response readers, `RetryPolicy`, `RetryBudget`,
  `RedirectConfig`, `CookieJar`) and the runtime (`backend()`, `clock()`,
  `timer()`, `run`).
- [`gaato/mttp_core`](https://mooncakes.io/docs/gaato/mttp_core): the
  module a library (an SDK, say) adds. It has no I/O and no runtime. Typed
  endpoints, the router, OpenAPI, multipart, rate limiters and the testing
  stubs live here.
- `gaato/mttp_digest`: Digest authentication, if you used it.

The family was renamed in November 2026. Older notes and releases call
`gaato/mttp_core` "gaato/mttp" 0.2 (and before that "gaato/http"), and call
`gaato/mttp` "gaato/mttp_async" 0.1 (and before that "gaato/http-async").
Everything below uses the current names.

requesto runs on `moonbitlang/async`; the replacement runs on
`moonbitlang/core/async`. A program cannot use both runtimes, so move the
whole program at once. core/async is experimental: each package that imports
it needs `options("allow-experimental-packages": ["moonbitlang/core/async"])`
in its `moon.pkg`.

## A minimal client

```moonbit
async fn main {
  let client = @mttp.client(timeout_ms=30_000)
  defer client.close()
  let reply = @mttp.get("https://example.com/").send(client)
  match reply.body {
    Ok(text) => println(text)
    Err(failure) => println("HTTP \{failure.head().status}")
  }
}
```

`@mttp.client()` builds the default backend, clock and timer for you. Pass
`backend?`, `clock?` or `timer?` to replace any of them.

## Feature map

| requesto | Replacement |
|---|---|
| Top-level verbs (`get`, `post`, …) | `@mttp.get(url)` / `@mttp.post(url)` / `@mttp.request(@mttp.Request::new(...))`, sent with `.send(client)` |
| `Client` with defaults | `@mttp.client(base_url?, headers?, timeout_ms?, total_ms?, max_body_bytes?, retry?, retry_budget?, redirect?, limiter?, cookies?, ...)` |
| Base URL, query, headers | `base_url~` and `headers~` on the client; `Request::query`, `Request::header` on a request |
| Basic and Bearer auth | `Request::basic` / `Request::bearer`, or `RequestPlan::bearer` |
| Bytes, text, JSON and form bodies | `Request::body_bytes`, `body_text`, `body_json`, `body_form` |
| Multipart and file uploads | `gaato/mttp_core/multipart` (`body`, `encode_body`, `Part`) |
| Streaming uploads | `Request::body_stream`; `RequestPlan::body_fn` supplies a fresh body for each retry |
| Response as a value, `raise_for_status()` | A reply's `body` is a `Result`: `Ok` for an accepted status, `Err(ResponseFailure)` otherwise. Choose the reader with `.response(...)`: `@mttp.as_string`, `as_bytes`, `as_json`, `as_json_value`; `as_form` and `ignore_body` are in `gaato/mttp_core/client` |
| Streaming responses | `as_stream` (`gaato/mttp_core/client`); the stream is valid only inside its callback |
| SSE and lines | `@mttp.as_sse` / `@mttp.as_lines`; set `read_idle_ms` explicitly (`RequestPlan::read_idle_ms`) |
| Redirects and history | `redirect~ : @mttp.RedirectConfig` (`default`, `none`; on by default); the final URL and the hops are the reply attributes `final_url` and `redirect_history` (`gaato/mttp_core/client`) |
| Cookie jar | `cookies~ : @mttp.CookieJar`, made with `@mttp.CookieJar::new(@mttp.clock())` |
| Digest authentication | `gaato/mttp_digest`: `DigestScheme::new(backend, user, password, origin~, random~)` |
| Retries | `retry~ : @mttp.RetryPolicy` (`default`, `conservative`, `none`, `from_rule`), with `retry_budget~ : @mttp.RetryBudget` |
| Per-attempt and total timeouts | `timeout_ms~` and `total_ms~` on the client |
| Rate limits | `limiter~` on the client; `gaato/mttp_core/client/ratelimit` has `WindowLimiter` |
| Body size limits | `max_body_bytes~` on the client or a request; `@mttp.backend(config~)` bounds the bytes on the wire |
| Proxies and connection limits | `config~ : @h1client.ClientConfig` (`gaato/mttp_core/h1client`) on `@mttp.client` or `@mttp.backend`; on JS the host's `fetch` handles them |
| TLS trust | `trust~ : @mttp.Trust` on `@mttp.client` or `@mttp.backend` |
| Steps and hooks | Wrap a backend with `@client.from_fn` (`gaato/mttp_core/client`); observe attempts with `observer~` on `@client.Client::new` |
| Mock transport | `BackendStub` (`gaato/mttp_core/testing`), or `@client.from_handler`; pass it as `backend~` |
| Virtual clock | `FakeClock` (`gaato/mttp_core/sim`), passed as `clock~` |
| `RequestoError` | `@mttp.TransportError` for the connection and protocol, `ResponseFailure` for a rejected status or an unreadable body |

## Defaults that differ

- **Cookies are off unless you add them; retries are on.** requesto kept
  cookies by default; pass `cookies~` to `@mttp.client` for that. `@mttp.client`
  retries by default (`RetryPolicy::conservative()`: up to two retries of an
  idempotent request, within a retry budget); pass `retry=@mttp.RetryPolicy::none()`
  to turn retries off.
- **Redirects are followed by default, and are a client setting.** Up to 10
  hops; `redirect=@mttp.RedirectConfig::none()` turns them off, and
  `RequestPlan::follow_redirects(false)` opts one request out. A retry starts
  the whole request again, including any redirects it followed, where
  requesto retried each hop.
- **requesto's derived total timeout is gone.** requesto defaulted the total
  budget to `(max_retries + 2) × timeout`. `@mttp.client` uses a fixed 30 s
  per attempt and 120 s in all; set `timeout_ms~` and `total_ms~` yourself.
- **Body limits are explicit.** The client reads at most 64 MiB of a body by
  default, counted after decompression.
- **Text is decoded lossily.** `as_string` replaces malformed UTF-8 with
  U+FFFD. Read `as_bytes` and decode it yourself if you need to reject it.
- **There are no `elapsed` or `retries` fields on a response.** Use
  `observer~` on `@client.Client::new`, which receives every attempt with
  its duration and decision.
