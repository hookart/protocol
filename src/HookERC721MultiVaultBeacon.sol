pragma solidity ^0.8.10;

import "./HookUpgradeableBeacon.sol";

/// @title HookERC721MultiVaultBeacon -- beacon holding pointer to current ERC721MultiVault implementation
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The beacon broadcasts the address which contains the existing implementation of the ERC721MultiVault
/// @dev Permissions for who can upgrade are contained within the protocol contract.
contract HookERC721MultiVaultBeacon is HookUpgradeableBeacon {
  constructor(
    address implementation,
    address hookProtocol,
    bytes32 upgraderRole
  ) HookUpgradeableBeacon(implementation, hookProtocol, upgraderRole) {}
}
