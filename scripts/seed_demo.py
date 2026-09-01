#!/usr/bin/env python3
"""End-to-end demo seed script for Honey Chain.

Drives the live GraphQL API exactly the way the Flutter client would (plain
HTTP + JWT, no Django import), walking the full happy path:

  register beekeeper -> createApiary -> createHive -> createHoneyBatch
  -> recordProcessingEvent -> (log in as admin) -> recordQualityCheck(PASSED)
  -> packageBatch -> publicTraceByBatchId (asserts every event verifies)

This is what proves the whole stack works end to end (HTTP + JWT +
resolvers + real on-chain transactions), not just the Django ORM.

Prerequisites (see scripts/dev_up.sh):
  - the local Hardhat node is running and the contract is deployed
  - `manage.py migrate` has run
  - `manage.py seed_admin` has created an admin account
  - `manage.py runserver` is serving /graphql

Usage:
  python3 scripts/seed_demo.py [--base-url http://127.0.0.1:8000] \
      [--admin-username hc_admin] [--admin-password AdminPass123!]
"""

import argparse
import json
import random
import string
import sys
import urllib.error
import urllib.request


def gql(base_url: str, query: str, variables: dict, token: str | None = None) -> dict:
    body = json.dumps({"query": query, "variables": variables}).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{base_url}/graphql", data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        print(exc.read().decode(), file=sys.stderr)
        raise
    if payload.get("errors"):
        raise RuntimeError(f"GraphQL error: {json.dumps(payload['errors'], indent=2)}")
    return payload["data"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--admin-username", default="hc_admin")
    parser.add_argument("--admin-password", default="AdminPass123!")
    args = parser.parse_args()

    suffix = "".join(random.choices(string.digits, k=5))
    beekeeper_username = f"demo_beekeeper_{suffix}"

    print(f"== Registering beekeeper {beekeeper_username} ==")
    data = gql(
        args.base_url,
        """
        mutation Register($u: String!, $e: String!, $p: String!) {
          register(username: $u, email: $e, password: $p) { token user { id username role } }
        }
        """,
        {"u": beekeeper_username, "e": f"{beekeeper_username}@example.com", "p": "BeekeeperPass123!"},
    )
    beekeeper_token = data["register"]["token"]
    print("  ok:", data["register"]["user"])

    print("== Creating apiary ==")
    data = gql(
        args.base_url,
        """
        mutation CreateApiary($name: String!, $loc: String!) {
          createApiary(name: $name, locationDescription: $loc) { id name }
        }
        """,
        {"name": "Sunny Meadow Apiary", "loc": "Back field, north of the orchard"},
        token=beekeeper_token,
    )
    apiary_id = data["createApiary"]["id"]
    print("  ok:", data["createApiary"])

    print("== Creating hive ==")
    data = gql(
        args.base_url,
        """
        mutation CreateHive($apiaryId: ID!, $label: String!, $hiveType: String!) {
          createHive(apiaryId: $apiaryId, label: $label, hiveType: $hiveType) { id label }
        }
        """,
        {"apiaryId": apiary_id, "label": "Hive-01", "hiveType": "Langstroth"},
        token=beekeeper_token,
    )
    hive_id = data["createHive"]["id"]
    print("  ok:", data["createHive"])

    print("== Creating honey batch (records HARVESTED on-chain) ==")
    data = gql(
        args.base_url,
        """
        mutation CreateBatch($apiaryId: ID!, $hiveIds: [ID!]!, $date: String!, $qty: Float!, $floral: String!) {
          createHoneyBatch(apiaryId: $apiaryId, hiveIds: $hiveIds, harvestDate: $date, quantityKg: $qty, floralSource: $floral) {
            id batchId status events { eventType txHash chainStatus }
          }
        }
        """,
        {"apiaryId": apiary_id, "hiveIds": [hive_id], "date": "2026-08-15", "qty": 12.5, "floral": "Wildflower"},
        token=beekeeper_token,
    )
    batch_id = data["createHoneyBatch"]["batchId"]
    print("  ok:", data["createHoneyBatch"])

    print("== Recording processing event ==")
    data = gql(
        args.base_url,
        """
        mutation RecordProcessing($batchId: String!, $method: String!, $notes: String!) {
          recordProcessingEvent(batchId: $batchId, method: $method, notes: $notes) {
            status events { eventType txHash chainStatus }
          }
        }
        """,
        {"batchId": batch_id, "method": "Cold extraction", "notes": "Extracted same day as harvest"},
        token=beekeeper_token,
    )
    print("  ok:", data["recordProcessingEvent"])

    print(f"== Logging in as admin {args.admin_username} ==")
    data = gql(
        args.base_url,
        """
        mutation Login($u: String!, $p: String!) { login(username: $u, password: $p) { token } }
        """,
        {"u": args.admin_username, "p": args.admin_password},
    )
    admin_token = data["login"]["token"]
    print("  ok")

    print("== Recording quality check (PASSED) ==")
    data = gql(
        args.base_url,
        """
        mutation QC($batchId: String!, $result: String!, $moisture: Float!, $notes: String!) {
          recordQualityCheck(batchId: $batchId, result: $result, moistureContent: $moisture, purityNotes: $notes) {
            status events { eventType txHash chainStatus }
          }
        }
        """,
        {"batchId": batch_id, "result": "PASSED", "moisture": 17.2, "notes": "Clear, low moisture, no defects"},
        token=admin_token,
    )
    print("  ok:", data["recordQualityCheck"])

    print("== Packaging batch (generates QR) ==")
    data = gql(
        args.base_url,
        """
        mutation Pack($batchId: String!, $code: String!, $units: Int!) {
          packageBatch(batchId: $batchId, packageCode: $code, unitCount: $units) {
            status
            package { qrCodeUrl publicUrl }
            events { eventType txHash chainStatus }
          }
        }
        """,
        {"batchId": batch_id, "code": f"PKG-{batch_id}", "units": 24},
        token=admin_token,
    )
    package = data["packageBatch"]["package"]
    print("  ok:", data["packageBatch"])

    print("== Fetching public trace page data (unauthenticated) ==")
    data = gql(
        args.base_url,
        """
        query Trace($batchId: String!) {
          publicTraceByBatchId(batchId: $batchId) {
            batchId apiaryName harvestDate hiveLabels quantityKg floralSource status
            qualityResult packageCode allEventsChainVerified
            events { eventType txHash chainStatus chainVerified }
          }
        }
        """,
        {"batchId": batch_id},
    )
    trace = data["publicTraceByBatchId"]
    assert trace is not None, "public trace lookup returned nothing for a packaged batch"
    assert trace["allEventsChainVerified"], "not every event verified against the chain!"
    for e in trace["events"]:
        assert e["chainVerified"], f"event failed verification: {e}"

    print("\n=== DEMO SUMMARY ===")
    print(f"Batch ID:        {batch_id}")
    print(f"Status:          {trace['status']}")
    print(f"Apiary:          {trace['apiaryName']}")
    print(f"Hives:           {', '.join(trace['hiveLabels'])}")
    print(f"Quality result:  {trace['qualityResult']}")
    print("Tx hashes per stage:")
    for e in trace["events"]:
        print(f"  - {e['eventType']:<16} {e['txHash']}  (verified={e['chainVerified']})")
    print(f"QR code image:   {package['qrCodeUrl']}")
    print(f"Public trace URL: {package['publicUrl']}")
    print("\nOpen the public trace URL above in a browser -- that's the 'consumer scans the QR' step.")
    print("All events verified against the blockchain. Demo data ready.")


if __name__ == "__main__":
    main()
