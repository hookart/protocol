// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (proxy/beacon/BeaconProxy.sol) (MODIFIED)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

/**
 * @dev This contract implements a proxy that gets the implementation address for each call from a {UpgradeableBeacon}.
 *
 * The beacon address is stored in storage slot `uint256(keccak256('eip1967.proxy.beacon')) - 1`, so that it doesn't
 * conflict with the storage layout of the implementation behind the proxy.
 *
 * This is an extension of the OpenZeppelin beacon proxy, however differs in that it is initializeable, which means
 * it is usable with Create2.
 */
contract HookBeaconProxy is Proxy, ERC1967Upgrade {
  /// @dev  The constructor is empty in this case because the proxy is initializeable
  constructor() {}

  /**
   * @dev Initializes the proxy with `beacon`.
   *
   * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
   * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
   * constructor.
   *
   * Requirements:
   *
   * - `beacon` must be a contract with the interface {IBeacon}.
   */

  function initializeBeacon(address beacon, bytes memory data) public {
    assert(
      _BEACON_SLOT == bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
    );
    _upgradeBeaconToAndCall(beacon, data, false);
  }

  /**
   * @dev Returns the current implementation address of the associated beacon.
   */
  function _implementation() internal view virtual override returns (address) {
    return IBeacon(_getBeacon()).implementation();
  }
}
