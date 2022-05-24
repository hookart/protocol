/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../lib/Entitlements.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Generic Hook Vault -- a vault designed to contain a single asset to be used as escrow.
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Vault holds an asset on behalf of the owner. The owner is able to post this
/// asset as collateral to other protocols by signing a messsage, called an "entitlement", that gives
/// a specific account the ability to change the owner. While the asset is held within the vault,
/// any account set as the beneficial owner is able to make external contract calls to benefit from
/// the utility of the asset. Specifically, that means this structure should not be used in order to
/// hold assets in escrow away from owner to benefit an owner for a short period of time.
///
/// The vault can work with multiple assets via the assetId, where the asset or set of assets covered by
/// each segment is granted an individual id.
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
    uint256 assetId,
    address entitledAccount,
    uint256 expiry,
    address beneficialOwner
  );

  /// @notice emitted when an entitlment is cleared from an asset
  event EntitlementCleared(uint256 assetId, address beneficialOwner);

  /// @notice emitted when the beneficial owner of an asset changes
  /// @dev it is not required that this event is emitted when an entitlement is
  /// imposed that also modifies the beneficial owner.
  event BeneficialOwnerSet(
    uint256 assetId,
    address beneficialOwner,
    address setBy
  );

  /// @notice emitted when an asset is added into the vault
  event AssetReceived(
    address owner,
    address sender,
    address contractAddress,
    uint256 assetId
  );

  /// @notice emitted when an asset is withdrawn from the vault
  event AssetWithdrawn(uint256 assetId, address to, address beneficialOwner);

  /// @notice Withdrawal an unencumbered asset from this vault
  /// @param assetId the asset to remove from the vault
  function withdrawalAsset(uint256 assetId) external;

  /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
  /// @param assetId the id of the subject asset to impose the entitlement
  /// @param newBeneficialOwner the account of the person who is able to withdrawl when there are no entitlements.
  function setBeneficialOwner(uint256 assetId, address newBeneficialOwner)
    external;

  /// @notice Add an entitlement claim to the asset held within the contract
  /// @param entitlement The entitlement to impose onto the contract
  /// @param signature an EIP-712 signauture of the entitlement struct signed by the beneficial owner
  function imposeEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) external;

  /// @notice Allows the beneficial owner to grant an entitlement to an asset within the contract
  /// @dev this function call is signed by the sender, so we know the entitlement is authentic
  /// @param entitlement The entitlement to impose onto the contract
  function grantEntitlement(Entitlements.Entitlement calldata entitlement)
    external;

  /// @notice Allowes the entitled address to release their claim on the asset
  /// @param assetId the id of the asset to clear
  function clearEntitlement(uint256 assetId) external;

  /// @notice Removes the active entitlement from a vault and returns the asset to the beneficial owner
  /// @param reciever the intended reciever of the asset
  /// @param assetId the Id of the asset to clear
  function clearEntitlementAndDistribute(uint256 assetId, address reciever)
    external;

  /// @notice looks up the current beneficial owner of the underlying asset
  function getBeneficialOwner(uint256 assetId) external view returns (address);

  /// @notice checks if the asset is currently stored in the vault
  function getHoldsAsset(uint256 assetId) external view returns (bool);

  /// @notice the contract address of the vaulted asset
  function assetAddress(uint256 assetId) external view returns (address);

  /// @notice looks up the current operator of an entitlemnt on an asset
  /// @param assetId the id of the underlying asset
  function getCurrentEntitlementOperator(uint256 assetId)
    external
    view
    returns (bool isActive, address operator);

  /// @notice Looks up the expiration timestamp of the current entitlement
  /// @dev returns the 0 if no entitlement is set
  /// @return expiry the block timestamp after which the entitlement expires
  function entitlementExpiration(uint256 assetId)
    external
    view
    returns (uint256 expiry);
}
