#!/usr/bin/env bash
# Brings up the full Honey Chain dev/demo stack from a cold start:
#   Hardhat node -> deploy contract -> Postgres migrate -> Django -> (optional) Flutter web
#
# Each service is started in the background and logs to /tmp/honeychain-*.log.
# Safe to re-run: it kills any previous instances of these dev processes first.
#
# Usage:
#   ./scripts/dev_up.sh              # backend + chain only
#   ./scripts/dev_up.sh --client     # ...and the Flutter debug web client on :8080
#                                       (this machine only -- see the DWDS note below)
#   ./scripts/dev_up.sh --lan        # ...and a LAN-reachable client, for testing from
#   ./scripts/dev_up.sh --lan=<ip>     a phone/other device on the same network/hotspot.
#                                       Auto-detects this machine's LAN IP unless given
#                                       explicitly. Builds a release client instead of
#                                       running the debug dev server, because Flutter's
#                                       debug web tooling (DWDS) does not reliably work
#                                       when loaded from a different device at all --
#                                       the page fetches but stays blank. A release
#                                       build has no debug tooling, so it isn't affected.
#   ./scripts/dev_up.sh --public     # ...and a real public URL via ngrok, for anyone on
#   ./scripts/dev_up.sh --public=<domain>  the internet (not just this network/hotspot).
#                                       Defaults to this account's reserved ngrok domain;
#                                       pass --public=ephemeral for a random one instead.
#                                       Django serves the built client itself (one port,
#                                       one tunnel) rather than running a second server.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# This account's one reserved (free-tier) ngrok domain -- see --public above.
DEFAULT_NGROK_DOMAIN="pseudocaptive-exactingly-nicholas.ngrok-free.dev"

CLIENT_MODE=""       # "", "debug", "lan", or "public"
LAN_IP_OVERRIDE=""
PUBLIC_DOMAIN_OVERRIDE=""
case "${1:-}" in
  "") ;;
  --client) CLIENT_MODE="debug" ;;
  --lan) CLIENT_MODE="lan" ;;
  --lan=*) CLIENT_MODE="lan"; LAN_IP_OVERRIDE="${1#--lan=}" ;;
  --public) CLIENT_MODE="public" ;;
  --public=*) CLIENT_MODE="public"; PUBLIC_DOMAIN_OVERRIDE="${1#--public=}" ;;
  *)
    echo "Unknown option: ${1}" >&2
    echo "Usage: $0 [--client | --lan | --lan=<ip> | --public | --public=<domain>]" >&2
    exit 1
    ;;
esac

echo "== Stopping any previous dev processes =="
# `pkill -f "flutter run"` looks tempting but is unreliable: `flutter run`
# actually execs into a Dart VM subprocess (.../dartvm ... flutter_tools.snapshot
# run -d web-server ...) whose argv never contains the literal substring
# "flutter run", so the pattern silently fails to match it. When that
# happens, a stale debug dev-server is left holding port 8080, the new
# release-mode static server below fails to bind ("Address already in
# use"), and curl/browser requests keep landing on the old, broken debug
# server instead -- which is exactly "page fetches but stays blank" again,
# just with the fix silently not applied. Killing by the port actually in
# use sidesteps guessing at command-line substrings entirely.
for port in 8545 8000 8080; do
  fuser -k -TERM "${port}/tcp" 2>/dev/null || true
done
pkill -f "hardhat node" 2>/dev/null || true
pkill -f "manage.py runserver" 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
sleep 1
for port in 8545 8000 8080; do
  fuser -k -KILL "${port}/tcp" 2>/dev/null || true
done
sleep 1

# Only ever stop an ngrok process THIS script started (tracked by its own
# pidfile from a previous run) -- never pattern-match/kill ngrok blindly.
# This machine's ngrok account/config is also used for other tunnels
# (ssh/terminal/dashboard access to this environment) that have nothing to
# do with this project and must not be touched.
NGROK_PIDFILE="/tmp/honeychain-ngrok.pid"
if [[ -f "$NGROK_PIDFILE" ]]; then
  old_ngrok_pid="$(cat "$NGROK_PIDFILE" 2>/dev/null || true)"
  if [[ -n "$old_ngrok_pid" ]] && kill -0 "$old_ngrok_pid" 2>/dev/null \
      && [[ "$(ps -p "$old_ngrok_pid" -o comm= 2>/dev/null)" == "ngrok" ]]; then
    kill "$old_ngrok_pid" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$NGROK_PIDFILE"
fi

echo "== Starting Hardhat node (local EVM-compatible testnet) =="
(cd "$ROOT/contracts" && npx hardhat node > /tmp/honeychain-hardhat.log 2>&1 &)
until curl -s -m 1 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://127.0.0.1:8545 >/dev/null 2>&1; do
  sleep 1
