/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../lib/Entitlements.sol";

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
interface IHookVault {
  event EntitlementImposed(
    uint256 assetId,
    address entitledAccout,
    uint256 expiry,
    address beneficialOwner
  );

  event EntitlementCleared(uint256 assetId, address beneficialOwner);

  event BeneficialOwnerSet(
    uint256 assetId,
    address beneficialOwner,
    address setBy
  );

  event AssetReceived(
    address owner,
    address sender,
    address contractAddress,
    uint256 tokenId,
    uint256 assetId
  );

  /// @notice Withdrawal an unencumbered asset from this vault
  function withdrawalAsset(uint256 assetId) external;

  /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
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
  function grantEntitlement(Entitlements.Entitlement memory entitlement)
    external;

  /// @notice Allowes the entitled address to release their claim on the asset
  function clearEntitlement() external;

  /// @notice Removes the active entitlement from a vault and returns the asset to the beneficial owner
  /// @param reciever the intended reciever of the asset
  function clearEntitlementAndDistribute(address reciever) external;

  /// @param to Destination address of transaction.
  /// @param data Data payload of transaction.
  /// @return success if the call was successful.
  function execTransaction(address to, bytes memory data)
    external
    payable
    returns (bool success);

  /// @notice looks up the current beneficial owner of the underlying asset
  function getBeneficialOwner(uint256 assetId) external view returns (address);

  /// @notice checks if the asset is currently stored in the vault
  function getHoldsAsset(uint256 assetId) external view returns (bool);

  function assetAddress(uint256 assetId) external view returns (address);

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
