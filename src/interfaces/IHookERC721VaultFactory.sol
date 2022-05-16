pragma solidity ^0.8.10;

/// @title HookERC721Factory -- factory for instances of the hook vault
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Factory creates a specific vault for ERC721s.
interface IHookERC721VaultFactory {
  event ERC721VaultCreated(
    address nftAddress,
    uint256 tokenId,
    address vaultId
  );

  function getVault(address nftAddress, uint256 tokenId)
    external
    view
    returns (address vault);

  function makeVault(address nftAddress, uint256 tokenId)
    external
    returns (address vault);
}
