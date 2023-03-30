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

import "@openzeppelin/contracts/utils/Create2.sol";

import "./HookBeaconProxy.sol";

import "./interfaces/IHookERC20VaultFactory.sol";
import "./interfaces/IHookERC20Vault.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IInitializeableBeacon.sol";

import "./mixin/PermissionConstants.sol";

import "./lib/BeaconSalts.sol";

/// @title Hook Vault Factory
/// @author Jake Nyquist-j@hook.xyz
/// @dev See {IHookERC20VaultFactory}.
/// @dev The factory itself is non-upgradeable; however, each vault is upgradeable (i.e. all vaults)
/// created by this factory can be upgraded at one time via the beacon pattern.
contract HookER20VaultFactory is IHookERC20VaultFactory, PermissionConstants {
    /// @notice Registry of all of the active multi-vaults within the protocol
    mapping(address => IHookERC20Vault) public override getVault;

    address private immutable _hookProtocol;
    address private immutable _beacon;

    constructor(address hookProtocolAddress, address beaconAddress) {
        require(Address.isContract(hookProtocolAddress), "hook protocol must be a contract");
        require(Address.isContract(beaconAddress), "beacon address must be a contract");
        _hookProtocol = hookProtocolAddress;
        _beacon = beaconAddress;
    }

    /// @notice See {IHookERC29VaultFactory-makeVault}.
    function makeVault(address tokenAddress) public returns (IHookERC20Vault) {
        require(
            IHookProtocol(_hookProtocol).hasRole(ALLOWLISTER_ROLE, msg.sender)
                || IHookProtocol(_hookProtocol).hasRole(ALLOWLISTER_ROLE, address(0)),
            "makeVault-Only accounts with the ALLOWLISTER role can make new vaults"
        );

        require(getVault[tokenAddress] == IHookERC20Vault(address(0)), "makeVault-vault cannot already exist");

        IInitializeableBeacon bp = IInitializeableBeacon(
            Create2.deploy(0, BeaconSalts.erc20VaultSalt(tokenAddress), type(HookBeaconProxy).creationCode)
        );

        bp.initializeBeacon(
            _beacon,
            /// This is the ABI encoded initializer on the IHookERC20Vault.sol
            abi.encodeWithSignature("initialize(address,address)", tokenAddress, _hookProtocol)
        );

        IHookERC20Vault vault = IHookERC20Vault(address(bp));
        getVault[tokenAddress] = vault;
        emit ERC20VaultCreated(tokenAddress, address(bp));

        return vault;
    }

    /// @notice See {IHookERC20VaultFactory-findOrCreateVault}.
    function findOrCreateVault(address tokenAddress) external returns (IHookERC20Vault) {
        if (getVault[tokenAddress] != IHookERC20Vault(address(0))) {
            return getVault[tokenAddress];
        }

        return makeVault(tokenAddress);
    }
}
