pragma solidity ^0.8.10;

import "./Signatures.sol";

library Entitlements {
  // TODO: Should we add a nonce to this struct? This would allow us to make the
  // tokenIds cancelable.
  uint256 private constant _ENTITLEMENT_TYPEHASH =
    uint256(
      keccak256(
        abi.encodePacked(
          "Entitlement(",
          "address beneficialOwner,",
          "address operator,",
          "address vaultAddress,",
          "uint256 expiry",
          ")"
        )
      )
    );

  /// ---- STRUCTS -----
  struct Entitlement {
    /// @notice the beneficial owner address this entitlement applies to. This address will also be the signer.
    address beneficialOwner;
    /// @notice the operating contract that can change ownership during the entitlement period.
    address operator;
    /// @notice the contract address for the vault that contains the underlying assets
    address vaultAddress;
    /// @notice the assetId of the asset or assets within the vault
    uint256 assetId;
    /// @notice the block timestamp after which the asset is free of the entitlement
    uint256 expiry;
  }

  function getEntitlementStructHash(Entitlement memory entitlement)
    internal
    pure
    returns (bytes32 structHash)
  {
    // TODO: Hash in place to save gas.
    return
      keccak256(
        abi.encode(
          _ENTITLEMENT_TYPEHASH,
          entitlement.beneficialOwner,
          entitlement.operator,
          entitlement.vaultAddress,
          entitlement.expiry
        )
      );
  }
}
