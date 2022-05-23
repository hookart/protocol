import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("Deploy", function () {
  it("the protocol should deploy", async function () {
    const [admin] = await ethers.getSigners();
    console.log("got signers");
    const weath = await ethers.getContractFactory("WETH");
    const weth = await weath.deploy();
    console.log(weth.address);
    const HookProtocol = await ethers.getContractFactory("HookProtocol");

    const protocol = await HookProtocol.deploy(admin.address, weth.address);
  });
});
