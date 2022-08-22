import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer, weth, approvedMarket } = await getNamedAccounts();
  // proxy only in non-live network (localhost and hardhat network) enabling HCR (Hot Contract Replacement)
  // in live network, proxy is disabled and constructor is invoked
  const protocol = await deploy("HookProtocol", {
    from: deployer,
    args: [deployer, deployer, deployer, deployer, deployer, deployer, weth],
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

  const vfSet = await protocolImpl.setVaultFactory(vaultFactory.address);

  console.log("Set vault factory onto protocol with hash: ", vfSet.hash);

  // const font1 = await deploy("Font1", {
  //   from: deployer,
  //   args: [],
  //   log: true,
  //   maxPriorityFeePerGas: "2048937",
  //   maxFeePerGas: "11489370",
  //   autoMine: true,
  // });
  // const font2 = await deploy("Font2", {
  //   from: deployer,
  //   args: [],
  //   log: true,
  //   maxPriorityFeePerGas: "2048937",
  //   maxFeePerGas: "11489370",
  //   autoMine: true,
  // });
  // const font3 = await deploy("Font3", {
  //   from: deployer,
  //   args: [],
  //   log: true,
  //   maxPriorityFeePerGas: "2048937",
  //   maxFeePerGas: "11489370",
  //   autoMine: true,
  // });

  const tokenURI = await deploy("TokenURI", {
    from: deployer,
    args: [],
    libraries: {
      Font1: "0x1Ac06Ef3cda4dC2CB30A866090041D3266c33d45",
      Font2: "0xfa10218700bFd179DE800a461C98357b39525f38",
      Font3: "0x4C6eDA9CBb9B31152f3f002CAe5E3eF805Ad19f9",
    },
    log: true,
    maxPriorityFeePerGas: "3000151502",
    maxFeePerGas: "3000151502",
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
    args: [callV1.address, protocol.address, ethers.utils.id("VAULT_UPGRADER")],
    log: true,
    autoMine: true,
  });

  const callFactory = await deploy("HookCoveredCallFactory", {
    from: deployer,
    args: [protocol.address, callBeacon.address, approvedMarket],
    log: true,
    autoMine: true,
  });

  const cfSet = await protocolImpl.setCoveredCallFactory(callFactory.address);

  console.log("Set call factory onto protocol with hash: ", cfSet.hash);

  // await protocolImpl.connect(deployer).unpause();
  return true;
};
export default func;
func.id = "deploy_hook_protocol"; // id required to prevent reexecution
func.tags = ["HookProtocol"];
