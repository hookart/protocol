import { ethers } from "hardhat";
import { expect, use } from "chai";
import { Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import waffle from "@nomiclabs/hardhat-waffle";
import { solidity } from "ethereum-waffle";
use(solidity);
describe("Vault", function () {
  let vaultFactory: Contract, protocol: Contract, testNFT: Contract;
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
      (await expect(vaultFactory.makeMultiVault(testNFT.address)).to.be) as any
    ).revertedWith("makeMultiVault -- vault cannot already exist");
  });

  it("the factory should be able to make both vault types, return them correctly on find or create", async function () {
    const singleVault = await vaultFactory.makeSoloVault(testNFT.address, 1);
    const sv = await singleVault.wait();
    const singleVaultCreate = sv.events.find(
      (event: any) => event?.event === "ERC721VaultCreated"
    );
    const [singleAsset, singleId, singleVaultAddress] = singleVaultCreate.args;
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
