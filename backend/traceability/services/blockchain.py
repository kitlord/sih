"""Thin wrapper around the HoneyChainRegistry smart contract.

The Django backend holds a single "relayer" private key and signs every
on-chain transaction itself -- beekeepers, admins, and consumers never touch
a wallet or need testnet funds. WEB3_RPC_URL / RELAYER_PRIVATE_KEY /
CONTRACT_ARTIFACT_PATH are the only things that would need to change to
point this at a public testnet (e.g. Sepolia) instead of the local Hardhat
node used for this MVP.

Known, accepted MVP limitation: nonce management uses the "pending" tx
count, which is correct for a single Django dev-server process but not
safe under concurrent writers. A production version would need a proper
nonce-management queue; out of scope here.
"""

import json

from django.conf import settings
from web3 import Web3

from .hashing import to_bytes32


class BlockchainError(Exception):
    """Raised when an on-chain call fails (revert, timeout, connection)."""


class BlockchainService:
    def __init__(self):
        self.w3 = Web3(Web3.HTTPProvider(settings.WEB3_RPC_URL))
        with open(settings.CONTRACT_ARTIFACT_PATH) as f:
            artifact = json.load(f)
        self.contract = self.w3.eth.contract(address=artifact["address"], abi=artifact["abi"])
        self.account = self.w3.eth.account.from_key(settings.RELAYER_PRIVATE_KEY)

    def _send(self, fn):
        try:
            tx = fn.build_transaction(
                {
                    "from": self.account.address,
                    "nonce": self.w3.eth.get_transaction_count(self.account.address, "pending"),
                    "gas": 500_000,
                    "gasPrice": self.w3.eth.gas_price,
                }
            )
            signed = self.account.sign_transaction(tx)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        except Exception as exc:  # noqa: BLE001 -- surfaced as a domain error to callers
            raise BlockchainError(str(exc)) from exc
        if receipt.status != 1:
            raise BlockchainError(f"transaction reverted: {receipt.transactionHash.hex()}")
        return receipt

    def create_batch_onchain(self, batch_id: str, apiary_id: str):
        """Returns the transaction receipt."""
        return self._send(self.contract.functions.createBatch(batch_id, apiary_id))

    def record_event_onchain(self, batch_id: str, event_type: str, data_hash_hex: str):
        """Records an event on-chain and returns
        (tx_hash_hex, block_number, chain_event_index)."""
        receipt = self._send(
            self.contract.functions.recordEvent(batch_id, event_type, to_bytes32(data_hash_hex))
        )
        logs = self.contract.events.BatchEventRecorded().process_receipt(receipt)
        if not logs:
            raise BlockchainError("BatchEventRecorded event not found in transaction receipt")
        event_index = logs[0]["args"]["eventIndex"]
        return "0x" + receipt.transactionHash.hex().removeprefix("0x"), receipt.blockNumber, event_index

    def get_batch(self, batch_id: str):
        return self.contract.functions.getBatch(batch_id).call()

    def get_batch_events(self, batch_id: str):
        return self.contract.functions.getBatchEvents(batch_id).call()

    def verify_hash(self, batch_id: str, index: int, expected_hash_hex: str) -> bool:
        try:
            return self.contract.functions.verifyHash(batch_id, index, to_bytes32(expected_hash_hex)).call()
        except Exception:
            return False


_instance = None


def get_blockchain_service() -> BlockchainService:
    """Lazily-constructed module-level singleton -- avoids re-reading the
    contract artifact file and reconnecting on every call."""
    global _instance
    if _instance is None:
        _instance = BlockchainService()
    return _instance
