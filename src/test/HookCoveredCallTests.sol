// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./utils/base.sol";

/// Mint ///
contract HookCoveredCallMintTests is HookProtocolTest {
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
  }

  function testMintOption() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

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

  function testMintMultipleOptions() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

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

    uint256 secondUnderlyingTokenId = 1;
    token.mint(address(writer), secondUnderlyingTokenId);

    vm.expectEmit(true, true, true, true);
    emit CallCreated(
      address(writer),
      address(token),
      secondUnderlyingTokenId,
      2, // This would be the second option id.
      1000,
      expiration
    );
    uint256 secondOptionId = calls.mint(
      address(token),
      secondUnderlyingTokenId,
      1000,
      expiration,
      makeSignature(secondUnderlyingTokenId, expiration, writer)
    );

    assertTrue(
      calls.ownerOf(secondOptionId) == address(writer),
      "owner should own the option"
    );
  }

  // Test that proxy smart contracts are able to mint options on behalf of the owner
  function testMintOptionAsOperator() public {
    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);
    vm.stopPrank();

    vm.startPrank(operator);

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

    assertTrue(
      calls.getApproved(optionId) == address(operator),
      "operator should be approved for option"
    );
  }

  function testCannotMintOptionInvalidSignature() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint256 expiration = block.timestamp + 3 days;

    vm.expectRevert(
      "validateEntitlementSignature --- not signed by beneficialOwner"
    );
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId + 1, expiration + 1, writer)
    );
  }

  function testCannotMintOptionInvalidExpiration() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint256 expiration = block.timestamp + 1 hours;

    vm.expectRevert(
      "mint -- _expirationTime must be more than one day in the future time"
    );
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintOptionPaused() public {
    vm.prank(address(admin));
    protocol.pause();

    uint256 expiration = block.timestamp + 3 days;

    vm.expectRevert("Pausable: paused");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintOptionHookContractNotApproved() public {
    vm.startPrank(address(writer));

    uint256 expiration = block.timestamp + 3 days;

    vm.expectRevert("mint -- HookCoveredCall must be operator");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintOptionNotUnderlyingOwner() public {
    vm.startPrank(address(buyer));

    uint256 expiration = block.timestamp + 3 days;

    vm.expectRevert("mint -- caller must be token owner or operator");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintMultipleOptionsSameToken() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

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

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mint -- caller must be token owner or operator");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintMultipleOptionsSameTokenAsOperator() public {
    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);
    vm.stopPrank();

    vm.startPrank(operator);
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
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mint -- caller must be token owner or operator");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintMultipleOptionsSameTokenAsOwnerThenOperator() public {
    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);

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
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );

    // Perform next mint attempt as operator
    vm.stopPrank();
    vm.startPrank(operator);

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mint -- caller must be token owner or operator");
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );
  }

  function testCannotMintOptionForUnallowedContract() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

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

    // Minting should only work for TestERC721
    vm.expectRevert("mint -- token must be on the project allowlist");
    calls.mint(
      address(calls),
      optionId,
      1000,
      expiration,
      makeSignature(optionId, expiration, writer)
    );
  }

  /// Approvals ///

  // The operator of the underlying asset will be approved for the option NFT
  // but approval for the underlying asset will be removed.
  function testApprovalsForUnderlyingRemovedAfterOptionMint() public {
    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);
    vm.stopPrank();

    vm.startPrank(operator);

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
    calls.mint(
      address(token),
      underlyingTokenId,
      1000,
      expiration,
      makeSignature(underlyingTokenId, expiration, writer)
    );

    assertTrue(
      token.getApproved(underlyingTokenId) != address(operator),
      "operator should be approved for option"
    );
  }
}

