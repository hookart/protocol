pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Base64.sol";

import "./HookStrings.sol";

/// @dev This contract implements some ERC721 / for hook instruments.
library TokenURI {
  function _generateMetadataERC721(
    address underlyingTokenAddress,
    uint256 underlyingTokenId,
    uint256 instrumentStrikePrice,
    uint256 instrumentExpiration,
    uint256 transfers
  ) internal pure returns (string memory) {
    return
      string(
        abi.encodePacked(
          ', "expiration": ',
          HookStrings.toString(instrumentExpiration),
          ', "underlying_address": ',
          HookStrings.toAsciiString(underlyingTokenAddress),
          ', "underlying_tokenId": ',
          HookStrings.toString(underlyingTokenId),
          ', "strike_price": ',
          HookStrings.toString(instrumentStrikePrice),
          ', "transfer_index": ',
          HookStrings.toString(transfers)
        )
      );
  }

  /// @dev this is a basic tokenURI based on the loot contract for an ERC721
  /// (ripped off from LOOT PROJECT)
  function tokenURIERC721(
    uint256 instrumentId,
    address underlyingAddress,
    uint256 underlyingTokenId,
    uint256 instrumentExpiration,
    uint256 instrumentStrike,
    uint256 transfers
  ) public pure returns (string memory) {
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
            HookStrings.toString(instrumentId),
            '", "description": "Hook is the on-chain covered call option protocol", "image": '
            '"data:image/svg+xml;base64,',
            Base64.encode(bytes(output)),
            _generateMetadataERC721(
              underlyingAddress,
              underlyingTokenId,
              instrumentStrike,
              instrumentExpiration,
              transfers
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
