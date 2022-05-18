pragma solidity ^0.8.10;

import "./IHookERC721Vault.sol";

/// @title HookERC721Factory -- factory for instances of the hook vault
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Factory creates a specific vault for ERC721s.
interface IHookERC721VaultFactory {
  event ERC721VaultCreated(
    address nftAddress,
    uint256 tokenId,
    address vaultAddress
  );

  event ERC721MultiVaultCreated(address nftAddress, address vaultAddress);

  function getVault(address nftAddress, uint256 tokenId)
    external
    view
    returns (IHookERC721Vault vault);

  function getMultiVault(address nftAddress)
    external
    view
    returns (IHookERC721Vault vault);

  function findOrCreateVault(address nftAddress, uint256 tokenId)
    external
    returns (IHookERC721Vault vault);
}
