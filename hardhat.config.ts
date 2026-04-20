import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun", // Required for EIP-1153 (TSTORE/TLOAD)
    },
  },
  networks: {
    // Add your network configs here (e.g. Sepolia, Base)
  },
};

export default config;
