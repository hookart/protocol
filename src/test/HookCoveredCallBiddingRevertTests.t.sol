// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./utils/base.t.sol";
import "./utils/mocks/MaliciousBidder.sol";

// @dev these tests try cases where a bidder maliciously reverts on save.
contract HookCoveredCallBiddingRevertTests is HookProtocolTest {
  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();

    // add address to the allowlist for minting
    vm.prank(address(admin));
    vaultFactory.makeMultiVault(address(token));

    // Set user balances
    vm.deal(address(buyer), 100 ether);

    // Mint underlying token
    underlyingTokenId = 0;
    token.mint(address(writer), underlyingTokenId);

    // Buyer swap 50 ETH <> 50 WETH
    vm.prank(address(buyer));
    weth.deposit{value: 50 ether}();

    // Seller approve ERC721TransferHelper
    vm.prank(address(writer));
    token.setApprovalForAll(address(calls), true);

    // Buyer approve covered call
    vm.prank(address(buyer));
    weth.approve(address(calls), 50 ether);
  }

  function test_SuccessfulAuctionAndSettlement() public {
    // create the call option
    vm.startPrank(address(writer));
    uint256 writerStartBalance = writer.balance;
    uint256 baseTime = block.timestamp;
    uint128 expiration = uint128(baseTime) + 3 days;
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // assume that the writer somehow sold to the buyer, outside the scope of this test
    calls.safeTransferFrom(writer, buyer, optionId);
    uint256 buyerStartBalance = buyer.balance;

    vm.stopPrank();
    // create some bidders
    MaliciousBidder bidder1 = new MaliciousBidder(address(calls));
    address mbcaller = address(6969420);
    address bidder2 = address(33456463);

    // made a bid
    vm.warp(baseTime + 2.1 days);
    vm.deal(mbcaller, 1100);
    vm.prank(mbcaller);
    bidder1.bid{value: 1050}(optionId);

    // validate that bid is updated
    assertTrue(
      calls.currentBid(optionId) == 1050,
      "contract should update the current high bid for the option"
    );
    assertTrue(
      calls.currentBidder(optionId) == address(bidder1),
      "bidder1 should be in the lead"
    );
    assertTrue(
      address(calls).balance == 1050,
      "bidder1 should have deposited money into escrow"
    );

    // make a competing bid
    vm.deal(bidder2, 1100);
    vm.prank(bidder2);
    calls.bid{value: 1100}(optionId);

    // validate that bid is updated
    assertTrue(
      calls.currentBid(optionId) == 1100,
      "contract should update the current high bid for the option"
    );
    assertTrue(
      calls.currentBidder(optionId) == bidder2,
      "bidder2 should be in the lead"
    );
    assertTrue(bidder2.balance == 0, "bidder2 should have funds in escrow");

    // settle the auction
    // assertTrue(token.ownerOf(underlyingTokenId) == address(calls), "call contract should own the token");
    vm.warp(expiration + 3 seconds);
    calls.settleOption(optionId, true);

    // verify the balances are correct
    uint256 writerEndBalance = writer.balance;
    uint256 buyerEndBalance = buyer.balance;

    assertTrue(
      token.ownerOf(underlyingTokenId) == bidder2,
      "the high bidder should own the nft"
    );
    assertTrue(
      writerEndBalance - writerStartBalance == 1000,
      "the writer gets the strike price"
    );
    assertTrue(
      buyerEndBalance - buyerStartBalance == 100,
      "the call owner gets the spread"
    );
  }
}
