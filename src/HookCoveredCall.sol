// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract HookCoveredCall is BeaconProxy {
  // TODO(HOOK-789)[GAS]: Explore implemeting the initialize function by setting storage slots on the
  // newly deployed contract to avoid additional method calls.
  constructor(
    address beacon,
    address nftAddress,
    address protocol,
    address hookVaultFactory
  )
    BeaconProxy(
      beacon,
      abi.encodeWithSignature(
        "initialize(address,address,address)",
        protocol,
        nftAddress,
        hookVaultFactory
      )
    )
  {}
}