done
echo "   node ready at http://127.0.0.1:8545"

echo "== Deploying HoneyChainRegistry =="
(cd "$ROOT/contracts" && npx hardhat run scripts/deploy.js --network localhost)

echo "== Running Django migrations =="
(cd "$ROOT/backend" && ./.venv/bin/python manage.py migrate)

# LAN mode needs Django reachable from other devices (not just loopback), plus
# DJANGO_ALLOWED_HOSTS/PUBLIC_BASE_URL/BACKEND_BASE_URL pointed at this
# machine's real IP instead of 127.0.0.1 -- 127.0.0.1 means "the phone" from
# a phone's own browser, not this laptop. Exporting these here overrides
# backend/.env (python-dotenv's load_dotenv() never overwrites variables
# already present in the environment), so nothing in .env needs to change.
DJANGO_BIND="127.0.0.1:8000"
LAN_IP=""
if [[ "$CLIENT_MODE" == "lan" ]]; then
  LAN_IP="$LAN_IP_OVERRIDE"
  if [[ -z "$LAN_IP" ]]; then
    LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
  fi
  if [[ -z "$LAN_IP" ]]; then
    echo "Could not auto-detect a LAN IP (are you connected to a network/hotspot?)." >&2
    echo "Pass one explicitly: $0 --lan=<your-lan-ip>" >&2
    exit 1
  fi
  echo "== LAN mode: using $LAN_IP (must be reachable from your phone's browser) =="
  DJANGO_BIND="0.0.0.0:8000"
  export DJANGO_ALLOWED_HOSTS="localhost,127.0.0.1,${LAN_IP}"
  export PUBLIC_BASE_URL="http://${LAN_IP}:8080"
  export BACKEND_BASE_URL="http://${LAN_IP}:8000"
elif [[ "$CLIENT_MODE" == "public" ]]; then
  # ngrok's local agent connects to the tunneled port from 127.0.0.1 itself
  # (it's a local process relaying traffic in, not a remote peer), so unlike
  # --lan, Django doesn't need to bind 0.0.0.0 here -- loopback is enough,
  # and keeps port 8000 from also being directly reachable on the LAN.
  NGROK_DOMAIN="$DEFAULT_NGROK_DOMAIN"
  if [[ -n "$PUBLIC_DOMAIN_OVERRIDE" ]]; then
    if [[ "$PUBLIC_DOMAIN_OVERRIDE" == "ephemeral" ]]; then
      NGROK_DOMAIN=""
    else
      NGROK_DOMAIN="$PUBLIC_DOMAIN_OVERRIDE"
    fi
  fi

  echo "== Starting ngrok tunnel to port 8000 =="
  NGROK_URL_FLAG=()
  [[ -n "$NGROK_DOMAIN" ]] && NGROK_URL_FLAG=(--url "https://${NGROK_DOMAIN}")
  (nohup ngrok http 8000 "${NGROK_URL_FLAG[@]}" --log=stdout > /tmp/honeychain-ngrok.log 2>&1 &
   echo $! > "$NGROK_PIDFILE")

  NGROK_URL=""
  for i in $(seq 1 30); do
    NGROK_URL="$(curl -s -m 1 http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c '
import json, sys
try:
    tunnels = json.load(sys.stdin).get("tunnels", [])
    urls = [t["public_url"] for t in tunnels if t.get("public_url", "").startswith("https://")]
    print(urls[0] if urls else "")
except Exception:
    print("")
' 2>/dev/null || true)"
    [[ -n "$NGROK_URL" ]] && break
    if ! kill -0 "$(cat "$NGROK_PIDFILE" 2>/dev/null)" 2>/dev/null; then break; fi
    sleep 1
  done

  if [[ -z "$NGROK_URL" ]]; then
    echo "ERROR: ngrok did not come up with a public URL. Log:" >&2
    cat /tmp/honeychain-ngrok.log >&2
    echo "" >&2
    echo "If this is 'ERR_NGROK_108' (simultaneous session limit) or a domain" >&2
    echo "conflict, another ngrok tunnel (e.g. this account's other 'dashboard'/" >&2
    echo "etc. presets) is probably already using the same session/domain --" >&2
    echo "stop that one first, or try: $0 --public=ephemeral" >&2
    exit 1
  fi
  echo "   public URL: $NGROK_URL"

  DJANGO_BIND="127.0.0.1:8000"
  # Deliberately wide open, not the actual ngrok hostname specifically: this
  # mode's entire point is "anyone on the internet can reach this", so
  # there's no meaningful host allowlist left to enforce, and an ephemeral
  # domain isn't known far enough ahead of Django's startup to allowlist
  # precisely anyway.
  export DJANGO_ALLOWED_HOSTS="*"
  export PUBLIC_BASE_URL="$NGROK_URL"
  export BACKEND_BASE_URL="$NGROK_URL"
