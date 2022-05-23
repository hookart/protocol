import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Vault", function () {
  let vaultFactory: Contract, protocol: Contract, testNFT: Contract;
  let admin: SignerWithAddress,
    beneficialOwner: SignerWithAddress,
    runner: SignerWithAddress;

  before(async () => {
    [admin, beneficialOwner, runner] = await ethers.getSigners();
    const weath = await ethers.getContractFactory("WETH");

    const protocolFactory = await ethers.getContractFactory("HookProtocol");

    const vaultFactoryFactory = await ethers.getContractFactory(
      "HookERC721VaultFactory"
    );

    const token = await ethers.getContractFactory("TestERC721");
    const vaultImplFactory = await ethers.getContractFactory(
      "HookERC721VaultImplV1"
    );
    const vaultBeaconFactory = await ethers.getContractFactory(
      "HookERC721VaultBeacon"
    );
    const multiVaultImplFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultImplV1"
    );
    const multiVaultBeaconFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultBeacon"
    );

    const weth = await weath.deploy();
    testNFT = await token.deploy();
    protocol = await protocolFactory.deploy(admin.address, weth.address);
    const vaultImpl = await vaultImplFactory.deploy();
    const multiVaultImpl = await multiVaultImplFactory.deploy();

    const vaultBeacon = await vaultBeaconFactory.deploy(
      vaultImpl.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER")
    );

    const multiVaultBeacon = await multiVaultBeaconFactory.deploy(
      multiVaultImpl.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER")
    );

    vaultFactory = await vaultFactoryFactory.deploy(
      protocol.address,
      vaultBeacon.address,
      multiVaultBeacon.address
    );
  });

  it("the factory should be able to make a vault", async function () {
    const [admin] = await ethers.getSigners();
    vaultFactory.callStatic["makeSoloVault"].call(testNFT.address, 1);
  });

  it("the factory should be able to make a multi vault", async function () {
    const [admin] = await ethers.getSigners();
    vaultFactory.callStatic["makeMultiVault"].call(testNFT.address);
  });
});
