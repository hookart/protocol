// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IHookProtocol.sol";

import "./mixin/PermissionConstants.sol";

contract HookProtocol is
  PermissionConstants,
  AccessControl,
  IHookProtocol,
  Pausable
{
  address public override coveredCallContract;
  address public override vaultContract;
  address public override getWETHAddress;

  constructor(address admin, address weth) {
    _setupRole(ALLOWLISTER_ROLE, admin);
    _setupRole(PAUSER_ROLE, admin);
    _setupRole(VAULT_UPGRADER, admin);
    // create a distinct admin role
    _setupRole(ADMIN_ROLE, admin);

    // allow the admin to add and remove other roles
    _setRoleAdmin(ALLOWLISTER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(VAULT_UPGRADER, ADMIN_ROLE);

    // set weth
    getWETHAddress = weth;
  }

  modifier adminOnly() {
    require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
    _;
  }

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
