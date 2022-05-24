import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("Deploy", function () {
  it("the protocol should deploy", async function () {
    const [admin] = await ethers.getSigners();
    const wethFactory = await ethers.getContractFactory("WETH");
    const weth = await wethFactory.deploy();
    const HookProtocol = await ethers.getContractFactory("HookProtocol");

    const protocol = await HookProtocol.deploy(admin.address, weth.address);
  });
});
