import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, providers } from "ethers";
import { getAddress } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { create } from "domain";
import {signEntitlement} from "./helpers/index";

chai.use(solidity);

describe("Call Instrument Tests", function() {
  // Constants
  const SECS_IN_A_DAY = 60 * 60 * 24;

  // Contracts
  let vaultFactory: Contract, protocol: Contract, token: Contract, calls: Contract;

  // Signers
  let admin: SignerWithAddress, writer: SignerWithAddress, operator: SignerWithAddress, buyer: SignerWithAddress, 
  firstBidder: SignerWithAddress, secondBidder: SignerWithAddress;

  beforeEach(async function () {
    // Create signers
    [admin, writer, operator, buyer, firstBidder, secondBidder] = await ethers.getSigners();

    // Deploy weth
    const wethFactory = await ethers.getContractFactory("WETH");
    const weth = await wethFactory.deploy();

    // Deploy test NFT
    const testNftFactory = await ethers.getContractFactory("TestERC721");
    token = await testNftFactory.deploy();

    // // Deploy protocol
    const protocolFactory = await ethers.getContractFactory("HookProtocol");
    protocol = await protocolFactory.deploy(admin.address, weth.address);

    // Deploy multi vault
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

    protocol.setVaultFactory(vaultFactory.address);

    // Deploy call instrument
    const callFactoryFactory = await ethers.getContractFactory(
      "HookCoveredCallFactory"
    );
    const callImplFactory = await ethers.getContractFactory(
      "HookCoveredCallImplV1"
    );
    const callBeaconFactory = await ethers.getContractFactory(
      "HookCoveredCallBeacon"
    );

    const callImpl = await callImplFactory.deploy();
    const callBeacon  = await callBeaconFactory.deploy(
      callImpl.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER")
    )
    const callFactory = await callFactoryFactory.deploy(
      protocol.address,
      callBeacon.address,
      getAddress("0x0000000000000000000000000000000000000000")
    );

    // Create another call instrument contract instance
    await callFactory.makeCallInstrument(token.address);
    const callInstrumentAddress = await callFactory.getCallInstrument(token.address);

    // Attach to existing address
    calls = await ethers.getContractAt("HookCoveredCallImplV1", callInstrumentAddress);

    // Mint 2 tokens
    await token.connect(writer).mint(writer.address, 0);
    await token.connect(writer).mint(writer.address, 1);
    await token.connect(writer).mint(writer.address, 2);

    // Set approval for call instrument
    await token.connect(writer).setApprovalForAll(calls.address, true);
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~ mintWithErc721 ~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("mintWithErc721", function() {
    it("should mint covered call with unvaulted erc721", async function() {
      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = await calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      expect(createCall).to.emit(calls, "CallCreated");
      expect(callCreatedEvent.args.writer).to.equal(writer.address);
      expect(callCreatedEvent.args.optionId).to.equal(1);
      expect(callCreatedEvent.args.strikePrice).to.equal(1000);
      expect(callCreatedEvent.args.expiration).to.equal(expiration);
    });

    it("should not mint covered call when project not on allowlist", async function() {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Set approval for call instrument
      await newToken.connect(writer).setApprovalForAll(calls.address, true);

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithErc721(
        newToken.address,
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith("mintWithErc721 -- token must be on the project allowlist");
    });

    it("should not mint covered call when call instrument not owner or operator", async function() {
      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(buyer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith("mintWithErc721 -- caller must be token owner or operator");
    });

    it("should not mint covered call when call instrument not approved", async function() {
      // Unapprove call instrument
      await token.connect(writer).setApprovalForAll(calls.address, false);

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith("mintWithErc721 -- HookCoveredCall must be operator");
    });

    it("should not mint covered call when vault already holds an asset", async function() {
      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );

      // Mint another call option
      const createCall2 = calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );

      await expect(createCall2).to.be.revertedWith("mintWithErc721 -- caller must be token owner or operator");
    });

    it("should mint covered call with unvaulted erc721 as operator", async function() {
      await token.connect(writer).setApprovalForAll(operator.address, true);

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = await calls.connect(operator).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      expect(createCall).to.emit(calls, "CallCreated");
      expect(callCreatedEvent.args.writer).to.equal(writer.address);
      expect(callCreatedEvent.args.optionId).to.equal(1);
      expect(callCreatedEvent.args.strikePrice).to.equal(1000);
      expect(callCreatedEvent.args.expiration).to.equal(expiration);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~ mintWithVault ~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("mintWithVault", function() {
    let multiVault: Contract;

    this.beforeEach(async function () {
      // Create multivault for token
      await vaultFactory.makeMultiVault(token.address);
      const multiValutAddress = await vaultFactory.getMultiVault(token.address);
      multiVault = await ethers.getContractAt("HookERC721MultiVaultImplV1", multiValutAddress);
    });

    it("should not mint covered call when project not on allowlist", async function() {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Create multivault for newToken
      await vaultFactory.makeMultiVault(newToken.address);
      const multiValutAddress = await vaultFactory.getMultiVault(newToken.address);
      const newTokenMultiVault = await ethers.getContractAt("HookERC721MultiVaultImplV1", multiValutAddress);

      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithVault(
        newTokenMultiVault.address, // invalid vault address
        0,
        1000,
        expiration,
        signature
      );
      await expect(createCall).to.be.revertedWith("mintWithVault -- token must be on the project allowlist");
    });

    it("should not mint covered call with empty vault", async function() {
      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithVault(
        multiVault.address,
        0,
        1000,
        expiration,
        signature
      );
      await expect(createCall).to.be.revertedWith("mintWithVault-- asset must be in vault");
    });

    it("should not mint covered call with invalid signature", async function() {
      await token.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        multiVault.address,
        0,
      );

      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithVault(
        multiVault.address,
        0,
        1000,
        expiration,
        signature
      );
      // TODO: Find revert reason
      await expect(createCall).to.be.reverted;
    });

    // TODO: mint with a valid signature
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~ mintWithEntitledVault ~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("mintWithEntitledVault", function() {
    let multiVault: Contract;

    this.beforeEach(async function () {
      // Create multivault for token
      await vaultFactory.makeMultiVault(token.address);
      const multiValutAddress = await vaultFactory.getMultiVault(token.address);
      multiVault = await ethers.getContractAt("HookERC721MultiVaultImplV1", multiValutAddress);
    });

    it("should not mint covered call when project not on allowlist", async function() {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Create multivault for newToken
      await vaultFactory.makeMultiVault(newToken.address);
      const multiValutAddress = await vaultFactory.getMultiVault(newToken.address);
      const newTokenMultiVault = await ethers.getContractAt("HookERC721MultiVaultImplV1", multiValutAddress);

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        newTokenMultiVault.address, // invalid vault address
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith("mintWithVault -- token must be on the project allowlist");
    });


    it("should not mint covered call with empty vault", async function() {
      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        multiVault.address,
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith("mintWithVault-- asset must be in vault");
    });

    it("should not mint covered call with no entitlement", async function() {
      await token.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        multiVault.address,
        0,
      );

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        multiVault.address,
        0,
        1000,
        expiration
      );
      // TODO: Find revert reason
      await expect(createCall).to.be.revertedWith("mintWithVault -- call contact must be the entitled operator");
    });

    it("should not mint covered call with inactive entitlement", async function() {
      await token.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        multiVault.address,
        0,
      );

      await multiVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: "0x0000000000000000000000000000000000000000",
        vaultAddress: multiVault.address,
        assetId: 0,
        expiry: Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5),
      });

      const expiration = String(Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5))

      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        multiVault.address,
        0,
        1000,
        expiration
      );

      await expect(createCall).to.be.revertedWith("mintWithVault -- call contact must be the entitled operator");
    });

    it("should not mint covered call with non matching entitlement expiration", async function() {
      await token.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        multiVault.address,
        0,
      );

      const expiration = Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)

      await multiVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: calls.address,
        vaultAddress: multiVault.address,
        assetId: 0,
        expiry: expiration,
      });


      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        multiVault.address,
        0,
        1000,
        String(expiration + 1)
      );

      await expect(createCall).to.be.revertedWith("mintWithVault -- entitlement expiration must match call expiration");
    });

    it("should mint covered call with entitled vault", async function() {
      await token.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        multiVault.address,
        0,
      );

      const expiration = Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5);

      await multiVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: calls.address,
        vaultAddress: multiVault.address,
        assetId: 0,
        expiry: expiration,
      });

      // Mint call option
      const createCall = await calls.connect(writer).mintWithEntitledVault(
        multiVault.address,
        0,
        1000,
        expiration
      );

      expect(createCall).to.emit(calls, "CallCreated");
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~ bid ~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("bid", function() {
    let optionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should not bid before last day before expiration", async function() {
      const bid = calls.connect(firstBidder).bid(optionTokenId, {value: 1000});
      await expect(bid).to.be.revertedWith("biddingEnabled -- bidding starts on last day");
    });

    it("should not bid with bid lower than strike", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(firstBidder).bid(optionTokenId, {value: 1000});
      await expect(bid).to.be.revertedWith("bid - bid is lower than the strike price");
    });

    it("should bid with first bid above strike", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(firstBidder).bid(optionTokenId, {value: 1001});
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(firstBidder.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);
    });

    it("should bid and outbid as standard bidder", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(firstBidder).bid(optionTokenId, {value: 1001});
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(firstBidder.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls.connect(secondBidder).bid(optionTokenId, {value: 1002});
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(secondBidder.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });

    it("should bid and outbid as option writer", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(firstBidder).bid(optionTokenId, {value: 1001});
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(firstBidder.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls.connect(writer).bid(optionTokenId, {value: 2});
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });

    it("should bid on spread as option writer", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(writer).bid(optionTokenId, {value: 1});
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);
    });

    it("should bid and outbid option writer", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(writer).bid(optionTokenId, {value: 1});
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls.connect(secondBidder).bid(optionTokenId, {value: 1002});
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(secondBidder.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~ settleOption ~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("settleOption", function() {
    let optionTokenId: BigNumber;
    let secondOptionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;

      // Mint another option - 3 day expiration
      const createCall2 = await calls.connect(writer).mintWithErc721(
        token.address,
        1,
        1000,
        expiration
      );
      const cc2 = await createCall2.wait();

      const callCreatedEvent2 = cc2.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      secondOptionTokenId = callCreatedEvent2.args.optionId;

      // Transfer option NFTs to buyer (assume this is a purchase)
      await calls.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        buyer.address,
        optionTokenId,
      );

      await calls.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        buyer.address,
        secondOptionTokenId,
      );

      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      // Create bids
      // First option the writer has the winning bid
      await calls.connect(firstBidder).bid(optionTokenId, {value: 1001});
      await calls.connect(writer).bid(optionTokenId, {value: 2});

      // Second option the secondBidder has the winning bid
      await calls.connect(firstBidder).bid(secondOptionTokenId, {value: 1001});
      await calls.connect(secondBidder).bid(secondOptionTokenId, {value: 1002});
    });

    it("should not settle auction with no bids", async function() {
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls.connect(writer).mintWithErc721(
        token.address,
        2,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      const tokenId = callCreatedEvent.args.optionId;

      // Move forward to after auction period ends
      await ethers.provider.send('evm_increaseTime', [4 * SECS_IN_A_DAY]);

      const settleCall = calls.connect(writer).settleOption(tokenId, false);
      await expect(settleCall).to.be.revertedWith("settle -- bid must be won by someone");
    });

    it("should not settle auction before expiration", async function() {
      const settleCall = calls.connect(writer).settleOption(optionTokenId, false);
      await expect(settleCall).to.be.revertedWith("settle -- option must be expired");
    });

    it("should not settle settled auction", async function() {
      // Move forward to after auction period ends
      await ethers.provider.send('evm_increaseTime', [1 * SECS_IN_A_DAY]);

      await calls.connect(writer).settleOption(optionTokenId, false);
      const settleCallAgain = calls.connect(writer).settleOption(optionTokenId, false);
      await expect(settleCallAgain).to.be.revertedWith("settle -- the call cannot already be settled");
    });

    it("should settle auction", async function() {
      // Move forward to after auction period ends
      await ethers.provider.send('evm_increaseTime', [1 * SECS_IN_A_DAY]);

      const settleCall = calls.connect(writer).settleOption(optionTokenId, false);
      await expect(settleCall).to.emit(calls, "CallDestroyed")

      const vaultAddress = await calls.getVaultAddress(optionTokenId);
      const vault = await ethers.getContractAt("HookERC721MultiVaultImplV1", vaultAddress);

      expect(await vault.getBeneficialOwner(optionTokenId)).to.eq(writer.address);
    });

    it("should settle auction when option writer is high bidder", async function() {
      // Move forward to after auction period ends
      await ethers.provider.send('evm_increaseTime', [1 * SECS_IN_A_DAY]);

      const settleCall = calls.connect(secondBidder).settleOption(secondOptionTokenId, false);
      await expect(settleCall).to.emit(calls, "CallDestroyed")

      const vaultAddress = await calls.getVaultAddress(secondOptionTokenId);
      const vault = await ethers.getContractAt("HookERC721MultiVaultImplV1", vaultAddress);

      expect(await vault.getBeneficialOwner(secondOptionTokenId)).to.eq(secondBidder.address);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~ reclaimAsset ~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("reclaimAsset", function() {
    let optionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls.connect(writer).mintWithErc721(
        token.address,
        0,
        1000,
        expiration
      );
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should not reclaim asset as non call writer", async function() {
      const reclaimAsset = calls.connect(buyer).reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith("reclaimAsset -- asset can only be reclaimed by the writer");
    });

    it("should not reclaim settled asset", async function() {
      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      // Bid as writer
      await calls.connect(writer).bid(optionTokenId, {value: 2});

      // Move forward to end of auction period
      await ethers.provider.send('evm_increaseTime', [1 * SECS_IN_A_DAY]);

      // Settle option
      await calls.connect(writer).settleOption(optionTokenId, false);

      const reclaimAsset = calls.connect(writer).reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith("reclaimAsset -- the option has already been settled");
    });

    it("should not reclaim sold asset as buyer", async function() {
      // Transfer option NFT to buyer (assume this is a purchase)
      await calls.connect(writer)["safeTransferFrom(address,address,uint256)"](
        writer.address,
        buyer.address,
        optionTokenId,
      );

      // Move forward to auction period
      await ethers.provider.send('evm_increaseTime', [2.1 * SECS_IN_A_DAY]);

      // Bid as writer
      await calls.connect(writer).bid(optionTokenId, {value: 2});
      
      const reclaimAsset = calls.connect(buyer).reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith("reclaimAsset -- cannot reclaim a sold asset if the option is not writer-owned.");
    });
  });
});