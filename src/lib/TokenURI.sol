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

/// @dev This contract implements some ERC721 / for hook instruments.
library TokenURI {
    function _generateMetadataERC721(
        address underlyingTokenAddress,
        uint256 underlyingTokenId,
        uint256 instrumentStrikePrice,
        uint256 instrumentExpiration,
        uint256 transfers
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"expiration": ',
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

    /// @dev this is a basic tokenURI based on the loot contract for an ERC721
    function tokenURIERC721(
        uint256 instrumentId,
        address underlyingAddress,
        uint256 underlyingTokenId,
        uint256 instrumentExpiration,
        uint256 instrumentStrike,
        uint256 transfers
    ) public view returns (string memory) {
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Option ID ',
                        HookStrings.toString(instrumentId),
                        '",',
                        _generateMetadataERC721(
                            underlyingAddress, underlyingTokenId, instrumentStrike, instrumentExpiration, transfers
                        ),
                        ', "description": "Option Instrument NFT on Hook: the NFT-native call options protocol. Learn more at https://hook.xyz", "image": "https://option-images-hook.s3.amazonaws.com/nft/live_0x',
                        HookStrings.toAsciiString(address(this)),
                        "_",
                        HookStrings.toString(instrumentId),
                        '.png" }'
                    )
                )
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }
}
