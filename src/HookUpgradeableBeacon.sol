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

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./mixin/PermissionConstants.sol";
import "./interfaces/IHookProtocol.sol";

/// @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
/// implementation contract, which is where they will delegate all function calls.
///
/// An owner is able to change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
/// Ownership is managed centrally on the Hook protocol level, where the owner is the holder of a specific permission.
/// This permission should be used only for the purpose of upgrading the particular contract (i.e., the permissions
/// should not be reused).
///
/// This contract is deliberately simple and only has one non-view
/// method - `upgrade`. Timelocks or other upgrade conditions will be managed by
/// the owner of this contract.
/// This contract is based on the UpgradeableBeaconContract from OZ and DharmaUpgradeBeaconController from Dharma
contract HookUpgradeableBeacon is IBeacon, PermissionConstants {
  using Address for address;
  address private _implementation;
  IHookProtocol private _protocol;
  bytes32 private _role;

  /// @dev Emitted when the implementation returned by the beacon is changed.
  event Upgraded(address indexed implementation);

  /// @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
  /// beacon.
  constructor(
    address implementation_,
    address hookProtocol,
    bytes32 upgraderRole
  ) {
    require(
      Address.isContract(hookProtocol),
      "UpgradeableBeacon: hookProtocol is not a contract"
    );

    require(
      upgraderRole == VAULT_UPGRADER || upgraderRole == CALL_UPGRADER,
      "upgrader role must be vault or call upgrader"
    );
    _setImplementation(implementation_);
    _protocol = IHookProtocol(hookProtocol);
    _role = upgraderRole;
  }

  /// @dev Throws if called by any account other than the owner.
  modifier onlyOwner() {
    require(
      _protocol.hasRole(_role, msg.sender),
      "HookUpgradeableBeacon: caller does not have the required upgrade permissions"
    );
    _;
  }

  /// @dev Returns the current implementation address.
  function implementation() external view virtual override returns (address) {
    return _implementation;
  }

  /// @dev Upgrades the beacon to a new implementation.
  ///
  /// Emits an {Upgraded} event.
  ///
  /// Requirements:
  ///
  /// - msg.sender must be the owner of the contract.
  /// - `newImplementation` must be a contract.
  function upgradeTo(address newImplementation) external virtual onlyOwner {
    _setImplementation(newImplementation);
    emit Upgraded(newImplementation);
  }

  /// @dev Sets the implementation contract address for this beacon
  ///
  /// Requirements:
  ///
  /// - `newImplementation` must be a contract.
  function _setImplementation(address newImplementation) private {
    require(
      Address.isContract(newImplementation),
      "HookUpgradeableBeacon: implementation is not a contract"
    );
    _implementation = newImplementation;
  }
}
