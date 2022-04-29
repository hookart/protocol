pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IHookProtocol is IAccessControl {
  // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations

  function coveredCallContract() external view returns (address);

  function vaultContract() external view returns (address);

  function throwWhenPaused() external;
}
