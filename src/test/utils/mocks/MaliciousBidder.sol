pragma solidity ^0.8.10;

import "../../../interfaces/IHookCoveredCall.sol";

// @dev a smart contract that reverts upon recieveing funds
// and allows a bid to be mocked to a specific covered call option.
// this can be used to write tests that fail if a contract reverting
// prevents new bids.
contract MaliciousBidder {
  IHookCoveredCall private callOption;
  bool private throwOnReceive;

  constructor(address _callOption) {
    callOption = IHookCoveredCall(_callOption);
    throwOnReceive = true;
  }

  function bid(uint256 optionId) public payable {
    callOption.bid{value: msg.value}(optionId);
  }

  receive() external payable {
    require(!throwOnReceive, "ha ha ha gotcha");
  }
}
