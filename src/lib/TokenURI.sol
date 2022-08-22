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

import "@openzeppelin/contracts/utils/Base64.sol";

import "./HookStrings.sol";
import "./Fonts.sol";
import "./BokkyPooBahsDateTimeLibrary.sol";

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
          '", "expiration": ',
          HookStrings.toString(instrumentExpiration),
          ', "underlying_address": "',
          HookStrings.toAsciiString(underlyingTokenAddress),
          '", "underlying_tokenId": ',
          HookStrings.toString(underlyingTokenId),
          ', "strike_price": ',
          HookStrings.toString(instrumentStrikePrice),
          ', "transfer_index": ',
          HookStrings.toString(transfers)
        )
      );
  }

  function renderSVG1(uint256 strike, uint256 expiration)
    public
    pure
    returns (bytes memory)
  {
    // string memory moduleName = attemptGetMetatdataUriName(module);

    (uint256 year, uint256 month, uint256 day) = BokkyPooBahsDateTimeLibrary
      .timestampToDate(expiration);

    return
      abi.encodePacked(
        '<svg width="500" height="500" viewBox="0 0 500 500" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><rect width="500" height="500" fill="#FAE6C9"/><g filter="url(#filter0_d_702_157)"><rect x="30" y="30" width="440" height="440" rx="30" fill="#FFF2E0" shape-rendering="crispEdges"/><rect x="60" y="60" width="187" height="187" rx="14" fill="black" fill-opacity="0.2"/><rect x="60" y="60" width="187" height="187" rx="14" fill="url(#pattern0)"/>',
        '<text fill="#E16900" font-size="24" font-weight="300"><tspan x="269" y="113.284">',
        HookStrings.toString(strike / 10**18), //strike,
        ' ETH</tspan></text><text fill="#1A5B6C" font-size="16" font-weight="300"><tspan x="269" y="137.284">Strike Price</tspan></text><text fill="#E16900" font-size="24" font-weight="300"><tspan x="269" y="184.284">',
        HookStrings.toString(year),
        "-",
        HookStrings.toString(month),
        "-",
        HookStrings.toString(day), // date
        '</tspan></text><text fill="#1A5B6C" font-size="16" font-weight="300"><tspan x="269" y="208.284">Expiration date</tspan></text><text fill="#1A5B6C" font-size="12" font-weight="300"><tspan x="62" y="314.356">Underlying Contract Address</tspan></text><text fill="#E16900" font-size="16" font-weight="300"><tspan x="62" y="298.356">'
      );
  }

  function renderSVG2(address underlyingAddress, uint256 underlyingTokenId)
    public
    pure
    returns (bytes memory)
  {
    return
      abi.encodePacked(
        HookStrings.toAsciiString(underlyingAddress),
        '</tspan></text><text fill="#1A5B6C" font-size="12" font-weight="300"><tspan x="62" y="358.356">Underlying Token ID</tspan></text><text fill="#E16900" font-size="16" font-weight="300"><tspan x="62" y="342.356">',
        HookStrings.toString(underlyingTokenId), // token ID
        '</tspan></text><text fill="#E16900" font-size="16"><tspan x="60" y="416.356">Call Option</tspan><tspan x="60" y="435.356">Instrument NFT</tspan></text><g clip-path="url(#clip0_702_157)"><path d="M312.667 439.421V400H319.929V416.138C321.359 414.037 324.066 412.565 327.513 412.565C333.929 412.565 337.745 417.19 337.745 424.024V439.425H330.482V425.232C330.482 421.446 328.837 419.135 325.816 419.135C322.424 419.135 319.932 421.554 319.932 426.599V439.425H312.667V439.421Z" fill="#E16900"/><path d="M341.651 426.282C341.651 418.608 347.907 412.562 355.596 412.562C363.285 412.562 369.541 418.608 369.541 426.282C369.541 433.955 363.285 440.001 355.596 440.001C347.907 440.001 341.651 434.009 341.651 426.282ZM362.169 426.282C362.169 422.235 359.36 419.292 355.596 419.292C351.832 419.292 348.968 422.235 348.968 426.282C348.968 430.328 351.777 433.271 355.596 433.271C359.415 433.271 362.169 430.328 362.169 426.282Z" fill="#E16900"/><path d="M372.178 426.282C372.178 418.608 378.434 412.562 386.123 412.562C393.812 412.562 400.068 418.608 400.068 426.282C400.068 433.955 393.812 440.001 386.123 440.001C378.434 440.001 372.178 434.009 372.178 426.282V426.282ZM392.697 426.282C392.697 422.235 389.888 419.292 386.123 419.292C382.359 419.292 379.495 422.235 379.495 426.282C379.495 430.328 382.304 433.271 386.123 433.271C389.942 433.271 392.697 430.328 392.697 426.282V426.282Z" fill="#E16900"/><path d="M411.273 427.333V439.421H404.01V400H411.273V422.813L419.863 413.14H428.611L418.112 424.968L431.051 439.421H422.089L411.273 427.333V427.333Z" fill="#E16900"/><path d="M433.166 412.031H431.948V411.373H435.084V412.031H433.859V415.537H433.166V412.031V412.031Z" fill="#E16900"/><path d="M436.426 411.373L437.895 413.344L439.367 411.373H439.998V415.537H439.299V412.552L437.898 414.44L436.484 412.546V415.537H435.792V411.373H436.423H436.426Z" fill="#E16900"/></g></g><defs><filter id="filter0_d_702_157" x="14" y="20" width="472" height="472" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/><feOffset dy="6"/><feGaussianBlur stdDeviation="8"/><feComposite in2="hardAlpha" operator="out"/><feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0"/><feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_702_157"/><feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow_702_157" result="shape"/></filter><pattern id="pattern0" patternContentUnits="objectBoundingBox" width="1" height="1"><use xlink:href="#image0_702_157" transform="scale(0.00534759358)"/></pattern><clipPath id="clip0_702_157"><rect width="127.333" height="40" fill="white" transform="translate(312.667 400)"/></clipPath><image id="image0_702_157" width="187" height="187" preserveAspectRatio="xMidYMid" alt="underlying nft" href="',
        abi.encodePacked(
          "https://app.hook.xyz/image/",
          HookStrings.toAsciiString(underlyingAddress),
          "/",
          HookStrings.toString(underlyingTokenId)
        ), // img url
        '" /><style>',
        "@font-face { font-family: Euclid Circular A; src: url('data:font/woff2;base64,",
        Font1.font(),
        Font2.font(),
        Font3.font(),
        "') format('woff2');} text { font-family: Euclid Circular A; white-space: pre; letter-spacing: -0.001em;}"
        "</style></defs></svg>"
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
    bytes memory output = abi.encodePacked(
      renderSVG1(instrumentStrike, instrumentExpiration),
      renderSVG2(underlyingAddress, underlyingTokenId)
    );

    string memory json = Base64.encode(
      bytes(
        string(
          abi.encodePacked(
            '{"name": "Option Id',
            HookStrings.toString(instrumentId),
            '", "description": "Option Instrument NFT on Hook: the NFT-native call options protocol. Learn more at https://hook.xyz", "image": '
            '"data:image/svg+xml;base64,',
            Base64.encode(output),
            _generateMetadataERC721(
              underlyingAddress,
              underlyingTokenId,
              instrumentStrike,
              instrumentExpiration,
              transfers
            ),
            "}"
          )
        )
      )
    );
    return string(abi.encodePacked("data:application/json;base64,", json));
  }
}
