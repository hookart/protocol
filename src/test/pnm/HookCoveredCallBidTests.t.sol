// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./base.t.sol";

contract HookCoveredCallBidTests is HookProtocolTest {
  address bidder;

  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();

    // Set buyer balances and give weth
    vm.deal(address(buyer), 100 ether);
    vm.prank(address(buyer));
    weth.deposit{value: 50 ether}();

    // Mint underlying token for writer
    underlyingTokenId = 0;
    token.mint(address(writer), underlyingTokenId);

    setUpMintOption();

    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    uint256 underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);
    vm.stopPrank();

    startHoax(operator);
    uint32 expiration = uint32(block.timestamp) + 3 days;

    calls.mintWithErc721(address(token), underlyingTokenId2, 1000, expiration);

    vm.warp(block.timestamp + 2.1 days);
    // stopHoax(operator);

    bidder = getAgent();
    hoax(bidder, 1 ether);
    calls.bid{value: 1 ether}(optionTokenId);
  }

  // verify that the original bidder gets their money returned regardless of what happens (once outbid)
  function invariantBidderTest() public virtual {
    address outbidder = address(3);
    // start with the current bid in case some other outbidding happened in between
    uint256 bid = calls.currentBid(optionTokenId);
    hoax(outbidder, bid + 1 ether);
    calls.bid{value: bid + 1 ether}(optionTokenId);

    require(
      calls.currentBid(optionTokenId) == bid + 1 ether,
      "bid should be increased by 1 eth"
    );
    require(
      calls.currentBidder(optionTokenId) == outbidder,
      "outbidder should be winning"
    );
    require(
      address(bidder).balance == 1 ether,
      "original bidder should have money still"
    );
  }
}
