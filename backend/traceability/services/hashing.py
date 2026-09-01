import json

from web3 import Web3


def compute_event_hash(batch_id: str, event_type: str, event_data: dict) -> str:
    """Compute the canonical keccak256 hash of a batch event's content.

    This is called exactly once per event creation. The returned hex string
    (with "0x" prefix) is written to BatchEvent.data_hash *and* passed as the
    bytes32 argument to the contract's recordEvent() -- since both values
    come from this single call, they can never drift apart.
    """
    canonical = json.dumps(
        {"batch_id": batch_id, "event_type": event_type, "event_data": event_data},
        sort_keys=True,
        separators=(",", ":"),
    )
    # HexBytes.hex() in this web3.py version omits the "0x" prefix -- add it
    # back explicitly so stored/compared hashes are consistently "0x"-prefixed.
    return "0x" + Web3.keccak(text=canonical).hex()


def to_bytes32(hex_hash: str) -> bytes:
    """Convert a "0x..." hex hash string (as stored in BatchEvent.data_hash)
    into the raw 32-byte value web3.py expects for a Solidity bytes32 arg."""
    return Web3.to_bytes(hexstr=hex_hash)
