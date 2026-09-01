const fs = require("fs");
const path = require("path");
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log(`Deploying HoneyChainRegistry to network "${hre.network.name}"`);
  console.log(`Deployer / initial relayer address: ${deployer.address}`);

  const Registry = await hre.ethers.getContractFactory("HoneyChainRegistry");
  const registry = await Registry.deploy(deployer.address);
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  const network = await hre.ethers.provider.getNetwork();

  const artifactPath = path.join(
    __dirname,
    "..",
    "artifacts",
    "contracts",
    "HoneyChainRegistry.sol",
    "HoneyChainRegistry.json"
  );
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

  const deploymentsDir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(deploymentsDir, { recursive: true });

  const outPath = path.join(deploymentsDir, `${hre.network.name}.json`);
  const payload = {
    network: hre.network.name,
    chainId: Number(network.chainId),
    address,
    deployerAddress: deployer.address,
    abi: artifact.abi,
    deployedAt: new Date().toISOString(),
  };
  fs.writeFileSync(outPath, JSON.stringify(payload, null, 2));

  console.log(`HoneyChainRegistry deployed at: ${address}`);
  console.log(`Deployment artifact written to: ${outPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
