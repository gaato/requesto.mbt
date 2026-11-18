# Test coverage ledger

Line coverage of `gaato/requesto`, measured on native with `moon test
--enable-coverage` and reported in Coveralls-JSON mode. The rule is a closed
ledger:

> **Every uncovered line is either covered by a test or listed below with a
> reason.** `scripts/coverage_report.sh` enforces this: a file with uncovered
> lines must have a row here whose budget is at least the actual count, and
> the script fails otherwise. Rows for fully covered files are flagged as
> stale and rows with slack are noted, so budgets only ever shrink.

## Running it

```sh
scripts/coverage_report.sh                    # measure, print tables, check the ledger
scripts/coverage_report.sh --from-json _build/coverage_report.json   # recheck only
```

CI runs it after the gates on every push and pull request. Exit status: 0 =
ledger OK, 1 = an unexplained or over-budget file, 2 = the run itself failed
(a failing test, a build error). The tests use `MockTransport` and
`VirtualClock` only: no sockets, no real sleeps.

### What is measured

- Sources: every non-test `.mbt` under `src/`.
- Counts are Coveralls lines: lines with at least one instrumented point,
  covered when any point on them ran.

### Pitfalls the script pins

- Counters from earlier runs and trace maps of moved or deleted packages
  silently corrupt the merge, so every run deletes `_build/**/moonbit_coverage_*`
  and `_build/native/debug/test` first, and passes the trace maps and counter
  files to the reporter explicitly.
- `-f summary` omits fully covered files, which skews totals; the script uses
  the Coveralls JSON.
- moon's bundled tcc cannot link on some hosts (openSUSE); the script sets
  `MOON_CC=cc` unless it is already set.

Snapshot at the last full measurement (2026-11-18): **97.7 %** (297/304
lines).

## Policy

Must be covered by tests:

- the pure decisions: URL joining, query and header merging, body
  selection and encoding, status classes and reason phrases, the mapping of
  every mttp failure kind and phase to an `HTTPError` variant, error
  messages, line splitting, the network settings a client's options make,
  and the Digest session bound;
- every `raise` arm reachable through the public API;
- the client, every verb, the top-level functions, hooks, the streamed
  readers (chunks, lines, events), Digest, cookies, redirects and
  `total_timeout`, through `MockTransport` and `VirtualClock`.

Accepted as uncovered (needs a row):

- defensive arms that are unreachable by construction;
- arms for a platform without a random source, which the test targets all
  have;
- testable lines not yet tested, marked `not yet tested`.

Budgets are exact uncovered counts at the last measurement.

## Accepted uncovered

| File | Budget | Reason |
| --- | --- | --- |
| src/client.mbt | 4 | Three arms for a reply whose body is `Err`, in `Client::send` (two lines) and `Client::stream`: both ask mttp for `any_status()`, which sends every status through `Ok`, and the readers they use cannot fail to decode. One arm of `multipart_boundary` for a platform without a random source; every test target has one. |
| src/error.mbt | 2 | The `None` arm of `HTTPError`'s `output`, reached only by variants that always carry an mttp error; and the catch-all arm of `from_mttp`, which `Kind`'s `#non_exhaustive` requires and only kinds requesto never builds reach (`CircuitOpen`, from a caller-supplied `CircuitBreaker` transport). |
| src/auth.mbt | 1 | The refusal of Digest on a platform without a random source; every test target has one. |
