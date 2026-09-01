#!/usr/bin/env bash
# Brings up the full Honey Chain dev/demo stack from a cold start:
#   Hardhat node -> deploy contract -> Postgres migrate -> Django -> (optional) Flutter web
#
# Each service is started in the background and logs to /tmp/honeychain-*.log.
# Safe to re-run: it kills any previous instances of these dev processes first.
#
# Usage:
#   ./scripts/dev_up.sh            # backend + chain only
#   ./scripts/dev_up.sh --client   # also launches the Flutter web client on :8080
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "== Stopping any previous dev processes =="
pkill -f "hardhat node" 2>/dev/null || true
pkill -f "manage.py runserver" 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
sleep 1

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

echo "== Starting Django (GraphQL API) =="
(cd "$ROOT/backend" && nohup ./.venv/bin/python manage.py runserver 127.0.0.1:8000 > /tmp/honeychain-django.log 2>&1 &)
until curl -s -m 1 -o /dev/null http://127.0.0.1:8000/graphql; do sleep 1; done
echo "   backend ready at http://127.0.0.1:8000/graphql (GraphiQL enabled)"

if [[ "${1:-}" == "--client" ]]; then
  echo "== Starting Flutter web client on :8080 =="
  (cd "$ROOT/client" && nohup flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0 \
      --dart-define=GRAPHQL_ENDPOINT=http://127.0.0.1:8000/graphql \
      > /tmp/honeychain-flutter.log 2>&1 &)
  echo "   client starting at http://127.0.0.1:8080 (first load compiles, can take ~30s)"
  echo "   NOTE: open it as http://127.0.0.1:8080, not http://localhost:8080 -- Flutter's"
  echo "   debug web tooling only attaches reliably from the exact host it serves on."
fi

cat <<'EOF'

== Stack is up ==
  Hardhat node:  http://127.0.0.1:8545          (logs: /tmp/honeychain-hardhat.log)
  Django/GraphQL: http://127.0.0.1:8000/graphql (logs: /tmp/honeychain-django.log)

Next steps:
  1. Seed an admin account (only needs to be done once per fresh DB):
       cd backend && ./.venv/bin/python manage.py seed_admin --username hc_admin --password AdminPass123!
  2. Run the full end-to-end demo (registers a beekeeper, harvests, processes,
     quality-checks, packages, and verifies against the chain):
       python3 scripts/seed_demo.py
  3. Open the printed public trace URL in a browser, or open the Flutter
     client (./scripts/dev_up.sh --client) and log in as hc_admin / a
     registered beekeeper to drive the whole flow by hand.
EOF
