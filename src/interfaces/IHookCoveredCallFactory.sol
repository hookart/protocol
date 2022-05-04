// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/// @title HookCoveredCallFactory -- factory for instances of the Covered Call contract
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Factory creates covered call instruments that support specific ERC-721 contracts, and
/// also tracks all of the existing active markets.
/// @dev Operating the factory requires specific permissions within the protocol.
interface IHookCoveredCallFactory {
  function getCallInstrument(address assetAddress)
    external
    view
    returns (address calls);

  /// @notice Create a call option instrument for a specific underlying asset address
  /// @dev Only the admin can create these addresses.
  /// @param assetAddress the address for the underling asset
  /// @return calls the address of the call option instrument contract (upgradeable)
  function makeCallInstrument(address assetAddress)
    external
    returns (address calls);
}
