// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @dev See {IHookCoveredCall}.
/// @dev The HookCoveredCall is a BeaconProxy, which allows the implemenation of the protocol to be upgraded in the
/// future. Further, each covered call is mapped to a specific ERC-721 contract address -- meaning there is one covered
/// call contract per collection.
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
