// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IHookProtocol.sol";

import "./mixin/PermissionConstants.sol";

/// @title HookProtocol configuration and access control repository
/// @author Jake Nyquist -- j@hook.xyz
/// @notice This contract contains the addresses of currently deployed Hook protocol
/// contract and contains the centralized Access Control and protocol pausing functions
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
  /// @notice the address of the deployed CoveredCallFactory used by the protocol
  address public override coveredCallContract;
  /// @notice the address of the deployed VaultFactory used by the protocol
  address public override vaultContract;

  /// @notice the standard weth address on this chain
  /// @dev these are values for popular chains:
  /// mainnet: 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
  /// kovan: 0xd0a1e359811322d97991e03f863a0c30c2cf029c
  /// ropsten: 0xc778417e063141139fce010982780140aa0cd5ab
  /// rinkeby: 0xc778417e063141139fce010982780140aa0cd5ab
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

  function throwWhenPaused() public view whenNotPaused {
    // depend on the modifier to throw.
    return;
  }

  function unpause() public {
    require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not an admin");
    _unpause();
  }

  function pause() public {
    require(hasRole(PAUSER_ROLE, msg.sender), "Caller is not an admin");
    _pause();
  }

  /// @notice Allows an admin to set the address of the deployed covered call factory
  /// @dev This address is used by other protocols searching for the registry of
  /// protocols.
  /// @param _coveredCallContract the address of the deployed covered call contract
  function setCoveredCallFactory(address _coveredCallContract)
    public
    adminOnly
  {
    coveredCallContract = _coveredCallContract;
  }

  /// @notice Allows an admin to set the address of the deployed vault factory
  /// @dev allows all protocol components, including the call factory, to look up the
  /// vault factory.
  /// @param _vaultFactoryContract the deployed vault factory
  function setVaultFactory(address _vaultFactoryContract) public adminOnly {
    vaultContract = _vaultFactoryContract;
  }
}
