import { ethers } from "hardhat";
import { expect, use } from "chai";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { solidity } from "ethereum-waffle";
import { signEntitlement } from "./helpers";
import { getAddress } from "ethers/lib/utils";

use(solidity);

describe("Protocol", function () {
  let protocol: Contract;
  let admin: SignerWithAddress, one: SignerWithAddress, two: SignerWithAddress;
  beforeEach(async () => {
    [admin, one, two] = await ethers.getSigners();
    const protocolFactory = await ethers.getContractFactory("HookProtocol");
    protocol = await protocolFactory.deploy(admin.address, admin.address);
  });

  it("can be paused", async () => {
    await protocol.connect(admin).pause();
    await expect(protocol.throwWhenPaused()).to.be.reverted;
  });

  it("can be unpaused", async () => {
    await protocol.connect(admin).pause();
    await expect(protocol.throwWhenPaused()).to.be.reverted;
    await protocol.connect(admin).unpause();
    await expect(protocol.throwWhenPaused()).not.to.be.reverted;
  });

  it("vault factory can be set", async () => {
    await protocol.connect(admin).pause();
    await expect(protocol.throwWhenPaused()).to.be.reverted;
    await protocol.connect(admin).unpause();
    await expect(protocol.throwWhenPaused()).not.to.be.reverted;
  });

  it("admin role can be revoked", async () => {
    /// give role to new user
    await protocol
      .connect(admin)
      .grantRole(ethers.utils.id("VAULT_UPGRADER"), one.address);
    // drop role
    await protocol
      .connect(admin)
      .renounceRole(ethers.utils.id("VAULT_UPGRADER"), admin.address);
    // new user gives role to a third user
    await protocol
      .connect(one)
      .grantRole(ethers.utils.id("VAULT_UPGRADER"), two.address);
    expect(
      await protocol.hasRole(ethers.utils.id("VAULT_UPGRADER"), one.address)
    ).to.be.true;
    expect(
      await protocol.hasRole(ethers.utils.id("VAULT_UPGRADER"), two.address)
    ).to.be.true;
    expect(
      await protocol.hasRole(ethers.utils.id("VAULT_UPGRADER"), admin.address)
    ).to.be.false;
  });

  it("collection configs can be set", async () => {
    await protocol
      .connect(admin)
      .setCollectionConfig(two.address, ethers.utils.id("config"), true);
    expect(
      await protocol.getCollectionConfig(two.address, ethers.utils.id("config"))
    ).to.be.true;
  });
});

describe("UpgradeableBeacon", function () {
  let beacon: Contract, impl1: Contract, impl2: Contract, protocol: Contract;
  let admin: SignerWithAddress;
  beforeEach(async () => {
    [admin] = await ethers.getSigners();
    const protocolFactory = await ethers.getContractFactory("HookProtocol");
    protocol = await protocolFactory.deploy(admin.address, admin.address);

    const vaultImplFactory = await ethers.getContractFactory(
      "HookERC721VaultImplV1"
    );

    const vaultBeaconFactory = await ethers.getContractFactory(
      "HookUpgradeableBeacon"
    );

    impl1 = await vaultImplFactory.deploy();
    impl2 = await vaultImplFactory.deploy();

    beacon = await vaultBeaconFactory.deploy(
      impl1.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER")
    );
  });

  it("the beacon should show an implementation", async function () {
    expect(await beacon.implementation()).to.eq(impl1.address);
  });

  it("the beacon should be upgradeable by the correct role", async () => {
    await beacon.connect(admin).upgradeTo(impl2.address);
    expect(await beacon.implementation()).to.eq(impl2.address);
  });

  it("the beacon should not be upgradeable by a random address", async () => {
    const [, actor] = await ethers.getSigners();
    expect(
      await protocol.hasRole(ethers.utils.id("VAULT_UPGRADER"), actor.address)
    ).to.be.false;
    await expect(
      beacon.connect(actor).upgradeTo(impl2.address)
    ).to.be.revertedWith("w");
    expect(await beacon.implementation()).to.eq(impl1.address);
  });

  it("the beacon should not be upgradeable by a granted address", async () => {
    const [, actor] = await ethers.getSigners();
    expect(
      await protocol.hasRole(ethers.utils.id("VAULT_UPGRADER"), actor.address)
    ).to.be.false;

    await protocol
      .connect(admin)
      .grantRole(ethers.utils.id("VAULT_UPGRADER"), actor.address);
    await beacon.connect(actor).upgradeTo(impl2.address);
    expect(await beacon.implementation()).to.eq(impl2.address);
  });
  it("the beacon should not be upgradeable not a non-contract", async () => {
    const [, actor] = await ethers.getSigners();
    await expect(
      beacon.connect(admin).upgradeTo(actor.address)
    ).to.be.revertedWith("UpgradeableBeacon: implementation is not a contract");
  });
});

