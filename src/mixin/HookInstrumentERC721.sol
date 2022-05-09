pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../lib/HookStrings.sol";

/// @dev This contract implements some ERC721 / for hook insturments.
abstract contract HookInsturmentERC721 is ERC721Burnable {
  using Counters for Counters.Counter;
  mapping(uint256 => Counters.Counter) private _transfers;

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

  /// @notice getter for the underlying address
  function getTokenAddress(uint256 optionId)
    external
    view
    virtual
    returns (address);

  function getTokenId(uint256 optionId) external view virtual returns (uint256);

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
  function contractUri(uint256 optionId) external view returns (string) {
    return
      abi.encodePacked(
        "token.hook.xyz/option-contract/",
        HookStrings.toAsciiString(address(this)),
        "/",
        HookStrings.toString(optionId)
      );
  }

  /// @dev this is a basic token URI that will show the underlying contract address as well as the
  /// token ID in an svg (ripped off from LOOT PROJECT)
  function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
  {
    string[5] memory parts;
    parts[
      0
    ] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>'
    '.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill='
    '"black" /><text x="10" y="20" class="base">';

    parts[1] = HookStrings.toAsciiString(this.getTokenAddress(tokenId));

    parts[2] = '</text><text x="10" y="40" class="base">';

    parts[3] = HookStrings.toString(this.getTokenId(tokenId));

    parts[4] = "</text></svg>";

    string memory output = string(
      abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4])
    );

    string memory json = Base64.encode(
      bytes(
        string(
          abi.encodePacked(
            '{"name": "Option Id',
            HookStrings.toString(tokenId),
            '", "description": "Hook powers fully on-chain covered call options", "image": '
            '"data:image/svg+xml;base64,',
            Base64.encode(bytes(output)),
            ', "expiration": ',
            HookStrings.toString(this.getExpiration(tokenId)),
            ', "underlying_address": ',
            HookStrings.toAsciiString(this.getTokenAddress(tokenId)),
            ', "underlying_tokenId": ',
            HookStrings.toString(this.getTokenId(tokenId)),
            ', "strike_price": ',
            HookStrings.toString(this.getStrikePrice(tokenId)),
            ', "transfer_index": ',
            HookStrings.toString(_transfers[tokenId].current()),
            '"}'
          )
        )
      )
    );
    output = string(abi.encodePacked("data:application/json;base64,", json));

    return output;
  }
}
