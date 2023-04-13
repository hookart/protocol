//SPDX-License-Identifier: ISC
pragma solidity 0.8.10;

/**
 * @title Math
 * @author Lyra
 * @dev Library to unify logic for common shared functions
 */
library Math {
    /// @dev Return the minimum value between the two inputs
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y) ? x : y;
    }

    /// @dev Return the maximum value between the two inputs
    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y) ? x : y;
    }

    /// @dev Compute the absolute value of `val`.
    function abs(int256 val) internal pure returns (uint256) {
        return uint256(val < 0 ? -val : val);
    }

    /// @dev Takes ceiling of a to m precision
    /// @param m represents 1eX where X is the number of trailing 0's
    function ceil(uint256 a, uint256 m) internal pure returns (uint256) {
        return ((a + m - 1) / m) * m;
    }
}
