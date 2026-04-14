#!/usr/bin/env bash
# Serve the iOS IPA simultaneously over:
#   - LAN mkcert HTTPS  (fast install on-network, needs root CA trusted once)
#   - Tailscale Funnel  (public HTTPS, works from anywhere)
#
# Ctrl-C stops both.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LAN_PID=""
cleanup() {
  if [[ -n "$LAN_PID" ]]; then
    kill "$LAN_PID" 2>/dev/null || true
    wait "$LAN_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Each worker binds its own HTTP listener; give them distinct ports so they
# don't collide. Overrides via FUNNEL_PORT / LAN_PORT honoured.
FUNNEL_PORT="${FUNNEL_PORT:-8765}"
LAN_PORT="${LAN_PORT:-8766}"

# Start LAN server in the background. Inherit stdout/stderr so its banner and
# install URL stay visible alongside the funnel banner.
PORT="$LAN_PORT" "$SCRIPT_DIR/serve-ipa-lan.sh" &
LAN_PID=$!

# Funnel runs in the foreground and drives the overall lifetime.
PORT="$FUNNEL_PORT" "$SCRIPT_DIR/serve-ipa.sh"
