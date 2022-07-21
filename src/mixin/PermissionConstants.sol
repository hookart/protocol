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

/// @notice roles on the hook protocol that can be read by other contract
/// @dev new roles here should be initialized in the constructor of the protocol
abstract contract PermissionConstants {
  /// ----- ROLES --------

  /// @notice the allowlister is able to enable and disable projects to mint instruments
  bytes32 public constant ALLOWLISTER_ROLE = keccak256("ALLOWLISTER_ROLE");

  /// @notice the pauser is able to start and pause various components of the protocol
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// @notice the vault upgrader role is able to upgrade the implementation for all vaults
  bytes32 public constant VAULT_UPGRADER = keccak256("VAULT_UPGRADER");

  /// @notice the call upgrader role is able to upgrade the implementation of the covered call options
  bytes32 public constant CALL_UPGRADER = keccak256("CALL_UPGRADER");

  /// @notice the market configuration role allows the actor to make changes to how the market operates
  bytes32 public constant MARKET_CONF = keccak256("MARKET_CONF");

  /// @notice the collection configuration role allows the actor to make changes the collection
  /// configs on the protocol contract
  bytes32 public constant COLLECTION_CONF = keccak256("COLLECTION_CONF");
}
