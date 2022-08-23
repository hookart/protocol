import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  console.log("what is happening");

  let {
    deployer,
    vaultUpgrader,
    callsUpgrader,
    pauserRole,
    marketConf,
    collectionConf,
    allowlister,
    weth,
    approvedMarket,
  } = await getNamedAccounts();

  console.log(deployer);

  console.log("Deploying from", deployer);

  console.log("Deploying with these args:", [
    allowlister,
    pauserRole,
    vaultUpgrader,
    callsUpgrader,
    marketConf,
    collectionConf,
    weth,
  ]);

  const protocol = await deploy("HookProtocol", {
    from: deployer,
    args: [
      allowlister,
      pauserRole,
      vaultUpgrader,
      callsUpgrader,
      marketConf,
      collectionConf,
      weth,
    ],
    log: true,
    autoMine: true,
  });

  const protocolImpl = await ethers.getContractAt(
    "HookProtocol",
    protocol.address
  );

  const soloVault = await deploy("HookERC721VaultImplV1", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  });

  const multiVault = await deploy("HookERC721MultiVaultImplV1", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  });

  const multiVaultBeacon = await deploy("HookUpgradeableBeacon", {
    from: deployer,
    args: [
      multiVault.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER"),
    ],
    log: true,
    autoMine: true,
  });

  const soloVaultBeacon = await deploy("HookUpgradeableBeacon", {
    from: deployer,
    args: [
      soloVault.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER"),
    ],
    log: true,
    autoMine: true,
  });

  const vaultFactory = await deploy("HookERC721VaultFactory", {
    from: deployer,
    args: [protocol.address, soloVaultBeacon.address, multiVaultBeacon.address],
    log: true,
    autoMine: true,
  });

  if (vaultUpgrader === deployer) {
    const vfSet = await protocolImpl.setVaultFactory(vaultFactory.address);
    console.log("Set vault factory onto protocol with hash: ", vfSet.hash);
  }

  const font1 = await deploy("Font1", {
    from: deployer,
    args: [],
    log: true,
    // maxPriorityFeePerGas: "2000000000",
    // maxFeePerGas: "50000000000",
    autoMine: true,
  });
  const font2 = await deploy("Font2", {
    from: deployer,
    args: [],
    log: true,
    // maxPriorityFeePerGas: "2000000000",
    // maxFeePerGas: "50000000000",
    autoMine: true,
  });
  const font3 = await deploy("Font3", {
    from: deployer,
    args: [],
    log: true,
    // maxPriorityFeePerGas: "2000000000",
    // maxFeePerGas: "50000000000",
    autoMine: true,
  });

  const tokenURI = await deploy("TokenURI", {
    from: deployer,
    args: [],
    libraries: {
      Font1: font1.address, // "0x1Ac06Ef3cda4dC2CB30A866090041D3266c33d45",
      Font2: font2.address, //"0xfa10218700bFd179DE800a461C98357b39525f38",
      Font3: font3.address, //"0x4C6eDA9CBb9B31152f3f002CAe5E3eF805Ad19f9",
    },
    log: true,
    // maxPriorityFeePerGas: "2000000000",
    // maxFeePerGas: "50000000000",
    autoMine: true,
  });
  const callV1 = await deploy("HookCoveredCallImplV1", {
    from: deployer,
    libraries: {
      TokenURI: tokenURI.address,
    },
    args: [],
    log: true,
    autoMine: true,
  });

  const callBeacon = await deploy("HookUpgradeableBeacon", {
    from: deployer,
    args: [
      "0x3648080307faC2EE51A01463e47B9ca076DC14A1",
      "0xE11CCED3E6555A1BcbA2E19b9Cf161f040186069",
      ethers.utils.id("CALL_UPGRADER"),
    ],
    log: true,
    autoMine: true,
  });

  const callFactory = await deploy("HookCoveredCallFactory", {
    from: deployer,
    args: [
      "0xE11CCED3E6555A1BcbA2E19b9Cf161f040186069",
      callBeacon.address,
      approvedMarket,
    ],
    log: true,
    autoMine: true,
  });

  if (deployer === callsUpgrader) {
    const cfSet = await protocolImpl.setCoveredCallFactory(callFactory.address);
    console.log("Set call factory onto protocol with hash: ", cfSet.hash);
  }

  if (deployer == pauserRole) {
    // Will need to pause outside of this context
    // for the process to work with mainnet deploys
    await protocolImpl.connect(deployer).pause();
  }

  return true;
};
export default func;
func.id = "deploy_hook_protocol"; // id required to prevent reexecution
func.tags = ["HookProtocol"];
