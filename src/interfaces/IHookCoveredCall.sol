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

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../lib/Signatures.sol";

/// @title A covered call instrument
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
///
/// @notice This contract implements a "Covered Call Option". A call option gives the holder the right, but not
/// the obligation to purchase an asset at a fixed time in the future (the expiry) for a fixed price (the strike).
///
///
/// This call option implementation here is similar to a "european" call option because the asset can
/// only be purchased at the expiration. The call option is "covered"  because the underlying
/// asset, must be held in escrow within a IHookVault for the entire duration of the option.
///
/// There are three phases to the call option:
///
/// (1) WRITING:
/// The owner of the NFT can mint an option by calling the "mint" function using the parameters of the subject ERC-721;
/// specifying additionally their preferred strike price and expiration. An "instrument nft" is minted to the writer's
/// address, where the holder of this ERC-721 will receive the economic benefit of holding the option.
///
/// (2) SALE:
/// The sale occurs outside of the context of this contract; however, the ZeroEx market contracts are pre-approved to
/// transfer the tokens. By Selling the instrument NFT, the writer earns a "premium" for selling their option. The
/// option may be sold and re-sold multiple times.
///
/// (3) SETTLEMENT:
/// One day prior to the expiration, and auction begins. People are able to call bid() for more than the strike price to
/// place a bid. If, at settlement, the high bid is greater than the strike, (b-strike) is transferred to the holder
/// of the instrument NFT, the strike price is transferred to the writer. The high bid is transferred to the holder of
/// the option.
interface IHookCoveredCall is IERC721Metadata {
  /// @notice emitted when a new call option is successfully minted with a specific underlying vault
  event CallCreated(
    address writer,
    address vaultAddress,
    uint256 assetId,
    uint256 optionId,
    uint256 strikePrice,
    uint256 expiration
  );

  /// @notice emitted when a call option is settled
  event CallSettled(uint256 optionId, bool claimable);

  /// @notice emitted when a call option is reclaimed
  event CallReclaimed(uint256 optionId);

  /// @notice emitted when a expired call option is burned
  event ExpiredCallBurned(uint256 optionId);

  /// @notice emitted when a call option settlement auction gets and accepts a new bid
  /// @param bidder the account placing the bid that is now the high bidder
  /// @param bidAmount the amount of wei bid
  /// @param optionId the option for the underlying that was bid on
  event Bid(uint256 optionId, uint256 bidAmount, address bidder);

  /// @notice emitted when an option owner claims their proceeds
  /// @param optionId the option the claim is on
  /// @param to the option owner making the claim
  /// @param amount the amount of the claim distributed
  event CallProceedsDistributed(uint256 optionId, address to, uint256 amount);

  /// @notice Mints a new call option for a particular "underlying" ERC-721 NFT with a given strike price and expiration
  /// @param tokenAddress the contract address of the ERC-721 token that serves as the underlying asset for the call
  /// option
  /// @param tokenId the tokenId of the underlying ERC-721 token
  /// @param strikePrice the strike price for the call option being written
  /// @param expirationTime time the timestamp after which the option will be expired
  function mintWithErc721(
    address tokenAddress,
    uint256 tokenId,
    uint128 strikePrice,
    uint32 expirationTime
  ) external returns (uint256);

  /// @notice Mints a new call option for the assets deposited in a particular vault given strike price and expiration.
  /// @param vaultAddress the contract address of the vault currently holding the call option
  /// @param assetId the id of the asset within the vault
  /// @param strikePrice the strike price for the call option being written
  /// @param expirationTime time the timestamp after which the option will be expired
  /// @param signature the signature used to place the entitlement onto the vault
  function mintWithVault(
    address vaultAddress,
    uint32 assetId,
    uint128 strikePrice,
    uint32 expirationTime,
    Signatures.Signature calldata signature
  ) external returns (uint256);

  /// @notice Mints a new call option for the assets deposited in a particular vault given strike price and expiration.
  /// That vault must already have a registered entitlement for this contract with the an expiration equal to {expirationTime}
  /// @param vaultAddress the contract address of the vault currently holding the call option
  /// @param assetId the id of the asset within the vault
  /// @param strikePrice the strike price for the call option being written
  /// @param expirationTime time the timestamp after which the option will be expired
  function mintWithEntitledVault(
    address vaultAddress,
    uint32 assetId,
    uint128 strikePrice,
    uint32 expirationTime
  ) external returns (uint256);

  /// @notice Bid in the settlement auction for an option. The paid amount is the bid,
  /// and the bidder is required to escrow this amount until either the auction ends or another bidder bids higher
  ///
  /// The bid must be greater than the strike price
  /// @param optionId the optionId corresponding to the settlement to bid on.
  function bid(uint256 optionId) external payable;

  /// @notice view function to get the current high settlement bid of an option, or 0 if there is no high bid
  /// @param optionId of the option to check
  function currentBid(uint256 optionId) external view returns (uint128);

  /// @notice view function to get the current high bidder for an option settlement auction, or the null address if no
  /// high bidder exists
  /// @param optionId of the option to check
  /// @return address of the account for the current high bidder, or the null address if there is none
  function currentBidder(uint256 optionId) external view returns (address);

  /// @notice Allows the writer to reclaim an entitled asset. This is only possible when the writer holds the option
  /// nft and calls this function.
  /// @dev Allows the writer to reclaim a NFT if they also hold the option NFT.
  /// @param optionId the option being reclaimed.
  /// @param returnNft true if token should be withdrawn from vault, false to leave token in the vault.
  function reclaimAsset(uint256 optionId, bool returnNft) external;

  /// @notice Looks up the latest optionId that covers a particular asset, if one exists. This option may be already settled.
  /// @dev getOptionIdForAsset
  /// @param vault the address of the hook vault that holds the covered asset
  /// @param assetId the id of the asset to check
  /// @return the optionId, if one exists or 0 otherwise
  function getOptionIdForAsset(address vault, uint32 assetId)
    external
    view
    returns (uint256);

  /// @notice Permissionlessly settle an expired option when the option expires in the money, distributing
  /// the proceeds to the Writer, Holder, and Bidder as follows:
  ///
  /// WRITER (who originally called mint() and owned underlying asset) - receives the `strike`
  /// HOLDER (ownerOf(optionId)) - receives `b-strike`
  /// HIGH BIDDER (call.highBidder) - becomes ownerOf NFT, pays `bid`.
  ///
  /// @dev the return nft param allows the underlying asset to remain in its vault. This saves gas
  /// compared to first distributing it and then re-depositing it. No royalties or other payments
  /// are subtracted from the distribution amounts.
  ///
  /// @param optionId of the option to settle.
  function settleOption(uint256 optionId) external;

  /// @notice Allows anyone to burn the instrument NFT for an expired option.
  /// @param optionId of the option to burn.
  function burnExpiredOption(uint256 optionId) external;

  /// @notice allows the option owner to claim proceeds if the option was settled
  /// by another account. The option NFT is burned after settlement.
  /// @dev this mechanism prevents the proceeds from being sent to an account
  /// temporarily custodying the option asset.
  /// @param optionId the option to claim and burn.
  function claimOptionProceeds(uint256 optionId) external;
}
