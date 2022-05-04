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
///
/// @dev Generally, EOAs should not be specified as the entitled account in an Entitlement because
/// users will be unable to verify the behavior of those accounts as they are non-deterministic.
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
  /// @dev withdrawals can only be performed by the beneficial owner if there are no entitlements
  function withdrawalAsset() external;

  /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
  /// @dev setBeneficialOwner can only be called by the entitlementContract if there is an activeEntitlement.
  /// @param newBeneficialOwner the account of the person who is able to withdrawl when there are no entitlements.
  function setBeneficialOwner(address newBeneficialOwner) external;

  /// @notice Add an entitlement claim to the asset held within the contract
  /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the
  /// entitlement
  /// @param entitlement The entitlement to impose onto the contract
  /// @param signature an EIP-712 signauture of the entitlement struct signed by the beneficial owner
  function imposeEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) external;

  /// @notice Allowes the entitled address to release their claim on the asset
  /// @dev This can only be called if an entitlement currently exists, otherwise it would be a no-op
  function clearEntitlement() external;

  /// @notice Removes the active entitlement from a vault and returns the asset to the beneficial owner
  /// @dev The entitlement must be exist, and must be called by the {operator}. The operator can specify a
  /// intended reciever, which should match the beneficialOwner. The function will throw if
  /// the reciever and owner do not match.
  /// @param reciever the intended reciever of the asset
  function clearEntitlementAndDistribute(address reciever) external;

  /// @dev Allows a beneficial owner to send an arbitrary call from this wallet as long as the underlying NFT
  /// is still owned by us after the transaction. The ether value sent is forwarded. Return value is suppressed.
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
