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

import "./interfaces/IHookCoveredCallFactory.sol";
import "./interfaces/IHookProtocol.sol";

import "./interfaces/IInitializeableBeacon.sol";
import "./HookBeaconProxy.sol";

import "./mixin/PermissionConstants.sol";

import "@openzeppelin/contracts/utils/Create2.sol";

/// @title Hook Covered Call Factory
/// @author Jake Nyquist-j@hook.xyz
/// @dev See {IHookCoveredCallFactory}.
/// @dev The factory looks up certain roles by calling the {IHookProtocol} to verify
//  that the caller is allowed to take certain actions
contract HookCoveredCallFactory is
  PermissionConstants,
  IHookCoveredCallFactory
{
  /// @notice Registry of all of the active markets projects with supported call instruments
  mapping(address => address) public override getCallInstrument;

  /// @notice address of the beacon that contains the address of the current {IHookCoveredCall} implementation
  address private immutable _beacon;

  /// @notice the address of the protocol, which contains the rule
  IHookProtocol private immutable _protocol;

  /// @notice the address of an account that should automatically be approved to transfer the ERC-721 tokens
  /// created by the {IHookCoveredCall} to represent instruments. This value is not used by the factory directly,
  /// as this functionality is implemented by the {IHookCoveredCall}
  address private immutable _preApprovedMarketplace;

  /// @param hookProtocolAddress the address of the deployed {IHookProtocol} contract on this chain
  /// @param beaconAddress the address of the deployed beacon pointing to the current covered call implementation
  /// @param preApprovedMarketplace the address of an account approved to transfer instrument NFTs without owner approval
  constructor(
    address hookProtocolAddress,
    address beaconAddress,
    address preApprovedMarketplace
  ) {
    require(
      Address.isContract(hookProtocolAddress),
      "hook protocol must be a contract"
    );
    require(
      Address.isContract(beaconAddress),
      "beacon address must be a contract"
    );
    require(
      Address.isContract(preApprovedMarketplace),
      "pre-approved marketplace must be a contract"
    );
    _beacon = beaconAddress;
    _protocol = IHookProtocol(hookProtocolAddress);
    _preApprovedMarketplace = preApprovedMarketplace;
  }

  /// @dev See {IHookCoveredCallFactory-makeCallInstrument}.
  /// @dev Only holders of the ALLOWLISTER_ROLE on the {IHookProtocol} can create these addresses.
  function makeCallInstrument(address assetAddress) external returns (address) {
    require(
      getCallInstrument[assetAddress] == address(0),
      "makeCallInstrument-a call instrument already exists"
    );
    // make sure new instruments created by admins or the role
    // has been burned
    require(
      _protocol.hasRole(ALLOWLISTER_ROLE, msg.sender) ||
        _protocol.hasRole(ALLOWLISTER_ROLE, address(0)),
      "makeCallInstrument-Only admins can make instruments"
    );

    IInitializeableBeacon bp = IInitializeableBeacon(
      Create2.deploy(
        0,
        _callInstrumentSalt(assetAddress),
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
        _preApprovedMarketplace
      )
    );

    // Persist the call instrument onto the hook protocol
    getCallInstrument[assetAddress] = address(bp);

    emit CoveredCallInstrumentCreated(assetAddress, address(bp));

    return address(bp);
  }

  /// @dev generate a consistent create2 salt to be used when deploying a
  /// call instrument
  /// @param underlyingAddress the account for the call option salt
  function _callInstrumentSalt(address underlyingAddress)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode(underlyingAddress));
  }
}
