#!/bin/sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build -c release --product AgentMeter
app="$root/dist/AgentMeter.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/AgentMeter" "$app/Contents/MacOS/AgentMeter"
cp "$root/Info.plist" "$app/Contents/Info.plist"
echo "$app"
