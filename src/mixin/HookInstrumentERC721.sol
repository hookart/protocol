pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "../interfaces/IHookERC721Vault.sol";

import "../lib/HookStrings.sol";

/// @dev This contract implements some ERC721 / for hook insturments.
abstract contract HookInsturmentERC721 is ERC721Burnable {
  using Counters for Counters.Counter;
  mapping(uint256 => Counters.Counter) private _transfers;
  bytes4 private constant ERC_721 = bytes4(keccak256("ERC712"));

  /// @dev hook called after the ERC721 is transferred,
  /// which allows us to increment the counters.
  function _afterTokenTransfer(
    address, // from
    address, // to
    uint256 tokenId
  ) internal override {
    // increment the counter for the token
    _transfers[tokenId].increment();
  }

  /// @notice the number of times the token has been transferred
  /// @dev this count can be used by orderbooks to invaildate orders after a
  /// token has been transfered, preveting stale order execution by
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
  function getAssetId(uint256 optionId) public view virtual returns (uint256);

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
      uint256 assetId = getAssetId(tokenId);
      address underlyingAddress = vault.assetAddress(assetId);
      uint256 underlyingTokenId = vault.assetTokenId(assetId);
      // currently nothing in the contract depends on the actual underlying metadata uri
      // IERC721 underlyingContract = IERC721(underlyingAddress);
      uint256 insturmentStrikePrice = this.getStrikePrice(tokenId);
      uint256 insturmentExpiration = this.getExpiration(tokenId);
      return
        _tokenURIERC721(
          tokenId,
          underlyingAddress,
          underlyingTokenId,
          insturmentExpiration,
          insturmentStrikePrice
        );
    }
    return "Invalid underlying asset";
  }

  /// @dev returns an internal identifier for the underlying type contained within
  /// the vault to determine what the instrument is on
  ///
  /// this class evalutation relies on the interfaceId of the underlying asset
  ///
  function _underlyingClass(uint256 optionId)
    internal
    view
    returns (bytes4 class)
  {
    if (
      ERC165Checker.supportsInterface(
        getVaultAddress(optionId),
        type(IHookERC721Vault).interfaceId
      )
    ) {
      class = ERC_721;
    } else {
      revert("_underlying-class: Unsupported underlying type");
    }
  }

  function _generateMetadataERC721(
    uint256 tokenId,
    address underlyingTokenAddress,
    uint256 underlyingTokenId,
    uint256 instrumentStrikePrice,
    uint256 insturmentExpiration
  ) internal view returns (string memory) {
    return
      string(
        abi.encodePacked(
          ', "expiration": ',
          HookStrings.toString(insturmentExpiration),
          ', "underlying_address": ',
          HookStrings.toAsciiString(underlyingTokenAddress),
          ', "underlying_tokenId": ',
          HookStrings.toString(underlyingTokenId),
          ', "strike_price": ',
          HookStrings.toString(instrumentStrikePrice),
          ', "transfer_index": ',
          HookStrings.toString(_transfers[tokenId].current())
        )
      );
  }

  /// @dev this is a basic tokenURI based on the loot contract for an ERC721
  /// (ripped off from LOOT PROJECT)
  function _tokenURIERC721(
    uint256 insturmentId,
    address underlyingAddress,
    uint256 underlyingTokenId,
    uint256 insturmentExpiration,
    uint256 insturmentStrike
  ) public view returns (string memory) {
    string[5] memory parts;
    parts[
      0
    ] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>'
    '.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill='
    '"black" /><text x="10" y="20" class="base">';

    parts[1] = HookStrings.toAsciiString(underlyingAddress);

    parts[2] = '</text><text x="10" y="40" class="base">';

    parts[3] = HookStrings.toString(underlyingTokenId);

    parts[4] = "</text></svg>";

    string memory output = string(
      abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4])
    );

    string memory json = Base64.encode(
      bytes(
        string(
          abi.encodePacked(
            '{"name": "Option Id',
            HookStrings.toString(insturmentId),
            '", "description": "Hook is the on-chain covered call option protocol", "image": '
            '"data:image/svg+xml;base64,',
            Base64.encode(bytes(output)),
            _generateMetadataERC721(
              insturmentId,
              underlyingAddress,
              underlyingTokenId,
              insturmentStrike,
              insturmentExpiration
            ),
            '"}'
          )
        )
      )
    );
    output = string(abi.encodePacked("data:application/json;base64,", json));

    return output;
  }
}
