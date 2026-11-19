# Agent notes for gaato/requesto

## Documentation

- `README.md` is a symbolic link to `src/overview.mbt.md`, and mooncakes.io
  renders it as the module page. Write it for visitors: what the module is,
  how to install and use it, and what a caller must know (limits, errors,
  retries). Keep design rationale, internal mechanics, test procedures and
  facts that go stale (version pins, "since 0.x") out of it; they belong in
  `RESOURCE_BOUNDS.md`, `TEST_COVERAGE.md`, `.notes/` or the changelog,
  because a visitor reads the page to decide whether and how to use the
  module.
- Keep its examples in `mbt check` fences: the file compiles with the
  package's tests, so a stale example fails `moon check` instead of
  misleading a reader.
- Run `moon run scripts/docs_audit.mbtx --self-test` (also run by
  `scripts/gates.sh` and CI) after changing docs or public declarations.
- `scripts/docs_audit.mbtx` is identical in every gaato MoonBit repository.
  Copy it from gaato/discord.mbt rather than editing it here, so the repos do
  not drift; put repository differences in `scripts/docs_audit.json` and
  `scripts/docs_audit.allow`.
- `.moonignore` lists what the package leaves out. A new repository-only file
  at the top level needs a line there, or it is published with the module.

## API changes

- When a published function's labelled parameter is renamed or removed, an
  optional one becomes required, or a positional one becomes labelled, keep
  existing calls compiling for one minor release with `#label_migration`
  (`alias=old`, `fill=false`, `fill=true` or `allow_positional=true`) and a
  `msg` naming the new form, and remove the attribute in the next minor
  release. Callers then get a warning instead of a build failure; the
  CHANGELOG still lists the change with its migration note. A renamed or
  removed function keeps a `#deprecated` alias for the same period.
