pragma solidity ^0.8.10;

import "./HookUpgradeableBeacon.sol";

/// @title HookCoveredCallBeacon
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The beacon broadcasts the address which contains the existing implementation of the CoveredCall contract
/// @dev Permissions for who can upgrade are contained within the protocol contract.
contract HookCoveredCallBeacon is HookUpgradeableBeacon {
    constructor(
        address implementation,
        address hookProtocol,
        bytes32 upgraderRole
    ) HookUpgradeableBeacon(implementation, hookProtocol, upgraderRole) {}
}
