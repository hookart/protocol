import { expect } from "chai";
import { ethers } from "hardhat";
import type { Contract, PayableOverrides } from "ethers";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// TODO: move to helpers later
const SECS_IN_A_DAY = 60 * 60 * 24;

export function getEpochTimestampDaysFromNow(days: number) {
  const nowEpoch = Date.now() / 1000;
  const epochDaysFromNow = nowEpoch + SECS_IN_A_DAY * days;

  return Math.floor(epochDaysFromNow);
}

// needs extra gas limit since proxied contracts are hard to calculate
const overrides: PayableOverrides = {
  gasLimit: "1000000",
};

describe("Integrations", function () {
  let vaultFactory: Contract,
    protocol: Contract,
    token: Contract,
    coveredCallImplInstance: Contract;

  let admin: SignerWithAddress,
    writer: SignerWithAddress,
    runner: SignerWithAddress;

  let callInstrument: string;

  before(async function () {
    [admin, writer, runner] = await ethers.getSigners();

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
    token = await erc721TokenFactory.deploy();

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

    await protocol.setVaultFactory(vaultFactory.address);
    await vaultFactory.makeMultiVault(token.address);

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

    await coveredCall.makeCallInstrument(token.address);

    // get call instrument for collection
    callInstrument = await coveredCall.getCallInstrument(token.address);

    console.log("callInstrument", callInstrument);

    coveredCallImplInstance = await ethers.getContractAt(
      "HookCoveredCallImplV1",
      callInstrument
    );
  });

  it("multiple options minted for different assets in a collection expiring at differet times", async function () {
    // mint NFTs
    await Promise.all([
      token.mint(writer.address, 1),
      token.mint(writer.address, 2),
      token.mint(writer.address, 3),
    ]);

    // check ownership
    const [ownerOf1, ownerOf2, ownerOf3] = await Promise.all([
      token.ownerOf(1),
      token.ownerOf(2),
      token.ownerOf(3),
    ]);

    expect(ownerOf1).to.equal(
      writer.address,
      "Owner of minted token didn't match."
    );
    expect(ownerOf2).to.equal(
      writer.address,
      "Owner of minted token didn't match."
    );
    expect(ownerOf3).to.equal(
      writer.address,
      "Owner of minted token didn't match."
    );

    // Approve callInstrument
    await token.connect(writer).setApprovalForAll(callInstrument, true);

    const isApproved = await token
      .connect(writer)
      .isApprovedForAll(writer.address, callInstrument);

    expect(isApproved).to.equal(true, "Call instrument approval didn't work.");

    const expiryArr = [
      Math.floor(getEpochTimestampDaysFromNow(2)), // around 2 days from now
      Math.floor(getEpochTimestampDaysFromNow(15)), // around 15 days from now
      Math.floor(getEpochTimestampDaysFromNow(30)), // around 30 days from now
    ];

    for (let i = 0; i < expiryArr.length; i++) {
      const currentTokenId = i + 1; // should be same as optionId
      const currentExpiry = expiryArr[i];

      const tx = await coveredCallImplInstance.connect(writer).mintWithErc721(
        token.address, // collection address
        currentTokenId, // tokenId
        1000, // strike price in wei
        currentExpiry, // expiry
        overrides
      );
      const receipt = await tx?.wait();
      // Get the option id out off result
      const event = (receipt as any)?.events?.find(
        ({ event }: any) => event === "CallCreated"
      );
      const optionId = event?.args?.optionId?.toNumber();

      expect(optionId).to.equal(
        currentTokenId,
        "OptionId after mint does not match expected one."
      );
    }
  });

  it("mint option using vault", async function () {
    // Mint NFT
    const tokenId = 4;
    await token.mint(writer.address, tokenId);

    const ownerOf4 = await token.ownerOf(tokenId);

    expect(ownerOf4).to.equal(
      writer.address,
      "Owner of minted token didn't match."
    );

    // Put in vault
    const tx = await vaultFactory.makeSoloVault(token.address, tokenId);
    const receipt = await tx?.wait();
    const event = (receipt as any)?.events?.find(
      ({ event }: any) => event === "ERC721VaultCreated"
    );
    const vault = event?.args?.vaultAddress;
    await token
      .connect(writer)
      ["safeTransferFrom(address,address,uint256)"](
        writer.address,
        vault,
        tokenId
      );
    const vaultInstance = await ethers.getContractAt(
      "HookERC721VaultImplV1",
      vault
    );

    expect(await vaultInstance.getBeneficialOwner(tokenId)).eq(writer.address);
   

    // Sign Entitlement
    // const signature = await signEntitlement(
    //   address,
    //   callInstrument,
    //   tokenContractAddress,
    //   tokenId,
    //   expiry,
    //   provider
    // );

    // Mint with vault
    const mintTx = await coveredCallImplInstance.connect(writer).mintWithVault(
      vault,
      tokenId,
      1000, // strike price in wei
      Math.floor(getEpochTimestampDaysFromNow(2)), // expiry
      ,
      overrides
    );
    const mintReceipt = await mintTx?.wait();
  });

  it("mint option using an entitled vault", async function () {});

  it("mint option using an unentitled vault and a signature", async function () {});

  it("reclaim asset", async function () {});

  //   it("protocol was deployed", async function () {
  //     const confirmations = await protocol?.deployTransaction?.confirmations;
  //     expect(confirmations).to.equal(1);
  //   });

  //   it("the factory should be able to make a vault", async function () {
  //     vaultFactory.callStatic["makeSoloVault"].call(token.address, 1);
  //   });
});
