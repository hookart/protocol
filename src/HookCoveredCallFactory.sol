//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./HookCoveredCall.sol";
import "./interfaces/IHookCoveredCallFactory.sol";
import "./interfaces/IHookProtocol.sol";

import "./mixin/PermissionConstants.sol";

/// @dev See {IHookCoveredCallFactory}.
/// @dev Operating the factory requires specific permissions within the protocol.
contract HookCoveredCallFactory is
  PermissionConstants,
  IHookCoveredCallFactory
{
  /// @notice Registry of all of the active markets projects with supported call instruments
  mapping(address => address) public override getCallInstrument;

  address private _beacon;
  IHookProtocol private _protocol;

  /// @dev there is only one instance of this contract, so the constructor is called exactly once.
  /// @param hookProtocolAddress the address of the deployed HookProtocol contract on this network
  /// @param beaconAddress the address of the deployed beacon pointing to the current covered call implementation
  constructor(address hookProtocolAddress, address beaconAddress) {
    _beacon = beaconAddress;
    _protocol = IHookProtocol(hookProtocolAddress);
  }

  /// @dev See {IHookCoveredCallFactory-makeCallInstrument}.
  /// @dev Only the admin can create these addresses.
  function makeCallInstrument(address assetAddress)
    external
    returns (address calls)
  {
    require(
      getCallInstrument[assetAddress] == address(0),
      "makeCallInstrument -- a call instrument already exists"
    );
    // make sure new instruments created by admins.
    require(
      _protocol.hasRole(ALLOWLISTER_ROLE, msg.sender),
      "makeCallInstrument -- Only admins can make instruments"
    );

    getCallInstrument[assetAddress] = address(
      new HookCoveredCall{salt: keccak256(abi.encode(assetAddress))}(
        _beacon,
        assetAddress,
        address(_protocol),
        _protocol.vaultContract()
      )
    );

    return getCallInstrument[assetAddress];
  }
}
