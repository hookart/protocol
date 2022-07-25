// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./utils/base.t.sol";

/// @notice Covered call minting test cases
/// @author Regynald Augustin -- regy@hook.xyz
contract HookCoveredCallMintTests is HookProtocolTest {
  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();

    // Set buyer balances and give weth
    vm.deal(address(buyer), 100 ether);
    vm.prank(address(buyer));
    weth.deposit{value: 50 ether}();

    vm.prank(address(admin));
    vaultFactory.makeMultiVault(address(token));

    // Mint underlying token for writer
    underlyingTokenId = 0;
    token.mint(address(writer), underlyingTokenId);
  }

  function testMintOption() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );
  }

  function testMultiVaultMintOption() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);

    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );

    // limit this call to 300,000 gas
    // overall gas usage depends on the underlying NFT contract
    uint256 optionId = calls.mintWithErc721{gas: 330_000}(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );
  }

  function testTransferApproval() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    vm.stopPrank();
    vm.expectRevert("ERC721: transfer caller is not owner nor approved");
    calls.safeTransferFrom(writer, address(55), optionId);

    vm.prank(preApprovedOperator);
    calls.safeTransferFrom(writer, address(55), optionId);
    assertTrue(
      calls.ownerOf(optionId) == address(55),
      "the transfer should work"
    );
  }

  function test_MintOptionWithVault() public {
    vm.startPrank(address(writer));

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(token), underlyingTokenId)
    );

    // place token in the vault
    token.safeTransferFrom(address(writer), address(vault), underlyingTokenId);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    Signatures.Signature memory sig = makeSignature(
      underlyingTokenId,
      expiration,
      writer
    );
    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 1, 1000, expiration);

    uint256 optionId = calls.mintWithVault(
      address(vault),
      0,
      1000,
      expiration,
      sig
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );

    (bool isActive, address operator) = vault.getCurrentEntitlementOperator(0);
    assertTrue(isActive, "there should be an active entitlement");
    assertTrue(
      operator == address(calls),
      "the call options should be the operator"
    );
  }

  function test_MintOptionWithAlienVault() public {
    vm.startPrank(address(writer));

    HookERC721VaultImplV1 alienVault = new HookERC721VaultImplV1();

    alienVault.initialize(address(token), underlyingTokenId, address(protocol));

    // place token in the vault
    token.safeTransferFrom(
      address(writer),
      address(alienVault),
      underlyingTokenId
    );

    uint32 expiration = uint32(block.timestamp) + 3 days;

    Signatures.Signature memory sig = makeSignature(
      underlyingTokenId,
      expiration,
      writer
    );

    vm.expectRevert("mintWithVault -- can only mint with protocol vaults");
    calls.mintWithVault(address(alienVault), 0, 1000, expiration, sig);
  }

  function test_MintOptionWithVaultFailsExpiration() public {
    vm.startPrank(address(writer));

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(token), underlyingTokenId)
    );

    // place token in the vault
    token.safeTransferFrom(address(writer), address(vault), underlyingTokenId);

    uint32 expiration = uint32(block.timestamp) + 1 days;

    Signatures.Signature memory sig = makeSignature(
      underlyingTokenId,
      expiration,
      writer
    );

    vm.expectRevert(
      "_mintOptionWithVault -- expirationTime must be more than one day in the future time"
    );
    calls.mintWithVault(address(vault), 0, 1000, expiration, sig);
  }

  function test_MintOptionWithVaultFailsEmptyVault() public {
    vm.startPrank(address(writer));

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(token), underlyingTokenId)
    );

    uint32 expiration = uint32(block.timestamp) + 3 days;

    Signatures.Signature memory sig = makeSignature(
      underlyingTokenId,
      expiration,
      writer
    );

    vm.expectRevert("mintWithVault-- asset must be in vault");
    calls.mintWithVault(address(vault), 0, 1000, expiration, sig);
  }

  function test_MintOptionWithVaultFailsUnsupportedCollection() public {
    vm.startPrank(address(writer));
    try
      vaultFactory.findOrCreateVault(address(calls), underlyingTokenId)
    {} catch {}

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(calls), underlyingTokenId)
    );

    uint32 expiration = uint32(block.timestamp) + 3 days;

    Signatures.Signature memory sig = makeSignature(
      underlyingTokenId,
      expiration,
      writer
    );

    vm.expectRevert("mintWithVault -- token must be on the project allowlist");
    calls.mintWithVault(address(vault), 0, 1000, expiration, sig);
  }

  function testMintMultipleOptions() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );

    uint256 secondUnderlyingTokenId = 1;
    token.mint(address(writer), secondUnderlyingTokenId);

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      2, // This would be the second option id.
      1000,
      expiration
    );
    uint256 secondOptionId = calls.mintWithErc721(
      address(token),
      secondUnderlyingTokenId,
      1000,
      expiration
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

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );

    assertTrue(
      calls.getApproved(optionId) == address(operator),
      "operator should be approved for option"
    );

    assertTrue(
      bytes(calls.tokenURI(optionId)).length > 100,
      "tokenURI should be long"
    );
  }

  function testCannotMintOptionInvalidSignature() public {
    vm.startPrank(address(writer));

    IHookERC721Vault vault = IHookERC721Vault(
      vaultFactory.findOrCreateVault(address(token), underlyingTokenId)
    );

    // place token in the vault
    token.safeTransferFrom(address(writer), address(vault), underlyingTokenId);
    uint32 expiration = uint32(block.timestamp) + 3 days;

    Signatures.Signature memory signature = makeSignature(
      underlyingTokenId + 1,
      expiration + 1,
      writer
    );
    vm.expectRevert(
      "validateEntitlementSignature --- not signed by beneficialOwner"
    );
    calls.mintWithVault(address(vault), 0, 1000, expiration, signature);
  }

  function testCannotMintOptionInvalidExpiration() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 1 hours;
    vm.expectRevert(
      "_mintOptionWithVault -- expirationTime must be more than one day in the future time"
    );
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionInvalidExpiration2() public {
    vm.prank(address(admin));
    callInternal.setMinOptionDuration(3 hours);
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 1 hours;

    vm.expectRevert(
      "_mintOptionWithVault -- expirationTime must be more than one day in the future time"
    );
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCanMintOptionShorterExpiration() public {
    vm.prank(address(admin));
    callInternal.setMinOptionDuration(3 hours);
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 5 hours;
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionPaused() public {
    vm.startPrank(address(admin));
    protocol.pause();

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectRevert("Pausable: paused");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionMarketPaused() public {
    vm.startPrank(address(admin));
    callInternal.setMarketPaused(true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectRevert("whenNotPaused -- market is paused");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionHookContractNotApproved() public {
    vm.startPrank(address(writer));

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectRevert("mintWithErc721 -- HookCoveredCall must be operator");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionNotUnderlyingOwner() public {
    vm.startPrank(address(buyer));

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectRevert("mintWithErc721 -- caller must be token owner or operator");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintMultipleOptionsSameToken() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    assertTrue(
      calls.ownerOf(optionId) == address(writer),
      "owner should own the option"
    );

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mintWithErc721 -- caller must be token owner or operator");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
    vm.stopPrank();
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
    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mintWithErc721 -- caller must be token owner or operator");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintMultipleOptionsSameTokenAsOwnerThenOperator() public {
    address operator = address(10);
    vm.label(operator, "additional token operator");

    vm.startPrank(address(writer));
    // Writer approve operator and covered call
    token.setApprovalForAll(operator, true);
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);

    // Perform next mint attempt as operator
    vm.stopPrank();
    vm.startPrank(operator);

    // Vault is now owner of the underlying token so this fails.
    vm.expectRevert("mintWithErc721 -- caller must be token owner or operator");
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);
  }

  function testCannotMintOptionForUnallowedContract() public {
    vm.startPrank(address(writer));

    // Writer approve covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // Minting should only work for TestERC721
    vm.expectRevert("mintWithErc721 -- token must be on the project allowlist");
    calls.mintWithErc721(address(calls), optionId, 1000, expiration);
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

    uint32 expiration = uint32(block.timestamp) + 3 days;

    vm.expectEmit(true, true, true, false);
    emit CallCreated(
      address(writer),
      address(token),
      0,
      1, // This would be the first option id.
      1000,
      expiration
    );
    calls.mintWithErc721(address(token), underlyingTokenId, 1000, expiration);

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
    uint32 expiration = uint32(block.timestamp) + 3 days;

    calls.mintWithErc721(address(token), underlyingTokenId2, 1000, expiration);

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
    vm.expectRevert(
      "bid - bid is lower than the current bid + minBidIncrementBips"
    );
    calls.bid{value: 0.09 ether}(optionTokenId);
  }

  function testCannotBidLessThanCurrentIncrement() public {
    vm.prank(admin);
    callInternal.setBidIncrement(1000); // set it to 10% for this test
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
    vm.expectRevert(
      "bid - bid is lower than the current bid + minBidIncrementBips"
    );
    calls.bid{value: 0.105 ether}(optionTokenId);
  }

  function testCanBidLessMoreThanCurrentIncrement() public {
    vm.prank(admin);
    callInternal.setBidIncrement(1000); // set it to 10% for this test
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
    calls.bid{value: 0.112 ether}(optionTokenId);
  }

  function testWriterCanBidOnSpread() public {
    vm.deal(writer, 1 ether);
    vm.warp(block.timestamp + 2.1 days);

    vm.prank(writer);
    calls.bid{value: 1}(optionTokenId);

    assertTrue(
      calls.currentBid(optionTokenId) == 1001,
      "bid 1 wei over strike price"
    );
    assertTrue(
      calls.currentBidder(optionTokenId) == writer,
      "writer should be highest bidder"
    );
    assertTrue(
      writer.balance == 1 ether - 1,
      "writer should have only used 1 wei to bid"
    );
  }

  function testWriterCanOutbidOnSpread() public {
    address firstBidder = address(37);
    vm.label(firstBidder, "First option bidder");
    vm.deal(firstBidder, 1 ether);
    vm.deal(writer, 1 ether);

    uint256 firstBidderStartBalance = firstBidder.balance;

    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    uint256 strike = 1000;
    uint256 bidAmount = 0.1 ether - strike + 1;

    vm.prank(writer);
    calls.bid{value: bidAmount}(optionTokenId);

    assertTrue(
      calls.currentBid(optionTokenId) == 0.1 ether + 1,
      "high bid should be 0.1 ether + 1 wei"
    );
    assertTrue(
      calls.currentBidder(optionTokenId) == writer,
      "writer should be highest bidder"
    );
    assertTrue(
      firstBidderStartBalance == firstBidder.balance,
      "first bidder should have been refunded their bid"
    );
    assertTrue(
      writer.balance == 1 ether - bidAmount,
      "writer should have only used 0.1 ether + 1 wei to bid"
    );
  }

  function testWriterCanOutbidSelfOnSpread() public {
    address firstBidder = address(37);
    vm.label(firstBidder, "First option bidder");
    vm.deal(firstBidder, 1 ether);
    vm.deal(writer, 1 ether);

    uint256 firstBidderStartBalance = firstBidder.balance;

    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    uint256 strike = 1000;
    uint256 bidAmount = 0.1 ether - strike + 1;

    vm.prank(writer);
    calls.bid{value: bidAmount}(optionTokenId);

    uint256 secondBidAmount = 0.1 ether - strike + 2;
    vm.prank(writer);
    calls.bid{value: secondBidAmount}(optionTokenId);

    assertTrue(
      calls.currentBid(optionTokenId) == 0.1 ether + 2,
      "high bid should be 0.1 ether + 1 wei"
    );
    assertTrue(
      calls.currentBidder(optionTokenId) == writer,
      "writer should be highest bidder"
    );
    assertTrue(
      firstBidderStartBalance == firstBidder.balance,
      "first bidder should have been refunded their bid"
    );
    assertTrue(
      writer.balance == 1 ether - secondBidAmount,
      "writer should have only used 0.1 ether + 1 wei to bid"
    );
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
    calls.settleOption(optionTokenId);

    assertTrue(
      buyerStartBalance + (0.2 ether - 1000 wei) == buyer.balance,
      "buyer gets the option spread (winning bid - strike price"
    );
    assertTrue(
      writerStartBalance + 1000 wei == writer.balance,
      "buyer should have received the option"
    );
  }

  function testSettleOption2() public {
    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    IHookERC721Vault vault = vaultFactory.getVault(
      address(token),
      underlyingTokenId
    );

    vm.prank(writer);
    calls.settleOption(optionTokenId);

    assertTrue(
      buyerStartBalance + (0.2 ether - 1000 wei) == buyer.balance,
      "buyer gets the option spread (winning bid - strike price"
    );
    assertTrue(
      writerStartBalance + 1000 wei == writer.balance,
      "buyer should have received the option"
    );
  }

  function testCannotSettleOptionNoWinningBid() public {
    vm.startPrank(address(writer));
    uint256 underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 3.1 days);
    vm.expectRevert("settle -- bid must be won by someone");
    calls.settleOption(optionId);
  }

  function testCannotSettleOptionBeforeExpiration() public {
    startHoax(address(writer));
    uint256 underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);
    calls.bid{value: 0.1 ether}(optionId);

    vm.expectRevert("settle -- option must be expired");
    calls.settleOption(optionId);
  }

  function testCannotSettleSettledOption() public {
    vm.prank(writer);
    calls.settleOption(optionTokenId);

    vm.expectRevert("settle -- the call cannot already be settled");
    calls.settleOption(optionTokenId);
  }

  function testSettleOptionWhenWriterHighBidder() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);

    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Assume that the writer somehow sold the option NFT to the buyer.
    // Outside of the scope of these tests.
    calls.safeTransferFrom(writer, buyer, optionId);

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);
    calls.bid{value: 1 wei}(optionId);
    vm.warp(block.timestamp + 1 days);

    calls.settleOption(optionId);

    assertTrue(
      buyerStartBalance + 1 wei == buyer.balance,
      "buyer gets the option spread (winning bid of 1001 wei - strike price of 1000)"
    );

    assertTrue(
      writerStartBalance - 1 == writer.balance,
      "option writer only loses spread (1 wei)"
    );
  }

  function testSettleOptionWhenWriterBidFirst() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Assume that the writer somehow sold the option NFT to the buyer.
    // Outside of the scope of these tests.
    calls.safeTransferFrom(writer, buyer, optionId);

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    calls.bid{value: 1 wei}(optionId);
    vm.stopPrank();

    vm.prank(firstBidder);
    calls.bid{value: 2000 wei}(optionId);

    vm.warp(block.timestamp + 1 days);

    vm.prank(writer);
    calls.settleOption(optionId);

    assertTrue(
      buyerStartBalance + 1000 wei == buyer.balance,
      "buyer gets the spread (2000 wei - 1000 wei strike)"
    );
    assertTrue(
      writerStartBalance + 1000 wei == writer.balance,
      "option writer only gets strike (1000 wei)"
    );
  }

  function testSettleOptionWhenWriterBidLast() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Assume that the writer somehow sold the option NFT to the buyer.
    // Outside of the scope of these tests.
    calls.safeTransferFrom(writer, buyer, optionId);

    vm.stopPrank();

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 1001 wei}(optionId);

    vm.prank(writer);
    calls.bid{value: 2 wei}(optionId);

    vm.warp(block.timestamp + 1 days);

    vm.prank(writer);
    calls.settleOption(optionId);

    assertTrue(
      buyerStartBalance + 2 wei == buyer.balance,
      "buyer gets the spread (10002 wei - 1000 wei strike)"
    );
    assertTrue(
      writerStartBalance - 2 wei == writer.balance,
      "option writer bid on strike"
    );
  }

  function testSettleOptionWhenWriterOutbid() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    uint256 buyerStartBalance = buyer.balance;
    uint256 writerStartBalance = writer.balance;

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Assume that the writer somehow sold the option NFT to the buyer.
    // Outside of the scope of these tests.
    calls.safeTransferFrom(writer, buyer, optionId);

    vm.stopPrank();

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 1001 wei}(optionId);

    vm.prank(writer);
    calls.bid{value: 2 wei}(optionId);

    vm.prank(firstBidder);
    calls.bid{value: 1003 wei}(optionId);

    vm.warp(block.timestamp + 1 days);

    vm.prank(writer);
    calls.settleOption(optionId);

    assertTrue(
      buyerStartBalance + 3 wei == buyer.balance,
      "buyer gets the spread (10002 wei - 1000 wei strike)"
    );
    assertTrue(
      writerStartBalance + 1000 == writer.balance,
      "option writer gets strike (1000 wei)"
    );
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

    // Transfer option NFT from buyer back to the writer
    // Writer needs to own the option NFT for reclaimAsset
    vm.prank(address(buyer));
    calls.safeTransferFrom(buyer, writer, optionTokenId);
  }

  function testReclaimAsset() public {
    // Option expires in 3 days from current block
    vm.warp(block.timestamp + 2.1 days);
    vm.prank(writer);
    calls.reclaimAsset(optionTokenId, false);
  }

  function testReclaimAssetReturnNft() public {
    // Option expires in 3 days from current block
    vm.warp(block.timestamp + 2.1 days);

    vm.startPrank(writer);

    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionTokenId);
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
    calls.settleOption(optionTokenId);

    vm.expectRevert("reclaimAsset -- the option has already been settled");
    calls.reclaimAsset(optionTokenId, true);
  }

  function testReclaimWithActiveBid() public {
    vm.warp(block.timestamp + 2.1 days);
    vm.deal(address(firstBidder), 1 ether);

    vm.prank(firstBidder);

    calls.bid{value: 0.1 ether}(optionTokenId);

    vm.startPrank(writer);

    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionTokenId);
    calls.reclaimAsset(optionTokenId, true);

    assertTrue(
      token.ownerOf(0) == address(writer),
      "writer should own the underlying asset"
    );
  }

  function testReclaimWithActiveBidWriterHighBidder() public {
    vm.warp(block.timestamp + 2.1 days);
    vm.deal(address(firstBidder), 1 ether);
    vm.deal(address(writer), 1 ether);

    vm.prank(firstBidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    vm.prank(writer);
    calls.bid{value: 0.2 ether}(optionTokenId);

    uint256 writerPostBidBalance = writer.balance;

    vm.startPrank(writer);
    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionTokenId);
    calls.reclaimAsset(optionTokenId, true);

    assertTrue(
      token.ownerOf(0) == address(writer),
      "writer should own the underlying asset"
    );

    assertTrue(
      (writerPostBidBalance + 0.2 ether) == writer.balance,
      "writer should have have bid returned post reclaim"
    );
  }

  function testCannotReclaimAfterExpiration() public {
    vm.startPrank(writer);
    vm.warp(block.timestamp + 3.1 days);

    vm.expectRevert("reclaimAsset -- the option must not be expired");
    calls.reclaimAsset(optionTokenId, true);
  }

  function testReclaimAssetWriterBidFirst() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    calls.bid{value: 1 wei}(optionId);
    vm.stopPrank();

    vm.prank(firstBidder);
    calls.bid{value: 2000 wei}(optionId);

    vm.startPrank(writer);

    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionId);
    calls.reclaimAsset(optionId, true);
  }

  function testReclaimAssetWriterBidLast() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    vm.stopPrank();

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 1001 wei}(optionId);

    vm.prank(writer);
    calls.bid{value: 2 wei}(optionId);

    vm.startPrank(writer);

    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionId);
    calls.reclaimAsset(optionId, true);
  }

  function testReclaimAssetWriterBidMultiple() public {
    vm.startPrank(writer);
    uint256 underlyingTokenId2 = 1;
    token.mint(writer, underlyingTokenId2);
    vm.deal(writer, 1 ether);
    vm.deal(firstBidder, 1 ether);

    // Writer approve operator and covered call
    token.setApprovalForAll(address(calls), true);

    uint32 expiration = uint32(block.timestamp) + 3 days;

    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration
    );

    vm.stopPrank();

    // Option expires in 3 days from current block; bidding starts in 2 days.
    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 1001 wei}(optionId);

    vm.prank(writer);
    calls.bid{value: 2 wei}(optionId);

    vm.prank(firstBidder);
    calls.bid{value: 1003 wei}(optionId);

    vm.startPrank(writer);

    vm.expectEmit(true, false, false, false);
    emit CallReclaimed(optionId);
    calls.reclaimAsset(optionId, true);
  }
}
