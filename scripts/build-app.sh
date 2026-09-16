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
# A stable signature lets Keychain's "Always Allow" persist across rebuilds.
# Create the identity once with scripts/make-signing-identity.sh.
if security find-certificate -c "agent-meter" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
    codesign --force --sign "agent-meter" "$app"
fi
echo "$app"
