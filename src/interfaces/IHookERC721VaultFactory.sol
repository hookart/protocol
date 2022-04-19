pragma solidity 0.8.10;

interface IHookERC721VaultFactory {
    // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations
    function getVault(address nftAddress, uint256 tokenId)
        external
        view
        returns (address vault);

    function makeVault(address nftAddress, uint256 tokenId)
        external
        returns (address vault);
}
