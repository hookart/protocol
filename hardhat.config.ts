import * as dotenv from "dotenv";
dotenv.config();
import { readFileSync } from "fs";
import * as toml from "toml";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-docgen";
import { HardhatUserConfig, subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
// import { LedgerSigner } from "@anders-t/ethers-ledger";

// default values here to avoid failures when running hardhat
const ROPSTEN_RPC = process.env.ROPSTEN_RPC || "1".repeat(32);
const GOERLI_RPC = process.env.GOERLI_RPC || "1".repeat(32);
const MAINNET_RPC = process.env.MAINNET_RPC || "1".repeat(32);
const PRIVATE_KEY = process.env.PRIVATE_KEY || "1".repeat(64);
const SOLC_DEFAULT = "0.8.10";

// try use forge config
let foundry: any;
try {
  foundry = toml.parse(readFileSync("./foundry.toml").toString());
  foundry.default.solc = foundry.default["solc-version"]
    ? foundry.default["solc-version"]
    : SOLC_DEFAULT;
} catch (error) {
  foundry = {
    default: {
      solc: SOLC_DEFAULT,
    },
  };
}

// prune forge style tests from hardhat paths
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
  async (_, __, runSuper) => {
    const paths = await runSuper();
    return paths.filter((p: string) => !p.endsWith(".t.sol"));
  }
);

const config: any = {
  docgen: {
    path: "./docs/generated",
    clear: true,
    runOnCompile: true,
    only: ["src/"],
    except: ["test/"],
  },
  paths: {
    cache: "cache-hardhat",
    sources: "./src",
    tests: "./integration",
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: { chainId: 1337, allowUnlimitedContractSize: true },
    ropsten: {
      url: ROPSTEN_RPC,
      accounts: [PRIVATE_KEY],
    },
    goerli: {
      url: GOERLI_RPC,
      accounts: [PRIVATE_KEY],
    },
    mainnet: {
      url: MAINNET_RPC,
    },
  },
  solidity: {
    version: foundry.default?.solc || SOLC_DEFAULT,
    settings: {
      optimizer: {
        enabled: true,
        runs: 10,
      },
    },
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 77,
    excludeContracts: ["src/test"],
    // API key for CoinMarketCap. https://pro.coinmarketcap.com/signup
    coinmarketcap: process.env.CMC_KEY ?? "",
  },
  namedAccounts: {
    deployer: "ledger://0x1cAA0034b17786E18D94Ca176b1F8ec3F7972908",
    weth: process.env.WETH_ADDRESS || "",
    approvedMarket:
      process.env.APROVED_MARKET ||
      "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
    vaultUpgrader: process.env.VAULT_UPGRADER || "",
    callsUpgrader: process.env.CALLS_UPGRADER || "",
    pauserRole: process.env.PAUSER_ROLE || "",
    marketConf: process.env.MARKET_CONF || "",
    collectionConf: process.env.COLLECTION_CONF || "",
    allowlister: process.env.ALLOWLISTER || "",
  },
  etherscan: {
    // API key for Etherscan. https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY ?? "",
  },
};

export default config;
