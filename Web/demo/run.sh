#!/usr/bin/env bash
# Builds the demo app (Web/demo/App) with SwiftUIWeb's browser build (Embedded Swift, WebAssembly) and serves it on
# http://127.0.0.1:${PORT:-8080}; --test runs the browser test instead, --build only builds.
#
# SWIFTUIWEB_ROOT names the SwiftUIWeb checkout (default: ../SwiftUIWeb next to this repository). The app depends on
# BlurHashSwift as `../BlurHashSwift`, as an app next to this checkout would, so it is built from a copy placed beside a
# link to this checkout, outside it.
set -euo pipefail

web="$(cd "$(dirname "$0")/.." && pwd)"
repository="$(cd "$web/.." && pwd)"
swiftuiweb="${SWIFTUIWEB_ROOT:-$repository/../SwiftUIWeb}"
[[ -x "$swiftuiweb/Tools/run-browser-embedded.sh" ]] || { echo "Set SWIFTUIWEB_ROOT to a SwiftUIWeb checkout." >&2; exit 2; }
swiftuiweb="$(cd "$swiftuiweb" && pwd)"

work="${TMPDIR:-/tmp}/blurhashswift-demo"
rm -rf "$work"
mkdir -p "$work"
ln -s "$repository" "$work/BlurHashSwift"
cp -R "$web/demo/App" "$work/BlurHashDemo"

# The app spells `import SwiftUI` (`-module-alias SwiftUI=SwiftUIWeb`), which the lowering has to know.
SWIFTUIWEB_MODULE_ALIASES=1 \
SWIFTUIWEB_PACKAGE_ROOT="$work/BlurHashDemo" \
SWIFTUIWEB_PRODUCT=BlurHashDemo \
SWIFTUIWEB_BUNDLE_ROOT="$work/browser" \
BUILD_ONLY=1 \
CONFIGURATION="${CONFIGURATION:-release}" \
  "$swiftuiweb/Tools/run-browser-embedded.sh" BlurHashDemo

[[ "${1:-}" == --build ]] && exit 0
if [[ "${1:-}" == --test ]]; then
  (cd "$web" && bun install --frozen-lockfile >/dev/null)
  exec bun "$web/demo/test-browser.mjs" "$work/browser/BlurHashDemo"
fi
exec bun "$swiftuiweb/Tools/bun-server.ts" "$work/browser/BlurHashDemo" "${PORT:-8080}"
