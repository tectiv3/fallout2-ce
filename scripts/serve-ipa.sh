#!/usr/bin/env bash
# Serve the iOS IPA for OTA install via Tailscale Funnel.
# Requires: tailscale CLI (+ Funnel enabled in admin console), python3, unzip,
# /usr/libexec/PlistBuddy (macOS).
set -euo pipefail

IPA_PATH="${IPA_PATH:-out/build/ios/export/fallout2-ce.ipa}"
DIST_DIR="${DIST_DIR:-out/dist}"
PORT="${PORT:-8765}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the tailscale CLI. Allow override via TS_BIN; fall back to PATH;
# fall back to the macOS App Store bundle's installed shim.
TS_BIN="${TS_BIN:-}"
if [[ -z "$TS_BIN" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="$(command -v tailscale)"
  elif [[ -x /usr/local/bin/tailscale ]]; then
    TS_BIN="/usr/local/bin/tailscale"
  elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  else
    echo "tailscale CLI not found. Install via Tailscale menu bar \xe2\x86\x92 Install CLI\xe2\x80\xa6" >&2
    exit 1
  fi
fi

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found at $IPA_PATH" >&2
  echo "Run 'make ipa-full' (or 'make ipa') first, or set IPA_PATH=..." >&2
  exit 1
fi

for bin in python3 unzip; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Missing required binary: $bin" >&2
    exit 1
  fi
done

# Resolve the device's public Funnel hostname from tailscale status.
TS_DNS="$("$TS_BIN" status --json 2>/dev/null \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["Self"]["DNSName"].rstrip("."))')"
if [[ -z "$TS_DNS" ]]; then
  echo "Could not determine Tailscale DNS name. Is tailscale running and logged in?" >&2
  exit 1
fi
PUBLIC_URL="https://$TS_DNS"

mkdir -p "$DIST_DIR"
cp "$IPA_PATH" "$DIST_DIR/fallout2-ce.ipa"

tmpdir="$(mktemp -d)"
unzip -qq -o "$IPA_PATH" "Payload/*.app/Info.plist" -d "$tmpdir"
info_plist="$(find "$tmpdir/Payload" -maxdepth 2 -name Info.plist | head -n1)"
if [[ -z "$info_plist" || ! -f "$info_plist" ]]; then
  echo "Could not extract Info.plist from IPA." >&2
  rm -rf "$tmpdir"
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
APP_TITLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist" 2>/dev/null \
  || echo "Fallout2-CE")"
rm -rf "$tmpdir"

LOG_DIR="$DIST_DIR/logs"
mkdir -p "$LOG_DIR"
HTTP_LOG="$LOG_DIR/http.log"
: > "$HTTP_LOG"
HTTP_PID=""
HTTP_TAIL_PID=""
FUNNEL_UP=0

cleanup() {
  [[ -n "$HTTP_TAIL_PID" ]] && kill "$HTTP_TAIL_PID" 2>/dev/null || true
  [[ -n "$HTTP_PID"      ]] && kill "$HTTP_PID"      2>/dev/null || true
  if [[ "$FUNNEL_UP" -eq 1 ]]; then
    "$TS_BIN" funnel reset >/dev/null 2>&1 || true
    "$TS_BIN" serve  reset >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

render() {
  sed -e "s|@@TUNNEL_URL@@|$PUBLIC_URL|g" \
      -e "s|@@BUNDLE_ID@@|$BUNDLE_ID|g" \
      -e "s|@@BUNDLE_VERSION@@|$BUNDLE_VERSION|g" \
      -e "s|@@APP_TITLE@@|$APP_TITLE|g" \
      "$1" > "$2"
}
render "$SCRIPT_DIR/manifest.plist.tmpl" "$DIST_DIR/manifest.plist"
render "$SCRIPT_DIR/index.html.tmpl"     "$DIST_DIR/index.html"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIST_DIR" \
  >"$HTTP_LOG" 2>&1 &
HTTP_PID=$!

# Stream http access log live with a prefix so iOS requests are visible.
( tail -n +1 -F "$HTTP_LOG" 2>/dev/null | sed -u 's/^/[http] /' ) &
HTTP_TAIL_PID=$!

# Wipe any prior serve/funnel config on this machine so we start clean.
"$TS_BIN" funnel reset >/dev/null 2>&1 || true
"$TS_BIN" serve  reset >/dev/null 2>&1 || true

# Wait for the local http server to bind before funnel proxies to it.
for _ in $(seq 1 20); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/" -o /dev/null 2>/dev/null; then
    break
  fi
  sleep 0.25
done

# Pre-provision the HTTPS cert so the first iOS request doesn't time out while
# Let's Encrypt issues. Fire-and-forget; funnel below will also trigger it.
( "$TS_BIN" cert "$TS_DNS" >/dev/null 2>&1 || true ) &

IPA_SIZE="$(du -h "$DIST_DIR/fallout2-ce.ipa" | cut -f1)"
cat <<EOF

==========================================
 Open on the target device in Safari:

   $PUBLIC_URL/

 Bundle:   $BUNDLE_ID
 Version:  $BUNDLE_VERSION
 IPA size: $IPA_SIZE

 Log:      $HTTP_LOG

 First request may take 30-90s while Tailscale provisions
 the HTTPS cert. Subsequent requests are instant.

 Ctrl-C to stop the funnel + local server.
==========================================

EOF

# Run funnel in the foreground. It blocks until Ctrl-C, actively serving
# traffic. Cleanup trap tears down the python server + tailers on exit.
FUNNEL_UP=1
"$TS_BIN" funnel "http://127.0.0.1:$PORT"
