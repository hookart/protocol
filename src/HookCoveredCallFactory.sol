//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./interfaces/IHookCoveredCallFactory.sol";
import "./interfaces/IHookProtocol.sol";

import "./interfaces/IInitializeableBeacon.sol";
import "./HookBeaconProxy.sol";

import "./mixin/PermissionConstants.sol";

import "@openzeppelin/contracts/utils/Create2.sol";

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
  address private _preapprovedMarketplace;

  /// @dev there is only one instance of this contract, so the constructor is called exactly once.
  /// @param hookProtocolAddress the address of the deployed HookProtocol contract on this network
  /// @param beaconAddress the address of the deployed beacon pointing to the current covered call implementation
  /// @param preapprovedMarketplace the address of a marketplace to automatically approve to transfer insturments
  constructor(
    address hookProtocolAddress,
    address beaconAddress,
    address preapprovedMarketplace
  ) {
    _beacon = beaconAddress;
    _protocol = IHookProtocol(hookProtocolAddress);
    _preapprovedMarketplace = preapprovedMarketplace;
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
    // make sure new instruments created by admins or the role
    // has been burned
    require(
      _protocol.hasRole(ALLOWLISTER_ROLE, msg.sender) ||
        _protocol.hasRole(ALLOWLISTER_ROLE, address(0)),
      "makeCallInstrument -- Only admins can make instruments"
    );

    IInitializeableBeacon bp = IInitializeableBeacon(
      Create2.deploy(
        0,
        _callInsturmentSalt(assetAddress),
        type(HookBeaconProxy).creationCode
      )
    );

    bp.initializeBeacon(
      _beacon,
      /// This is the ABI encoded initializer on the IHookERC721Vault.sol
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        _protocol,
        assetAddress,
        _protocol.vaultContract(),
        _preapprovedMarketplace
      )
    );

    getCallInstrument[assetAddress] = address(bp);

    emit CoveredCallInsturmentCreated(
      assetAddress,
      getCallInstrument[assetAddress]
    );

    return getCallInstrument[assetAddress];
  }

  function _callInsturmentSalt(address underlyingAddress)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode(underlyingAddress));
  }
}
