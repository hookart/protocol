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

import "./interfaces/IHookERC721VaultFactory.sol";
import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IInitializeableBeacon.sol";

import "./mixin/PermissionConstants.sol";

import "./lib/BeaconSalts.sol";

/// @title Hook Vault Factory
/// @author Jake Nyquist-j@hook.xyz
/// @dev See {IHookERC721VaultFactory}.
/// @dev The factory itself is non-upgradeable; however, each vault is upgradeable (i.e. all vaults)
/// created by this factory can be upgraded at one time via the beacon pattern.
contract HookERC721VaultFactory is
  IHookERC721VaultFactory,
  PermissionConstants
{
  /// @notice Registry of all of the active vaults within the protocol, allowing users to find vaults by
  /// project address and tokenId;
  /// @dev From this view, we do not know if a vault is empty or full
  mapping(address => mapping(uint256 => IHookERC721Vault))
    public
    override getVault;

  /// @notice Registry of all of the active multi-vaults within the protocol
  mapping(address => IHookERC721Vault) public override getMultiVault;

  address private immutable _hookProtocol;
  address private immutable _beacon;
  address private immutable _multiBeacon;

  constructor(
    address hookProtocolAddress,
    address beaconAddress,
    address multiBeaconAddress
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
      Address.isContract(multiBeaconAddress),
      "multi beacon address must be a contract"
    );
    _hookProtocol = hookProtocolAddress;
    _beacon = beaconAddress;
    _multiBeacon = multiBeaconAddress;
  }

  /// @notice See {IHookERC721VaultFactory-makeMultiVault}.
  function makeMultiVault(address nftAddress)
    external
    returns (IHookERC721Vault)
  {
    require(
      IHookProtocol(_hookProtocol).hasRole(ALLOWLISTER_ROLE, msg.sender) ||
        IHookProtocol(_hookProtocol).hasRole(ALLOWLISTER_ROLE, address(0)),
      "makeMultiVault-Only accounts with the ALLOWLISTER role can make new multiVaults"
    );

    require(
      getMultiVault[nftAddress] == IHookERC721Vault(address(0)),
      "makeMultiVault-vault cannot already exist"
    );

    IInitializeableBeacon bp = IInitializeableBeacon(
      Create2.deploy(
        0,
        BeaconSalts.multiVaultSalt(nftAddress),
        type(HookBeaconProxy).creationCode
      )
    );

    bp.initializeBeacon(
      _multiBeacon,
      /// This is the ABI encoded initializer on the IHookERC721Vault.sol
      abi.encodeWithSignature(
        "initialize(address,address)",
        nftAddress,
        _hookProtocol
      )
    );

    IHookERC721Vault vault = IHookERC721Vault(address(bp));
    getMultiVault[nftAddress] = vault;
    emit ERC721MultiVaultCreated(nftAddress, address(bp));

    return vault;
  }

  /// @notice See {IHookERC721VaultFactory-makeSoloVault}.
  function makeSoloVault(address nftAddress, uint256 tokenId)
    public
    override
    returns (IHookERC721Vault)
  {
    require(
      getVault[nftAddress][tokenId] == IHookERC721Vault(address(0)),
      "makeVault-a vault cannot already exist"
    );

    IInitializeableBeacon bp = IInitializeableBeacon(
      Create2.deploy(
        0,
        BeaconSalts.soloVaultSalt(nftAddress, tokenId),
        type(HookBeaconProxy).creationCode
      )
    );

    bp.initializeBeacon(
      _beacon,
      /// This is the ABI encoded initializer on the IHookERC721MultiVault.sol
      abi.encodeWithSignature(
        "initialize(address,uint256,address)",
        nftAddress,
        tokenId,
        _hookProtocol
      )
    );
    IHookERC721Vault vault = IHookERC721Vault(address(bp));
    getVault[nftAddress][tokenId] = vault;

    emit ERC721VaultCreated(nftAddress, tokenId, address(vault));

    return vault;
  }

  /// @notice See {IHookERC721VaultFactory-findOrCreateVault}.
  function findOrCreateVault(address nftAddress, uint256 tokenId)
    external
    returns (IHookERC721Vault)
  {
    if (getMultiVault[nftAddress] != IHookERC721Vault(address(0))) {
      return getMultiVault[nftAddress];
    }

    if (getVault[nftAddress][tokenId] != IHookERC721Vault(address(0))) {
      return getVault[nftAddress][tokenId];
    }

    return makeSoloVault(nftAddress, tokenId);
  }
}
