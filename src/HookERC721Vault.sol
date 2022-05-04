pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

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
