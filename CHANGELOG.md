# Changelog

All notable changes to `gaato/requesto` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). While the version is
0.x, a minor release (0.x → 0.y) may contain breaking changes; a patch release
never does. Every breaking change is listed with a migration note.

## [Unreleased]

### Deprecated

- The requesto facade is being retired in favor of mttp and mttp-net. This
  change adds a feature-by-feature migration guide and leaves the current
  runtime and dependency versions unchanged. The replacement's local
  integration is not a registry release; migration requires the unpublished
  workspace until that release is approved. Digest authentication lives in
  the separate mttp-digest module.

### Changed

- **The README has sections and a compile-checked example.** It now has
  Install, Usage, Limits and timeouts, Testing, Links and License sections;
  its examples are type-checked with the tests, and every public declaration
  has a doc comment. The package no longer ships the repository's notes,
  ledgers and scripts.

## [0.2.2] - 2026-10-22

### Changed

- **Requires `gaato/http` 0.5.0 and `gaato/http-async` 0.5.0**, and
  `moonbitlang/x` 0.5.6. No API of requesto changes. What a caller can
  notice comes from those releases: a client's cookie jar follows RFC 6265bis-22,
  `Retry-After` also accepts the obsolete HTTP-date forms, `*.example.com` in
  `NO_PROXY` bypasses the proxy like `.example.com`, gzip, deflate, Brotli and
  zstd bodies are decoded by `gaato/deflate`, `gaato/brotli` and `gaato/zstd`
  (the `Protocol` error text for a malformed gzip or deflate body reads
  differently), and a stream reader receives the output decoded before an error.
- Built with MoonBit 0.10.16. `moon info` now prints `Int` as `Int32` in
  `pkg.generated.mbti`; it is the same type.

## [0.2.1] - 2026-10-19

### Changed

- **Retry decisions now come from `gaato/http/retry`**, the retry core
  shared with `gaato/sdk-runtime`: a `Retry` becomes a `RetryRule` and each
  failed send asks it whether and how long to wait. Behaviour is unchanged:
  the same statuses, methods, unsent failures, `Retry-After` and its cap,
  backoff draws and `total_timeout` cut-off as in 0.2.0.
- **Requires `gaato/http` 0.4.1 and `gaato/http-async` 0.4.2.**

## [0.2.0] - 2026-10-19

### Added

- **`total_timeout` bounds a whole call**: its steps, redirects, retries
  and the waits between them, up to the whole response or, for `stream`
  and `sse`, the response's head. Set per client or per call; unset, it is
  `(max_retries + 2) * timeout`, 150 s by default, so it follows a raised
  `timeout`; `total_timeout=None` lifts it. When it runs out the call
  raises the new `RequestoError::TotalTimeout`, which is never retried,
  and a retry whose wait would not fit is not waited for: the last
  response is returned or the last failure raised.
- **`sse` waits up to `idle_timeout` for the next bytes**, 5 minutes by
  default (`None` for no bound), instead of the call's `timeout`, which
  now bounds only the exchange up to the head. `Response::each_event`
  takes `idle_timeout` too; without it, a streamed response keeps the
  call's `timeout` per read.
- **`Response.retries`** counts the sends after the first on the final
  hop. For a request `retry` would send again, a status in `statuses`
  with fewer retries than `max_retries` is one the client chose not to
  wait for.

### Changed

- **`RequestoError` has a new variant, `TotalTimeout`.** `is_timeout()` is
  true for it; `is_transport_error()` and `is_unsent()` are false.
  Migration: an exhaustive `match` on `RequestoError` needs an arm for it.
- **A call can now end sooner than its retries would have taken**: with
  the default retries and `timeout`, at 150 s. Migration: pass
  `total_timeout=None` for the previous behaviour, or a larger value.

- **`Auth` is `#non_exhaustive`.** Another credential scheme can then be
  added without breaking matches in your code. Migration: a `match` on
  `Auth` ends with `@req.Auth::.. => …` after the existing constructors.
- **Requires `gaato/http` 0.4.0, whose `Phase` is `#non_exhaustive`, and
  `gaato/http-async` 0.4.1, built on it.** A phase this version does not
  know is named in no message, as `Unknown` is.

## [0.1.2] - 2026-10-19

### Changed

- Built on `gaato/http-async` 0.4.0: on native and Wasm, a request without
  its own `Accept-Encoding` now offers `zstd` too (`gzip, deflate, br, zstd`)
  and a `zstd` response body is decoded like the others, with its window
  capped at 8 MiB (RFC 9659). A request that sets `Accept-Encoding` itself
  still gets the body as sent.

## [0.1.1] - 2026-10-19

### Changed

