pragma solidity ^0.8.10;

import "../interfaces/IHookERC721Vault.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

library VaultAuthenticator {
    function isHookERC721Vault(address vaultAddress, uint32 assetId) returns (bool) {
    if (
      vaultAddress ==
      Create2.computeAddress(
        BeaconSalts.multiVaultSalt(underlyingAddress),
        BeaconSalts.ByteCodeHash,
        address(_erc721VaultFactory)
      )
    ) {
      return true;
    }

    try IHookERC721Vault(vaultAddress).assetTokenId(assetId) returns (
      uint256 _tokenId
    ) {
      if (
        vaultAddress ==
        Create2.computeAddress(
          BeaconSalts.soloVaultSalt(underlyingAddress, _tokenId),
          BeaconSalts.ByteCodeHash,
          address(_erc721VaultFactory)
        )
      ) {
        return true;
      }
    } catch (bytes memory) {
      return false;
    }

    return false;
  }
}