import { ethers } from "hardhat";
import { expect, use } from "chai";
import { Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { solidity } from "ethereum-waffle";
import { signEntitlement } from "./helpers";

use(solidity);
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
      "HookERC721VaultBeacon"
    );
    const multiVaultImplFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultImplV1"
    );
    const multiVaultBeaconFactory = await ethers.getContractFactory(
      "HookERC721MultiVaultBeacon"
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
          "setBeneficialOwner -- this contract only contains one asset"
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
              ["tuple(address, address, address, uint256, uint256)"],
              [
                [
                  beneficialOwner.address,
                  runner.address,
                  vaultInstance.address,
                  0,
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
        expect(await vaultInstance.hasActiveEntitlement()).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
        );
      });
      it("cannot impose entitlment with invalid asset id", async function () {
        const nowEpoch = Date.now() / 1000;
        await expect(
          testNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256,bytes)"](
              beneficialOwner.address,
              vaultInstance.address,
              1,
              ethers.utils.defaultAbiCoder.encode(
                ["tuple(address, address, address, uint256, uint256)"],
                [
                  [
                    beneficialOwner.address,
                    runner.address,
                    vaultInstance.address,
                    10,
                    Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                  ],
                ]
              )
            )
        ).to.be.revertedWith(
          "_verifyAndRegisterEntitlement -- the asset id must match an actual asset id"
        );
      });

      it("cannot impose entitlment with for a different vault", async function () {
        const nowEpoch = Date.now() / 1000;
        await expect(
          testNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256,bytes)"](
              beneficialOwner.address,
              vaultInstance.address,
              1,
              ethers.utils.defaultAbiCoder.encode(
                ["tuple(address, address, address, uint256, uint256)"],
                [
                  [
                    beneficialOwner.address,
                    runner.address,
                    runner.address,
                    0,
                    Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                  ],
                ]
              )
            )
        ).to.be.revertedWith(
          "_verifyAndRegisterEntitlement -- the entitled contract must match the vault contract"
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
        expect(await vaultInstance.hasActiveEntitlement()).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
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

        await vaultInstance.connect(runner).imposeEntitlement(
          {
            beneficialOwner: beneficialOwner.address,
            operator: runner.address,
            vaultAddress: vaultInstance.address,
            assetId: 0,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          },
          await signEntitlement(
            beneficialOwner.address,
            runner.address,
            vaultInstance.address,
            "0",
            String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
            beneficialOwner,
            protocol.address
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

        expect(await vaultInstance.hasActiveEntitlement()).to.be.true;
        expect(await vaultInstance.entitlementExpiration(0)).eq(
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
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

        await expect(
          vaultInstance.connect(runner).imposeEntitlement(
            {
              beneficialOwner: beneficialOwner.address,
              operator: runner.address,
              vaultAddress: vaultInstance.address,
              assetId: 0,
              expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
            },
            await signEntitlement(
              beneficialOwner.address,
              runner.address,
              vaultInstance.address,
              "0",
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
              runner,
              protocol.address
            )
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

        await expect(
          vaultInstance.connect(runner).imposeEntitlement(
            {
              beneficialOwner: beneficialOwner.address,
              operator: runner.address,
              vaultAddress: vaultInstance.address,
              assetId: 0,
              expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
            },
            await signEntitlement(
              beneficialOwner.address,
              runner.address,
              vaultInstance.address,
              "0",
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1)),
              beneficialOwner,
              protocol.address
            )
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
          "clearEntitlementAndDistribute -- Only the beneficial owner can recieve the asset"
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
        ).to.be.revertedWith("flashLoan -- invalid asset id");
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
              ["tuple(address, address, address, uint256, uint256)"],
              [
                [
                  beneficialOwner.address,
                  runner.address,
                  vaultInstance.address,
                  1,
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
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
        );
      });
      it("cannot impose entitlment with different entitlement id", async function () {
        const nowEpoch = Date.now() / 1000;
        await expect(
          testNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256,bytes)"](
              beneficialOwner.address,
              vaultInstance.address,
              1,
              ethers.utils.defaultAbiCoder.encode(
                ["tuple(address, address, address, uint256, uint256)"],
                [
                  [
                    beneficialOwner.address,
                    runner.address,
                    vaultInstance.address,
                    10,
                    Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                  ],
                ]
              )
            )
        ).to.be.revertedWith(
          "onERC721Recieved -- cannot impose an entitlement on an asset other than the asset deposited in the transfer"
        );
      });

      it("cannot impose entitlment with for a different vault", async function () {
        const nowEpoch = Date.now() / 1000;
        await expect(
          testNFT
            .connect(beneficialOwner)
            ["safeTransferFrom(address,address,uint256,bytes)"](
              beneficialOwner.address,
              vaultInstance.address,
              1,
              ethers.utils.defaultAbiCoder.encode(
                ["tuple(address, address, address, uint256, uint256)"],
                [
                  [
                    beneficialOwner.address,
                    runner.address,
                    runner.address,
                    1,
                    Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
                  ],
                ]
              )
            )
        ).to.be.revertedWith(
          "_verifyAndRegisterEntitlement -- the entitled contract must match the vault contract"
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
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
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

        await vaultInstance.connect(runner).imposeEntitlement(
          {
            beneficialOwner: beneficialOwner.address,
            operator: runner.address,
            vaultAddress: vaultInstance.address,
            assetId: 1,
            expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
          },
          await signEntitlement(
            beneficialOwner.address,
            runner.address,
            vaultInstance.address,
            "1",
            String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
            beneficialOwner,
            protocol.address
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
          String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5))
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

        await expect(
          vaultInstance.connect(runner).imposeEntitlement(
            {
              beneficialOwner: beneficialOwner.address,
              operator: runner.address,
              vaultAddress: vaultInstance.address,
              assetId: 1,
              expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
            },
            await signEntitlement(
              beneficialOwner.address,
              runner.address,
              vaultInstance.address,
              "1",
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5)),
              runner,
              protocol.address
            )
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

        await expect(
          vaultInstance.connect(runner).imposeEntitlement(
            {
              beneficialOwner: beneficialOwner.address,
              operator: runner.address,
              vaultAddress: vaultInstance.address,
              assetId: 1,
              expiry: Math.floor(nowEpoch + SECS_IN_A_DAY * 1.5),
            },
            await signEntitlement(
              beneficialOwner.address,
              runner.address,
              vaultInstance.address,
              "1",
              String(Math.floor(nowEpoch + SECS_IN_A_DAY * 1)),
              beneficialOwner,
              protocol.address
            )
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
          "clearEntitlementAndDistribute -- Only the beneficial owner can recieve the asset"
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
