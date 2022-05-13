// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IHookProtocol.sol";

import "./mixin/PermissionConstants.sol";

/// @dev Other contracts in the protocol refer to this one to get configuration and pausing issues.
/// to reduce attack surface area, this contract cannot be upgraded; however, additional roles can be
/// added.
///
/// This contract does not implement any specific timelocks or other safety measures. The roles are granted
/// with the principal of least privildge. As the protocol matures, these additional measures can be layered
/// by granting these roles to other contracts. In the extreme, the upgrade and other roles can be burned,
/// which would effectively make the protocol static and non-upgradeable.
contract HookProtocol is
  PermissionConstants,
  AccessControl,
  IHookProtocol,
  Pausable
{
  address public override coveredCallContract;
  address public override vaultContract;
  address public override getWETHAddress;
  mapping(address => mapping(bytes32 => bool)) collectionConfigs;

  constructor(address admin, address weth) {
    _setupRole(ALLOWLISTER_ROLE, admin);
    _setupRole(PAUSER_ROLE, admin);
    _setupRole(VAULT_UPGRADER, admin);
    _setupRole(CALL_UPGRADER, admin);
    // create a distinct admin role
    _setupRole(ADMIN_ROLE, admin);
    _setupRole(MARKET_CONF, admin);
    _setupRole(COLLECTION_CONF, admin);

    // allow the admin to add and remove other roles
    _setRoleAdmin(ALLOWLISTER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(VAULT_UPGRADER, ADMIN_ROLE);
    _setRoleAdmin(CALL_UPGRADER, ADMIN_ROLE);
    _setRoleAdmin(MARKET_CONF, ADMIN_ROLE);
    _setRoleAdmin(COLLECTION_CONF, ADMIN_ROLE);
    // set weth
    getWETHAddress = weth;
  }

  function setCollectionConfig(
    address collectionAddress,
    bytes32 config,
    bool value
  ) external onlyRole(COLLECTION_CONF) {
    collectionConfigs[collectionAddress][config] = value;
  }

  /// @dev See {IHookProtocol-getCollectionConfig}.
  function getCollectionConfig(address collectionAddress, bytes32 conf)
    external
    view
    returns (bool value)
  {
    return collectionConfigs[collectionAddress][conf];
  }

  modifier adminOnly() {
    require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
    _;
  }

  /// @notice throws an exception when the protocol is paused
  function throwWhenPaused() external view whenNotPaused {
    // depend on the modifier to throw.
    return;
  }

  function unpause() external {
    require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not an admin");
    _unpause();
  }

  function pause() external {
    require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not an admin");
    _pause();
  }

  /// @notice Allows an admin to set the address of the deployed covered call factory
  /// @dev This address is used by other protocols searching for the registry of
  /// protocols.
  /// @param coveredCallFactoryContract the address of the deployed covered call contract
  function setCoveredCallFactory(address coveredCallFactoryContract)
    external
    adminOnly
  {
    coveredCallContract = coveredCallFactoryContract;
  }

  /// @notice Allows an admin to set the address of the deployed vault factory
  /// @dev allows all protocol components, including the call factory, to look up the
  /// vault factory.
  /// @param vaultFactoryContract the deployed vault factory
  function setVaultFactory(address vaultFactoryContract) external adminOnly {
    vaultContract = vaultFactoryContract;
  }
}
