pragma solidity 0.8.10;

interface IHookCoveredCallFactory {
    // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations
    function getCallInsturment(address nftAddress)
        external
        view
        returns (address calls);

    function makeCallInsturment(address nftAddress)
        external
        returns (address calls);
}
