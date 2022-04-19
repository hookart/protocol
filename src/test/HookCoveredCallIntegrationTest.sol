// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./utils/base.sol";

contract HookCoveredCallIntegrationTest is HookProtocolTest {

    function setUp() public {
        setUpAddresses();
        setUpFullProtocol();
        
        // add address to the allowlist for minting

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

    function test_MintOption() public {
        vm.prank(address(writer));
        uint256 expiration = block.timestamp + 3 days;

        vm.expectEmit(true, true, true, true);
        emit CallCreated(
            address(writer),
            address(token),
            underlyingTokenId,
            1, // This would be the first option id.
            1000,
            expiration
        );
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        assertTrue(
            calls.ownerOf(optionId) == address(writer),
            "owner should own the option"
        );
    }

    function testRevert_MintOptionMustBeOwnerOrOperator() public {
        vm.expectRevert("mint -- caller must be token owner or operator");
        calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            block.timestamp + 3 days,
            makeSignature(underlyingTokenId, block.timestamp + 3 days, writer)
        );
    }

    function testRevert_MintOptionExpirationMustBeMoreThan1DayInTheFuture()
        public
    {
        vm.prank(address(writer));
        vm.expectRevert(
            "mint -- _expirationTime must be more than one day in the future time"
        );
        calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            block.timestamp + 30 minutes,
            makeSignature(
                underlyingTokenId,
                block.timestamp + 30 minutes,
                writer
            )
        );
    }

    function test_SuccessfulAuctionAndSettlement() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );
        vm.prank(address(writer));
        // assume that the writer somehow sold to the buyer, outside the scope of this test
        calls.safeTransferFrom(writer, buyer, optionId);
        uint256 buyerStartBalance = buyer.balance;

        // create some bidders
        address bidder1 = address(3456);
        address bidder2 = address(33456463);

        // bid at an invalid time
        vm.warp(baseTime + 0.5 days);
        vm.prank(bidder1);
        vm.expectRevert("biddingEnabled -- bidding starts on last day");
        calls.bid{value: 0}(optionId);

        // make the first bid, but have it be too low
        vm.warp(baseTime + 2.1 days);
        vm.deal(bidder1, 300);
        vm.prank(bidder1);
        vm.expectRevert("bid - bid is lower than the strike price");
        calls.bid{value: 300}(optionId);

        // made a bid
        vm.deal(bidder1, 1100);
        vm.prank(bidder1);
        calls.bid{value: 1050}(optionId);

        // validate that bid is updated
        assertTrue(
            calls.currentBid(optionId) == 1050,
            "contract should update the current high bid for the option"
        );
        assertTrue(
            calls.currentBidder(optionId) == bidder1,
            "bidder1 should be in the lead"
        );
        assertTrue(
            bidder1.balance == 50,
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
        assertTrue(
            bidder1.balance == 1100,
            "bidder1 should have their money back from escrow"
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

    // Test that the option was sold as per usual, but no settlement
    // bid activity occurred.
    function test_NoSettlemetBidAssetReclaim() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        // assume that the writer somehow sold to the buyer, outside the scope of this test
        vm.prank(address(writer));
        calls.safeTransferFrom(writer, buyer, optionId);

        vm.warp(expiration + 50 seconds);

        vm.prank(address(writer));
        calls.reclaimAsset(optionId, true);
        assertTrue(
            token.ownerOf(underlyingTokenId) == writer,
            "the nft should have returned to the buyer"
        );
    }

    // Test that the option was not transferred, a bid was made,
    // but the owner re-obtained the option and therefore can stop
    // the auction.
    function test_NoSettlemetBidAssetEarlyReclaim() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        // made a bid
        vm.warp(baseTime + 2.1 days);
        address bidder1 = address(3456);
        vm.deal(bidder1, 1100);
        vm.prank(bidder1);
        calls.bid{value: 1050}(optionId);

        vm.prank(address(writer));
        calls.reclaimAsset(optionId, false);
    }

    function test_NoSettlemetBidAssetRecaimFailRandomClaimer() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        // assume that the writer somehow sold to the buyer, outside the scope of this test
        vm.prank(address(writer));
        calls.safeTransferFrom(writer, buyer, optionId);

        vm.warp(expiration + 3 seconds);

        vm.prank(address(5555));
        vm.expectRevert(
            "reclaimAsset -- asset can only be reclaimed by the writer"
        );
        calls.reclaimAsset(optionId, true);
    }

    // test: writer must not steal asset by buying back option nft after expiration.
    function test_WriterCannotStealBackAssetAfterExpiration() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        // assume that the writer somehow sold to the buyer, outside the scope of this test
        vm.prank(address(writer));
        calls.safeTransferFrom(writer, buyer, optionId);

        // made a bid
        vm.warp(baseTime + 2.1 days);
        address bidder1 = address(3456);
        vm.deal(bidder1, 1100);
        vm.prank(bidder1);
        calls.bid{value: 1050}(optionId);

        vm.warp(expiration + 3 seconds);

        // The writer somehow buys back the option
        vm.prank(address(buyer));
        calls.safeTransferFrom(buyer, writer, optionId);

        vm.prank(address(writer));
        vm.expectRevert("reclaimAsset -- cannot reclaim a sold asset");
        calls.reclaimAsset(optionId, true);
    }

    // make sure that the writer cannot reclaim when a settlement bid is ongoing.
    function test_ActiveSettlementBidAssetRecaimFail() public {
        // create the call option
        vm.prank(address(writer));
        uint256 writerStartBalance = writer.balance;
        uint256 baseTime = block.timestamp;
        uint256 expiration = baseTime + 3 days;
        uint256 optionId = calls.mint(
            address(token),
            underlyingTokenId,
            1000,
            expiration,
            makeSignature(underlyingTokenId, expiration, writer)
        );

        // assume that the writer somehow sold to the buyer, outside the scope of this test
        vm.prank(address(writer));
        calls.safeTransferFrom(writer, buyer, optionId);

        // made a bid
        vm.warp(baseTime + 2.1 days);
        address bidder1 = address(3456);
        vm.deal(bidder1, 1100);
        vm.prank(bidder1);
        calls.bid{value: 1050}(optionId);

        vm.warp(expiration + 3 seconds);

        vm.prank(address(writer));
        vm.expectRevert(
            "reclaimAsset -- cannot reclaim a sold asset if the option is not writer-owned."
        );
        calls.reclaimAsset(optionId, true);
    }
}
