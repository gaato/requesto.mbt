// httpx2's way of writing HTTP calls, on gaato/mttp: requesto adds the
// requests-style surface and its defaults, and mttp does the HTTP.

name = "gaato/requesto"

version = "0.3.2"

license = "Apache-2.0"

readme = "README.md"

repository = "https://github.com/gaato/requesto.mbt"

keywords = [ "http", "client", "requests", "async" ]

description = "httpx2's way of writing HTTP calls for MoonBit, on gaato/mttp: verb functions, a client with defaults, responses as values, raise_for_status, streaming, event hooks and a mock transport that runs an mttp server handler."

source = "src"

preferred_target = "native"

import {
  "gaato/mttp@0.5.1",
  "gaato/mttp_core@0.3.2",
  "gaato/mttp_digest@0.5.1",
}