- No longer depends on `gaato/sdk-runtime`: the multipart encoder, the
  boundary's random source and `Retry-After` parsing come from `gaato/http`
  0.3.1 (`gaato/http/multipart`, `gaato/http/random`), where they moved.
  `Part` is the same type as before, so the public API is unchanged.

## [0.1.0] - 2026-10-18

### Added

- `Client::new` with a base URL, default headers, query parameters, `Auth`
  (`Basic`, `Bearer`, `Digest`), a timeout (30 s by default) and a buffered body limit
  (64 MiB by default), plus `steps`, `transport` and `clock`. For the
  default transport: `connect_timeout`, `write_timeout`, `read_timeout`,
  `pool_timeout`, `max_connections`, `max_connections_per_origin`,
  `max_idle_per_origin`, `proxy` and `trust_env` (on by default).
- `request` and the `get`, `head`, `options`, `delete`, `post`, `put` and
  `patch` shortcuts, on a client and as top-level functions that use a
  throw-away client.
- Body encoders: `content` (bytes), `text`, `data` (URL-encoded form),
  `files` (multipart, with parts that stream), `json` and `body_stream`
  (sent as it is read), one per call, each setting its `Content-Type`
  unless the call sets one.
- `Response` with `status`, `headers`, `url`, `request`, `history` and
  `elapsed`; `content`, `text`, `json`, `json_as`, status-class predicates
  and `raise_for_status`; `Response::new` for steps and tests.
- `Client::stream` and the top-level `stream`: the response arrives with its
  body on the connection, read with `read`, `read_some`, `each_chunk` or
  `each_line` (lines up to `max_line_bytes`, 16 MiB by default), and closed
  when the callback returns. Calling `close` in an `each_*` callback stops
  the loop there.
- Server-sent events: `Response::each_event` parses a `text/event-stream`
  body into `SseEvent`s (each up to `max_event_bytes`, 16 MiB by default),
  and `Client::sse` and the top-level `sse` send the request with
  `Accept: text/event-stream` and `Cache-Control: no-store` and call back with each event, raising
  `Status` for a non-2xx response. No automatic reconnection.
- `Url`, gaato/http's RFC 3986 URL, to take apart, resolve and compare
  response URLs. A call's URL is parsed with it before sending: a bad port,
  IPv6 literal or host raises `InvalidURL`, and the URL sent is normalised
  (lower-case scheme and host, no default port, no dot segments, non-ASCII
  percent-encoded). Credentials in the URL (`user:pass@`) leave it and are
  sent as Basic `Authorization`, in place of the client's `auth`, unless
  the call sets `Authorization`, as requests and httpx do; error messages
  and debug output show them as `<redacted>`.
- `RequestoError`, one error for every failure, naming the phase a transport
  failure happened in, with `is_timeout`, `is_transport_error` and
  `is_unsent`.
- Retries, on by default: `Retry::new` (3 retries of GET, HEAD, OPTIONS,
  PUT, DELETE and TRACE on 408, 429, 500, 502, 503, 504, `Timeout` and
  `Network`, and of any method when nothing reached the server) and
  `Retry::none()`, per client and per call (`retry`). `Retry-After` is
  honoured up to 60 s, otherwise the wait is exponential with full jitter on
  the client's clock; a body that streams is never sent twice. Retries and
  auth run per redirect hop, as in requests and Req: only the hop that
  failed is sent again, and auth answers each hop on the call's origin
  with that hop's method and URI.
- `Auth::Digest` (RFC 7616 and RFC 2617): MD5, SHA-256 and their `-sess`
  forms, qop `auth` and `auth-int`, `userhash`, stale nonces, and nonce
  reuse per origin with a counted `nc`.
- `Client::new(random~)`, the source of retry jitter, Digest client nonces
  and multipart boundaries.
- `Step`, a link of the chain around the transport, and the `on_request` and
  `on_response` hooks built on it.
- `MockTransport`, a transport that answers with a function, for tests.
- Redirects, followed by default with gaato/http's `follow_redirects`:
  `follow_redirects` per client and per call, `max_redirects` (10 by
  default). 303, and 301 or 302 after `POST`, become `GET` without the
  body; `Authorization`, `Cookie` and `Proxy-Authorization` are dropped
  when the origin changes; `https` to `http` and resending a stream body
  are refused with `InvalidRedirect`, a longer chain with
  `TooManyRedirects`. `history` holds the redirect responses, oldest first,
  and `url` the final URL; a streamed call closes each redirect before the
  next request.
- Cookies: a client keeps an RFC 6265 jar of its own on its clock (50
  cookies per domain, 3000 in all) and applies it on every redirect hop;
  `cookies=Jar(jar)` shares or seeds one, `cookies=Off` keeps none.
  `Client::cookies`, and `CookieJar`, `Cookie` and `SameSite` from
  gaato/http.
