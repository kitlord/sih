require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    // In-memory ephemeral chain used by `hardhat test`.
    hardhat: {},
    // Persistent local node (`npx hardhat node`) that the Django backend
    // treats as its "EVM-compatible testnet" for the whole dev/demo session.
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
};
