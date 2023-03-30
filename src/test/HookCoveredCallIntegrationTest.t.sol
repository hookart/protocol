// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./utils/base.t.sol";

/// @notice Integration tests for the Hook Protocol
/// @author Regynald Augustin-regy@hook.xyz
contract HookCoveredCallIntegrationTest is HookProtocolTest {
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

  function testMintOption() public {
    vm.startPrank(address(writer));
    uint32 expiration = uint32(block.timestamp) + 3 days;

    emit log_named_address("writer", address(writer));
    Exec.Operation[] memory operations = new Exec.Operation[](1);
    operations[0] = Exec.Operation(address(calls), abi.encodeWithSignature(
      "mintWithErc721(address,uint256,uint128,uint32)",
      address(token),
      underlyingTokenId,
      1000,
      expiration
      )
    );

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    bytes memory result = exec.batch(operations);
    uint256 optionId = uint256(bytes32(result));
    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );
    vm.stopPrank();
  }

  function testRevertMintOptionMustBeOwnerOrOperator() public {
    vm.expectRevert("mWE7-caller not owner or operator");
    calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      uint32(block.timestamp + 3 days)
    );
  }

  function testRevertMintOptionExpirationMustBeMoreThan1DayInTheFuture()
    public
  {
    vm.startPrank(address(writer));

    vm.expectRevert("_mOWV-expires sooner than min duration");
    calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      uint32(block.timestamp + 30 minutes)
    );
    vm.stopPrank();
  }

  function testSuccessfulAuctionAndSettlement() public {
    // create the call option
    vm.startPrank(address(writer));
    uint256 writerStartBalance = writer.balance;
    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
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
    address bidder1 = address(3456);
    address bidder2 = address(33456463);

    // bid at an invalid time
    vm.warp(baseTime + 0.5 days);
    vm.prank(bidder1);
    vm.expectRevert("bE-bidding starts on last day");
    calls.bid{value: 0}(optionId);

    // make the first bid, but have it be too low
    vm.warp(baseTime + 2.1 days);
    vm.deal(bidder1, 300);
    vm.prank(bidder1);
    vm.expectRevert("b-bid is lower than the strike price");
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
    vm.prank(buyer);
    calls.settleOption(optionId);

    // verify the balances are correct
    uint256 writerEndBalance = writer.balance;
    uint256 buyerEndBalance = buyer.balance;

    assertTrue(
      writerEndBalance - writerStartBalance == 1000,
      "the writer gets the strike price"
    );
    assertTrue(
      buyerEndBalance - buyerStartBalance == 100,
      "the call owner gets the spread"
    );
  }

  // Test that the option was not transferred, a bid was made,
  // but the owner re-obtained the option and therefore can stop
  // the auction.
  function testNoSettlemetBidAssetEarlyReclaim() public {
    // create the call option
    vm.startPrank(address(writer));
    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );
    vm.stopPrank();

    // made a bid
    vm.warp(baseTime + 2.1 days);
    address bidder1 = address(3456);
    vm.deal(bidder1, 1100);
    vm.prank(bidder1);
    calls.bid{value: 1050}(optionId);

    vm.prank(address(writer));
    calls.reclaimAsset(optionId, false);
  }

  function testNoSettlemetBidAssetRecaimFailRandomClaimer() public {
    // create the call option
    vm.startPrank(address(writer));
    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // assume that the writer somehow sold to the buyer, outside the scope of this test
    calls.safeTransferFrom(writer, buyer, optionId);
    vm.stopPrank();

    vm.warp(expiration + 3 seconds);

    vm.prank(address(5555));
    vm.expectRevert("rA-only writer");
    calls.reclaimAsset(optionId, true);
  }

  // test: writer must not steal asset by buying back option nft after expiration.
  function testWriterCannotStealBackAssetAfterExpiration() public {
    // create the call option
    vm.startPrank(address(writer));
    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // assume that the writer somehow sold to the buyer, outside the scope of this test
    calls.safeTransferFrom(writer, buyer, optionId);
    vm.stopPrank();

    // made a bid
    vm.warp(baseTime + 2.1 days);
    address bidder1 = address(3456);
    vm.deal(bidder1, 1100);
    vm.prank(bidder1);
    calls.bid{value: 1050}(optionId);

    vm.warp(expiration + 1 days);

    // The writer somehow buys back the option
    vm.prank(address(buyer));
    calls.safeTransferFrom(buyer, writer, optionId);

    vm.prank(address(writer));
    vm.expectRevert("rA-option expired");
    calls.reclaimAsset(optionId, true);
  }

  function testWriterCanMintOptionAfterBurning() public {
    // mint first call option
    vm.startPrank(address(writer));

    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint32 afterExpiration = uint32(baseTime) + 3.1 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // call option #1 expires
    vm.warp(afterExpiration);
    calls.burnExpiredOption(optionId);

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(token), underlyingTokenId)
    );

    // grant entitlement on vault for token id 0
    uint32 expiration2 = expiration + 3 days;
    IHookVault(vault).grantEntitlement(
      Entitlements.Entitlement(
        writer,
        address(calls),
        address(vault),
        0,
        expiration2
      )
    );

    // mint second call option
    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 3, 1000, expiration2);
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }
}
