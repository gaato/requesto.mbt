#!/usr/bin/env bash
# Runs the repository validation suite. Usage: scripts/gates.sh [--no-js] [--no-wasm]
set -euo pipefail
cd "$(dirname "$0")/.."

targets=(native js wasm)
for arg in "$@"; do
  case "$arg" in
    --no-js) targets=("${targets[@]/js}") ;;
    --no-wasm) targets=("${targets[@]/wasm}") ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() { echo "+ $*"; "$@"; }

# CHANGELOG.md opens with [Unreleased].
first_heading="$(grep -m1 '^## ' CHANGELOG.md || true)"
if [ "$first_heading" != "## [Unreleased]" ]; then
  echo "CHANGELOG.md: the first section must be [Unreleased], found: $first_heading" >&2
  exit 1
fi
# The default User-Agent names the version in moon.mod.
version="$(sed -nE 's/^version = "(.*)"$/\1/p' moon.mod)"
grep -Fq "let user_agent : String = \"requesto/$version\"" src/client.mbt || {
  echo "src/client.mbt: user_agent does not name version $version from moon.mod" >&2
  exit 1
}
# Scripts import moonbitlang/core/async, not the registry moonbitlang/async:
# the registry package is to be replaced by core/async and its API is not
# stable, and copied scripts kept bringing it back. Every import block in the
# frontmatter (between the `---` or `----` lines) counts; comments do not.
registry_async="$(find . \( -name _build -o -name .mooncakes -o -name .git -o -name .jj \) -prune -o -type f -name '*.mbtx' -print0 |
  xargs -0 -r awk '
    FNR == 1 { inside = 0; done = 0 }
    done { next }
    /^---+[[:space:]]*$/ { if (inside) done = 1; else inside = 1; next }
    inside {
      line = $0
      sub(/\/\/.*/, "", line)
      if (line ~ /"moonbitlang\/async[@"\/]/) { print FILENAME; done = 1 }
    }')"
if [ -n "$registry_async" ]; then
  echo "use moonbitlang/core/async, not the registry moonbitlang/async (to be replaced by core/async, API not stable):" >&2
  echo "$registry_async" >&2
  exit 1
fi
# Every enforced limit in RESOURCE_BOUNDS.md names tests that exist.
run scripts/bounds_check.sh
run moon update
for t in "${targets[@]}"; do
  [ -n "$t" ] || continue
  run moon check --deny-warn --target "$t"
  MOON_CC="${MOON_CC:-cc}" run timeout 300 moon test --target "$t"
done
run moon fmt --check
# Module README sections, published links and doc comments (shared across gaato repos).
run moon run scripts/docs_audit.mbtx --self-test
run moon info
# Only meaningful in CI: in a jj working copy `git diff` compares against the parent change,
# so uncommitted edits would look stale. Set REQ_CHECK_MBTI=1 to enforce locally.
if [ "${CI:-}" = true ] || [ "${REQ_CHECK_MBTI:-}" = 1 ]; then
  git diff --exit-code -- '*.mbti' || { echo "pkg.generated.mbti is stale: run 'moon info' and commit" >&2; exit 1; }
fi
echo "gates: OK"
