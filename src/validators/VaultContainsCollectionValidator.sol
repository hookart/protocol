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
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract VaultContainsCollectionValidator is IHookOptionExercisableVaultValidator {

function validate(
    address vaultAddress,
    uint32 assetId,
    bytes calldata params
  ) external returns (bool) {
    require(ERC165Checker.supportsInterface(vaultAddress, type(IHookERC721Vault).interfaceId), "must be a ERC721 vault");
    require(VaultAuthenticator.isHookERC721Vault(vaultAddress, assetId), "must be an authentic hook protocol vol");

    // extract the address from the params
    address underlyingAddress = address(params);

    require(IHookERC721Vault(vaultAddress).getHoldsAsset(assetId), "asset must be deposited within the vault");
    require(IHookERC721Vault(vaultAddress).assetAddress(assetId) == underlyingAddress, "asset must match");
    return true;
  }
}