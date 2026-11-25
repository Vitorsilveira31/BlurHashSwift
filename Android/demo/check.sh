#!/usr/bin/env bash
# Builds the Skip Fuse demo app (Android/demo), installs it on the running Android emulator or device, and checks the
# placeholders on screen: each tile is filled with a filtered (bilinear) gradient, before and after a resize.
#
# Needs a running emulator or device, the Android SDK (ANDROID_HOME, default ~/Library/Android/sdk), gradle, skip and
# bun, and `bun install` in Web/ (the check decodes the screenshot with Playwright's Chromium).
set -euo pipefail

demo="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$demo/../.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
adb="$ANDROID_HOME/platform-tools/adb"
work="${TMPDIR:-/tmp}/blurhashswift-android-check"
mkdir -p "$work"

(cd "$demo/Android" && gradle installDebug --console=plain --quiet)

# Waits for the tiles, then writes the screen (PNG) and its view hierarchy (XML) to $work/<name>.
capture() {
  for _ in $(seq 1 60); do
    "$adb" shell uiautomator dump /sdcard/blurhash-ui.xml >/dev/null 2>&1 || true
    "$adb" shell cat /sdcard/blurhash-ui.xml > "$work/$1.xml" 2>/dev/null || true
    grep -q 'resource-id="tile-3"' "$work/$1.xml" && break
    sleep 1
  done
  sleep 1
  "$adb" exec-out screencap -p > "$work/$1.png"
}

"$adb" shell am force-stop dev.blurhashswift.demo
"$adb" shell monkey -p dev.blurhashswift.demo -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
capture narrow
bun "$demo/check-screenshot.mjs" "$work/narrow.png" "$work/narrow.xml" 120

# Resize: the tiles widen to 180 points.
resize=$(grep -oE 'resource-id="resize"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' "$work/narrow.xml" | grep -oE '\[[0-9]+,[0-9]+\]' | tr -d '[]' | head -1)
"$adb" shell input tap "${resize%,*}" "${resize#*,}"
sleep 2
capture wide
bun "$demo/check-screenshot.mjs" "$work/wide.png" "$work/wide.xml" 180
"$adb" shell am force-stop dev.blurhashswift.demo
echo "Android check passed (screenshots in $work)"
