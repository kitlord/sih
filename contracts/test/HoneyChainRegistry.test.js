const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("HoneyChainRegistry", function () {
  async function deployFixture() {
    const [owner, relayer, other] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("HoneyChainRegistry");
    const registry = await Registry.deploy(relayer.address);
    await registry.waitForDeployment();
    return { registry, owner, relayer, other };
  }

  function hashOf(text) {
    return ethers.keccak256(ethers.toUtf8Bytes(text));
  }

  describe("deployment", function () {
    it("sets the deployer as owner and the constructor arg as an allowed relayer", async function () {
      const { registry, owner, relayer } = await loadFixture(deployFixture);
      expect(await registry.owner()).to.equal(owner.address);
      expect(await registry.relayers(relayer.address)).to.equal(true);
    });
  });

  describe("access control", function () {
    it("reverts createBatch from a non-relayer", async function () {
      const { registry, other } = await loadFixture(deployFixture);
      await expect(registry.connect(other).createBatch("HC-2026-0001", "APIARY-1")).to.be.revertedWith(
        "HoneyChainRegistry: not relayer"
      );
    });

    it("reverts recordEvent from a non-relayer", async function () {
      const { registry, relayer, other } = await loadFixture(deployFixture);
      await registry.connect(relayer).createBatch("HC-2026-0001", "APIARY-1");
      await expect(
        registry.connect(other).recordEvent("HC-2026-0001", "HARVESTED", hashOf("payload"))
      ).to.be.revertedWith("HoneyChainRegistry: not relayer");
    });

    it("lets the owner add/remove relayers, and only the owner", async function () {
      const { registry, owner, other } = await loadFixture(deployFixture);
      await expect(registry.connect(other).setRelayer(other.address, true)).to.be.revertedWith(
        "HoneyChainRegistry: not owner"
      );
      await expect(registry.connect(owner).setRelayer(other.address, true))
        .to.emit(registry, "RelayerUpdated")
        .withArgs(other.address, true);
      expect(await registry.relayers(other.address)).to.equal(true);
    });
  });

  describe("batch + event lifecycle", function () {
    it("reverts on duplicate batch creation", async function () {
      const { registry, relayer } = await loadFixture(deployFixture);
      await registry.connect(relayer).createBatch("HC-2026-0001", "APIARY-1");
      await expect(registry.connect(relayer).createBatch("HC-2026-0001", "APIARY-1")).to.be.revertedWith(
        "HoneyChainRegistry: batch exists"
      );
    });

    it("reverts recordEvent for an unknown batch", async function () {
      const { registry, relayer } = await loadFixture(deployFixture);
      await expect(
        registry.connect(relayer).recordEvent("HC-NOPE", "HARVESTED", hashOf("x"))
      ).to.be.revertedWith("HoneyChainRegistry: unknown batch");
    });

    it("records a full batch history in order and exposes it via getBatchEvents", async function () {
      const { registry, relayer } = await loadFixture(deployFixture);
      const batchId = "HC-2026-0001";
      await registry.connect(relayer).createBatch(batchId, "APIARY-1");

      const stages = ["HARVESTED", "PROCESSED", "QUALITY_CHECKED", "PACKAGED"];
      const hashes = stages.map((stage) => hashOf(`${batchId}:${stage}`));

      for (let i = 0; i < stages.length; i++) {
        const tx = registry.connect(relayer).recordEvent(batchId, stages[i], hashes[i]);
        // Confirm the event fires with the correct non-indexed fields (batchId,
        // eventType, dataHash, recordedBy, eventIndex). The timestamp arg is
        // omitted from the assertion since block.timestamp isn't known in advance.
        await expect(tx).to.emit(registry, "BatchEventRecorded");
        const receipt = await (await tx).wait();
        const parsed = receipt.logs
          .map((log) => {
            try {
              return registry.interface.parseLog(log);
            } catch {
              return null;
            }
          })
          .find((e) => e && e.name === "BatchEventRecorded");
        expect(parsed.args.batchId).to.equal(batchId);
        expect(parsed.args.eventType).to.equal(stages[i]);
        expect(parsed.args.dataHash).to.equal(hashes[i]);
        expect(parsed.args.recordedBy).to.equal(relayer.address);
        expect(parsed.args.eventIndex).to.equal(BigInt(i));
      }

      expect(await registry.getBatchEventCount(batchId)).to.equal(4);
      const events = await registry.getBatchEvents(batchId);
      expect(events.map((e) => e.eventType)).to.deep.equal(stages);
      expect(events.map((e) => e.dataHash)).to.deep.equal(hashes);

      const batch = await registry.getBatch(batchId);
      expect(batch.batchId).to.equal(batchId);
      expect(batch.apiaryId).to.equal("APIARY-1");
      expect(batch.exists).to.equal(true);
    });

    it("verifyHash returns true for the exact stored hash and false for a tampered one", async function () {
      const { registry, relayer } = await loadFixture(deployFixture);
      const batchId = "HC-2026-0002";
      const goodHash = hashOf("real-payload");
      const badHash = hashOf("tampered-payload");

      await registry.connect(relayer).createBatch(batchId, "APIARY-1");
      await registry.connect(relayer).recordEvent(batchId, "HARVESTED", goodHash);

      expect(await registry.verifyHash(batchId, 0, goodHash)).to.equal(true);
      expect(await registry.verifyHash(batchId, 0, badHash)).to.equal(false);
    });
  });
});
