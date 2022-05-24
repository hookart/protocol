pragma solidity ^0.8.10;

import "../HookBeaconProxy.sol";

library BeaconSalts {
  bytes32 constant ByteCodeHash = keccak256(type(HookBeaconProxy).creationCode);

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
