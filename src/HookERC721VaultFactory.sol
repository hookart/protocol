// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./HookERC721Vault.sol";
import "./interfaces/IHookERC721VaultFactory.sol";

/// @title HookERC721Factory -- factory for instances of the hook vault
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Factory creates a specific vault for ERC721s.
/// @dev The factory itself is non-upgradeable; however, each vault is upgradeable (i.e. all vaults)
/// created by this factory can be upgraded at one time via the beacon pattern.
contract HookERC721VaultFactory is IHookERC721VaultFactory {
  /// @notice Registry of all of the active vaults within the protocol, allowing users to find vaults by
  /// project address and tokenId;
  /// @dev From this view, we do not know if a vault is empty or full
  mapping(address => mapping(uint256 => address)) public override getVault;

  address private _hookProtocol;
  address private _beacon;

  constructor(address hookProtocolAddress, address beaconAddress) {
    _hookProtocol = hookProtocolAddress;
    _beacon = beaconAddress;
  }

  function makeVault(address nftAddress, uint256 tokenId)
    external
    returns (address vault)
  {
    require(
      getVault[nftAddress][tokenId] == address(0),
      "makeVault -- a vault cannot already exist"
    );

    // use the salt here to attempt to pre-compute the address where the vault will live.
    // we don't leverage this predictability for now.
    getVault[nftAddress][tokenId] = address(
      new HookERC721Vault{salt: keccak256(abi.encode(nftAddress, tokenId))}(
        _beacon,
        nftAddress,
        tokenId,
        _hookProtocol
      )
    );
    
    return getVault[nftAddress][tokenId];
  }
}