fi

echo "== Starting Django (GraphQL API) =="
(cd "$ROOT/backend" && nohup ./.venv/bin/python manage.py runserver "$DJANGO_BIND" > /tmp/honeychain-django.log 2>&1 &)
until curl -s -m 1 -o /dev/null http://127.0.0.1:8000/graphql; do sleep 1; done
echo "   backend ready at http://127.0.0.1:8000/graphql (GraphiQL enabled)"

if [[ "$CLIENT_MODE" == "lan" || "$CLIENT_MODE" == "public" ]]; then
  # A batch's QR code + public_url are baked in once, at packaging time, from
  # whatever PUBLIC_BASE_URL was in effect then -- they never update on their
  # own. A batch packaged during an earlier session (a different hotspot IP,
  # or a previous ephemeral ngrok URL) is still pointing at that old host, so
  # its QR is dead weight until this runs. Idempotent and cheap, so just
  # always run it in these modes rather than making it another manual step.
  echo "== Refreshing existing QR codes to point at $PUBLIC_BASE_URL =="
  (cd "$ROOT/backend" && ./.venv/bin/python manage.py refresh_qr_codes)
fi

if [[ "$CLIENT_MODE" == "debug" ]]; then
  echo "== Starting Flutter web client (debug) on :8080 =="
  (cd "$ROOT/client" && nohup flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0 \
      --dart-define=GRAPHQL_ENDPOINT=http://127.0.0.1:8000/graphql \
      > /tmp/honeychain-flutter.log 2>&1 &)
  echo "   client starting at http://127.0.0.1:8080 (first load compiles, can take ~30s)"
  echo "   NOTE: open it as http://127.0.0.1:8080, not http://localhost:8080 -- Flutter's"
  echo "   debug web tooling only attaches reliably from the exact host it serves on."
elif [[ "$CLIENT_MODE" == "lan" ]]; then
  echo "== Building Flutter web client (release) for LAN access =="
  echo "   compiling from scratch -- can take a minute or two"
  # --no-web-resources-cdn: by default `flutter build web` still fetches
  # CanvasKit from https://www.gstatic.com/flutter-canvaskit at runtime even
  # though a copy is already bundled in build/web/canvaskit/ -- fine on a
  # normal internet connection, but a phone on a mobile hotspot may not
  # reliably reach that CDN (carrier/corporate filtering, no general
  # internet while hotspotting, etc.), which renders as exactly this: the
  # page fetches fine (our own server), then stays blank forever (the
  # engine never finishes initializing). This flag makes the build use only
  # the locally bundled copy, so there's no runtime dependency on anything
  # outside this machine.
  (cd "$ROOT/client" && flutter build web --no-web-resources-cdn \
      --dart-define=GRAPHQL_ENDPOINT="http://${LAN_IP}:8000/graphql")
  echo "== Serving client on :8080 (all interfaces, with SPA fallback routing) =="
  # Plain `python3 -m http.server` 404s any deep link (e.g. /trace/<batchId>
  # -- exactly what a scanned QR code opens) because there's no real file at
  # that path; spa_server.py falls back to index.html so Flutter's own
  # client-side router can handle it instead.
  (cd "$ROOT/client/build/web" && nohup python3 "$ROOT/scripts/spa_server.py" . 8080 > /tmp/honeychain-flutter-lan.log 2>&1 &)
  until curl -s -m 1 -o /dev/null http://127.0.0.1:8080; do sleep 1; done
  # Something answering on :8080 isn't proof it's THIS build -- if the port
  # cleanup above ever fails to free it (e.g. a process holding it in a way
  # fuser/pkill can't see), the old server would keep answering right through
  # this whole script, and it would print "success" anyway. dart2js is only
  # ever the compile target for a release build (`flutter build web`);
  # dartdevc means something else -- almost certainly a stale `flutter run`
  # debug server -- is still what's actually serving this port.
  if ! curl -s http://127.0.0.1:8080/flutter_bootstrap.js | grep -q '"compileTarget":"dart2js"'; then
    echo "ERROR: port 8080 is not serving this build (saw something other than a" >&2
    echo "dart2js/release bootstrap config) -- a stale process is likely still" >&2
    echo "holding the port. Find it and stop it manually:" >&2
    echo "  ss -tlnp | grep 8080   # or: fuser -k 8080/tcp" >&2
    echo "then re-run: $0 --lan" >&2
    cat /tmp/honeychain-flutter-lan.log >&2
    exit 1
  fi
  echo "   client ready -- open from any device on this network/hotspot at:"
  echo "     http://${LAN_IP}:8080"
  echo "   this is a release build, so there's no debug/hot-reload -- re-run"
  echo "   '$0 --lan' after making code changes to pick them up."
