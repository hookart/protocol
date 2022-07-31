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

import "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title HookProtocol configuration and access control repository
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
///
/// @dev it is critically important that the particular protocol implementation
/// is correct as, if it is not, all assets contained within protocol contracts
/// can be easily compromised.
interface IHookProtocol is IAccessControl {
  /// @notice the address of the deployed CoveredCallFactory used by the protocol
  function coveredCallContract() external view returns (address);

  /// @notice the address of the deployed VaultFactory used by the protocol
  function vaultContract() external view returns (address);

  /// @notice callable function that reverts when the protocol is paused
  function throwWhenPaused() external;

  /// @notice the standard weth address on this chain
  /// @dev these are values for popular chains:
  /// mainnet: 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
  /// kovan: 0xd0a1e359811322d97991e03f863a0c30c2cf029c
  /// ropsten: 0xc778417e063141139fce010982780140aa0cd5ab
  /// rinkeby: 0xc778417e063141139fce010982780140aa0cd5ab
  /// @return the weth address
  function getWETHAddress() external view returns (address);

  /// @notice get a configuration flag with a specific key for a collection
  /// @param collectionAddress the collection for which to lookup a configuration flag
  /// @param conf the config identifier for the configuration flag
  /// @return the true or false value of the config
  function getCollectionConfig(address collectionAddress, bytes32 conf)
    external
    view
    returns (bool);
}
