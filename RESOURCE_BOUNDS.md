# Resource bounds

What a client and its calls can accumulate, and what keeps each structure
from growing without limit. The rule: **every structure that grows with input
from the network or with the number of calls is listed here with its bound**.
A new one needs a row before it ships.

**Every row of "Enforced limits" names a test that checks the bound**, in its
Tests column: a backticked file path, then the quoted names of that file's
tests. A test counts only if it drives the structure to its limit and one past
it, or pins a default the row states. `scripts/bounds_check.sh`, run by
`scripts/gates.sh`, enforces the naming; whether a named test really reaches
the bound is checked in review. The other tables are prose.

Limits enforced by mttp (connection pools, response heads, decompression,
the cookie jar, Digest nonces) are listed in its own ledger,
https://github.com/gaato/mttp/blob/main/RESOURCE_BOUNDS.md; rows here say
which defaults this module sets on them.

## Enforced limits

| Structure | Bound | On overflow | Tests |
|---|---|---|---|
| Buffered response body (`src/client.mbt`, `Client::new`, `max_body_bytes`, passed to mttp's `Client::new`) | 64 MiB by default (`default_max_body_bytes`), counted after decompression; replaceable per client | mttp stops reading and the call raises `TooLarge` | `src/bounds_test.mbt`: "a buffered body holds max_body_bytes and refuses one more"; `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" |
| A streamed body read into memory (`src/stream.mbt`, `StreamResponse::read`, `@mttp.read_bounded`) | The client's `max_body_bytes` | The read stops and raises `TooLarge` | `src/bounds_test.mbt`: "read holds max_body_bytes of a streamed body and refuses one more" |
| One line (`src/stream.mbt`, `StreamResponse::each_line`, `max_line_bytes`) | 1 MiB by default (`default_max_line_bytes`), the line's bytes without its terminator; replaceable per call | The line is not kept; the body is closed and `each_line` raises `TooLarge` after the lines before it | `src/bounds_test.mbt`: "each_line holds max_line_bytes of a line and refuses one more"; `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" |
| One server-sent event (`src/stream.mbt`, `StreamResponse::each_event`, `max_event_bytes`, passed to `@sse.SseReader::new`) | 16 MiB by default (`default_max_event_bytes`); replaceable per call | The event is not kept and `each_event` raises `TooLarge` after the events before it | `src/bounds_test.mbt`: "each_event holds max_event_bytes of an event and refuses one more"; `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" |
| Redirects followed per call (`src/client.mbt`, `Client::new`, `max_redirects`, mttp's `RedirectConfig`) | 20 by default (`default_max_redirects`), when `follow_redirects` holds | The call raises `TooManyRedirects` | `src/bounds_test.mbt`: "follow_redirects follows max_redirects hops and refuses one more"; `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" |
| Time per phase (`src/client.mbt`, `network_config`: connect, read, write, pool) | 5 s each by default (`default_phase_timeout_ms`); `Timeout` replaces each, `None` lifts one. Enforced by mttp's network backend (tested there); the read limit also bounds each read of a streamed body (`read_idle_ms`) | The call raises `ConnectTimeout`, `ReadTimeout`, `WriteTimeout` or `PoolTimeout` | `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent", "Timeout::new sets one phase apart, and proxies come from proxy or the environment" |
| The whole call (`src/client.mbt`, `Client::new`, `total_timeout`, mttp's `total_ms`) | None by default, as in httpx2; `total_timeout` sets one, on the client's clock, redirects and retries included | The call is cancelled and raises `TotalTimeout` | `src/bounds_test.mbt`: "total_timeout ends a call that is still running, on virtual time" |
| Connections (`src/client.mbt`, `network_config`, `Limits`) | httpx2's defaults: 100 open, 20 idle, each idle one closed after 5 s; enforced by mttp's network backend (tested there) | A send waits for a free connection, up to the pool timeout | `src/client_wbtest.mbt`: "defaults: httpx2's 5 s phases, 20 redirects and pool limits, 64 MiB bodies, a versioned User-Agent" |
| Digest sessions a client keeps (`src/auth.mbt`, `DigestLayer::session`) | 16 (`max_digest_sessions`), one per origin and credentials; each holds mttp_digest's nonce state, bounded there | The oldest session is forgotten; its origin is challenged again on its next call | `src/client_wbtest.mbt`: "a client keeps max_digest_sessions Digest sessions and drops the oldest" |
| A client's cookie jar (`src/client.mbt`, `Client::new`, `@mttp.CookieJar::new`) | mttp's `CookieJar` defaults (tested there); `cookies=false` keeps none | mttp evicts the oldest cookies | `src/features_test.mbt`: "the client keeps cookies across calls, and cookies=false drops them" |

## Bounded by rate and lifetime

| Structure | Grows with | Bound |
|---|---|---|
| The network backend's parked connections | Origins a client talks to | `Limits`: at most 20 idle, closed after 5 s. `Client::close` drops them; a throw-away client of a top-level function closes them when the call returns |
| Hooks (`src/client.mbt`, `EventHooks`) | Nothing at run time | The arrays the caller passes; each hook runs once per request and response |

## Left to the caller

| Structure | Grows with | Why it is not bounded here |
|---|---|---|
| Request bodies (`content`, `text`, `data`, `files`, `json`) | What the caller sends | The caller builds them in memory before the call |
| A streamed body taken with `each_bytes` | What the caller keeps | Each chunk is handed over and not kept by the response |
| Time spent in hooks and in the function passed to `stream` | What that code does | Hooks run before and after the exchange, so no limit of this module covers them. The function passed to `stream` runs inside it: `total_timeout` covers it when set, and the read timeout each read it makes |
| A transport passed to `Client::new` | Its own buffers | Its owner sets its limits; `max_body_bytes` still bounds what requesto buffers |
