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

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title Flash Loan Operator Interface (ERC-721)
/// @author Jake Nyquist-j@hook.xyz
/// @dev contracts that will utilize vaulted assets in flash loans should implement this interface in order to
/// receive the asset. Users may want to receive the asset within a single block to claim airdrops, participate
/// in governance, and other things with their assets.
///
/// The implementer may do whatever they like with the vaulted NFT within the executeOperation method,
/// so long as they approve the vault (passed as a param) to operate the underlying NFT. The Vault
/// will move the asset back into the vault after executionOperation returns, and also validate that
/// it is the owner of the asset.
///
/// The flashloan receiver is able to abort a flashloan by returning false from the executeOperation method.
interface IERC721FlashLoanReceiver is IERC721Receiver {
  /// @notice the method that contains the operations to be performed with the loaned asset
  /// @dev executeOperation is called immediately after the asset is transferred to this contract. After return,
  /// the asset is returned to the vault by the vault contract. The executeOperation implementation MUST
  /// approve the {vault} to operate the transferred NFT
  /// i.e. `IERC721(nftContract).setApprovalForAll(vault, true);`
  ///
  /// @param nftContract the address of the underlying erc-721 asset
  /// @param tokenId the address of the received erc-721 asset
  /// @param beneficialOwner the current beneficialOwner of the vault, who initialized the flashLoan
  /// @param vault the address of the vault performing the flashloan (in most cases, equal to msg.sender)
  /// @param params additional params passed by the caller into the flashloan
  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address beneficialOwner,
    address vault,
    bytes calldata params
  ) external returns (bool);
}