describe("Vault", function () {
  let vaultFactory: Contract,
    protocol: Contract,
    testNFT: Contract,
    weth: Contract;
  let admin: SignerWithAddress,
    beneficialOwner: SignerWithAddress,
    runner: SignerWithAddress;

  beforeEach(async () => {
    [admin, beneficialOwner, runner] = await ethers.getSigners();
    const weath = await ethers.getContractFactory("WETH");

    const protocolFactory = await ethers.getContractFactory("HookProtocol");

    const vaultFactoryFactory = await ethers.getContractFactory(
      "HookERC721VaultFactory"
    );

    const vaultImplFactory = await ethers.getContractFactory(
      "HookERC721VaultImplV1"
    );
    const vaultBeaconFactory = await ethers.getContractFactory(
      "HookUpgradeableBeacon"
    );
    const multiVaultImplFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultImplV1"
    );
    const multiVaultBeaconFactory = await ethers.getContractFactory(
      "HookUpgradeableBeacon"
    );

    weth = await weath.deploy();
    const token = await ethers.getContractFactory("TestERC721");
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

  describe("VaultFactory", function () {
    it("the factory should be able to make a vault", async function () {
      expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq("0");
    });

    it("the factory should not be able to make a single vault twice", async function () {
      await vaultFactory.makeSoloVault(testNFT.address, 4);
      (
        (await expect(vaultFactory.makeSoloVault(testNFT.address, 4)).to
          .be) as any
      ).revertedWith("makeVault -- a vault cannot already exist");
    });

    it("the factory should be able to make a multi vault", async function () {
      await vaultFactory.makeMultiVault(testNFT.address);
    });

    it("the factory shouldn't be able to make a multi vault without perms", async function () {
      await expect(
        vaultFactory.connect(runner).makeMultiVault(testNFT.address)
      ).to.be.revertedWith(
        "makeMultiVault -- Only accounts with the ALLOWLISTER role can make new multiVaults"
      );
    });

    it("the factory should not be able to make a multi vault twice", async function () {
      await vaultFactory.makeMultiVault(testNFT.address);
      (
        (await expect(vaultFactory.makeMultiVault(testNFT.address)).to
          .be) as any
      ).revertedWith("makeMultiVault -- vault cannot already exist");
    });

    it("the factory should be able to make both vault types, return them correctly on find or create", async function () {
      const singleVault = await vaultFactory.makeSoloVault(testNFT.address, 1);
      const sv = await singleVault.wait();
      const singleVaultCreate = sv.events.find(
        (event: any) => event?.event === "ERC721VaultCreated"
      );
      const [singleAsset, singleId, singleVaultAddress] =
        singleVaultCreate.args;
      expect(singleAsset).to.eq(testNFT.address);
      expect(singleId.toNumber()).to.eq(1);

      const singleVaultLookup = await vaultFactory.getVault(testNFT.address, 1);
      expect(singleVaultLookup).to.eq(singleVaultAddress);

      const multiVault = await vaultFactory.makeMultiVault(testNFT.address);
      const rc = await multiVault.wait();
      const vaultCreate = rc.events.find(
        (event: any) => event?.event === "ERC721MultiVaultCreated"
      );
      const [contract, vaultaddress] = vaultCreate.args;
      expect(contract).to.eq(testNFT.address);

      const lookupVault = await vaultFactory.getMultiVault(testNFT.address);
      expect(lookupVault).to.eq(vaultaddress);

      const foundVault = await (
        await vaultFactory.findOrCreateVault(testNFT.address, 1)
      ).wait();
      expect(foundVault.events.length).to.eq(
        0,
        "no events should be emitted as vault already exists"
      );
    });

    it("the factory should be able to make just a multi vault and return it in find or create", async function () {
      const multiVault = await vaultFactory.makeMultiVault(testNFT.address);
      const rc = await multiVault.wait();

      const foundVault = await (
        await vaultFactory.findOrCreateVault(testNFT.address, 1)
      ).wait();
      expect(foundVault.events.length).to.eq(
        0,
        "no events should be emitted as vault already exists"
      );
    });

    it("the factory should be able to make just a single vault and return it in find or create", async function () {
      const singleVault = await vaultFactory.makeSoloVault(testNFT.address, 1);
      const rc = await singleVault.wait();

      const foundVault = await (
        await vaultFactory.findOrCreateVault(testNFT.address, 1)
      ).wait();
      expect(foundVault.events.length).to.eq(
        0,
        "no events should be emitted as vault already exists"
      );
    });

    it("the factory should be able to create a single vault in find or create", async function () {
      const foundVault = await (
        await vaultFactory.findOrCreateVault(testNFT.address, 1)
      ).wait();
      const vaultCreate = foundVault.events.find(
        (event: any) => event?.event === "ERC721VaultCreated"
      );
      const [singleAsset, singleId, singleVaultAddress] = vaultCreate.args;
      expect(singleAsset).to.eq(testNFT.address);
      expect(singleId.toNumber()).to.eq(1);
    });
  });

  describe("HookERC721VaultImplV1", function () {
    beforeEach(function () {
      /// mint one token to the beneficial owner
      testNFT.mint(beneficialOwner.address, 1);
    });
    it("should implement supportsInterface", async () => {
      expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq("0");
      const vault = vaultFactory.getVault(testNFT.address, 1);
      const vaultInstance = await ethers.getContractAt(
        "HookERC721VaultImplV1",
        vault
      );
      expect(await vaultInstance.supportsInterface("0x00000022")).to.be.false;
    });
    describe("Emtpy State", function () {
      it("should not think it contains a NFT", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );

        expect(await vaultInstance.getHoldsAsset(0)).to.eq(false);
      });

      it("should return a vaild asset address", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );

        expect(await vaultInstance.assetAddress(0)).to.eq(testNFT.address);
      });

      it("should return a vaild beneficial owner", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
        expect(await vaultInstance.getBeneficialOwner(0)).to.eq(
          "0x0000000000000000000000000000000000000000"
        );
      });

      it("should not show an entitlementExpiration", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
        expect(await vaultInstance.entitlementExpiration(0)).to.eq(0);
      });

      it("should not successfully flash loan", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
        await expect(
          vaultInstance.flashLoan(
            0,
            "0x0000000000000000000000000000000000000022",
            "0x0000000000000000000000000000000000000022"
          )
        ).to.be.reverted;
      });

      it("should not successfully exec txn", async () => {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
        await expect(
          vaultInstance.execTransaction(
            "0x0000000000000000000000000000000000000022",
            "0x0000000000000000000000000000000000000022"
          )
        ).to.be.reverted;
      });
    });
    describe("Deposit", function () {
      let vaultInstance: Contract;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = vaultFactory.getVault(testNFT.address, 1);
        vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
      });
      it("accepts the relevant NFT", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );
      });

      it("accepts the correct tokenId", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.assetTokenId(0)).eq(1);
      });

      it("accepts the airdropped NFT", async function () {
        const erc721 = await ethers.getContractFactory("TestERC721");
        const newNFT = await erc721.deploy();

        newNFT.mint(beneficialOwner.address, 3);
        await newNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            3
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          "0x0000000000000000000000000000000000000000"
        );
      });

      it("blocks airdrops if the protocol blocks them", async function () {
        const erc721 = await ethers.getContractFactory("TestERC721");
        const newNFT = await erc721.deploy();

        newNFT.mint(beneficialOwner.address, 3);

        await protocol
          .connect(admin)
          .setCollectionConfig(
            testNFT.address,
            ethers.utils.id("vault.airdropsProhibited"),
            true
          );
        await expect(
          newNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256)"](
              beneficialOwner.address,
              vaultInstance.address,
              3
            )
        ).to.be.revertedWith(
          "onERC721Received -- non-escrow asset returned when airdrops are disabled"
        );
      });

      it("allows owner to change owner", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );
        await vaultInstance
          .connect(beneficialOwner)
          .setBeneficialOwner(0, runner.address);
        expect(await vaultInstance.getBeneficialOwner(0)).to.eq(runner.address);
      });

      it("prevents others from changing owner", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        await expect(
          vaultInstance.connect(runner).setBeneficialOwner(0, runner.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the current owner can update the beneficial owner"
        );
      });

      it("prevents skips beneficial owner checks on other assets", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .setBeneficialOwner(10, runner.address)
        ).to.be.revertedWith(
          "assetIdIsZero -- this vault only supports asset id 0"
        );
      });
    });
    describe("Entitlement", function () {
      let vaultInstance: Contract;
      const SECS_IN_A_DAY = 60 * 60 * 24;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = await vaultFactory.getVault(testNFT.address, 1);
        vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );
      });

      it("applies entitlement transferred in with the relevant NFT", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256,bytes)"](
            beneficialOwner.address,
            vaultInstance.address,
            1,
            ethers.utils.defaultAbiCoder.encode(
              ["tuple(address, address, uint128)"],
              [
                [
                  beneficialOwner.address,
                  runner.address,
                  Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                ],
              ]
            )
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["isActive"]
        ).to.be.true;
        expect(await vaultInstance.hasActiveEntitlement(0)).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });
      it("cannot impose entitlement with invalid asset id", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance.connect(beneficialOwner).grantEntitlement({
            beneficialOwner: beneficialOwner.address,
            operator: runner.address,
            vaultAddress: vaultInstance.address,
            assetId: 10,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          })
        ).to.be.revertedWith(
          "grantEntitlement -- only the beneficial owner can grant an entitlement"
        );
      });

      it("allows the beneficial owner to specify an entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["isActive"]
        ).to.be.true;
        expect(await vaultInstance.hasActiveEntitlement(0)).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });

      it("allows the beneficial owner to impose using a signature", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "0",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          beneficialOwner,
          protocol.address
        );
        await vaultInstance
          .connect(runner)
          .imposeEntitlement(
            runner.address,
            String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
            "0",
            signed.v,
            signed.r,
            signed.s
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(0))["isActive"]
        ).to.be.true;

        expect(await vaultInstance.hasActiveEntitlement(0)).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });

      it("doesn't allow the beneficial owner to impose using an invalid signature (by someone else)", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "0",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          runner,
          protocol.address
        );
        await expect(
          vaultInstance
            .connect(runner)
            .imposeEntitlement(
              runner.address,
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
              "0",
              signed.v,
              signed.r,
              signed.s
            )
        ).to.be.revertedWith(
          "validateEntitlementSignature --- not signed by beneficialOwner"
        );
      });

      it("doesn't allow the beneficial owner to impose using an invalid signature (bad content)", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "0",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          beneficialOwner,
          protocol.address
        );
        await expect(
          vaultInstance
            .connect(runner)
            .imposeEntitlement(
              runner.address,
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1)),
              "0",
              signed.v,
              signed.r,
              signed.s
            )
        ).to.be.revertedWith(
          "validateEntitlementSignature --- not signed by beneficialOwner"
        );
      });

      it("prevents the beneficial owner to specify another entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance.connect(beneficialOwner).grantEntitlement({
            beneficialOwner: beneficialOwner.address,
            operator: vaultInstance.address,
            vaultAddress: vaultInstance.address,
            assetId: 0,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          })
        ).to.be.revertedWith(
          "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
        );
      });

      it("allows operator to clear entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(runner).clearEntitlement(0);
        await vaultInstance.connect(beneficialOwner).withdrawalAsset(0);
      });

      it("allows asset to be withdrawn by beneficialOwner", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        expect(await vaultInstance.connect(beneficialOwner).withdrawalAsset(0))
          .not.to.throw;

        expect(await vaultInstance.getHoldsAsset(0)).to.be.false;
      });

      it("allows asset to be blocks withdrawals by others", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance.connect(runner).withdrawalAsset(0)
        ).to.be.revertedWith(
          "withdrawalAsset -- only the beneficial owner can withdrawal an asset"
        );

        expect(await vaultInstance.getHoldsAsset(0)).to.be.true;
      });

      it("allows operator to clear entitlement and distribute", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance
          .connect(runner)
          .clearEntitlementAndDistribute(0, beneficialOwner.address);
        expect(await testNFT.ownerOf(1)).to.eq(beneficialOwner.address);
      });

      it("blocks operator to clear entitlement and distribute to someone else", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance
            .connect(runner)
            .clearEntitlementAndDistribute(0, runner.address)
        ).to.be.revertedWith(
          "clearEntitlementAndDistribute -- Only the beneficial owner can receive the asset"
        );
      });

      it("allows operator to set a new beneficial owner", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance
          .connect(runner)
          .setBeneficialOwner(0, vaultInstance.address);
        expect(await vaultInstance.getBeneficialOwner(0)).to.eq(
          vaultInstance.address
        );
      });

      it("prevents owner from setting new beneficial owner", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(0)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .setBeneficialOwner(0, vaultInstance.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the contract with the active entitlement can update the beneficial owner"
        );
      });
    });
    describe("Flash Loan", function () {
      let vaultInstance: Contract;
      const SECS_IN_A_DAY = 60 * 60 * 24;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeSoloVault(testNFT.address, 1)).not.eq(
          "0"
        );
        const vault = await vaultFactory.getVault(testNFT.address, 1);
        vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );

        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );
        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 0,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
      });

      it("doesn't allow transactions to be sent to the contract address", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .execTransaction(
              testNFT.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "execTransaction -- cannot send transactions to the NFT contract itself"
        );
      });
      it("doesn't allow transactions to be sent if disabled for a collection", async function () {
        await protocol.setCollectionConfig(
          testNFT.address,
          ethers.utils.id("vault.execTransactionDisabled"),
          true
        );
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .execTransaction(
              runner.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "execTransaction -- feature is disabled for this collection"
        );
      });
      it("blocks exec transactions targeting the vault itself", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .execTransaction(
              vaultInstance.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "execTransaction -- cannot call the vault contract"
        );
      });

      it("execs transactions ", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .execTransaction(
              weth.address,
              new ethers.utils.Interface([
                "function totalSupply()",
              ]).encodeFunctionData("totalSupply")
            )
        );
      });

      it("doesn't allow flashloans if disabled for a collection", async function () {
        await protocol.setCollectionConfig(
          testNFT.address,
          ethers.utils.id("vault.flashLoanDisabled"),
          true
        );
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              0,
              runner.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "flashLoan -- flashLoan feature disabled for this contract"
        );
      });

      it("doesn't allow flashloans to zero address", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              0,
              "0x0000000000000000000000000000000000000000",
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith("flashLoan -- zero address");
      });

      it("doesn't allow flashloans with invalid asset ids", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              10,
              runner.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "assetIdIsZero -- this vault only supports asset id 0"
        );
      });

      it("allows basic flashloans", async function () {
        const flashLoan = await ethers.getContractFactory("FlashLoanSuccess");
        const flashLoanRec = await flashLoan.deploy();
        await vaultInstance
          .connect(beneficialOwner)
          .flashLoan(
            0,
            flashLoanRec.address,
            "0x0000000000000000000000000000000000000000"
          );
      });

      it("blocks non-approving flashloans", async function () {
        const flashLoan = await ethers.getContractFactory(
          "FlashLoanDoesNotApprove"
        );
        const flashLoanRec = await flashLoan.deploy();
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              0,
              flashLoanRec.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "ERC721: transfer caller is not owner nor approve"
        );
      });

      it("blocks false-returning flashloan", async function () {
        const flashLoan = await ethers.getContractFactory(
          "FlashLoanReturnsFalse"
        );
        const flashLoanRec = await flashLoan.deploy();
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              0,
              flashLoanRec.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "flashLoan -- the flash loan contract must return true"
        );
      });
    });
  });

  describe("HookERC721MultiVaultImplV1", function () {
    beforeEach(function () {
      /// mint one token to the beneficial owner
      testNFT.mint(beneficialOwner.address, 1);
    });
    it("should implement supportsInterface", async () => {
      expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
      const vault = vaultFactory.getMultiVault(testNFT.address);
      const vaultInstance = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        vault
      );
      expect(await vaultInstance.supportsInterface("0x00000022")).to.be.false;
    });
    describe("Emtpy State", function () {
      it("should not think it contains a NFT", async () => {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );

        expect(await vaultInstance.getHoldsAsset(1)).to.eq(false);
      });

      it("should return a vaild asset address", async () => {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );

        expect(await vaultInstance.assetAddress(1)).to.eq(testNFT.address);
      });

      it("should return a vaild beneficial owner", async () => {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );
        expect(await vaultInstance.getBeneficialOwner(1)).to.eq(
          "0x0000000000000000000000000000000000000000"
        );
      });

      it("should not show an entitlementExpiration", async () => {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );
        expect(await vaultInstance.entitlementExpiration(1)).to.eq(0);
      });

      it("should not successfully flash loan", async () => {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        const vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );
        await expect(
          vaultInstance.flashLoan(
            1,
            "0x0000000000000000000000000000000000000022",
            "0x0000000000000000000000000000000000000022"
          )
        ).to.be.reverted;
      });
    });
    describe("Deposit", function () {
      let vaultInstance: Contract;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = vaultFactory.getMultiVault(testNFT.address);
        vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );
      });
      it("accepts the relevant NFT", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );
      });

      it("accepts the correct tokenId", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.assetTokenId(1)).eq(1);
      });

      it("accepts the airdropped NFT", async function () {
        const erc721 = await ethers.getContractFactory("TestERC721");
        const newNFT = await erc721.deploy();

        newNFT.mint(beneficialOwner.address, 3);
        await newNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            3
          );

        expect(await vaultInstance.getBeneficialOwner(3)).eq(
          "0x0000000000000000000000000000000000000000"
        );
      });

      it("blocks airdrops if the protocol blocks them", async function () {
        const erc721 = await ethers.getContractFactory("TestERC721");
        const newNFT = await erc721.deploy();

        newNFT.mint(beneficialOwner.address, 3);

        await protocol
          .connect(admin)
          .setCollectionConfig(
            testNFT.address,
            ethers.utils.id("vault.airdropsProhibited"),
            true
          );
        await expect(
          newNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256)"](
              beneficialOwner.address,
              vaultInstance.address,
              3
            )
        ).to.be.revertedWith(
          "onERC721Received -- non-escrow asset returned when airdrops are disabled"
        );
      });

      it("allows owner to change owner", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );
        await vaultInstance
          .connect(beneficialOwner)
          .setBeneficialOwner(1, runner.address);
        expect(await vaultInstance.getBeneficialOwner(1)).to.eq(runner.address);
      });

      it("prevents others from changing owner", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        await expect(
          vaultInstance.connect(runner).setBeneficialOwner(1, runner.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the current owner can update the beneficial owner"
        );
      });

      it("prevents skips beneficial owner checks on other assets", async function () {
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .setBeneficialOwner(10, runner.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the current owner can update the beneficial owner"
        );
      });
    });

    describe("Entitlement", function () {
      let vaultInstance: Contract;
      const SECS_IN_A_DAY = 60 * 60 * 24;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = await vaultFactory.getMultiVault(testNFT.address);
        vaultInstance = await ethers.getContractAt(
          "HookERC721MultiVaultImplV1",
          vault
        );
      });

      it("applies entitlement transferred in with the relevant NFT", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256,bytes)"](
            beneficialOwner.address,
            vaultInstance.address,
            1,
            ethers.utils.defaultAbiCoder.encode(
              ["tuple(address, address, uint128)"],
              [
                [
                  beneficialOwner.address,
                  runner.address,
                  Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                ],
              ]
            )
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["isActive"]
        ).to.be.true;
        expect(await vaultInstance.entitlementExpiration(1)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });
      it("cannot impose entitlment with different entitlement id", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance.connect(beneficialOwner).grantEntitlement({
            beneficialOwner: beneficialOwner.address,
            operator: runner.address,
            vaultAddress: beneficialOwner.address,
            assetId: 10,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          })
        ).to.be.revertedWith(
          "grantEntitlement -- only the beneficial owner can grant an entitlement"
        );
      });

      it("allows the beneficial owner to specify an entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["isActive"]
        ).to.be.true;
        expect(await vaultInstance.entitlementExpiration(1)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });

      it("allows the beneficial owner to impose using a signature", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "1",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          beneficialOwner,
          protocol.address
        );
        await vaultInstance
          .connect(runner)
          .imposeEntitlement(
            runner.address,
            String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
            "1",
            signed.v,
            signed.r,
            signed.s
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["operator"]
        ).eq(runner.address);
        expect(
          (await vaultInstance.getCurrentEntitlementOperator(1))["isActive"]
        ).to.be.true;

        expect(await vaultInstance.entitlementExpiration(1)).eq(
          Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)
        );
      });

      it("doesn't allow the beneficial owner to impose using an invalid signature (by someone else)", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "1",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          runner,
          protocol.address
        );
        await expect(
          vaultInstance
            .connect(runner)
            .imposeEntitlement(
              runner.address,
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
              "1",
              signed.v,
              signed.r,
              signed.s
            )
        ).to.be.revertedWith(
          "validateEntitlementSignature --- not signed by beneficialOwner"
        );
      });

      it("doesn't allow the beneficial owner to impose using an invalid signature (bad content)", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        const signed = await signEntitlement(
          beneficialOwner.address,
          runner.address,
          vaultInstance.address,
          "1",
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
          beneficialOwner,
          protocol.address
        );
        await expect(
          vaultInstance
            .connect(runner)
            .imposeEntitlement(
              runner.address,
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1)),
              1,
              signed.v,
              signed.r,
              signed.s
            )
        ).to.be.revertedWith(
          "validateEntitlementSignature --- not signed by beneficialOwner"
        );
      });

      it("prevents the beneficial owner to specify another entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance.connect(beneficialOwner).grantEntitlement({
            beneficialOwner: beneficialOwner.address,
            operator: vaultInstance.address,
            vaultAddress: vaultInstance.address,
            assetId: 1,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          })
        ).to.be.revertedWith(
          "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
        );
      });

      it("allows operator to clear entitlement", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(runner).clearEntitlement(1);
        await vaultInstance.connect(beneficialOwner).withdrawalAsset(1);
      });

      it("allows operator to clear entitlement and distribute", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance
          .connect(runner)
          .clearEntitlementAndDistribute(1, beneficialOwner.address);
        expect(await testNFT.ownerOf(1)).to.eq(beneficialOwner.address);
      });

      it("blocks operator to clear entitlement and distribute to someone else", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance
            .connect(runner)
            .clearEntitlementAndDistribute(1, runner.address)
        ).to.be.revertedWith(
          "clearEntitlementAndDistribute -- Only the beneficial owner can receive the asset"
        );
      });

      it("allows operator to set a new beneficial owner", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance
          .connect(runner)
          .setBeneficialOwner(1, vaultInstance.address);
        expect(await vaultInstance.getBeneficialOwner(1)).to.eq(
          vaultInstance.address
        );
      });

      it("prevents operator to set a new beneficial owner on different asset", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance
            .connect(runner)
            .setBeneficialOwner(12, vaultInstance.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the current owner can update the beneficial owner"
        );
      });

      it("prevents owner from setting new beneficial owner", async function () {
        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );

        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
        expect(await vaultInstance.getBeneficialOwner(1)).eq(
          beneficialOwner.address
        );

        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .setBeneficialOwner(1, vaultInstance.address)
        ).to.be.revertedWith(
          "setBeneficialOwner -- only the contract with the active entitlement can update the beneficial owner"
        );
      });
    });
    describe("Flash Loan", function () {
      let vaultInstance: Contract;
      const SECS_IN_A_DAY = 60 * 60 * 24;
      this.beforeEach(async function () {
        expect(await vaultFactory.makeMultiVault(testNFT.address)).not.eq("0");
        const vault = await vaultFactory.getMultiVault(testNFT.address);
        vaultInstance = await ethers.getContractAt(
          "HookERC721VaultImplV1",
          vault
        );

        const nowEpoch = Date.now() / 1000;
        await testNFT
          .connect(beneficialOwner)
          ["safeTransferFrom(address,address,uint256)"](
            beneficialOwner.address,
            vaultInstance.address,
            1
          );
        await vaultInstance.connect(beneficialOwner).grantEntitlement({
          beneficialOwner: beneficialOwner.address,
          operator: runner.address,
          vaultAddress: vaultInstance.address,
          assetId: 1,
          expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
        });
      });

      it("doesn't allow flashloans if disabled for a collection", async function () {
        await protocol.setCollectionConfig(
          testNFT.address,
          ethers.utils.id("vault.flashLoanDisabled"),
          true
        );
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              1,
              runner.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "flashLoan -- flashLoan feature disabled for this contract"
        );
      });

      it("doesn't allow flashloans to zero address", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              1,
              "0x0000000000000000000000000000000000000000",
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith("flashLoan -- zero address");
      });

      it("doesn't allow flashloans with invalid asset ids", async function () {
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              10,
              runner.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith("ERC721: owner query for nonexistent token");
      });

      it("allows basic flashloans", async function () {
        const flashLoan = await ethers.getContractFactory("FlashLoanSuccess");
        const flashLoanRec = await flashLoan.deploy();
        await vaultInstance
          .connect(beneficialOwner)
          .flashLoan(
            1,
            flashLoanRec.address,
            "0x0000000000000000000000000000000000000000"
          );
      });

      it("blocks non-approving flashloans", async function () {
        const flashLoan = await ethers.getContractFactory(
          "FlashLoanDoesNotApprove"
        );
        const flashLoanRec = await flashLoan.deploy();
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              1,
              flashLoanRec.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "ERC721: transfer caller is not owner nor approve"
        );
      });

      it("blocks false-returning flashloan", async function () {
        const flashLoan = await ethers.getContractFactory(
          "FlashLoanReturnsFalse"
        );
        const flashLoanRec = await flashLoan.deploy();
        await expect(
          vaultInstance
            .connect(beneficialOwner)
            .flashLoan(
              1,
              flashLoanRec.address,
              "0x0000000000000000000000000000000000000000"
            )
        ).to.be.revertedWith(
          "flashLoan -- the flash loan contract must return true"
        );
      });
    });
  });
});

