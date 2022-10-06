// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./utils/tokens/TestERC721.sol";
import "./utils/tokens/WETH.sol";

import "../HookUpgradeableBeacon.sol";
import "../HookCoveredCallFactory.sol";
import "../HookCoveredCallImplV1.sol";
import "../HookCoveredCallImplV2.sol";
import "../HookUpgradeableBeacon.sol";
import "../HookERC721VaultFactory.sol";
import "../HookERC721VaultImplV1.sol";
import "../HookERC721MultiVaultImplV1.sol";
import "../HookUpgradeableBeacon.sol";
import "../HookProtocol.sol";

import "../lib/Entitlements.sol";
import "../lib/Signatures.sol";

import "../mixin/EIP712.sol";
import "../mixin/PermissionConstants.sol";
import "../interfaces/IHookProtocol.sol";
import "../interfaces/IHookCoveredCall.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

/// @dev these tests try cases where a bidder maliciously reverts on save.
/// @author Jake Nyquist-j@hook.xyz
contract HookCoveredCallUpgradeTests is Test, EIP712, PermissionConstants {
  address internal admin;
  address internal buyer;
  uint256 internal writerpkey;
  address internal writer;
  address internal firstBidder;
  address internal secondBidder;
  IHookERC721Vault vault;
  IHookCoveredCall calls;
  HookCoveredCallImplV1 callImplv1;
  HookCoveredCallImplV2 callImplv2;
  TestERC721 internal token;
  WETH internal weth;
  uint256 internal underlyingTokenId;
  uint256 internal underlyingTokenId2;
  uint256 internal optionTokenId;
  HookUpgradeableBeacon callBeacon;
  HookCoveredCallImplV1 callImpl;

  event CallCreated(
    address writer,
    address vaultAddress,
    uint256 assetId,
    uint256 optionId,
    uint256 strikePrice,
    uint256 expiration
  );

  event Upgraded(address indexed implementation);

  function setUp() public {
    setUpAddresses();
    deployProtocol();

    // Set user balances
    vm.deal(address(buyer), 100 ether);

    // Mint underlying tokens
    underlyingTokenId = 0;
    token.mint(address(writer), underlyingTokenId);

    underlyingTokenId2 = 1;
    token.mint(address(writer), underlyingTokenId2);

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

  function setUpAddresses() public {
    token = new TestERC721();
    weth = new WETH();

    buyer = address(4);
    vm.label(buyer, "option buyer");

    writerpkey = uint256(0xBDCE);
    writer = vm.addr(writerpkey);
    vm.label(writer, "option writer");

    admin = address(69);
    vm.label(admin, "contract admin");

    firstBidder = address(37);
    vm.label(firstBidder, "First option bidder");

    secondBidder = address(38);
    vm.label(secondBidder, "Second option bidder");
  }

  function deployProtocol() public {
    HookProtocol protocol = new HookProtocol(
      admin,
      admin,
      admin,
      admin,
      admin,
      admin,
      address(weth)
    );
    address protocolAddress = address(protocol);
    // set the operator to a new protocol to make it a contract
    address preApprovedOperator = address(weth);
    setAddressForEipDomain(protocolAddress);

    // Deploy new vault factory
    HookERC721VaultImplV1 vaultImpl = new HookERC721VaultImplV1();

    HookUpgradeableBeacon vaultBeacon = new HookUpgradeableBeacon(
      address(vaultImpl),
      address(protocol),
      PermissionConstants.VAULT_UPGRADER
    );

    HookERC721MultiVaultImplV1 multiVaultImpl = new HookERC721MultiVaultImplV1();

    HookUpgradeableBeacon multiVaultBeacon = new HookUpgradeableBeacon(
      address(multiVaultImpl),
      address(protocol),
      PermissionConstants.VAULT_UPGRADER
    );

    HookERC721VaultFactory vaultFactory = new HookERC721VaultFactory(
      protocolAddress,
      address(vaultBeacon),
      address(multiVaultBeacon)
    );
    vm.prank(address(admin));
    protocol.setVaultFactory(address(vaultFactory));

    // make a vault factory for our token
    vm.prank(address(admin));
    vault = IHookERC721Vault(vaultFactory.makeMultiVault(address(token)));

    // Deploy coverd call implementations
    callImplv1 = new HookCoveredCallImplV1();
    callImplv2 = new HookCoveredCallImplV2();

    // Deploy a new Covered Call Factory
    callBeacon = new HookUpgradeableBeacon(
      address(callImplv1),
      address(protocol),
      PermissionConstants.CALL_UPGRADER
    );
    HookCoveredCallFactory callFactory = new HookCoveredCallFactory(
      protocolAddress,
      address(callBeacon),
      preApprovedOperator
    );
    vm.prank(address(admin));
    protocol.setCoveredCallFactory(address(callFactory));
    
    // make a call insturment for our token
    vm.prank(address(admin));
    calls = IHookCoveredCall(callFactory.makeCallInstrument(address(token)));
  }

  function useImplV1() public {
    vm.prank(admin);
    callBeacon.upgradeTo(address(callImplv1));
  }

  function useImplV2() public {
    vm.prank(admin);
    callBeacon.upgradeTo(address(callImplv2));
  }

  // Mint with erc721; burn expired option; following mint will fail [expected]
  function testControl() public {
    // mint first call option
    vm.startPrank(address(writer));

    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint32 afterExpiration = uint32(baseTime) + 3.1 days;

    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 2, 1000, expiration);
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // call option #1 expires
    vm.warp(afterExpiration);
    calls.burnExpiredOption(optionId);

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
    vm.expectRevert("_mOWV-previous option must be settled");
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }

  // Mint with erc721; burn expired option; "upgrade" to impl1; following mint will fail
  function testExpirement1() public {
    // mint first call option
    vm.startPrank(address(writer));

    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint32 afterExpiration = uint32(baseTime) + 3.1 days;

    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 2, 1000, expiration);
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // call option #1 expires
    vm.warp(afterExpiration);
    calls.burnExpiredOption(optionId);

    vm.stopPrank();
    // Upgrade to call impl 1
    vm.expectEmit(true, true, true, true);
    emit Upgraded(address(callImplv1));
    useImplV1();
    vm.startPrank(address(writer));

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

    // mint second call option - will fail because first option never settled
    vm.expectRevert("_mOWV-previous option must be settled");
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }

  // Mint with erc721; burn expired option; upgrade to impl2; mint new option
  function testExpirement2() public {
    // mint first call option
    vm.startPrank(address(writer));

    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;
    uint32 afterExpiration = uint32(baseTime) + 3.1 days;

    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 2, 1000, expiration);
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // call option #1 expires
    vm.warp(afterExpiration);
    calls.burnExpiredOption(optionId);

    vm.stopPrank();
    // Upgrade to call impl 2
    useImplV2();
    vm.startPrank(address(writer));

    // mint second option
    uint32 expiration2 = expiration + 3 days;

    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 1, 3, 1000, expiration2);
    callImplv2.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration2
    );
    vm.stopPrank();
  }

    // Mint with erc721; get expiration; upgrade to impl2; get expiration again
  function testExpirement3() public {
    // mint first call option
    vm.startPrank(address(writer));

    uint256 baseTime = block.timestamp;
    uint32 expiration = uint32(baseTime) + 3 days;

    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 2, 1000, expiration);
    uint256 optionId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // get expiration
    uint256 e1 = HookCoveredCallImplV1(address(calls)).getExpiration(optionId);
    assertEq(uint32(e1), expiration);

    vm.stopPrank();
    // Upgrade to call impl 2
    useImplV2();
    vm.startPrank(address(writer));

    uint256 e2 = HookCoveredCallImplV2(address(calls)).getExpiration(optionId);
    assertEq(uint32(e2), expiration);

    vm.stopPrank();
  }

  function testExpirement4() public {
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

    // deploy v2 and upgrade back to v1
    vm.stopPrank();
    useImplV2();

    vm.startPrank(address(writer));
    uint256 baseTime2 = expiration;
    uint32 expiration2 = uint32(baseTime2) + 3 days;
    uint256 optionId2 = calls.mintWithErc721(
      address(token),
      underlyingTokenId2,
      1000,
      expiration2
    );

  }

}
