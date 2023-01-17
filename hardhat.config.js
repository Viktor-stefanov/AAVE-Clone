require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");

module.exports = {
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545/",
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    deployer2: {
      default: 1,
    },
  },
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10,
      },
    },
  },
};
