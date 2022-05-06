pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @dev Generally, EOAs should not be specified as the entitled account in an Entitlement because
/// users will be unable to verify the behavior of those accounts as they are non-deterministic.
contract HookERC721Vault is BeaconProxy {
  constructor(
    address beacon,
    address nftAddress,
    uint256 nftTokenId,
    address hookProtocolAddress
  )
    BeaconProxy(
      beacon,
      abi.encodeWithSignature(
        "initialize(address,uint256,address)",
        nftAddress,
        nftTokenId,
        hookProtocolAddress
      )
    )
  {}
}
