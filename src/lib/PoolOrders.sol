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

import "../interfaces/zeroex-v4/IPropertyValidator.sol";

library PoolOrders {
    uint256 private constant _PROPERTY_TYPEHASH =
        uint256(keccak256(abi.encodePacked("Property(", "address propertyValidator,", "bytes propertyData", ")")));

    // uint256 private constant _ORDER_TYPEHASH = abi.encode(
    //     "Order(",
    //     "uint8 direction,",
    //     "address maker,",
    //     "uint256 orderExpiry,",
    //     "uint256 nonce,",
    //     "uint8 size,",
    //     "uint8 optionType,",
    //     "uint256 maxStrikePriceMultiple,"
    //     "uint64 minOptionDuration,",
    //     "uint64 maxOptionDuration,",
    //     "uint64 maxPriceSignalAge,",
    //     "Property[] nftProperties,",
    //     "address optionMarketAddress,",
    //     "uint64 impliedVolBips,",
    //     "uint256 skewDecimal,",
    //     "uint64 riskFreeRateBips",
    //     ")",
    //     _PROPERTY_TYPEHASH
    // );
    uint256 private constant _ORDER_TYPEHASH = 0xcf88a2fdf20e362d67310061df675df92f17bd55a872a02e14b7dc017475f705;

    /// ---- ENUMS -----
    enum OptionType {
        CALL,
        PUT
    }

    enum OrderDirection {
        BUY,
        SELL
    }

    /// ---- STRUCTS -----
    struct Property {
        IPropertyValidator propertyValidator;
        bytes propertyData;
    }

    struct Order {
        /// @notice the direction of the order. Only BUY orders are currently supported
        OrderDirection direction;
        /// @notice the address of the maker who must sign this order
        address maker;
        /// @notice the block timestamp at which this order can no longer be filled
        uint256 orderExpiry;
        /// @notice a cryptographic nonce used to make the order unique
        uint256 nonce;
        /// @notice the maximum number of times this order can be filled
        uint8 size;
        OptionType optionType;
        /// @notice decimal in the money or out of the money an option can be filled at. For example, 5e17 == 50% out of the money max for a call option. 0 means no max
        uint256 maxStrikePriceMultiple;
        /// @notice minimum time from the time the order is filled that the option could expire. 0 means no min
        uint64 minOptionDuration;
        /// @notice maximum time from the time the order is filled that the option could expire. 0 means no max
        uint64 maxOptionDuration;
        /// @notice maximum age of a price signal to accept as a valid floor price
        uint64 maxPriceSignalAge;
        /// @notice array of property validators if the filler would like more fine-grained control of the filling option instrument
        Property[] nftProperties;
        /// @notice address of Hook option market (and option instrument) that can fill this order. This address must be trusted by the orderer to deliver the correct type of call instrument.
        address optionMarketAddress;
        /// @notice impliedVolBips is the maximum implied volatility of the desired options in bips (1/100th of a percent). For example, 100 bips = 1%.
        uint64 impliedVolBips;
        /// @notice the decimal-described slope of the skew for the desired implied volatility
        uint256 skewDecimal;
        /// @notice riskFreeRateBips is the percentage risk free rate + carry costs (e.g. 100 = 1%). About 5% is typical.
        uint64 riskFreeRateBips;
    }

    function _propertiesHash(Property[] memory properties) private pure returns (bytes32 propertiesHash) {
        uint256 numProperties = properties.length;
        if (numProperties == 0) {
            return 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        }
        bytes32[] memory propertyStructHashArray = new bytes32[](numProperties);
        for (uint256 i = 0; i < numProperties; i++) {
            propertyStructHashArray[i] = keccak256(
                abi.encode(_PROPERTY_TYPEHASH, properties[i].propertyValidator, keccak256(properties[i].propertyData))
            );
        }
        return keccak256(abi.encodePacked(propertyStructHashArray));
    }

    /// @dev split the hash to resolve a stack too deep error
    function _hashPt1(Order memory poolOrder) private pure returns (bytes memory) {
        return abi.encode(
            _ORDER_TYPEHASH,
            poolOrder.direction,
            poolOrder.maker,
            poolOrder.orderExpiry,
            poolOrder.nonce,
            poolOrder.size,
            poolOrder.optionType,
            poolOrder.maxStrikePriceMultiple
        );
    }

    /// @dev split the hash to resolve a stack too deep error
    function _hashPt2(Order memory poolOrder) private pure returns (bytes memory) {
        return abi.encode(
            poolOrder.minOptionDuration,
            poolOrder.maxOptionDuration,
            poolOrder.maxPriceSignalAge,
            _propertiesHash(poolOrder.nftProperties),
            poolOrder.optionMarketAddress,
            poolOrder.impliedVolBips,
            poolOrder.skewDecimal,
            poolOrder.riskFreeRateBips
        );
    }

    function getPoolOrderStructHash(Order memory poolOrder) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_hashPt1(poolOrder), _hashPt2(poolOrder)));
    }
}
