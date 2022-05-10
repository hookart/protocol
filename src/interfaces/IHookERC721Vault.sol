pragma solidity ^0.8.10;

import "./IHookVault.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice the IHookERC721 vault is an extension of the standard IHookVault
/// specifically designed to hold and receive ERC721 Tokens.
///
/// SEND TRANSACTION (FLASH LOAN) -
///     (1) owners are able to forward transactions to this vault to other wallets
///     (2) calls to the ERC-721 address are blocked to prevent approvals from being set on the
///         NFT while in escrow, which could allow for theft
///     (3) At the end of each transaction, the ownerOf the vaulted token must still be the vault
interface IHookERC721Vault is IHookVault, IERC721Receiver {
  /// @notice the tokenID of the underlying ERC721 token;
  function assetTokenId() external view returns (uint256);
}
