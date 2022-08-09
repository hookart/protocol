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

import "../lib/Entitlements.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Generic Hook Vault-a vault designed to contain a single asset to be used as escrow.
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
///
/// @notice The Vault holds an asset on behalf of the owner. The owner is able to post this
/// asset as collateral to other protocols by signing a message, called an "entitlement", that gives
/// a specific account the ability to change the owner.
///
/// The vault can work with multiple assets via the assetId, where the asset or set of assets covered by
/// each segment is granted an individual id.
/// Every asset must be identified by an assetId to comply with this interface, even if the vault only contains
/// one asset.
///
/// ENTITLEMENTS -
///     (1) only one entitlement can be placed at a time.
///     (2) entitlements must expire, but can also be cleared by the entitled party
///     (3) if an entitlement expires, the current beneficial owner gains immediate sole control over the
///        asset
///     (4) the entitled entity can modify the beneficial owner of the asset, but cannot withdrawal.
///     (5) the beneficial owner cannot modify the beneficial owner while an entitlement is in place
///
interface IHookVault is IERC165 {
  /// @notice emitted when an entitlement is placed on an asset
  event EntitlementImposed(
    uint32 assetId,
    address entitledAccount,
    uint32 expiry,
    address beneficialOwner
  );

  /// @notice emitted when an entitlement is cleared from an asset
  event EntitlementCleared(uint256 assetId, address beneficialOwner);

  /// @notice emitted when the beneficial owner of an asset changes
  /// @dev it is not required that this event is emitted when an entitlement is
  /// imposed that also modifies the beneficial owner.
  event BeneficialOwnerSet(
    uint32 assetId,
    address beneficialOwner,
    address setBy
  );

  /// @notice emitted when an asset is added into the vault
  event AssetReceived(
    address owner,
    address sender,
    address contractAddress,
    uint32 assetId
  );

  /// @notice Emitted when `beneficialOwner` enables `approved` to manage the `assetId` asset.
  event Approval(
    address indexed beneficialOwner,
    address indexed approved,
    uint32 indexed assetId
  );

  /// @notice emitted when an asset is withdrawn from the vault
  event AssetWithdrawn(uint32 assetId, address to, address beneficialOwner);

  /// @notice Withdrawal an unencumbered asset from this vault
  /// @param assetId the asset to remove from the vault
  function withdrawalAsset(uint32 assetId) external;

  /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
  /// @param assetId the id of the subject asset to impose the entitlement
  /// @param newBeneficialOwner the account of the person who is able to withdrawal when there are no entitlements.
  function setBeneficialOwner(uint32 assetId, address newBeneficialOwner)
    external;

  /// @notice Add an entitlement claim to the asset held within the contract
  /// @param operator the operator to entitle
  /// @param expiry the duration of the entitlement
  /// @param assetId the id of the asset within the vault
  /// @param v sig v
  /// @param r sig r
  /// @param s sig s
  function imposeEntitlement(
    address operator,
    uint32 expiry,
    uint32 assetId,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  /// @notice Allows the beneficial owner to grant an entitlement to an asset within the contract
  /// @dev this function call is signed by the sender per the EVM, so we know the entitlement is authentic
  /// @param entitlement The entitlement to impose onto the contract
  function grantEntitlement(Entitlements.Entitlement calldata entitlement)
    external;

  /// @notice Allows the entitled address to release their claim on the asset
  /// @param assetId the id of the asset to clear
  function clearEntitlement(uint32 assetId) external;

  /// @notice Removes the active entitlement from a vault and returns the asset to the beneficial owner
  /// @param receiver the intended receiver of the asset
  /// @param assetId the Id of the asset to clear
  function clearEntitlementAndDistribute(uint32 assetId, address receiver)
    external;

  /// @notice looks up the current beneficial owner of the asset
  /// @param assetId the referenced asset
  /// @return the address of the beneficial owner of the asset
  function getBeneficialOwner(uint32 assetId) external view returns (address);

  /// @notice checks if the asset is currently stored in the vault
  /// @param assetId the referenced asset
  /// @return true if the asset is currently within the vault, false otherwise
  function getHoldsAsset(uint32 assetId) external view returns (bool);

  /// @notice the contract address of the vaulted asset
  /// @param assetId the referenced asset
  /// @return the contract address of the vaulted asset
  function assetAddress(uint32 assetId) external view returns (address);

  /// @notice looks up the current operator of an entitlement on an asset
  /// @param assetId the id of the underlying asset
  function getCurrentEntitlementOperator(uint32 assetId)
    external
    view
    returns (bool, address);

  /// @notice Looks up the expiration timestamp of the current entitlement
  /// @dev returns the 0 if no entitlement is set
  /// @return the block timestamp after which the entitlement expires
  function entitlementExpiration(uint32 assetId) external view returns (uint32);

  /// @notice Gives permission to `to` to impose an entitlement upon `assetId`
  ///
  /// @dev Only a single account can be approved at a time, so approving the zero address clears previous approvals.
  ///   * Requirements:
  ///
  /// -  The caller must be the beneficial owner
  /// - `tokenId` must exist.
  ///
  /// Emits an {Approval} event.
  function approveOperator(address to, uint32 assetId) external;

  /// @dev Returns the account approved for `tokenId` token.
  ///
  /// Requirements:
  ///
  /// - `assetId` must exist.
  ///
  function getApprovedOperator(uint32 assetId) external view returns (address);
}
