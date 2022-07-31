// SPDX-License-Identifier: MIT
//
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        ██████████████                                        ██████████████
//        ██████████████          ▄▄████████████████▄▄         ▐█████████████▌
//        ██████████████    ▄█████████████████████████████▄    ██████████████
//         ██████████▀   ▄█████████████████████████████████   ██████████████▌
//          ██████▀   ▄██████████████████████████████████▀  ▄███████████████
//           ███▀   ██████████████████████████████████▀   ▄████████████████
//            ▀▀  ████████████████████████████████▀▀   ▄█████████████████▌
//              █████████████████████▀▀▀▀▀▀▀      ▄▄███████████████████▀
//             ██████████████████▀    ▄▄▄█████████████████████████████▀
//            ████████████████▀   ▄█████████████████████████████████▀  ██▄
//          ▐███████████████▀  ▄██████████████████████████████████▀   █████▄
//          ██████████████▀  ▄█████████████████████████████████▀   ▄████████
//         ██████████████▀   ███████████████████████████████▀   ▄████████████
//        ▐█████████████▌     ▀▀▀▀████████████████████▀▀▀▀      █████████████▌
//        ██████████████                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████

pragma solidity ^0.8.10;

import "./IHookERC721Vault.sol";

/// @title HookERC721Factory-factory for instances of the hook vault
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
///
/// @notice The Factory creates a specific vault for ERC721s.
interface IHookERC721VaultFactory {
  event ERC721VaultCreated(
    address nftAddress,
    uint256 tokenId,
    address vaultAddress
  );

  /// @notice emitted when a new MultiVault is deployed by the protocol
  /// @param nftAddress the address of the nft contract that may be deposited into the new vault
  /// @param vaultAddress address of the newly deployed vault
  event ERC721MultiVaultCreated(address nftAddress, address vaultAddress);

  /// @notice gets the address of a vault for a particular ERC-721 token
  /// @param nftAddress the contract address for the ERC-721
  /// @param tokenId the tokenId for the ERC-721
  /// @return the address of a {IERC721Vault} if one exists that supports the particular ERC-721, or the null address otherwise
  function getVault(address nftAddress, uint256 tokenId)
    external
    view
    returns (IHookERC721Vault);

  /// @notice gets the address of a multi-asset vault for a particular ERC-721 contract, if one exists
  /// @param nftAddress the contract address for the ERC-721
  /// @return the address of the {IERC721Vault} multi asset vault, or the null address if one does not exist
  function getMultiVault(address nftAddress)
    external
    view
    returns (IHookERC721Vault);

  /// @notice deploy a multi-asset vault if one has not already been deployed
  /// @param nftAddress the contract address for the ERC-721 to be supported by the vault
  /// @return the address of the newly deployed {IERC721Vault} multi asset vault
  function makeMultiVault(address nftAddress)
    external
    returns (IHookERC721Vault);

  /// @notice creates a vault for a specific tokenId. If there
  /// is a multi-vault in existence which supports that address
  /// the address for that vault is returned as a new one
  /// does not need to be made.
  /// @param nftAddress the contract address for the ERC-721
  /// @param tokenId the tokenId for the ERC-721
  function findOrCreateVault(address nftAddress, uint256 tokenId)
    external
    returns (IHookERC721Vault);

  /// @notice make a new vault that can contain a single asset only
  /// @dev the only valid asset id in this vault is = 0
  /// @param nftAddress the address of the underlying nft contract
  /// @param tokenId the individual token that can be deposited into this vault
  function makeSoloVault(address nftAddress, uint256 tokenId)
    external
    returns (IHookERC721Vault);
}
