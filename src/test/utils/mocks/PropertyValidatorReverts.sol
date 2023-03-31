pragma solidity ^0.8.10;

import "../../../interfaces/zeroex-v4/IPropertyValidator.sol";

contract PropertyValidatorReverts is IPropertyValidator {
    function validateProperty(address tokenAddress, uint256 tokenId, bytes calldata propertyData)
        external
        view
        override
    {
        revert("PropertyValidator: BAD PROPERTIES");
    }
}
