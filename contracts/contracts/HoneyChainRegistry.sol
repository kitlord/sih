// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title HoneyChainRegistry
/// @notice Minimal on-chain registry that anchors honey batch provenance data.
///         The application database (Postgres) holds the full record; this
///         contract stores only the essential identifiers and content hashes
///         needed to independently verify that off-chain history has not
///         been tampered with. Writes are restricted to an allowlisted set
///         of "relayer" addresses (the backend service wallet) so that
///         end users never need a wallet or testnet funds of their own.
contract HoneyChainRegistry {
    address public owner;
    mapping(address => bool) public relayers;

    struct BatchRecord {
        string batchId;
        string apiaryId;
        address recordedBy;
        uint256 createdAt;
        bool exists;
    }

    struct EventRecord {
        string eventType; // "HARVESTED" | "PROCESSED" | "QUALITY_CHECKED" | "PACKAGED"
        bytes32 dataHash; // keccak256 of the canonical off-chain event payload
        address recordedBy;
        uint256 timestamp;
    }

    mapping(string => BatchRecord) private batches;
    mapping(string => EventRecord[]) private batchEvents;

    event RelayerUpdated(address indexed relayer, bool allowed);
    event BatchCreated(string indexed batchIdIndexed, string batchId, string apiaryId, address indexed recordedBy, uint256 timestamp);
    event BatchEventRecorded(
        string indexed batchIdIndexed,
        string batchId,
        string eventType,
        bytes32 dataHash,
        address indexed recordedBy,
        uint256 timestamp,
        uint256 eventIndex
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "HoneyChainRegistry: not owner");
        _;
    }

    modifier onlyRelayer() {
        require(relayers[msg.sender], "HoneyChainRegistry: not relayer");
        _;
    }

    constructor(address initialRelayer) {
        owner = msg.sender;
        relayers[initialRelayer] = true;
        emit RelayerUpdated(initialRelayer, true);
    }

    /// @notice Owner-only: grant or revoke relayer (write) access.
    function setRelayer(address relayer, bool allowed) external onlyOwner {
        relayers[relayer] = allowed;
        emit RelayerUpdated(relayer, allowed);
    }

    /// @notice Register a new batch on-chain. Reverts if the batchId already exists.
    function createBatch(string calldata batchId, string calldata apiaryId) external onlyRelayer {
        require(!batches[batchId].exists, "HoneyChainRegistry: batch exists");
        batches[batchId] = BatchRecord({
            batchId: batchId,
            apiaryId: apiaryId,
            recordedBy: msg.sender,
            createdAt: block.timestamp,
            exists: true
        });
        emit BatchCreated(batchId, batchId, apiaryId, msg.sender, block.timestamp);
    }

    /// @notice Append a lifecycle event (with its content hash) to a batch's history.
    /// @return eventIndex The index of the newly appended event in the batch's event array.
    function recordEvent(
        string calldata batchId,
        string calldata eventType,
        bytes32 dataHash
    ) external onlyRelayer returns (uint256 eventIndex) {
        require(batches[batchId].exists, "HoneyChainRegistry: unknown batch");
        batchEvents[batchId].push(
            EventRecord({eventType: eventType, dataHash: dataHash, recordedBy: msg.sender, timestamp: block.timestamp})
        );
        eventIndex = batchEvents[batchId].length - 1;
        emit BatchEventRecorded(batchId, batchId, eventType, dataHash, msg.sender, block.timestamp, eventIndex);
    }

    /// @notice Read a batch's core record.
    function getBatch(string calldata batchId) external view returns (BatchRecord memory) {
        return batches[batchId];
    }

    /// @notice Read the full chronological event history for a batch.
    function getBatchEvents(string calldata batchId) external view returns (EventRecord[] memory) {
        return batchEvents[batchId];
    }

    /// @notice Number of events recorded for a batch (cheaper than fetching the whole array).
    function getBatchEventCount(string calldata batchId) external view returns (uint256) {
        return batchEvents[batchId].length;
    }

    /// @notice Verify that the hash stored on-chain for a given batch/event index
    ///         matches an expected hash computed off-chain from the current data.
    function verifyHash(string calldata batchId, uint256 index, bytes32 expectedHash) external view returns (bool) {
        require(index < batchEvents[batchId].length, "HoneyChainRegistry: index out of range");
        return batchEvents[batchId][index].dataHash == expectedHash;
    }
}
