//SPDX-License-Identifier: ISC
pragma solidity 0.8.10;

// Libraries
import "../synthetix/SignedDecimalMath.sol";
import "../synthetix/DecimalMath.sol";
import "./FixedPointMathLib.sol";
import "./Math.sol";

/**
 * @title BlackScholes
 * @author Lyra
 * @dev Contract to compute the black scholes price of options. Where the unit is unspecified, it should be treated as a
 * PRECISE_DECIMAL, which has 1e27 units of precision. The default decimal matches the ethereum standard of 1e18 units
 * of precision.
 */
library BlackScholes {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;

    struct PricesDeltaStdVega {
        uint256 callPrice;
        uint256 putPrice;
        int256 callDelta;
        int256 putDelta;
        uint256 vega;
        uint256 stdVega;
    }

    /**
     * @param timeToExpirySec Number of seconds to the expiry of the option
     * @param volatilityDecimal Implied volatility over the period til expiry as a percentage
     * @param spotDecimal The current price of the base asset
     * @param strikePriceDecimal The strikePrice price of the option
     * @param rateDecimal The percentage risk free rate + carry cost
     */
    struct BlackScholesInputs {
        uint256 timeToExpirySec;
        uint256 volatilityDecimal;
        uint256 spotDecimal;
        uint256 strikePriceDecimal;
        int256 rateDecimal;
    }

    uint256 private constant SECONDS_PER_YEAR = 31536000;
    /// @dev Internally this library uses 27 decimals of precision
    uint256 private constant PRECISE_UNIT = 1e27;
    uint256 private constant SQRT_TWOPI = 2506628274631000502415765285;
    /// @dev Value to use to avoid any division by 0 or values near 0
    uint256 private constant MIN_T_ANNUALISED = PRECISE_UNIT / SECONDS_PER_YEAR; // 1 second
    uint256 private constant MIN_VOLATILITY = PRECISE_UNIT / 10000; // 0.001%
    uint256 private constant VEGA_STANDARDISATION_MIN_DAYS = 7 days;
    /// @dev Magic numbers for normal CDF
    uint256 private constant SPLIT = 7071067811865470000000000000;
    uint256 private constant N0 = 220206867912376000000000000000;
    uint256 private constant N1 = 221213596169931000000000000000;
    uint256 private constant N2 = 112079291497871000000000000000;
    uint256 private constant N3 = 33912866078383000000000000000;
    uint256 private constant N4 = 6373962203531650000000000000;
    uint256 private constant N5 = 700383064443688000000000000;
    uint256 private constant N6 = 35262496599891100000000000;
    uint256 private constant M0 = 440413735824752000000000000000;
    uint256 private constant M1 = 793826512519948000000000000000;
    uint256 private constant M2 = 637333633378831000000000000000;
    uint256 private constant M3 = 296564248779674000000000000000;
    uint256 private constant M4 = 86780732202946100000000000000;
    uint256 private constant M5 = 16064177579207000000000000000;
    uint256 private constant M6 = 1755667163182640000000000000;
    uint256 private constant M7 = 88388347648318400000000000;

    /////////////////////////////////////
    // Option Pricing public functions //
    /////////////////////////////////////

    /**
     * @dev Returns call and put prices for options with given parameters.
     */
    function optionPrices(BlackScholesInputs memory bsInput) public pure returns (uint256 call, uint256 put) {
        uint256 tAnnualised = _annualise(bsInput.timeToExpirySec);
        uint256 spotPrecise = bsInput.spotDecimal.decimalToPreciseDecimal();
        uint256 strikePricePrecise = bsInput.strikePriceDecimal.decimalToPreciseDecimal();
        int256 ratePrecise = bsInput.rateDecimal.decimalToPreciseDecimal();
        (int256 d1, int256 d2) = _d1d2(
            tAnnualised,
            bsInput.volatilityDecimal.decimalToPreciseDecimal(),
            spotPrecise,
            strikePricePrecise,
            ratePrecise
        );
        (call, put) = _optionPrices(tAnnualised, spotPrecise, strikePricePrecise, ratePrecise, d1, d2);
        return (call.preciseDecimalToDecimal(), put.preciseDecimalToDecimal());
    }

    /**
     * @dev Returns call/put prices and delta/stdVega for options with given parameters.
     */
    function pricesDeltaStdVega(BlackScholesInputs memory bsInput) public pure returns (PricesDeltaStdVega memory) {
        uint256 tAnnualised = _annualise(bsInput.timeToExpirySec);
        uint256 spotPrecise = bsInput.spotDecimal.decimalToPreciseDecimal();

        (int256 d1, int256 d2) = _d1d2(
            tAnnualised,
            bsInput.volatilityDecimal.decimalToPreciseDecimal(),
            spotPrecise,
            bsInput.strikePriceDecimal.decimalToPreciseDecimal(),
            bsInput.rateDecimal.decimalToPreciseDecimal()
        );
        (uint256 callPrice, uint256 putPrice) = _optionPrices(
            tAnnualised,
            spotPrecise,
            bsInput.strikePriceDecimal.decimalToPreciseDecimal(),
            bsInput.rateDecimal.decimalToPreciseDecimal(),
            d1,
            d2
        );
        (uint256 vegaPrecise, uint256 stdVegaPrecise) = _standardVega(d1, spotPrecise, bsInput.timeToExpirySec);
        (int256 callDelta, int256 putDelta) = _delta(d1);

        return PricesDeltaStdVega(
            callPrice.preciseDecimalToDecimal(),
            putPrice.preciseDecimalToDecimal(),
            callDelta.preciseDecimalToDecimal(),
            putDelta.preciseDecimalToDecimal(),
            vegaPrecise.preciseDecimalToDecimal(),
            stdVegaPrecise.preciseDecimalToDecimal()
        );
    }

    /**
     * @dev Returns call delta given parameters.
     */

    function delta(BlackScholesInputs memory bsInput)
        public
        pure
        returns (int256 callDeltaDecimal, int256 putDeltaDecimal)
    {
        uint256 tAnnualised = _annualise(bsInput.timeToExpirySec);
        uint256 spotPrecise = bsInput.spotDecimal.decimalToPreciseDecimal();

        (int256 d1,) = _d1d2(
            tAnnualised,
            bsInput.volatilityDecimal.decimalToPreciseDecimal(),
            spotPrecise,
            bsInput.strikePriceDecimal.decimalToPreciseDecimal(),
            bsInput.rateDecimal.decimalToPreciseDecimal()
        );

        (int256 callDelta, int256 putDelta) = _delta(d1);
        return (callDelta.preciseDecimalToDecimal(), putDelta.preciseDecimalToDecimal());
    }

    /**
     * @dev Returns non-normalized vega given parameters. Quoted in cents.
     */
    function vega(BlackScholesInputs memory bsInput) public pure returns (uint256 vegaDecimal) {
        uint256 tAnnualised = _annualise(bsInput.timeToExpirySec);
        uint256 spotPrecise = bsInput.spotDecimal.decimalToPreciseDecimal();

        (int256 d1,) = _d1d2(
            tAnnualised,
            bsInput.volatilityDecimal.decimalToPreciseDecimal(),
            spotPrecise,
            bsInput.strikePriceDecimal.decimalToPreciseDecimal(),
            bsInput.rateDecimal.decimalToPreciseDecimal()
        );
        return _vega(tAnnualised, spotPrecise, d1).preciseDecimalToDecimal();
    }

    //////////////////////
    // Computing Greeks //
    //////////////////////

    /**
     * @dev Returns internal coefficients of the Black-Scholes call price formula, d1 and d2.
     * @param tAnnualised Number of years to expiry
     * @param volatility Implied volatility over the period til expiry as a percentage
     * @param spot The current price of the base asset
     * @param strikePrice The strikePrice price of the option
     * @param rate The percentage risk free rate + carry cost
     */
    function _d1d2(uint256 tAnnualised, uint256 volatility, uint256 spot, uint256 strikePrice, int256 rate)
        internal
        pure
        returns (int256 d1, int256 d2)
    {
        // Set minimum values for tAnnualised and volatility to not break computation in extreme scenarios
        // These values will result in option prices reflecting only the difference in stock/strikePrice, which is expected.
        // This should be caught before calling this function, however the function shouldn't break if the values are 0.
        tAnnualised = tAnnualised < MIN_T_ANNUALISED ? MIN_T_ANNUALISED : tAnnualised;
        volatility = volatility < MIN_VOLATILITY ? MIN_VOLATILITY : volatility;

        int256 vtSqrt = int256(volatility.multiplyDecimalRoundPrecise(_sqrtPrecise(tAnnualised)));
        int256 log = FixedPointMathLib.lnPrecise(int256(spot.divideDecimalRoundPrecise(strikePrice)));
        int256 v2t = (int256(volatility.multiplyDecimalRoundPrecise(volatility) / 2) + rate).multiplyDecimalRoundPrecise(
            int256(tAnnualised)
        );
        d1 = (log + v2t).divideDecimalRoundPrecise(vtSqrt);
        d2 = d1 - vtSqrt;
    }

    /**
     * @dev Internal coefficients of the Black-Scholes call price formula.
     * @param tAnnualised Number of years to expiry
     * @param spot The current price of the base asset
     * @param strikePrice The strikePrice price of the option
     * @param rate The percentage risk free rate + carry cost
     * @param d1 Internal coefficient of Black-Scholes
     * @param d2 Internal coefficient of Black-Scholes
     */
    function _optionPrices(uint256 tAnnualised, uint256 spot, uint256 strikePrice, int256 rate, int256 d1, int256 d2)
        internal
        pure
        returns (uint256 call, uint256 put)
    {
        uint256 strikePricePV = strikePrice.multiplyDecimalRoundPrecise(
            FixedPointMathLib.expPrecise(int256(-rate.multiplyDecimalRoundPrecise(int256(tAnnualised))))
        );
        uint256 spotNd1 = spot.multiplyDecimalRoundPrecise(_stdNormalCDF(d1));
        uint256 strikePriceNd2 = strikePricePV.multiplyDecimalRoundPrecise(_stdNormalCDF(d2));

        // We clamp to zero if the minuend is less than the subtrahend
        // In some scenarios it may be better to compute put price instead and derive call from it depending on which way
        // around is more precise.
        call = strikePriceNd2 <= spotNd1 ? spotNd1 - strikePriceNd2 : 0;
        put = call + strikePricePV;
        put = spot <= put ? put - spot : 0;
    }

    /*
   * Greeks
   */

    /**
     * @dev Returns the option's delta value
     * @param d1 Internal coefficient of Black-Scholes
     */
    function _delta(int256 d1) internal pure returns (int256 callDelta, int256 putDelta) {
        callDelta = int256(_stdNormalCDF(d1));
        putDelta = callDelta - int256(PRECISE_UNIT);
    }

    /**
     * @dev Returns the option's vega value based on d1. Quoted in cents.
     *
     * @param d1 Internal coefficient of Black-Scholes
     * @param tAnnualised Number of years to expiry
     * @param spot The current price of the base asset
     */
    function _vega(uint256 tAnnualised, uint256 spot, int256 d1) internal pure returns (uint256) {
        return _sqrtPrecise(tAnnualised).multiplyDecimalRoundPrecise(_stdNormal(d1).multiplyDecimalRoundPrecise(spot));
    }

    /**
     * @dev Returns the option's vega value with expiry modified to be at least VEGA_STANDARDISATION_MIN_DAYS
     * @param d1 Internal coefficient of Black-Scholes
     * @param spot The current price of the base asset
     * @param timeToExpirySec Number of seconds to expiry
     */
    function _standardVega(int256 d1, uint256 spot, uint256 timeToExpirySec) internal pure returns (uint256, uint256) {
        uint256 tAnnualised = _annualise(timeToExpirySec);
        uint256 normalisationFactor = _getVegaNormalisationFactorPrecise(timeToExpirySec);
        uint256 vegaPrecise = _vega(tAnnualised, spot, d1);
        return (vegaPrecise, vegaPrecise.multiplyDecimalRoundPrecise(normalisationFactor));
    }

    function _getVegaNormalisationFactorPrecise(uint256 timeToExpirySec) internal pure returns (uint256) {
        timeToExpirySec =
            timeToExpirySec < VEGA_STANDARDISATION_MIN_DAYS ? VEGA_STANDARDISATION_MIN_DAYS : timeToExpirySec;
        uint256 daysToExpiry = timeToExpirySec / 1 days;
        uint256 thirty = 30 * PRECISE_UNIT;
        return _sqrtPrecise(thirty / daysToExpiry) / 100;
    }

    /////////////////////
    // Math Operations //
    /////////////////////

    /// @notice Calculates the square root of x, rounding down (borrowed from https://github.com/paulrberg/prb-math)
    /// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
    /// @param x The uint256 number for which to calculate the square root.
    /// @return result The result as an uint256.
    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }

        // Calculate the square root of the perfect square of a power of two that is the closest to x.
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }

        // The operations can never overflow because the result is max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }

    /**
     * @dev Returns the square root of the value using Newton's method.
     */
    function _sqrtPrecise(uint256 x) internal pure returns (uint256) {
        // Add in an extra unit factor for the square root to gobble;
        // otherwise, sqrt(x * UNIT) = sqrt(x) * sqrt(UNIT)
        return _sqrt(x * PRECISE_UNIT);
    }

    /**
     * @dev The standard normal distribution of the value.
     */
    function _stdNormal(int256 x) internal pure returns (uint256) {
        return FixedPointMathLib.expPrecise(int256(-x.multiplyDecimalRoundPrecise(x / 2))).divideDecimalRoundPrecise(
            SQRT_TWOPI
        );
    }

    /**
     * @dev The standard normal cumulative distribution of the value.
     * borrowed from a C++ implementation https://stackoverflow.com/a/23119456
     */
    function _stdNormalCDF(int256 x) public pure returns (uint256) {
        uint256 z = Math.abs(x);
        int256 c = 0;

        if (z <= 37 * PRECISE_UNIT) {
            uint256 e = FixedPointMathLib.expPrecise(-int256(z.multiplyDecimalRoundPrecise(z / 2)));
            if (z < SPLIT) {
                c = int256(
                    (
                        _stdNormalCDFNumerator(z).divideDecimalRoundPrecise(_stdNormalCDFDenom(z))
                            .multiplyDecimalRoundPrecise(e)
                    )
                );
            } else {
                uint256 f = (
                    z
                        + PRECISE_UNIT.divideDecimalRoundPrecise(
                            z
                                + (2 * PRECISE_UNIT).divideDecimalRoundPrecise(
                                    z
                                        + (3 * PRECISE_UNIT).divideDecimalRoundPrecise(
                                            z + (4 * PRECISE_UNIT).divideDecimalRoundPrecise(z + ((PRECISE_UNIT * 13) / 20))
                                        )
                                )
                        )
                );
                c = int256(e.divideDecimalRoundPrecise(f.multiplyDecimalRoundPrecise(SQRT_TWOPI)));
            }
        }
        return uint256((x <= 0 ? c : (int256(PRECISE_UNIT) - c)));
    }

    /**
     * @dev Helper for _stdNormalCDF
     */
    function _stdNormalCDFNumerator(uint256 z) internal pure returns (uint256) {
        uint256 numeratorInner = ((((((N6 * z) / PRECISE_UNIT + N5) * z) / PRECISE_UNIT + N4) * z) / PRECISE_UNIT + N3);
        return (((((numeratorInner * z) / PRECISE_UNIT + N2) * z) / PRECISE_UNIT + N1) * z) / PRECISE_UNIT + N0;
    }

    /**
     * @dev Helper for _stdNormalCDF
     */
    function _stdNormalCDFDenom(uint256 z) internal pure returns (uint256) {
        uint256 denominatorInner =
            ((((((M7 * z) / PRECISE_UNIT + M6) * z) / PRECISE_UNIT + M5) * z) / PRECISE_UNIT + M4);
        return (
            ((((((denominatorInner * z) / PRECISE_UNIT + M3) * z) / PRECISE_UNIT + M2) * z) / PRECISE_UNIT + M1) * z
        ) / PRECISE_UNIT + M0;
    }

    /**
     * @dev Converts an integer number of seconds to a fractional number of years.
     */
    function _annualise(uint256 secs) internal pure returns (uint256 yearFraction) {
        return secs.divideDecimalRoundPrecise(SECONDS_PER_YEAR);
    }
}
