//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/// @notice roles on the hook protocol that can be read by other contract
/// @dev new roles here should be initialized in the constructor of the protocol
abstract contract PermissionConstants {
  /// ----- ROLES --------
  /// @notice The Hook protocol admin can make any changes to the protocol
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  /// @notice the allowlister is able to enable and disable projects to mint instruments
  bytes32 public constant ALLOWLISTER_ROLE = keccak256("ALLOWLISTER_ROLE");

  /// @notice the paueser is able to start and pause various components of the protocol
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// @notice the vault upgrader role is able to upgrade the implementation for all vaults
  bytes32 public constant VAULT_UPGRADER = keccak256("VAULT_UPGRADER");

  /// @notice the call upgrader role is able to upgrade the implementation of the covered call options
  bytes32 public constant CALL_UPGRADER = keccak256("CALL_UPGRADER");
}
