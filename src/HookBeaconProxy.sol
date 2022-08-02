// SPDX-License-Identifier: MIT
// Modified version of : OpenZeppelin Contracts v4.4.1 (proxy/beacon/BeaconProxy.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

/// @title HookBeaconProxy a proxy contract that points to an implementation provided by a Beacon
/// @dev This contract implements a proxy that gets the implementation address for each call from a {UpgradeableBeacon}.
///
/// The beacon address is stored in storage slot `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
/// conflict with the storage layout of the implementation behind the proxy.
///
/// This is an extension of the OpenZeppelin beacon proxy, however differs in that it is initializeable, which means
/// it is usable with Create2.
contract HookBeaconProxy is Proxy, ERC1967Upgrade {
  /// @dev  The constructor is empty in this case because the proxy is initializeable
  constructor() {}

  bytes32 constant _INITIALIZED_SLOT =
    bytes32(uint256(keccak256("initializeable.beacon.version")) - 1);
  bytes32 constant _INITIALIZING_SLOT =
    bytes32(uint256(keccak256("initializeable.beacon.initializing")) - 1);

  ///
  /// @dev Triggered when the contract has been initialized or reinitialized.
  ///
  event Initialized(uint8 version);

  /// @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
  /// `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
  modifier initializer() {
    bool isTopLevelCall = _setInitializedVersion(1);
    if (isTopLevelCall) {
      StorageSlot.getBooleanSlot(_INITIALIZING_SLOT).value = true;
    }
    _;
    if (isTopLevelCall) {
      StorageSlot.getBooleanSlot(_INITIALIZING_SLOT).value = false;
      emit Initialized(1);
    }
  }

  function _setInitializedVersion(uint8 version) private returns (bool) {
    // If the contract is initializing we ignore whether _initialized is set in order to support multiple
    // inheritance patterns, but we only do this in the context of a constructor, and for the lowest level
    // of initializers, because in other contexts the contract may have been reentered.
    if (StorageSlot.getBooleanSlot(_INITIALIZING_SLOT).value) {
      require(
        version == 1 && !Address.isContract(address(this)),
        "contract is already initialized"
      );
      return false;
    } else {
      require(
        StorageSlot.getUint256Slot(_INITIALIZED_SLOT).value < version,
        "contract is already initialized"
      );
      StorageSlot.getUint256Slot(_INITIALIZED_SLOT).value = version;
      return true;
    }
  }

  /// @dev Initializes the proxy with `beacon`.
  ///
  /// If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
  /// will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
  /// constructor.
  ///
  /// Requirements:
  ///
  ///- `beacon` must be a contract with the interface {IBeacon}.
  ///
  function initializeBeacon(address beacon, bytes memory data)
    public
    initializer
  {
    assert(
      _BEACON_SLOT == bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    );
    _upgradeBeaconToAndCall(beacon, data, false);
  }

  ///
  /// @dev Returns the current implementation address of the associated beacon.
  ///
  function _implementation() internal view virtual override returns (address) {
    return IBeacon(_getBeacon()).implementation();
  }
}
