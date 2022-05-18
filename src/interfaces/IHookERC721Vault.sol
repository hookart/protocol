pragma solidity ^0.8.10;

import "./IHookVault.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice the IHookERC721 vault is an extension of the standard IHookVault
/// specifically designed to hold and receive ERC721 Tokens.
///
/// SEND TRANSACTION -
///     (1) owners are able to forward transactions to this vault to other wallets
///     (2) calls to the ERC-721 address are blocked to prevent approvals from being set on the
///         NFT while in escrow, which could allow for theft
///     (3) At the end of each transaction, the ownerOf the vaulted token must still be the vault
///
/// FLASH LOAN -
///     (1) beneficial owners are able to borrow the vaulted asset for a single function call
///     (2) to borrow the asset, they must implement and deploy a {IERC721FlashLoanReceiver}
///         contract, and then call the flashLoan method.
///     (3) At the end of the flashLoan, we ensure the asset is still owned by the vault.
interface IHookERC721Vault is IHookVault, IERC721Receiver {
  /// @notice emitted after an asset is flash loaned by its beneficial owner.
  /// @dev only one asset can be flash loaned at a time, and that asset is
  /// denoted by the tokenId emitted.
  event AssetFlashLoaned(address owner, uint256 tokenId, address flashLoanImpl);

  /// @notice the tokenID of the underlying ERC721 token;
  function assetTokenId(uint256 assetId) external view returns (uint256);

  /// @notice flashLoans the vaulted asset to another contract for use and return to the vault. Only the owner
  /// may perform the flashloan
  /// @dev the flashloan receiver can perform arbitrary logic, but must approve the vault as an operator
  /// before returning.
  /// @param receiverAddress the contract which implements the {IERC721FlashLoanReceiver} interface to utilize the
  /// asset while it is loaned out
  /// @param params calldata params to forward to the reciever
  function flashLoan(
    uint256 assetId,
    address receiverAddress,
    bytes calldata params
  ) external;
}
