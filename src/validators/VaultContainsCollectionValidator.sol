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

import "../interfaces/IHookOptionExercisableVaultValidator.sol";
import "../interfaces/IHookERC721Vault.sol";
import "../lib/VaultAuthenticator.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract VaultContainsCollectionValidator is IHookOptionExercisableVaultValidator {
    address private immutable _vaultFactory;
    address private immutable _underlyingTokenAddress;

    constructor(address erc721VaultFactory, address underlyingAddress) {
        _vaultFactory = erc721VaultFactory;
        _underlyingTokenAddress = underlyingAddress;
    }

    function validate(address vaultAddress, uint32 assetId, bytes calldata) external override returns (bool) {
        require(
            ERC165Checker.supportsInterface(vaultAddress, type(IHookERC721Vault).interfaceId), "must be a ERC721 vault"
        );
        // extract the address from the params
        require(
            VaultAuthenticator.isHookERC721Vault(_vaultFactory, _underlyingTokenAddress, vaultAddress, assetId),
            "must be an authentic hook protocol vol"
        );

        require(IHookERC721Vault(vaultAddress).getHoldsAsset(assetId), "asset must be deposited within the vault");

        // this check is not required because the isHookERC721Vault check validates that the vault was deployed
        // for a specific underlying address.
        // require(IHookERC721Vault(vaultAddress).assetAddress(assetId) == underlyingAddress, "asset must match");
        return true;
    }
}
