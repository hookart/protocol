pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title ERC-721 MultiVault Proxy Contract
/// @author Jake Nyquist -- j@hook.xyz
/// @notice Each instance of this contract is a unique multi-vault which references the
/// shared implementation pointed to by the Beacon
contract HookERC721MultiVault is BeaconProxy {
  constructor(
    address beacon,
    address nftAddress,
    address hookProtocolAddress
  )
    BeaconProxy(
      beacon,
      abi.encodeWithSignature(
        "initialize(address,address)",
        nftAddress,
        hookProtocolAddress
      )
    )
  {}
}
