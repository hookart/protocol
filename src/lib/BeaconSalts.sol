pragma solidity ^0.8.10;

import "../HookBeaconProxy.sol";

library Create2BeaconSalts {
  bytes32 constant ByteCodeHash = type(HookBeaconProxy).hash;

  function soloVaultSalt(address nftAddress, uint256 tokenId)
    public
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode(nftAddress, tokenId));
  }

  function multiVaultSalt(address nftAddress) public pure returns (bytes32) {
    return keccak256(abi.encode(nftAddress));
  }
}
