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

# Start LAN server in the background. Inherit stdout/stderr so its banner and
# install URL stay visible alongside the funnel banner.
"$SCRIPT_DIR/serve-ipa-lan.sh" &
LAN_PID=$!

# Funnel runs in the foreground and drives the overall lifetime.
"$SCRIPT_DIR/serve-ipa.sh"
