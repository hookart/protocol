// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./HookERC721Vault.sol";
import "./HookERC721MultiVault.sol";
import "./interfaces/IHookERC721VaultFactory.sol";
import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IHookProtocol.sol";

import "./mixin/PermissionConstants.sol";

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

  address private _hookProtocol;
  address private _beacon;
  address private _multiBeacon;

  constructor(
    address hookProtocolAddress,
    address beaconAddress,
    address multiBeaconAddress
  ) {
    _hookProtocol = hookProtocolAddress;
    _beacon = beaconAddress;
    _multiBeacon = multiBeaconAddress;
  }

  /// @notice create a new vault that can support multiple ERC-721s within the same
  /// instance
  function makeMultiVault(address nftAddress)
    external
    returns (IHookERC721Vault vault)
  {
    require(
      IHookProtocol(_hookProtocol).hasRole(ALLOWLISTER_ROLE, msg.sender),
      "makeMultiVault -- Only accounts with the ALLOWLISTER role can make new multiVaults"
    );

    require(
      getMultiVault[nftAddress] == IHookERC721Vault(address(0)),
      "makeMultiVault -- vault cannot already exist"
    );

    getMultiVault[nftAddress] = IHookERC721Vault(
      address(
        new HookERC721MultiVault{salt: keccak256(abi.encode(nftAddress))}(
          _beacon,
          nftAddress,
          _hookProtocol
        )
      )
    );

    return getMultiVault[nftAddress];
  }

  /// @notice make a new vault that
  function makeSoloVault(address nftAddress, uint256 tokenId)
    public
    returns (IHookERC721Vault vault)
  {
    require(
      getVault[nftAddress][tokenId] == IHookERC721Vault(address(0)),
      "makeVault -- a vault cannot already exist"
    );
    // use the salt here to attempt to pre-compute the address where the vault will live.
    // we don't leverage this predictability for now.
    getVault[nftAddress][tokenId] = IHookERC721Vault(
      address(
        new HookERC721Vault{salt: keccak256(abi.encode(nftAddress, tokenId))}(
          _beacon,
          nftAddress,
          tokenId,
          _hookProtocol
        )
      )
    );

    emit ERC721VaultCreated(
      nftAddress,
      tokenId,
      address(getVault[nftAddress][tokenId])
    );
    return getVault[nftAddress][tokenId];
  }

  /// @notice creates a vault for a specific tokenId. If there
  /// is a multi-vault in existence which supports that address
  /// the address for that vault is returned as a new one
  /// does not need to be made.
  function findOrCreateVault(address nftAddress, uint256 tokenId)
    external
    returns (IHookERC721Vault vault)
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