/// Bidding ///
contract HookCoveredCallBidTests is HookProtocolTest {
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
  }

  function testBidAsOwner() public {
    address bidder = address(37);
    vm.label(bidder, "Option bidder");

    vm.warp(block.timestamp + 2.1 days);
    hoax(bidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    assertTrue(
      calls.currentBid(optionTokenId) == 0.1 ether,
      "bid should be 0.1 ether"
    );
    assertTrue(
      calls.currentBidder(optionTokenId) == bidder,
      "bid should be 0.1 ether"
    );
  }

  function testBidAsOperator() public {
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
    uint256 expiration = block.timestamp + 3 days;

    calls.mint(
      address(token),
      underlyingTokenId2,
      1000,
      expiration,
      makeSignature(underlyingTokenId2, expiration, writer)
    );

    vm.warp(block.timestamp + 2.1 days);
    calls.bid{value: 0.1 ether}(optionTokenId);

    assertTrue(
      calls.currentBid(optionTokenId) == 0.1 ether,
      "bid should be 0.1 ether"
    );
    assertTrue(
      calls.currentBidder(optionTokenId) == operator,
      "bid should be 0.1 ether"
    );
  }

  function testNewHighBidReturnOldHighBidTokens() public {
    address firstBidder = address(37);
    vm.label(firstBidder, "First option bidder");
    vm.deal(address(firstBidder), 1 ether);

    address secondBidder = address(38);
    vm.label(secondBidder, "Second option bidder");
    vm.deal(address(secondBidder), 1 ether);

    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    uint256 firstBidderStartBalance = firstBidder.balance;
    calls.bid{value: 0.1 ether}(optionTokenId);

    vm.prank(secondBidder);
    uint256 secondBidderStartBalance = secondBidder.balance;
    calls.bid{value: 0.2 ether}(optionTokenId);

    assertTrue(
      firstBidder.balance == firstBidderStartBalance,
      "first bidder should have lower bid returned"
    );

    assertTrue(
      secondBidder.balance + 0.2 ether == secondBidderStartBalance,
      "first bidder should have lower bid returned"
    );
  }

  function testCannotBidBeforeAuctionStart() public {
    address bidder = address(37);
    vm.label(bidder, "Option bidder");

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 1.9 days);
    hoax(bidder);
    vm.expectRevert("biddingEnabled -- bidding starts on last day");
    calls.bid{value: 0.1 ether}(optionTokenId);
  }

  function testCannotBidAfterOptionExpired() public {
    address bidder = address(37);
    vm.label(bidder, "Option bidder");

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 4 days);
    hoax(bidder);
    vm.expectRevert("biddingEnabled -- option already expired");
    calls.bid{value: 0.1 ether}(optionTokenId);
  }

  function testCannotBidLessThanStrikePrice() public {
    address bidder = address(37);
    vm.label(bidder, "Option bidder");

    vm.warp(block.timestamp + 2.1 days);
    hoax(bidder);

    /// Option strike price is 1000 wei.
    vm.expectRevert("bid - bid is lower than the strike price");
    calls.bid{value: 1 wei}(optionTokenId);
  }

  function testCannotBidLessThanCurrentBid() public {
    address firstBidder = address(37);
    vm.label(firstBidder, "First option bidder");
    vm.deal(address(firstBidder), 1 ether);

    address secondBidder = address(38);
    vm.label(secondBidder, "Second option bidder");
    vm.deal(address(secondBidder), 1 ether);

    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    vm.prank(secondBidder);
    vm.expectRevert("bid - bid is lower than the current bid");
    calls.bid{value: 0.09 ether}(optionTokenId);
  }
}

