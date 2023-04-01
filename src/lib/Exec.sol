// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

contract Exec {
  struct Operation {
    address dest;
    bytes data;
  }

  function batch(Operation[] calldata operations) external returns (bytes memory) {
    for (uint256 i = 0; i < operations.length; ++i) {
      Operation calldata operation = operations[i];
      address destAddr = operation.dest;
      bytes memory dataWithSender = abi.encodePacked(operation.data, msg.sender);
      (bool success, bytes memory result) = destAddr.call(dataWithSender);
      require(success, "Delegate call failed");
      return result;
    }
  }
}

contract BatchUtil {
  function unpackTrailingParamMsgSender() internal pure returns (address msgSender) {
    assembly {
      msgSender := shr(96, calldataload(sub(calldatasize(), 20)))
    }
  }
}