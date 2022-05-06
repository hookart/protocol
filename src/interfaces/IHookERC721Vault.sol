/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../lib/Entitlements.sol";

/// @title ERC721 Vault -- a vault designed to contain a single ERC721 asset to be used as escrow.
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The ERC721Vault holds an asset on behalf of the owner. The owner is able to post this
/// asset as collateral to other protocols by signing a messsage, called an "entitlement", that gives
/// a specific account the ability to change the owner. While the asset is held within the vault,
/// any account set as the beneficial owner is able to make external contract calls to benefit from
/// the utility of the asset. Specifically, that means this structure should not be used in order to
/// hold assets in escrow away from owner to benefit an owner for a short period of time.
///
/// ENTITLEMENTS -
///     (1) only one entitlement can be placed at a time.
///     (2) entitlements must expire, but can also be cleared by the entitled party
///     (3) if an entitlement expires, the current beneficial owner gains immediate sole control over the
///        asset
///     (4) the entitled entity can modify the beneficial owner of the asset, but cannot withdrawal.
///     (5) the beneficial owner cannot modify the beneficial owner while an entitlement is in place
///
///
/// SEND TRANSACTION (FLASH LOAN) -
///     (1) owners are able to forward transactions to this vault to other wallets
///     (2) calls to the ERC-721 address are blocked to prevent approvals from being set on the
///         NFT while in escrow, which could allow for theft
///     (3) At the end of each transaction, the ownerOf the vaulted token must still be the vault
interface IHookERC721Vault is IERC721Receiver {
  event EntitlementImposed(
    address entitledAccout,
    uint256 expiry,
    address beneficialOwner
  );

  event EntitlementCleared(address beneficialOwner);

  event BeneficialOwnerSet(address beneficialOwner, address setBy);

  event AssetWithdrawn(address caller, address assetReceiver);

  event AssetReceived(
    address owner,
    address sender,
    address contractAddress,
    uint256 tokenId
  );

  /// @notice Withdrawl an unencumbered asset from this vault
  function withdrawalAsset() external;

  /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
  /// @param newBeneficialOwner the account of the person who is able to withdrawl when there are no entitlements.
  function setBeneficialOwner(address newBeneficialOwner) external;

  /// @notice Add an entitlement claim to the asset held within the contract
  /// @param entitlement The entitlement to impose onto the contract
  /// @param signature an EIP-712 signauture of the entitlement struct signed by the beneficial owner
  function imposeEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) external;

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
  function getBeneficialOwner() external view returns (address);

  /// @notice checks if the asset is currently stored in the vault
  function getHoldsAsset() external view returns (bool);
}
