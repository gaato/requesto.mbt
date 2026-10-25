# Migrating from requesto to mttp

The unreleased deprecation chooses a single new HTTP implementation instead
of maintaining a second requesto facade. This documentation does not publish
or remove any registry version. Existing requesto 0.2.2 applications can keep
using that version while mttp's consumer and runtime validation is completed.

The replacement modules are `gaato/mttp` (runtime-free model, client policies
and codecs), `gaato/mttp-net` (runtime adapters), and `gaato/mttp-digest`
(optional Digest authentication). Their current integration uses `moon.work`
path members. Do not replace registry dependencies until the replacement
release is available and your application's tests pass.

## Feature map

| requesto | Replacement |
|---|---|
| Top-level verbs and one-call scripts | `mttp-net/quick.send(client.quick_request(model.Request::get(...)))`; call `quick.close()` when finished |
| Owned `Client` with defaults | `mttp/client.Client` over `mttp-net/backend.AsyncBackend` and `mttp-net/runtime.AsyncClock` |
| Base URL and query defaults | Client prefix joining; immutable `Request::query` and model URI helpers |
| Default headers, Basic and Bearer | Immutable default headers or `Request::basic` / `Request::bearer` |
| Bytes, text, JSON and form bodies | `Request::body_bytes`, `body_text`, `body_json`, `body_form` |
| Multipart files and streamed files | `mttp/multipart`, including streamed parts; attach the resulting body and content type |
| Streaming uploads and replay | `Request::body_stream`; provide `ClientRequest::body_fn` when each retry needs a fresh stream |
| Status-as-value response | `client.quick_request` for a string body, or a custom response reader; typed `as_*` readers normally reject non-success statuses |
| Buffered JSON or bytes | `client.as_json` / `as_bytes` inside the attempt |
| Scoped streaming response | `client.as_stream`; use the stream only inside its callback |
| SSE and lines | `client.as_sse` / `as_lines`; set `read_idle_ms` explicitly |
| Redirect policy and history | `client.FollowRedirects`; final URL and history are response attributes |
| Cookie jar | `client/cookies.Cookies` over `mttp/cookie.CookieJar` |
| Digest | `mttp-digest.DigestScheme`, retaining the separate crypto dependency; supply a credential origin and an unpredictable cnonce source |
| Retry policy | `client.RetryPolicy` and a retry decider, supplied explicitly |
| Per-exchange and total timeouts | `RequestOptions.timeout_ms`, phase budgets, and `Client::new(total_ms=...)` |
| Proxies and connection limits | `AsyncBackend` settings on native/Wasm; JS uses the host Fetch implementation |
| Steps and hooks | Backend wrappers (`client.from_fn`) and attempt observers |
| Mock transport | `client.BackendStub`, or a Router used as a Backend |
| Virtual clock | `mttp-net/runtime.VirtualClock`; use `settle(until=...)` for observable progress |
| Response URL parsing | `mttp/model.Url` |
| Elapsed time and retries | Collect attempt observer data instead of reading requesto response fields |
| Requesto errors | `model.TransportError`, client response errors and decoder-specific errors |

## Defaults and ordering to review

The quick client follows redirects but does not enable retries or cookies.
Requesto enables both by default. Configure an explicit client and wrapper
chain when those policies matter; changing import names does not preserve
requesto's defaults.

Retries run above redirects: retrying a failure on the second hop starts the
original request again. Backend wrappers run per attempt, whereas requesto
steps ran around a whole call. Cross-origin credential stripping, redirect
limits and body replayability still apply. A stream without a fresh body
factory cannot be retried.

Buffered readers execute inside the attempt, so parsing failure participates
in policy and limiter accounting. Streaming callbacks execute after the retry
decision and own their response only for the callback lifetime. There is no
automatic retry after an application has consumed part of a response.

Review all time and byte limits explicitly. In particular, do not translate
requesto's `None` limits to guessed sentinel integers. JavaScript Fetch
restrictions differ from native sockets, including browser redirect, cookie
and proxy behavior. Validate against the host you actually deploy.

## Scope of this change

No requesto implementation or released dependency is rewritten here. The
Digest parser, hashes and reference cases were carried into mttp-digest, and
the new core retains the shared URL, cookie and SSE conformance corpora.
That evidence does not substitute for application-specific migration tests.
