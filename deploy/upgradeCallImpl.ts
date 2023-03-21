// import { HardhatRuntimeEnvironment } from "hardhat/types";
// import { DeployFunction } from "hardhat-deploy/types";

// const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
//   const { deployments, getNamedAccounts } = hre;
//   const { deploy } = deployments;
//   console.log("what is happening");

//   let {
//     deployer,
//     vaultUpgrader,
//     callsUpgrader,
//     pauserRole,
//     marketConf,
//     collectionConf,
//     allowlister,
//     weth,
//     // `    approvedMarket,`
//   } = await getNamedAccounts();

//   console.log(deployer);

//   console.log("Deploying from", deployer);

//   console.log("Upgrading with these args:", [
//     allowlister,
//     pauserRole,
//     vaultUpgrader,
//     callsUpgrader,
//     marketConf,
//     collectionConf,
//     weth,
//   ]);

//   const callV1 = await deploy("HookCoveredCallImplV1", {
//     from: deployer,
//     skipIfAlreadyDeployed: false,
//     libraries: {
//       TokenURI: "0xa74f6fa54019BD7c8f2479DFEfD4c04CA5d7eE3d", // tokenURI.address,
//     },
//     args: [],
//     log: true,
//     autoMine: true,
//     gasLimit: 5200000,
//   });

//   return true;
// };

// export default func;
// func.id = "deploy_call_impl"; // id required to prevent reexecution
// func.tags = ["CallImpl"];
