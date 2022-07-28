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

import "./Signatures.sol";

library Entitlements {
  uint256 private constant _ENTITLEMENT_TYPEHASH =
    uint256(
      keccak256(
        abi.encodePacked(
          "Entitlement(",
          "address beneficialOwner,",
          "address operator,",
          "address vaultAddress,",
          "uint32 assetId,",
          "uint32 expiry",
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
    uint32 assetId;
    /// @notice the block timestamp after which the asset is free of the entitlement
    uint32 expiry;
  }

  function getEntitlementStructHash(Entitlement memory entitlement)
    internal
    pure
    returns (bytes32)
  {
    // TODO: Hash in place to save gas.
    return
      keccak256(
        abi.encode(
          _ENTITLEMENT_TYPEHASH,
          entitlement.beneficialOwner,
          entitlement.operator,
          entitlement.vaultAddress,
          entitlement.assetId,
          entitlement.expiry
        )
      );
  }
}
