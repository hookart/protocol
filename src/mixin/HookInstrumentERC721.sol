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

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "../interfaces/IHookERC721Vault.sol";

import "../lib/HookStrings.sol";
import "../lib/TokenURI.sol";

/// @dev This contract implements some ERC721 / for hook instruments.
abstract contract HookInstrumentERC721 is ERC721Burnable {
  using Counters for Counters.Counter;
  mapping(uint256 => Counters.Counter) private _transfers;
  bytes4 private constant ERC_721 = bytes4(keccak256("ERC721"));

  /// @dev the contact address for a marketplace to pre-approve
  address public _preApprovedMarketplace = address(0);

  /// @dev hook called after the ERC721 is transferred,
  /// which allows us to increment the counters.
  function _afterTokenTransfer(
    address, // from
    address, // to
    uint256 tokenId
  ) override internal {
    // increment the counter for the token
    _transfers[tokenId].increment();
  }

  ///
  /// @dev See {IERC721-isApprovedForAll}.
  /// this extension ensures that any operator contract located
  /// at {_approvedMarketpace} is considered approved internally
  /// in the ERC721 contract
  ///
  function isApprovedForAll(address owner, address operator)
    public
    view
    virtual
    override
    returns (bool)
  {
    return
      operator == _preApprovedMarketplace ||
      super.isApprovedForAll(owner, operator);
  }

  constructor(string memory instrumentType)
    ERC721(makeInstrumentName(instrumentType), "INST")
  {}

  function makeInstrumentName(string memory z)
    internal
    pure
    returns (string memory)
  {
    return string(abi.encodePacked("Hook ", z, " instrument"));
  }

  /// @notice the number of times the token has been transferred
  /// @dev this count can be used by overbooks to invalidate orders after a
  /// token has been transferred, preventing stale order execution by
  /// malicious parties
  function getTransferCount(uint256 optionId) external view returns (uint256) {
    return _transfers[optionId].current();
  }

  /// @notice getter for the address holding the underlying asset
  function getVaultAddress(uint256 optionId)
    public
    view
    virtual
    returns (address);

  /// @notice getter for the assetId of the underlying asset within a vault
  function getAssetId(uint256 optionId) public view virtual returns (uint32);

  /// @notice getter for the option strike price
  function getStrikePrice(uint256 optionId)
    external
    view
    virtual
    returns (uint256);

  /// @notice getter for the options expiration. After this time the
  /// option is invalid
  function getExpiration(uint256 optionId)
    external
    view
    virtual
    returns (uint256);

  /// @dev this is the OpenSea compatible collection - level metadata URI.
  function contractUri(uint256 optionId) external view returns (string memory) {
    return
      string(
        abi.encodePacked(
          "token.hook.xyz/option-contract/",
          HookStrings.toAsciiString(address(this)),
          "/",
          HookStrings.toString(optionId)
        )
      );
  }

  ///
  /// @dev See {IERC721-tokenURI}.
  ///
  function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
  {
    bytes4 class = _underlyingClass(tokenId);
    if (class == ERC_721) {
      IHookERC721Vault vault = IHookERC721Vault(getVaultAddress(tokenId));
      uint32 assetId = getAssetId(tokenId);
      address underlyingAddress = vault.assetAddress(assetId);
      uint256 underlyingTokenId = vault.assetTokenId(assetId);
      // currently nothing in the contract depends on the actual underlying metadata uri
      // IERC721 underlyingContract = IERC721(underlyingAddress);
      uint256 instrumentStrikePrice = this.getStrikePrice(tokenId);
      uint256 instrumentExpiration = this.getExpiration(tokenId);
      uint256 transfers = _transfers[tokenId].current();
      return
        TokenURI.tokenURIERC721(
          tokenId,
          underlyingAddress,
          underlyingTokenId,
          instrumentExpiration,
          instrumentStrikePrice,
          transfers
        );
    }
    return "Invalid underlying asset";
  }

  /// @dev returns an internal identifier for the underlying type contained within
  /// the vault to determine what the instrument is on
  ///
  /// this class evaluation relies on the interfaceId of the underlying asset
  ///
  function _underlyingClass(uint256 optionId)
    internal
    view
    returns (bytes4)
  {
    if (
      ERC165Checker.supportsInterface(
        getVaultAddress(optionId),
        type(IHookERC721Vault).interfaceId
      )
    ) {
      return ERC_721;
    } else {
      revert("_underlying-class: Unsupported underlying type");
    }
  }
}
