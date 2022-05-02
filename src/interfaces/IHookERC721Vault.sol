/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../lib/Entitlements.sol";

interface IHookERC721Vault is IERC721Receiver {
  // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations
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

  function withdrawalAsset() external;

  function setBeneficialOwner(address _newBeneficialOwner) external;

  function imposeEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) external;

  function clearEntitlement() external;

  function clearEntitlementAndDistribute(address reciever) external;

  function execTransaction(address to, bytes memory data)
    external
    payable
    returns (bool success);

  function getBeneficialOwner() external view returns (address);

  function getHoldsAsset() external view returns (bool);
}
