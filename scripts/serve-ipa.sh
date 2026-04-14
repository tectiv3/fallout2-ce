#!/usr/bin/env bash
# Serve the iOS IPA over HTTPS for OTA install, simultaneously exposed via:
#   - Tailscale Funnel (public URL, Let's Encrypt cert, works from anywhere)
#   - LAN HTTPS (mkcert cert, no cloud needed; requires root CA trusted once)
#
# One Python process hosts two listeners sharing the same files:
#   127.0.0.1:FUNNEL_PORT  plain HTTP behind the funnel
#   0.0.0.0 :LAN_PORT      HTTPS (mkcert) for LAN
#
# Ctrl-C stops everything.
#
# Requires: tailscale, mkcert, python3, unzip, /usr/libexec/PlistBuddy (macOS).
set -euo pipefail

IPA_PATH="${IPA_PATH:-out/build/ios/export/fallout2-ce.ipa}"
DIST_DIR="${DIST_DIR:-out/dist}"
FUNNEL_PORT="${FUNNEL_PORT:-8765}"
LAN_PORT="${LAN_PORT:-8766}"
LAN_IP="${LAN_IP:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- prereqs -----------------------------------------------------------------
TS_BIN="${TS_BIN:-}"
if [[ -z "$TS_BIN" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    TS_BIN="$(command -v tailscale)"
  elif [[ -x /usr/local/bin/tailscale ]]; then
    TS_BIN="/usr/local/bin/tailscale"
  elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    TS_BIN="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  fi
fi

for bin in mkcert python3 unzip; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Missing required binary: $bin" >&2
    exit 1
  fi
done

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found at $IPA_PATH" >&2
  echo "Run 'make ipa' first, or set IPA_PATH=..." >&2
  exit 1
fi

# --- LAN IP + mkcert cert ----------------------------------------------------
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
LAN_ENABLED=1
if [[ -z "$LAN_IP" ]]; then
  echo "WARN: could not auto-detect LAN IP; LAN install will be disabled." >&2
  LAN_ENABLED=0
fi

CA_ROOT="$(mkcert -CAROOT)"
if [[ ! -f "$CA_ROOT/rootCA.pem" ]]; then
  echo "mkcert root CA not found at $CA_ROOT/rootCA.pem. Run 'mkcert -install' first." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
CERT_DIR="$DIST_DIR/certs"
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"
mkdir -p "$CERT_DIR"

if [[ "$LAN_ENABLED" -eq 1 ]]; then
  # Regenerate when missing, when the LAN IP changed, or when the CA has
  # rotated since the cert was last issued (mkcert reinstall).
  need_cert=1
  if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
    cert_issuer_hash="$(openssl x509 -in "$CERT_FILE" -noout -issuer_hash 2>/dev/null || true)"
    ca_subject_hash="$(openssl x509 -in "$CA_ROOT/rootCA.pem" -noout -subject_hash 2>/dev/null || true)"
    if openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -q "IP Address:$LAN_IP" \
       && [[ -n "$cert_issuer_hash" && "$cert_issuer_hash" == "$ca_subject_hash" ]]; then
      need_cert=0
    fi
  fi
  if [[ "$need_cert" -eq 1 ]]; then
    rm -f "$CERT_FILE" "$KEY_FILE"
    mkcert -cert-file "$CERT_FILE" -key-file "$KEY_FILE" "$LAN_IP" localhost 127.0.0.1 >/dev/null
  fi
fi

# --- resolve Tailscale hostname ----------------------------------------------
FUNNEL_ENABLED=0
TS_DNS=""
if [[ -n "$TS_BIN" ]]; then
  TS_DNS="$("$TS_BIN" status --json 2>/dev/null \
    | python3 -c 'import json,sys;
try:
    d = json.load(sys.stdin); print(d["Self"]["DNSName"].rstrip("."))
except Exception:
    pass' 2>/dev/null || true)"
  if [[ -n "$TS_DNS" ]]; then
    FUNNEL_ENABLED=1
  fi
fi
if [[ "$FUNNEL_ENABLED" -eq 0 ]]; then
  echo "WARN: tailscale not available or not logged in; funnel install will be disabled." >&2
fi

if [[ "$FUNNEL_ENABLED" -eq 0 && "$LAN_ENABLED" -eq 0 ]]; then
  echo "Neither LAN nor funnel could be configured. Aborting." >&2
  exit 1
fi

FUNNEL_URL="${TS_DNS:+https://$TS_DNS}"
LAN_URL="${LAN_IP:+https://$LAN_IP:$LAN_PORT}"

# --- stage artifacts ---------------------------------------------------------
cp "$IPA_PATH" "$DIST_DIR/fallout2-ce.ipa"
cp "$CA_ROOT/rootCA.pem" "$DIST_DIR/rootCA.pem"

tmpdir="$(mktemp -d)"
unzip -qq -o "$IPA_PATH" "Payload/*.app/Info.plist" -d "$tmpdir"
info_plist="$(find "$tmpdir/Payload" -maxdepth 2 -name Info.plist | head -n1)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
APP_TITLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$info_plist" 2>/dev/null \
  || echo "Fallout2-CE")"
rm -rf "$tmpdir"

render() {
  sed -e "s|@@TUNNEL_URL@@|${1:-}|g" \
      -e "s|@@FUNNEL_URL@@|${FUNNEL_URL:-}|g" \
      -e "s|@@LAN_URL@@|${LAN_URL:-}|g" \
      -e "s|@@CA_URL@@|${LAN_URL:-}/rootCA.pem|g" \
      -e "s|@@LAN_HIDE@@|$([[ "$LAN_ENABLED" -eq 1 ]] && echo "" || echo "hide")|g" \
      -e "s|@@BUNDLE_ID@@|$BUNDLE_ID|g" \
      -e "s|@@BUNDLE_VERSION@@|$BUNDLE_VERSION|g" \
      -e "s|@@APP_TITLE@@|$APP_TITLE|g" \
      "$2" > "$3"
}

# Each manifest points the IPA URL at its own transport so iOS fetches it over
# the channel the user clicked.
[[ "$FUNNEL_ENABLED" -eq 1 ]] && render "$FUNNEL_URL" "$SCRIPT_DIR/manifest.plist.tmpl" "$DIST_DIR/manifest-funnel.plist"
[[ "$LAN_ENABLED"    -eq 1 ]] && render "$LAN_URL"    "$SCRIPT_DIR/manifest.plist.tmpl" "$DIST_DIR/manifest-lan.plist"
render "" "$SCRIPT_DIR/index.html.tmpl" "$DIST_DIR/index.html"

# --- listeners ---------------------------------------------------------------
LOG_DIR="$DIST_DIR/logs"
mkdir -p "$LOG_DIR"
HTTP_LOG="$LOG_DIR/http.log"
HTTPS_LOG="$LOG_DIR/https.log"
: > "$HTTP_LOG"
: > "$HTTPS_LOG"

HTTP_PID=""
HTTPS_PID=""
HTTP_TAIL_PID=""
HTTPS_TAIL_PID=""
FUNNEL_UP=0

cleanup() {
  for pid in "$HTTP_TAIL_PID" "$HTTPS_TAIL_PID" "$HTTP_PID" "$HTTPS_PID"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  if [[ "$FUNNEL_UP" -eq 1 && -n "$TS_BIN" ]]; then
    "$TS_BIN" funnel reset >/dev/null 2>&1 || true
    "$TS_BIN" serve  reset >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "$FUNNEL_ENABLED" -eq 1 ]]; then
  python3 -m http.server "$FUNNEL_PORT" --bind 127.0.0.1 --directory "$DIST_DIR" \
    >"$HTTP_LOG" 2>&1 &
  HTTP_PID=$!
  ( tail -n +1 -F "$HTTP_LOG" 2>/dev/null | sed -u 's/^/[funnel] /' ) &
  HTTP_TAIL_PID=$!
fi

if [[ "$LAN_ENABLED" -eq 1 ]]; then
  python3 - "$DIST_DIR" "$LAN_PORT" "$CERT_FILE" "$KEY_FILE" >"$HTTPS_LOG" 2>&1 <<'PY' &
import http.server, ssl, socketserver, sys, os
root, port, cert, key = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
os.chdir(root)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
with socketserver.ThreadingTCPServer(("0.0.0.0", port), H) as srv:
    srv.allow_reuse_address = True
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    srv.serve_forever()
PY
  HTTPS_PID=$!
  ( tail -n +1 -F "$HTTPS_LOG" 2>/dev/null | sed -u 's/^/[lan   ] /' ) &
  HTTPS_TAIL_PID=$!
fi

# --- funnel start-up ---------------------------------------------------------
if [[ "$FUNNEL_ENABLED" -eq 1 ]]; then
  "$TS_BIN" funnel reset >/dev/null 2>&1 || true
  "$TS_BIN" serve  reset >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    if curl -fsS --max-time 1 "http://127.0.0.1:$FUNNEL_PORT/" -o /dev/null 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
  ( "$TS_BIN" cert "$TS_DNS" >/dev/null 2>&1 || true ) &
fi

# --- banner ------------------------------------------------------------------
IPA_SIZE="$(du -h "$DIST_DIR/fallout2-ce.ipa" | cut -f1)"
cat <<EOF

==========================================
 IPA OTA serve

 Bundle:   $BUNDLE_ID
 Version:  $BUNDLE_VERSION
 IPA size: $IPA_SIZE

EOF
[[ "$FUNNEL_ENABLED" -eq 1 ]] && echo " Funnel (public): $FUNNEL_URL/"
[[ "$LAN_ENABLED"    -eq 1 ]] && echo " LAN    (direct): $LAN_URL/"
cat <<EOF

 Open the URL in Safari on the target device.

 Logs: $HTTP_LOG  $HTTPS_LOG
 Ctrl-C to stop.
==========================================

EOF

if [[ "$FUNNEL_ENABLED" -eq 1 ]]; then
  FUNNEL_UP=1
  "$TS_BIN" funnel "http://127.0.0.1:$FUNNEL_PORT"
else
  # LAN-only mode — block on the HTTPS server until Ctrl-C.
  wait "$HTTPS_PID"
fi
