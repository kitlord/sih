# Honey Chain

A blockchain-based honey traceability and beekeeping management MVP.
Beekeepers register apiaries and hives, harvest and create honey batches,
and track them through processing, quality verification, and packaging.
Every stage is anchored on an EVM-compatible blockchain, and a QR code on
each packaged product opens a public page where any consumer can see the
full provenance and verify it against the chain — no wallet required.

## Architecture

```
contracts/   Solidity smart contract (Hardhat project) -- the immutable
             verification layer. Stores only batch IDs, event types, and
             content hashes; never the full application data.
backend/     Django + Strawberry GraphQL API + PostgreSQL -- the source of
             truth for all application data (users, apiaries, hives,
             batches, events, quality checks, packages, QR images).
client/      Flutter Web app -- beekeeper, admin, and public consumer UIs,
             talking only to the GraphQL API (never touches the chain
             directly).
scripts/     dev_up.sh (bring up the whole stack) and seed_demo.py (drives
             the full happy-path flow through the live API).
```

**Blockchain layer**: a local Hardhat node stands in for "an EVM-compatible
testnet" (Hardhat is a standard, real EVM implementation — this just avoids
needing a funded public-testnet wallet for a demo). The Django backend
holds one relayer private key and signs every on-chain transaction itself;
beekeepers, admins, and consumers never see a wallet, a gas fee, or a seed
phrase. Pointing this at a public testnet (Sepolia, Polygon Amoy, etc.)
later is purely a config change — `WEB3_RPC_URL`, `RELAYER_PRIVATE_KEY`,
and redeploying the contract — no code changes.

**Data model**: Postgres holds the full record (`User`, `Apiary`, `Hive`,
`HoneyBatch`, `BatchEvent`, `QualityCheck`, `Package`). `BatchEvent` is the
chronological spine — every stage transition (Harvested → Processed →
Quality checked → Packaged) creates one, carrying a `data_hash` that is
also written on-chain, so the public trace page can independently recompute
and verify each stage rather than just trusting the database.

## Prerequisites

Python 3.11+, Node 18+, Flutter (web support enabled), a running
PostgreSQL server. All confirmed working with Python 3.14, Node 26,
Flutter 3.44, PostgreSQL 18.

## First-time setup

```bash
# 1. Database (adjust credentials as you like, then match them in backend/.env)
psql -U postgres -c "CREATE ROLE honeychain WITH LOGIN PASSWORD 'honeychain_dev_pw' CREATEDB;"
psql -U postgres -c "CREATE DATABASE honeychain OWNER honeychain;"

# 2. Contracts
cd contracts && npm install && cd ..

# 3. Backend
cd backend
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
cp .env.example .env   # adjust DB creds / secrets if needed
cd ..

# 4. Client
cd client && flutter pub get && cd ..
```

## Running it

```bash
./scripts/dev_up.sh              # starts Hardhat node + deploys contract + migrates + runs Django
./scripts/dev_up.sh --client     # ...and also serves the Flutter web client on :8080

# one-time per fresh database: seed an admin (the public `register`
# mutation can only ever create beekeeper accounts, by design)
cd backend && ./.venv/bin/python manage.py seed_admin --username hc_admin --password AdminPass123!
cd ..

# drives the full golden-path flow against the live API and prints a summary
# with real transaction hashes and the public trace URL
python3 scripts/seed_demo.py
```

Then either open the printed `/trace/<batchId>` URL directly, or open the
Flutter client and log in as `hc_admin` / a registered beekeeper to drive
apiaries → hives → batches → processing → quality check → packaging by
hand.

> **Flutter debug-mode quirk**: if you run the client with `flutter run`
> (debug web-server or Chrome), always open it via `http://127.0.0.1:8080`,
> not `http://localhost:8080` — Flutter's debug tooling (DWDS) only attaches
> reliably from the exact host it reports serving on; the other hostname
> loads a blank black page. This doesn't apply to a `flutter build web`
> production build, which has no debug tooling at all. `PUBLIC_BASE_URL` in
> `backend/.env` is already set to the `127.0.0.1` form for this reason.

## The demo flow (spec's primary end-to-end scenario)