elif [[ "$CLIENT_MODE" == "public" ]]; then
  echo "== Building Flutter web client (release) for public access =="
  echo "   compiling from scratch -- can take a minute or two"
  (cd "$ROOT/client" && flutter build web --no-web-resources-cdn \
      --dart-define=GRAPHQL_ENDPOINT="${NGROK_URL}/graphql")
  # No separate client server here: Django's catch-all view
  # (honeychain/flutter_spa_view.py) serves client/build/web directly, so
  # the one ngrok tunnel to port 8000 already covers the client too.
  echo "== Verifying through the public tunnel =="
  # Same reasoning as the --lan dart2js check: confirm the tunnel is
  # actually reaching a Django serving THIS build, not stale content or a
  # broken tunnel, before declaring success.
  if ! curl -s -m 15 -H "ngrok-skip-browser-warning: true" "${NGROK_URL}/flutter_bootstrap.js" | grep -q '"compileTarget":"dart2js"'; then
    echo "ERROR: the public URL isn't serving this build. Check:" >&2
    echo "  cat /tmp/honeychain-ngrok.log" >&2
    echo "  cat /tmp/honeychain-django.log" >&2
    exit 1
  fi
  echo "   verified -- anyone can now reach:"
  echo "     $NGROK_URL"
  echo "   this is a release build, so there's no debug/hot-reload -- re-run"
  echo "   '$0 --public' after making code changes to pick them up."
  echo "   NOTE: free ngrok shows a one-time 'Visit Site' page to browsers on"
  echo "   first load of this URL -- expected, just click through."
fi

cat <<EOF

== Stack is up ==
  Hardhat node:   http://127.0.0.1:8545          (logs: /tmp/honeychain-hardhat.log)
  Django/GraphQL: http://127.0.0.1:8000/graphql  (bound to $DJANGO_BIND, running in this terminal below)

Next steps:
  1. Seed an admin account (only needs to be done once per fresh DB):
       cd backend && ./.venv/bin/python manage.py seed_admin --username hc_admin --password AdminPass123!
  2. Run the full end-to-end demo (registers a beekeeper, harvests, processes,
     quality-checks, packages, and verifies against the chain):
       python3 scripts/seed_demo.py
EOF

if [[ "$CLIENT_MODE" == "lan" ]]; then
  cat <<EOF
  3. Open http://${LAN_IP}:8080 on your phone (or any device on the same
     network/hotspot) and log in as hc_admin / a registered beekeeper.
     QR codes and the printed public trace URL will also use ${LAN_IP},
     so they open correctly from another device too.
EOF
elif [[ "$CLIENT_MODE" == "public" ]]; then
  cat <<EOF
  3. Share $NGROK_URL with anyone -- it's reachable from any network, not
     just this one. QR codes and the trace URL now point at it too.
     This tunnel dies when this script's ngrok process is stopped (or this
     machine sleeps/reboots) -- there's nothing persistent running elsewhere.
EOF
else
  cat <<EOF
  3. Open the printed public trace URL in a browser, or open the Flutter
     client (./scripts/dev_up.sh --client) and log in as hc_admin / a
     registered beekeeper to drive the whole flow by hand.
     To test from a phone or another device on this network, use
     ./scripts/dev_up.sh --lan. To let anyone on the internet in, use
     ./scripts/dev_up.sh --public.
EOF
fi

# Everything above (Hardhat, and for --lan/--public the client server) runs
# detached via nohup and is meant to keep running as a background daemon --
# re-running this script is what cleans those up (see the port-kill at the
# top). Django was also started backgrounded, just so the steps above could
# curl/verify it while they ran. Now that setup is done, swap it into THIS
# terminal instead: kill the backgrounded instance and exec a foreground
# copy in its place, so its request logs print here directly and Ctrl+C
# stops the backend cleanly (the daemons above are unaffected and keep
# running, same as if you'd left them from a previous run).
echo ""
echo "== Attaching Django to this terminal (Ctrl+C stops the backend only) =="
fuser -k -TERM 8000/tcp 2>/dev/null || true
sleep 1
fuser -k -KILL 8000/tcp 2>/dev/null || true
cd "$ROOT/backend"
exec ./.venv/bin/python manage.py runserver "$DJANGO_BIND"
