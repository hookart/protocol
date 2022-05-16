// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/// @title HookCoveredCallFactory -- factory for instances of the Covered Call contract
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The Factory creates covered call instruments that support specific ERC-721 contracts, and
/// also tracks all of the existing active markets.
interface IHookCoveredCallFactory {
  /// @dev emitted whenever a new call insturment instance is created
  /// @param assetAddress the address of the asset underlying the covered call
  /// @param insturmentAddress the address of the coveredcall insturment
  event CoveredCallInsturmentCreated(
    address assetAddress,
    address insturmentAddress
  );

  /// @notice Lookup the call instrument contract based on the asset address
  /// @param assetAddress the contract address for the underlying asset
  /// @return calls the address of the insturment contract
  function getCallInstrument(address assetAddress)
    external
    view
    returns (address calls);

  /// @notice Create a call option instrument for a specific underlying asset address
  /// @param assetAddress the address for the underling asset
  /// @return calls the address of the call option instrument contract (upgradeable)
  function makeCallInstrument(address assetAddress)
    external
    returns (address calls);
}