describe("Call Instrument Tests", function () {
  // Constants
  const SECS_IN_A_DAY = 60 * 60 * 24;

  // Contracts
  let vaultFactory: Contract,
    protocol: Contract,
    token: Contract,
    calls: Contract,
    weth: Contract;

  // Signers
  let admin: SignerWithAddress,
    writer: SignerWithAddress,
    operator: SignerWithAddress,
    buyer: SignerWithAddress,
    firstBidder: SignerWithAddress,
    secondBidder: SignerWithAddress;

  beforeEach(async function () {
    // Create signers
    [admin, writer, operator, buyer, firstBidder, secondBidder] =
      await ethers.getSigners();

    // Deploy weth
    const wethFactory = await ethers.getContractFactory("WETH");
    weth = await wethFactory.deploy();

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
      "HookUpgradeableBeacon"
    );
    const multiVaultImplFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultImplV1"
    );
    const multiVaultBeaconFactory = await ethers.getContractFactory(
      "HookUpgradeableBeacon"
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
    const tokenURILib = await ethers.getContractFactory("TokenURI");
    const tokenURI = await tokenURILib.deploy();
    const callImplFactory = await ethers.getContractFactory(
      "HookCoveredCallImplV1",
      { libraries: { TokenURI: tokenURI.address } }
    );
    const callBeaconFactory = await ethers.getContractFactory(
      "HookUpgradeableBeacon"
    );

    const callImpl = await callImplFactory.deploy();
    const callBeacon = await callBeaconFactory.deploy(
      callImpl.address,
      protocol.address,
      ethers.utils.id("VAULT_UPGRADER")
    );
    const callFactory = await callFactoryFactory.deploy(
      protocol.address,
      callBeacon.address,
      getAddress("0x0000000000000000000000000000000000000000")
    );

    protocol.setCoveredCallFactory(callFactory.address);

    // Create another call instrument contract instance
    await callFactory.makeCallInstrument(token.address);
    const callInstrumentAddress = await callFactory.getCallInstrument(
      token.address
    );

    // Attach to existing address
    calls = await ethers.getContractAt(
      "HookCoveredCallImplV1",
      callInstrumentAddress
    );

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
  describe("mintWithErc721", function () {
    it("should mint covered call with unvaulted erc721", async function () {
      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
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

    it("should not mint covered call when project not on allowlist", async function () {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Set approval for call instrument
      await newToken.connect(writer).setApprovalForAll(calls.address, true);

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithErc721(newToken.address, 0, 1000, expiration);
      await expect(createCall).to.be.revertedWith(
        "mintWithErc721 -- token must be on the project allowlist"
      );
    });

    it("should not mint covered call when call instrument not owner or operator", async function () {
      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(buyer)
        .mintWithErc721(token.address, 0, 1000, expiration);
      await expect(createCall).to.be.revertedWith(
        "mintWithErc721 -- caller must be token owner or operator"
      );
    });

    it("should not mint covered call when call instrument not approved", async function () {
      // Unapprove call instrument
      await token.connect(writer).setApprovalForAll(calls.address, false);

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
      await expect(createCall).to.be.revertedWith(
        "mintWithErc721 -- HookCoveredCall must be operator"
      );
    });

    it("should not mint covered call when vault already holds an asset", async function () {
      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);

      // Mint another call option
      const createCall2 = calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);

      await expect(createCall2).to.be.revertedWith(
        "mintWithErc721 -- caller must be token owner or operator"
      );
    });

    it("should mint covered call with unvaulted erc721 as operator", async function () {
      await token.connect(writer).setApprovalForAll(operator.address, true);

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = await calls
        .connect(operator)
        .mintWithErc721(token.address, 0, 1000, expiration);
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

    it("should mint covered call with unvaulted erc721 with existing multivault", async function () {
      await vaultFactory.makeMultiVault(token.address);

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
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
  describe("mintWithVault", function () {
    let multiVault: Contract;

    this.beforeEach(async function () {
      // Create multivault for token
      await vaultFactory.makeMultiVault(token.address);
      const multiValutAddress = await vaultFactory.getMultiVault(token.address);
      multiVault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        multiValutAddress
      );
    });

    it("should not mint covered call when project not on allowlist", async function () {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Create multivault for newToken
      await vaultFactory.makeMultiVault(newToken.address);
      const multiValutAddress = await vaultFactory.getMultiVault(
        newToken.address
      );
      const newTokenMultiVault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        multiValutAddress
      );

      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls.connect(writer).mintWithVault(
        newTokenMultiVault.address, // invalid vault address
        0,
        1000,
        expiration,
        signature
      );
      await expect(createCall).to.be.revertedWith(
        "mintWithVault -- token must be on the project allowlist"
      );
    });

    it("should not mint covered call with empty vault", async function () {
      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithVault(multiVault.address, 0, 1000, expiration, signature);
      await expect(createCall).to.be.revertedWith(
        "mintWithVault-- asset must be in vault"
      );
    });

    it("should not mint covered call with invalid signature", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
        );

      // Create signature
      const signature = {
        signatureType: 2, // EIP712 - signature utils 0x
        r: "0x0000000000000000000000000000000000000000000000000000000000000000",
        s: "0x0000000000000000000000000000000000000000000000000000000000000000",
        v: "0x01",
      };

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithVault(multiVault.address, 0, 1000, expiration, signature);
      // TODO: Find revert reason
      await expect(createCall).to.be.reverted;
    });

    it("should mint covered call with valid signature", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
        );

      const expiration = Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5);

      const signature = await signEntitlement(
        writer.address,
        calls.address,
        multiVault.address,
        "0",
        String(expiration),
        writer,
        protocol.address
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithVault(multiVault.address, 0, 1000, expiration, signature);

      await createCall;
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~ mintWithEntitledVault ~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("mintWithEntitledVault", function () {
    let multiVault: Contract;

    this.beforeEach(async function () {
      // Create multivault for token
      await vaultFactory.makeMultiVault(token.address);
      const multiValutAddress = await vaultFactory.getMultiVault(token.address);
      multiVault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        multiValutAddress
      );
    });

    it("should not mint covered call when project not on allowlist", async function () {
      // Deploy test NFT
      const testNftFactory = await ethers.getContractFactory("TestERC721");
      const newToken = await testNftFactory.deploy();

      // Mint token
      await newToken.connect(writer).mint(writer.address, 0);

      // Create multivault for newToken
      await vaultFactory.makeMultiVault(newToken.address);
      const multiValutAddress = await vaultFactory.getMultiVault(
        newToken.address
      );
      const newTokenMultiVault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        multiValutAddress
      );

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls.connect(writer).mintWithEntitledVault(
        newTokenMultiVault.address, // invalid vault address
        0,
        1000,
        expiration
      );
      await expect(createCall).to.be.revertedWith(
        "mintWithVault -- token must be on the project allowlist"
      );
    });

    it("should not mint covered call with empty vault", async function () {
      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithEntitledVault(multiVault.address, 0, 1000, expiration);
      await expect(createCall).to.be.revertedWith(
        "mintWithVault-- asset must be in vault"
      );
    });

    it("should not mint covered call with no entitlement", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
        );

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithEntitledVault(multiVault.address, 0, 1000, expiration);
      // TODO: Find revert reason
      await expect(createCall).to.be.revertedWith(
        "mintWithVault -- call contact must be the entitled operator"
      );
    });

    it("should not mint covered call with inactive entitlement", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
        );

      await multiVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: "0x0000000000000000000000000000000000000000",
        vaultAddress: multiVault.address,
        assetId: 0,
        expiry: Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5),
      });

      const expiration = String(
        Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = calls
        .connect(writer)
        .mintWithEntitledVault(multiVault.address, 0, 1000, expiration);

      await expect(createCall).to.be.revertedWith(
        "mintWithVault -- call contact must be the entitled operator"
      );
    });

    it("should not mint covered call with non matching entitlement expiration", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
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
      const createCall = calls
        .connect(writer)
        .mintWithEntitledVault(
          multiVault.address,
          0,
          1000,
          String(expiration + 1)
        );

      await expect(createCall).to.be.revertedWith(
        "mintWithVault -- entitlement expiration must match call expiration"
      );
    });

    it("should mint covered call with entitled vault", async function () {
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
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
      const createCall = await calls
        .connect(writer)
        .mintWithEntitledVault(multiVault.address, 0, 1000, expiration);

      expect(createCall).to.emit(calls, "CallCreated");
    });

    it("should mint covered call with entitled solo vault", async function () {
      // Create solovault for token 1
      await vaultFactory.makeSoloVault(token.address, 1);
      const soloValutAddress = await vaultFactory.getVault(token.address, 1);
      const soloVault = await ethers.getContractAt(
        "HookERC721VaultImplV1",
        soloValutAddress
      );

      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          soloVault.address,
          1
        );

      const expiration = Math.floor(Date.now() / 1000 + SECS_IN_A_DAY * 1.5);

      await soloVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: calls.address,
        vaultAddress: soloVault.address,
        assetId: 0,
        expiry: expiration,
      });

      // Mint call option
      const createCall = await calls
        .connect(writer)
        .mintWithEntitledVault(soloVault.address, 0, 1000, expiration);

      expect(createCall).to.emit(calls, "CallCreated");
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~ bid ~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("bid", function () {
    let optionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should not bid before last day before expiration", async function () {
      const bid = calls
        .connect(firstBidder)
        .bid(optionTokenId, { value: 1000 });
      await expect(bid).to.be.revertedWith(
        "biddingEnabled -- bidding starts on last day"
      );
    });

    it("should not bid with bid lower than strike", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls
        .connect(firstBidder)
        .bid(optionTokenId, { value: 1000 });
      await expect(bid).to.be.revertedWith(
        "bid - bid is lower than the strike price"
      );
    });

    it("should bid with first bid above strike", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls
        .connect(firstBidder)
        .bid(optionTokenId, { value: 1001 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        firstBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);
    });

    it("should bid and outbid as standard bidder", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls
        .connect(firstBidder)
        .bid(optionTokenId, { value: 1001 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        firstBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls
        .connect(secondBidder)
        .bid(optionTokenId, { value: 1002 });
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        secondBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });

    it("should bid and outbid as with malicious bidder", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const maliciousBidder = await ethers.getContractFactory(
        "MaliciousBidder"
      );
      const deployedMaliciousBidder = await maliciousBidder.deploy(
        calls.address
      );

      const bid = deployedMaliciousBidder.bid(optionTokenId, { value: 1001 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        deployedMaliciousBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls
        .connect(secondBidder)
        .bid(optionTokenId, { value: 1002 });
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        secondBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
      expect(await weth.balanceOf(deployedMaliciousBidder.address)).to.eq(1001);
    });

    it("should bid and outbid as option writer", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls
        .connect(firstBidder)
        .bid(optionTokenId, { value: 1001 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        firstBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls.connect(writer).bid(optionTokenId, { value: 2 });
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });

    it("should bid on spread as option writer", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(writer).bid(optionTokenId, { value: 1 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);
    });

    it("should bid and outbid option writer", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      const bid = calls.connect(writer).bid(optionTokenId, { value: 1 });
      await expect(bid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(writer.address);
      expect(await calls.currentBid(optionTokenId)).to.equal(1001);

      const secondBid = calls
        .connect(secondBidder)
        .bid(optionTokenId, { value: 1002 });
      await expect(secondBid).to.emit(calls, "Bid");

      expect(await calls.currentBidder(optionTokenId)).to.equal(
        secondBidder.address
      );
      expect(await calls.currentBid(optionTokenId)).to.equal(1002);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~ settleOption ~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("settleOption", function () {
    let optionTokenId: BigNumber;
    let secondOptionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;

      // Mint another option - 3 day expiration
      const createCall2 = await calls
        .connect(writer)
        .mintWithErc721(token.address, 1, 1000, expiration);
      const cc2 = await createCall2.wait();

      const callCreatedEvent2 = cc2.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      secondOptionTokenId = callCreatedEvent2.args.optionId;

      // Transfer option NFTs to buyer (assume this is a purchase)
      await calls
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          buyer.address,
          optionTokenId
        );

      await calls
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          buyer.address,
          secondOptionTokenId
        );

      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      // Create bids
      // First option the writer has the winning bid
      await calls.connect(firstBidder).bid(optionTokenId, { value: 1001 });
      await calls.connect(writer).bid(optionTokenId, { value: 2 });

      // Second option the secondBidder has the winning bid
      await calls
        .connect(firstBidder)
        .bid(secondOptionTokenId, { value: 1001 });
      await calls
        .connect(secondBidder)
        .bid(secondOptionTokenId, { value: 1002 });
    });

    it("should not settle auction with no bids", async function () {
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 2, 1000, expiration);
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      const tokenId = callCreatedEvent.args.optionId;

      // Move forward to after auction period ends
      await ethers.provider.send("evm_increaseTime", [4 * SECS_IN_A_DAY]);

      const settleCall = calls.connect(writer).settleOption(tokenId);
      await expect(settleCall).to.be.revertedWith(
        "settle -- bid must be won by someone"
      );
    });

    it("should not settle auction before expiration", async function () {
      const settleCall = calls.connect(writer).settleOption(optionTokenId);
      await expect(settleCall).to.be.revertedWith(
        "settle -- option must be expired"
      );
    });

    it("should not settle settled auction", async function () {
      // Move forward to after auction period ends
      await ethers.provider.send("evm_increaseTime", [1 * SECS_IN_A_DAY]);

      await calls.connect(writer).settleOption(optionTokenId);
      const settleCallAgain = calls.connect(writer).settleOption(optionTokenId);
      await expect(settleCallAgain).to.be.revertedWith(
        "settle -- the call cannot already be settled"
      );
    });

    it("should settle auction", async function () {
      // Move forward to after auction period ends
      await ethers.provider.send("evm_increaseTime", [1 * SECS_IN_A_DAY]);

      const settleCall = calls.connect(writer).settleOption(optionTokenId);
      await expect(settleCall).to.emit(calls, "CallSettled");

      const vaultAddress = await calls.getVaultAddress(optionTokenId);
      const vault = await ethers.getContractAt(
        "HookERC721VaultImplV1",
        vaultAddress
      );

      expect(await vault.getBeneficialOwner(0)).to.eq(writer.address);
    });

    it("should settle auction when option writer is high bidder", async function () {
      // Move forward to after auction period ends
      await ethers.provider.send("evm_increaseTime", [1 * SECS_IN_A_DAY]);

      const settleCall = calls
        .connect(secondBidder)
        .settleOption(secondOptionTokenId);
      await expect(settleCall).to.emit(calls, "CallSettled");

      const vaultAddress = await calls.getVaultAddress(secondOptionTokenId);
      const vault = await ethers.getContractAt(
        "HookERC721VaultImplV1",
        vaultAddress
      );

      expect(await vault.getBeneficialOwner(0)).to.eq(secondBidder.address);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~ reclaimAsset ~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("reclaimAsset", function () {
    let optionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Mint option - 3 day expiration
      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = Math.floor(blockTimestamp + SECS_IN_A_DAY * 3);

      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);
      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should not reclaim asset as non call writer", async function () {
      const reclaimAsset = calls
        .connect(buyer)
        .reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith(
        "reclaimAsset -- asset can only be reclaimed by the writer"
      );
    });

    it("should not reclaim settled asset", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      // Bid as writer
      await calls.connect(writer).bid(optionTokenId, { value: 2 });

      // Move forward to end of auction period
      await ethers.provider.send("evm_increaseTime", [1 * SECS_IN_A_DAY]);

      // Settle option
      await calls.connect(writer).settleOption(optionTokenId);

      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith(
        "reclaimAsset -- the option has already been settled"
      );
    });

    it("should not reclaim asset when writer is not option owner", async function () {
      // Transfer option NFT to buyer (assume this is a purchase)
      await calls
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          buyer.address,
          optionTokenId
        );

      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith(
        "reclaimAsset -- the option must be owned by the writer"
      );
    });

    it("should not reclaim asset from expired option", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [3.1 * SECS_IN_A_DAY]);

      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith(
        "reclaimAsset -- the option must not be expired"
      );
    });

    it("should reclaim asset with an active bid", async function () {
      // Move forward to auction period
      await ethers.provider.send("evm_increaseTime", [2.1 * SECS_IN_A_DAY]);

      // Bid as firstBidder
      await calls.connect(firstBidder).bid(optionTokenId, { value: 1001 });

      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);

      await expect(reclaimAsset).to.emit(calls, "CallReclaimed");

      // Check that there's no entitlment on the vault
      const vaultAddress = await calls.getVaultAddress(optionTokenId);
      const vault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        vaultAddress
      );

      const result = await vault.getCurrentEntitlementOperator(0);
      expect(result.isActive).to.be.false;
    });

    it("should reclaim asset with no bids", async function () {
      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);

      await expect(reclaimAsset).to.emit(calls, "CallReclaimed");

      // Check that there's no entitlment on the vault
      const vaultAddress = await calls.getVaultAddress(optionTokenId);
      const vault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        vaultAddress
      );

      const result = await vault.getCurrentEntitlementOperator(0);
      expect(result.isActive).to.be.false;
    });

    it("should reclaim asset with no bids and return nft", async function () {
      await calls.connect(writer).reclaimAsset(optionTokenId, true);

      expect(await token.ownerOf(0)).to.eq(writer.address);
    });

    it("should not reclaim asset when paused", async function () {
      // Pause protocol
      await protocol.connect(admin).pause();
      await expect(protocol.throwWhenPaused()).to.be.reverted;

      // Attempt to reclaim asset
      const reclaimAsset = calls
        .connect(writer)
        .reclaimAsset(optionTokenId, false);
      await expect(reclaimAsset).to.be.revertedWith("Pausable: paused");
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~ config ~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("config", function () {
    let marketController: SignerWithAddress;

    this.beforeEach(async function () {
      [marketController] = await ethers.getSigners();

      const MARKET_CONF_ROLE = calls.MARKET_CONF();
      protocol
        .connect(admin)
        .grantRole(MARKET_CONF_ROLE, marketController.address);
    });

    it("should not modify configuration as non market controller", async function () {
      const setMinOptionDuration = calls
        .connect(writer)
        .setMinOptionDuration(0);
      await expect(setMinOptionDuration).to.be.revertedWith(
        "onlyMarketController -- caller does not have the MARKET_CONF protocol role"
      );
    });

    it("should set min option duration as market controller", async function () {
      await expect(calls.connect(marketController).setMinOptionDuration(100))
        .to.emit(calls, "MinOptionDurationUpdated")
        .withArgs(100);
    });

    it("should set bid increment as market controller", async function () {
      await expect(calls.connect(marketController).setBidIncrement(37))
        .to.emit(calls, "MinBidIncrementUpdated")
        .withArgs(37);
    });

    it("should set settlement auction start offset as market controller", async function () {
      await expect(
        calls.connect(marketController).setSettlementAuctionStartOffset(6)
      )
        .to.emit(calls, "SettlementAuctionStartOffsetUpdated")
        .withArgs(6);
    });

    it("should no set settlement auction start offset when more than minimum option duration", async function () {
      await calls.connect(marketController).setMinOptionDuration(100);

      await expect(
        calls.connect(marketController).setSettlementAuctionStartOffset(101)
      ).to.be.revertedWith(
        "the settlement auctions cannot start sooner than an option expired"
      );
    });

    it("should set market paused as market controller", async function () {
      await expect(calls.connect(marketController).setMarketPaused(true))
        .to.emit(calls, "MarketPauseUpdated")
        .withArgs(true);
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~ getters ~~~~~~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("getters", function () {
    let optionTokenId: BigNumber;
    let multiVault: Contract;
    let expiration: BigNumber;

    this.beforeEach(async function () {
      // Create multivault for token
      await vaultFactory.makeMultiVault(token.address);
      const multiValutAddress = await vaultFactory.getMultiVault(token.address);
      multiVault = await ethers.getContractAt(
        "HookERC721MultiVaultImplV1",
        multiValutAddress
      );

      // Transfer token to vault
      await token
        .connect(writer)
        ["safeTransferFrom(address,address,uint256)"](
          writer.address,
          multiVault.address,
          0
        );

      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      expiration = BigNumber.from(
        Math.floor(blockTimestamp + SECS_IN_A_DAY * 1.5)
      );

      await multiVault.connect(writer).grantEntitlement({
        beneficialOwner: writer.address,
        operator: calls.address,
        vaultAddress: multiVault.address,
        assetId: 0,
        expiry: expiration,
      });

      // Mint call option
      const createCall = await calls
        .connect(writer)
        .mintWithEntitledVault(multiVault.address, 0, 1000, expiration);

      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should get vault address", async function () {
      expect(await calls.getVaultAddress(optionTokenId)).to.eq(
        multiVault.address
      );
    });

    it("should get asset id", async function () {
      expect(await calls.getAssetId(optionTokenId)).to.eq(0);
    });

    it("should get strike price", async function () {
      expect(await calls.getStrikePrice(optionTokenId)).to.eq(1000);
    });

    it("should get expiration", async function () {
      expect(await calls.getExpiration(optionTokenId)).to.eq(expiration);
    });

    it("should have a tokenURI", async function () {
      expect(await calls.tokenURI(optionTokenId)).to.not.be.null;
    });
  });

  /*
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ~~~~~~~~ burnExpiredOption ~~~~~~~~~
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  */
  describe("burnExpiredOption", function () {
    let optionTokenId: BigNumber;

    this.beforeEach(async function () {
      // Create solovault for token 0
      await vaultFactory.makeSoloVault(token.address, 0);
      const soloValutAddress = await vaultFactory.getVault(token.address, 0);
      const soloVault = await ethers.getContractAt(
        "HookERC721VaultImplV1",
        soloValutAddress
      );

      const blockNumber = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNumber);
      const blockTimestamp = block.timestamp;
      const expiration = BigNumber.from(
        Math.floor(blockTimestamp + SECS_IN_A_DAY * 1.5)
      );

      // Mint call option
      const createCall = await calls
        .connect(writer)
        .mintWithErc721(token.address, 0, 1000, expiration);

      const cc = await createCall.wait();

      const callCreatedEvent = cc.events.find(
        (event: any) => event?.event === "CallCreated"
      );

      optionTokenId = callCreatedEvent.args.optionId;
    });

    it("should not burn expired option before expiration", async function () {
      await expect(calls.burnExpiredOption(optionTokenId)).to.be.revertedWith(
        "burnExpiredOption -- the option must be expired"
      );
    });

    it("should burn expired option", async function () {
      // Move forward past expiration
      await ethers.provider.send("evm_increaseTime", [2 * SECS_IN_A_DAY]);

      await expect(calls.burnExpiredOption(optionTokenId)).to.emit(
        calls,
        "ExpiredCallBurned"
      );
    });

    it("should not burn expired option with bids", async function () {
      // Move forward to settlement auction
      await ethers.provider.send("evm_increaseTime", [0.5 * SECS_IN_A_DAY]);

      // First bidder bid
      await calls.connect(firstBidder).bid(optionTokenId, { value: 1001 });

      // Move forward past option expiration
      await ethers.provider.send("evm_increaseTime", [2 * SECS_IN_A_DAY]);

      // Burn expired option
      await expect(calls.burnExpiredOption(optionTokenId)).to.be.revertedWith(
        "burnExpiredOption -- the option must not have bids"
      );
    });

    it("should not burn expired option when paused", async function () {
      // Pause protocol
      await protocol.connect(admin).pause();
      await expect(protocol.throwWhenPaused()).to.be.reverted;

      // Move forward past expiration
      await ethers.provider.send("evm_increaseTime", [2 * SECS_IN_A_DAY]);

      // Attempt to burn expired option
      await expect(calls.burnExpiredOption(optionTokenId)).to.be.revertedWith(
        "Pausable: paused"
      );
    });
  });
});