1. A beekeeper registers, creates an apiary, adds a hive.
2. After a harvest, they create a honey batch (apiary, hives, harvest date,
   quantity, floral source) — this writes `HARVESTED` to Postgres **and**
   to the chain.
3. They record processing (method/notes) — `PROCESSED`, another on-chain
   event.
4. An admin records a quality check (result/moisture/notes) — passing
   advances the batch to `QUALITY_CHECKED`, another on-chain event.
5. The admin packages the batch (package code, unit count) — this
   generates a QR code, advances the batch to `PACKAGED`, and writes the
   final on-chain event.
6. Anyone opens the QR's URL (`/trace/<batchId>`) with no login and no
   wallet, and sees the complete history with a real transaction hash per
   stage, each independently re-verified against the chain at page-load
   time.

## FSSAI license verification (via API Setu)

Separate from the batch-provenance chain above: an apiary can have a
self-reported FSSAI license number independently confirmed against the
real government registry, live — not just format-checked.

- **Mocked by default** (`DIGILOCKER_USE_MOCK=True` in `backend/.env`) —
  accepts any correctly-shaped 14-digit number; no real registry behind it.
- Set **`DIGILOCKER_USE_MOCK=False`** to call the real thing: **API Setu**
  (`apisetu.gov.in`), the official government API exchange (NIC/MeitY),
  whose FSSAI collection exposes the same DigiLocker-backed verification
  as a direct synchronous call — no OAuth redirect. `APISETU_API_KEY` /
  `APISETU_CLIENT_ID` already default to API Setu's own public sandbox
  demo credentials, so this works against the live sandbox with zero
  signup or extra config. See `backend/.env.example` and
  `backend/traceability/services/digilocker.py`'s module docstring for
  why getting a *personal* API Setu key is a separate, much heavier thing
  (a Partner account verified by GSTIN/PAN/MSME/a `.gov.in` site — built
  for registered businesses/government bodies, not needed for this MVP).

To try it: on an apiary's detail page in the Flutter client, add an
FSSAI license number, then tap **"Verify via DigiLocker"** — it opens a
consent page in a new tab; approving it fires the real API Setu call and
the tab redirects back with the result. The backend console
(`manage.py runserver`) logs one line per real check —
`API Setu FSSAI check (...): HTTP <code> from https://sandbox.api-setu.in/...`
— as on-screen evidence a call actually went out over the network. A
"not verified" result on a made-up license number is the *expected*,
correct outcome and is itself proof this is real: the mock accepts any
correctly-shaped number, the live registry only confirms numbers that
actually exist in it.

## Testing / verification

```bash
cd contracts && npx hardhat test        # 8 tests: access control, lifecycle, hash verification
cd backend && ./.venv/bin/python manage.py test traceability   # model smoke tests + digilocker service tests
cd client && flutter analyze            # static analysis, should report "No issues found!"
```

`scripts/seed_demo.py` is itself the strongest end-to-end check: it exits
non-zero if any event fails to verify against the live chain.

## Known, deliberate MVP limitations

- **Nonce management** in `backend/traceability/services/blockchain.py`
  uses the pending transaction count — correct for a single Django dev
  server, not safe for concurrent writers. A production version would need
  a proper nonce-management queue.
- **No reject/retry flow** for a failed quality check — the batch simply
  stays at `PROCESSED`. Out of scope for this MVP per the spec.
- **No IoT sensors, AI, disease detection, predictive analytics,
  marketplace, payments, NFTs, token economics, GPS tracking, or custom
  blockchain** — explicitly excluded by the spec in favor of one clean,
  working end-to-end flow.
- `myApiaries`/`myBatches` are simple list queries filtered client-side for
  detail screens (e.g. "batches from this apiary") rather than dedicated
  single-entity GraphQL queries — a reasonable simplification at this
  MVP's data scale.
- **FSSAI has two certificate types** ("Registration Certificate" for
  small/petty food businesses, "Food Stuff License" for larger ones),
  both colloquially "the FSSAI license number." `Apiary.fssai_license_number`
  doesn't distinguish between them — `APISETU_FSSAI_ENDPOINT` picks which
  one the whole deployment checks against (default `recer`, the tier most
  individual beekeepers are likely to hold), rather than supporting both
  per-apiary.
