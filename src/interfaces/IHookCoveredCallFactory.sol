// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IHookCoveredCallFactory {
  // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations
  function getCallInstrument(address nftAddress)
    external
    view
    returns (address calls);

  function makeCallInstrument(address nftAddress)
    external
    returns (address calls);
}