/// Settlement ///
contract HookCoveredCallSettleTests is HookProtocolTest {
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
    setUpOptionBids();
  }

  function testSettleOption() public {
    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    vm.prank(writer);
    calls.settleOption(optionTokenId, false);

    assertTrue(
      buyerStartBalance + (0.2 ether - 1000 wei) == buyer.balance,
      "buyer gets the option spread (winning bid - strike price"
    );
    assertTrue(
      writerStartBalance + 1000 wei == writer.balance,
      "buyer should have received the option"
    );
  }

  function testSettleOptionReturnNft() public {
    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    address vaultAddress = vaultFactory.getVault(
      address(token),
      underlyingTokenId
    );
    vm.expectCall(vaultAddress, abi.encodeWithSignature("withdrawalAsset()"));

    vm.prank(writer);
    calls.settleOption(optionTokenId, true);

    assertTrue(
      buyerStartBalance + (0.2 ether - 1000 wei) == buyer.balance,
      "buyer gets the option spread (winning bid - strike price"
    );
    assertTrue(
      writerStartBalance + 1000 wei == writer.balance,
      "buyer should have received the option"
    );
    assertTrue(
      token.ownerOf(underlyingTokenId) == address(secondBidder),
      "secondBidder (winner) should get the underlying asset"
    );
  }

  function testCannotSettleOptionNoWinningBid() public {
    vm.startPrank(address(writer));
    uint256 underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint256 expiration = block.timestamp + 3 days;

    uint256 optionId = calls.mint(
      address(token),
      underlyingTokenId2,
      1000,
      expiration,
      makeSignature(underlyingTokenId2, expiration, writer)
    );

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 3.1 days);
    vm.expectRevert("settle -- bid must be won by someone");
    calls.settleOption(optionId, true);
  }

  function testCannotSettleOptionBeforeExpiration() public {
    startHoax(address(writer));
    uint256 underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint256 expiration = block.timestamp + 3 days;

    uint256 optionId = calls.mint(
      address(token),
      underlyingTokenId2,
      1000,
      expiration,
      makeSignature(underlyingTokenId2, expiration, writer)
    );

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);
    calls.bid{value: 0.1 ether}(optionId);

    vm.expectRevert("settle -- option must be expired");
    calls.settleOption(optionId, true);
  }

  function testCannotSettleSettledOption() public {
    vm.prank(writer);
    calls.settleOption(optionTokenId, false);

    vm.expectRevert("settle -- the call cannot already be settled");
    calls.settleOption(optionTokenId, true);
  }
}

/// Reclaiming ///
contract HookCoveredCallReclaimTests is HookProtocolTest {
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
  }

  function testReclaimAsset() public {
    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 3.1 days);
    vm.prank(writer);
    calls.reclaimAsset(optionTokenId, false);
  }

  function testReclaimAssetReturnNft() public {
    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 3.1 days);

    vm.startPrank(writer);

    address vaultAddress = vaultFactory.getVault(
      address(token),
      underlyingTokenId
    );
    vm.expectCall(vaultAddress, abi.encodeWithSignature("withdrawalAsset()"));
    calls.reclaimAsset(optionTokenId, true);
  }

  function testCannotReclaimAssetAsNonCallWriter() public {
    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 3.1 days);

    vm.startPrank(buyer);

    vm.expectRevert(
      "reclaimAsset -- asset can only be reclaimed by the writer"
    );
    calls.reclaimAsset(optionTokenId, true);
  }

  function testCannotReclaimFromSettledOption() public {
    setUpOptionBids();

    vm.startPrank(writer);
    calls.settleOption(optionTokenId, false);

    vm.expectRevert("reclaimAsset -- the option has already been settled");
    calls.reclaimAsset(optionTokenId, true);
  }

  function testCannotReclaimWithActiveBid() public {
    setUpOptionBids();

    vm.startPrank(writer);
    vm.expectRevert(
      "reclaimAsset -- cannot reclaim a sold asset if the option is not writer-owned."
    );
    calls.reclaimAsset(optionTokenId, true);
  }

  function testCannotReclaimBeforeExpiration() public {
    vm.startPrank(writer);
    vm.warp(block.timestamp + 2.1 days);

    vm.expectRevert(
      "reclaimAsset -- the option must expired unless writer-owned"
    );
    calls.reclaimAsset(optionTokenId, true);
  }
}
