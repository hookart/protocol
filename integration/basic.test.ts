import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, Signer } from 'ethers';

describe('Mover', function () {
  let mover: Contract, nft: Contract;
  let alice: Signer, bob: Signer;

  before(async () => {
    const MockNFT = await ethers.getContractFactory('MockNFT');
    nft = await MockNFT.deploy();
    await nft.deployed();

    const Mover = await ethers.getContractFactory('Mover');
    mover = await Mover.deploy();
    await mover.deployed();

    [, alice, bob] = await ethers.getSigners();

    let balance = await nft.balanceOf(await alice.getAddress()); 
    expect(balance.toNumber()).eq(0);

    await nft.connect(alice).mint(2);

    balance = await nft.balanceOf(await alice.getAddress()); 
    expect(balance.toNumber()).eq(2);
    await nft.connect(alice).setApprovalForAll(mover.address, true);
  });

  it('should move many NFTs', async () => {
    let address = await bob.getAddress();

    let balance = await nft.balanceOf(address);
    expect(balance.toNumber()).eq(0);

    await mover.connect(alice).moveBatch(nft.address, [1, 2], address);

    balance = await nft.balanceOf(address);
    expect(balance.toNumber()).eq(2);
  });
  
})