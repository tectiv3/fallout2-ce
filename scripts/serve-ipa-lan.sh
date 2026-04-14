#!/usr/bin/env bash
# Serve the iOS IPA for OTA install over LAN HTTPS using a mkcert-issued cert.
# No cloud / tunnel needed. One-time setup per iPad: trust the mkcert root CA
# (instructions printed below).
#
# Requires: mkcert, python3, unzip, /usr/libexec/PlistBuddy (macOS).
set -euo pipefail

IPA_PATH="${IPA_PATH:-out/build/ios/export/fallout2-ce.ipa}"
DIST_DIR="${DIST_DIR:-out/dist}"
PORT="${PORT:-8765}"
CA_PORT="${CA_PORT:-$((PORT + 1))}"
LAN_IP="${LAN_IP:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$LAN_IP" ]]; then
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [[ -z "$LAN_IP" ]]; then
  echo "Could not auto-detect LAN IP. Set LAN_IP=192.168.x.y explicitly." >&2
  exit 1
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

# Regenerate the server cert when missing, when the LAN IP changed, or when
# the issuer no longer matches the current mkcert root CA (e.g. mkcert was
# reinstalled and rotated the CA since the last cached cert).
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

cp "$IPA_PATH" "$DIST_DIR/fallout2-ce.ipa"
# Expose the root CA so the iPad can fetch it from the plain-HTTP port on first run.
cp "$CA_ROOT/rootCA.pem" "$DIST_DIR/rootCA.pem"

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

PUBLIC_URL="https://$LAN_IP:$PORT"
CA_URL="http://$LAN_IP:$CA_PORT/rootCA.pem"

render() {
  sed -e "s|@@TUNNEL_URL@@|$PUBLIC_URL|g" \
      -e "s|@@BUNDLE_ID@@|$BUNDLE_ID|g" \
      -e "s|@@BUNDLE_VERSION@@|$BUNDLE_VERSION|g" \
      -e "s|@@APP_TITLE@@|$APP_TITLE|g" \
      "$1" > "$2"
}
render "$SCRIPT_DIR/manifest.plist.tmpl" "$DIST_DIR/manifest.plist"
render "$SCRIPT_DIR/index.html.tmpl"     "$DIST_DIR/index.html"

LOG_DIR="$DIST_DIR/logs"
mkdir -p "$LOG_DIR"
HTTPS_LOG="$LOG_DIR/https.log"
HTTP_LOG="$LOG_DIR/http-ca.log"
: > "$HTTPS_LOG"
: > "$HTTP_LOG"
HTTPS_PID=""
HTTP_PID=""
HTTPS_TAIL_PID=""
HTTP_TAIL_PID=""

cleanup() {
  for pid in "$HTTPS_TAIL_PID" "$HTTP_TAIL_PID" "$HTTPS_PID" "$HTTP_PID"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# HTTPS server with the mkcert-issued cert. Serves the IPA + manifest + index.
python3 - "$DIST_DIR" "$PORT" "$CERT_FILE" "$KEY_FILE" >"$HTTPS_LOG" 2>&1 <<'PY' &
import http.server, ssl, socketserver, sys, os
root, port, cert, key = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
os.chdir(root)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Safari caches aggressively; bust it for the install flow.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
with socketserver.ThreadingTCPServer(("0.0.0.0", port), H) as srv:
    srv.allow_reuse_address = True
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    srv.serve_forever()
PY
HTTPS_PID=$!

# Plain-HTTP mini-server on CA_PORT that exposes rootCA.pem so the iPad can
# download and trust it before the HTTPS port becomes usable.
python3 -m http.server "$CA_PORT" --bind 0.0.0.0 --directory "$DIST_DIR" \
  >"$HTTP_LOG" 2>&1 &
HTTP_PID=$!

( tail -n +1 -F "$HTTPS_LOG" 2>/dev/null | sed -u 's/^/[https] /' ) &
HTTPS_TAIL_PID=$!
( tail -n +1 -F "$HTTP_LOG" 2>/dev/null | sed -u 's/^/[http ] /' ) &
HTTP_TAIL_PID=$!

IPA_SIZE="$(du -h "$DIST_DIR/fallout2-ce.ipa" | cut -f1)"
cat <<EOF

==========================================
 LAN IPA serve

 Install URL (iPad Safari):
   $PUBLIC_URL/

 Bundle:   $BUNDLE_ID
 Version:  $BUNDLE_VERSION
 IPA size: $IPA_SIZE

 FIRST-TIME SETUP (once per iPad):

   1. Visit on the iPad Safari:
        $CA_URL
   2. Allow the profile download, then:
        Settings -> General -> VPN & Device Management -> install "mkcert ..."
   3. Trust it:
        Settings -> General -> About -> Certificate Trust Settings
        -> toggle ON the mkcert root.

 After that, the install URL above works over HTTPS with no warning.

 Logs: $HTTPS_LOG  $HTTP_LOG
 Ctrl-C to stop both servers.
==========================================

EOF

wait "$HTTPS_PID"
