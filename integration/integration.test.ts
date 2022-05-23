import { expect } from "chai";
import { ethers } from "hardhat";
import type { Contract, PayableOverrides } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Integrations", function () {
  let vaultFactory: Contract,
    protocol: Contract,
    erc721TestNFT: Contract,
    coveredCallImplInstance: Contract;

  let admin: SignerWithAddress,
    beneficialOwner: SignerWithAddress,
    runner: SignerWithAddress;

  let callInstrument: string;

  before(async function () {
    [admin, beneficialOwner, runner] = await ethers.getSigners();

    const erc721TokenFactory = await ethers.getContractFactory("TestERC721");

    const wethFactory = await ethers.getContractFactory("WETH");

    const protocolFactory = await ethers.getContractFactory("HookProtocol");

    const vaultFactoryFactory = await ethers.getContractFactory(
      "HookERC721VaultFactory"
    );

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

    const coveredCallFactory = await ethers.getContractFactory(
      "HookCoveredCallFactory"
    );
    const coveredCallBeaconFactory = await ethers.getContractFactory(
      "HookCoveredCallBeacon"
    );
    const coveredCallImplFactory = await ethers.getContractFactory(
      "HookCoveredCallImplV1"
    );

    // EXTERNAL CONTRACTS DEPLOYS
    const weth = await wethFactory.deploy();
    erc721TestNFT = await erc721TokenFactory.deploy();

    // PROTOCOL DEPLOY
    protocol = await protocolFactory.deploy(admin.address, weth.address);

    // VAULT DEPLOY
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

    // COVERED CALL DEPLOY
    const coveredCallImpl = await coveredCallImplFactory.deploy();
    const coveredCallBeacon = await coveredCallBeaconFactory.deploy(
      coveredCallImpl.address,
      protocol.address,
      ethers.utils.id("CALL_UPGRADER")
    );

    const coveredCall = await coveredCallFactory.deploy(
      protocol.address,
      coveredCallBeacon.address,
      "0x0000000000000000000000000000000000000000" // preapproved marketplace
    );

    await coveredCall.makeCallInstrument(erc721TestNFT.address);

    // get call instrument for collection
    callInstrument = await coveredCall.getCallInstrument(erc721TestNFT.address);

    console.log("callInstrument", callInstrument);

    coveredCallImplInstance = await ethers.getContractAt(
      "HookCoveredCallImplV1",
      callInstrument
    );
  });

  it("the factory should be able to make a multi vault", async function () {
    const tx = await vaultFactory.makeMultiVault(erc721TestNFT.address);
    const receipt = await tx?.wait();

    console.log("makeMultiVault - receipt", receipt);
  });

  it("multiple options minted for different assets in a collection expiring at differet times", async function () {
    // mint NFTs
    await Promise.all([
      erc721TestNFT.mint(beneficialOwner.address, 1),
      erc721TestNFT.mint(beneficialOwner.address, 2),
      erc721TestNFT.mint(beneficialOwner.address, 3),
    ]);

    // check ownership
    const [ownerOf1, ownerOf2, ownerOf3] = await Promise.all([
      erc721TestNFT.ownerOf(1),
      erc721TestNFT.ownerOf(2),
      erc721TestNFT.ownerOf(3),
    ]);

    expect(ownerOf1).to.equal(beneficialOwner.address);
    expect(ownerOf2).to.equal(beneficialOwner.address);
    expect(ownerOf3).to.equal(beneficialOwner.address);

    // Approve callInstrument
    await erc721TestNFT
      .connect(beneficialOwner)
      .setApprovalForAll(callInstrument, true);

    const isApproved = await erc721TestNFT
      .connect(beneficialOwner)
      .isApprovedForAll(beneficialOwner.address, callInstrument);

    expect(isApproved).to.equal(true);

    const nowEpoch = Date.now() / 1000;
    const SECS_IN_A_DAY = 60 * 60 * 24;
    const overrides: PayableOverrides = {
      gasLimit: "3000000",
    };

    const tx = await coveredCallImplInstance
      .connect(beneficialOwner)
      .mintWithErc721(
        erc721TestNFT.address, // collection address
        "1", // tokenId
        "1000", // strike price in wei
        String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)), // expiry
        overrides
      );

    console.log("tx", tx);
    const receipt = await tx?.wait();
    console.log("receipt", receipt);
  });

  //   it("protocol was deployed", async function () {
  //     const confirmations = await protocol?.deployTransaction?.confirmations;
  //     expect(confirmations).to.equal(1);
  //   });

  //   it("the factory should be able to make a vault", async function () {
  //     vaultFactory.callStatic["makeSoloVault"].call(erc721TestNFT.address, 1);
  //   });
});
