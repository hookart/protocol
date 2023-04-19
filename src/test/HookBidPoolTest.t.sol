// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { HookProtocolTest, HookProtocol } from "./utils/base.t.sol";
import "./utils/mocks/PropertyValidator1.sol";
import "./utils/mocks/PropertyValidatorReverts.sol";
import "../HookBidPool.sol";
import "../lib/PoolOrders.sol";

import { EIP712 as EIP712Legacy } from "../mixin/EIP712.sol";

contract EIP712Imp is EIP712Legacy {
    constructor(address protocol) {
        setAddressForEipDomain(protocol);
    }

    function hash(bytes32 hash) public view returns (bytes32) {
        return _getEIP712Hash(hash);
    }
}

contract FakeInstrument {
    function getStrikePrice(uint256 id) public pure returns (uint256) {
        return 1;
    }

    function getExpiration(uint256 id) public view returns (uint256) {
        return block.timestamp + 79 days;
    }

    function safeTransferFrom(address from, address to, uint256 id) public {}
}

contract BidPoolTest is HookProtocolTest {
    HookBidPool bidPool;

    uint256 internal priceSignerPkey;
    uint256 internal orderSignerPkey;
    uint256 internal bidderPkey;

    address priceSigner;
    address orderSigner;
    address feeRecipient;

    address bidder;
    address seller;

    EIP712Imp eip712;

    // 1% = 0.01, 100 bips = 1%, 10000 bps = 100% == 1
    uint256 constant BPS_TO_DECIMAL = 10e14;

    event PauseUpdated(bool newState);
    event FeesUpdated(uint64 feeBips);
    event PriceOracleSignerUpdated(address oracle);
    event ProtocolFeeRecipientUpdated(address recipient);
    event OrderValidityOracleSignerUpdated(address oracle);
    event ProtocolAddressSet(address protocol);

    function setUp() public {
        setUpAddresses();
        setUpFullProtocol();

        priceSignerPkey = 0xA11CE;
        orderSignerPkey = 0xB11CE;
        bidderPkey = 0xB0B;

        priceSigner = vm.addr(priceSignerPkey);
        orderSigner = vm.addr(orderSignerPkey);
        bidder = vm.addr(bidderPkey);
        feeRecipient = address(0x8327);
        seller = address(0x45);

        bidPool = new HookBidPool(address(weth), admin, priceSigner, orderSigner, 500, feeRecipient, address(protocol));
        eip712 = new EIP712Imp(address(bidPool));
        vm.prank(address(admin));
        bidPool.setPoolPaused(false);
        // add address to the allowlist for minting
        vm.prank(address(admin));
        vaultFactory.makeMultiVault(address(token));

        // Set user balances
        vm.deal(address(bidder), 100 ether);

        // Mint underlying token
        underlyingTokenId = 0;
        token.mint(address(seller), underlyingTokenId);

        // Buyer swap 50 ETH <> 50 WETH
        vm.prank(address(bidder));
        weth.deposit{value: 50 ether}();

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(calls), true);
        vm.prank(address(seller));
        calls.setApprovalForAll(address(bidPool), true);

        // Buyer approve the bid pool to bid
        vm.prank(address(bidder));
        weth.approve(address(bidPool), 50 ether);
    }

    function testDeployerCannotChangeRoles() public {
        // make sure the background admin cannot change roles
        vm.stopPrank();
        bytes32 pauser = bidPool.PAUSER_ROLE();
        vm.expectRevert();
        bidPool.grantRole(pauser, address(0));

        bytes32 oracle = bidPool.ORACLE_ROLE();
        vm.expectRevert();
        bidPool.grantRole(oracle, address(0));

        bytes32 protocol = bidPool.PROTOCOL_ROLE();
        vm.expectRevert();
        bidPool.grantRole(protocol, address(0));

        bytes32 fees = bidPool.FEES_ROLE();
        vm.expectRevert();
        bidPool.grantRole(fees, address(0));
    }

    function testSetProtocol() public {
        vm.startPrank(address(admin));
        // deploy a new protocol

        HookProtocol protocol2 = new HookProtocol(
            admin,
            admin,
            admin,
            admin,
            admin,
            admin,
            address(weth)
        );

        vm.expectEmit(true, true, true, true);
        emit ProtocolAddressSet(address(protocol2));
        bidPool.setProtocol(address(protocol2));
    }

    function testSetProtocolNotOwner() public {
        // deploy a new protocol
        HookProtocol protocol2 = new HookProtocol(
            admin,
            admin,
            admin,
            admin,
            admin,
            admin,
            address(weth)
        );

        vm.startPrank(bidder);
        vm.expectRevert();
        emit ProtocolAddressSet(address(protocol2));
        bidPool.setProtocol(address(protocol2));
    }

    function testSetPriceOracleSigner() public {
        address newSigner = address(0x1234);
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit PriceOracleSignerUpdated(newSigner);
        bidPool.setPriceOracleSigner(newSigner);
    }

    function testSetPriceOracleSignerNotOwner() public {
        address newSigner = address(0x1234);
        vm.startPrank(bidder);
        vm.expectRevert();
        emit PriceOracleSignerUpdated(newSigner);
        bidPool.setPriceOracleSigner(newSigner);
    }

    function testSetOrderValidityOracleSigner() public {
        address newSigner = address(0x1234);
        vm.expectEmit(true, true, true, true);
        emit OrderValidityOracleSignerUpdated(newSigner);
        vm.startPrank(admin);
        bidPool.setOrderValidityOracleSigner(newSigner);
    }

    function testSetOrderValidityOracleSignerNotOwner() public {
        address newSigner = address(0x1234);
        vm.startPrank(bidder);
        vm.expectRevert();
        emit OrderValidityOracleSignerUpdated(newSigner);
        bidPool.setOrderValidityOracleSigner(newSigner);
    }

    function testSetFeeBips() public {
        uint64 newBips = 3737;
        vm.prank(address(admin));
        vm.expectEmit(true, true, true, true);
        emit FeesUpdated(newBips);
        bidPool.setFeeBips(newBips);
    }

    function testSetFeeBipsNotOwner() public {
        uint64 newBips = 3737;
        vm.startPrank(bidder);
        vm.expectRevert();
        emit FeesUpdated(newBips);
        bidPool.setFeeBips(newBips);
    }

    function testSetFeeBipsOverLimit() public {
        uint64 newBips = 10001;
        vm.expectRevert("Fee bips over 10000");
        emit FeesUpdated(newBips);
        vm.prank(address(admin));
        bidPool.setFeeBips(newBips);
    }

    function testSetFeeRecipient() public {
        address newRecipient = address(0x1234);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeRecipientUpdated(newRecipient);
        vm.prank(address(admin));
        bidPool.setFeeRecipient(newRecipient);
    }

    function testSetFeeRecipientNotOwner() public {
        address newRecipient = address(0x1234);
        vm.startPrank(bidder);
        vm.expectRevert();
        emit ProtocolFeeRecipientUpdated(newRecipient);
        bidPool.setFeeRecipient(newRecipient);
    }

    function testSetProtocolPaused() public {
        vm.startPrank(address(admin));
        vm.expectEmit(true, true, true, true);
        emit PauseUpdated(true);
        bidPool.setPoolPaused(true);
    }

    function testSetProtocolPausedNotOwner() public {
        vm.startPrank(bidder);
        vm.expectRevert();
        emit PauseUpdated(true);
        bidPool.setPoolPaused(true);
    }

    function testSetProtocolPausedAlreadyPaused() public {
        vm.startPrank(address(admin));
        vm.expectEmit(true, true, true, true);
        emit PauseUpdated(true);
        bidPool.setPoolPaused(true);
        vm.expectRevert("cannot set to current state");
        bidPool.setPoolPaused(true);
    }

    function testSetProtocolPausedAlreadyNotPaused() public {
        vm.expectRevert("cannot set to current state");
        vm.prank(address(admin));
        bidPool.setPoolPaused(false);
    }

    function testBS() public {
        (uint256 call, uint256 put) = BlackScholes.optionPrices(
            BlackScholes.BlackScholesInputs({
                timeToExpirySec: 1209600, // seconds in 2 weeks
                volatilityDecimal: 700000000000000000, // 0.70
                spotDecimal: 10000000000000000000, // 10
                strikePriceDecimal: 12000000000000000000, // 12
                rateDecimal: 50000000000000000 // 0.05
            })
        );

        assertEq(call, 65919925077818231, "call price should be ~.065");
        assertEq(put, 2042928280277283091, "bs should be 0");
    }

    function _signOrder(PoolOrders.Order memory order, uint256 pkey) internal returns (bytes memory, bytes32 hash) {
        bytes32 hash = PoolOrders.getPoolOrderStructHash(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkey, eip712.hash(hash));
        return (combineSignature(v, r, s), eip712.hash(hash));
    }

    function combineSignature(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        return abi.encodePacked(r, s, v);
    }

    function _makeAssetPriceClaim(uint256 assetPrice) internal returns (HookBidPool.AssetPriceClaim memory) {
        HookBidPool.AssetPriceClaim memory claim = HookBidPool.AssetPriceClaim({
            assetPriceInWei: assetPrice,
            priceObservedTimestamp: uint32(block.timestamp) - 30 seconds,
            goodTilTimestamp: uint32(block.timestamp) + 20 days,
            signature: new bytes(65)
        });

        (uint8 va, bytes32 ar, bytes32 sa) = vm.sign(
            priceSignerPkey,
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n96",
                    abi.encode(claim.assetPriceInWei, claim.priceObservedTimestamp, claim.goodTilTimestamp)
                )
            )
        );

        claim.signature = combineSignature(va, ar, sa);
        return claim;
    }

    function _makeInvalidAssetPriceClaim(uint256 assetPrice) internal returns (HookBidPool.AssetPriceClaim memory) {
        HookBidPool.AssetPriceClaim memory claim = HookBidPool.AssetPriceClaim({
            assetPriceInWei: assetPrice,
            priceObservedTimestamp: uint32(block.timestamp) - 30 seconds,
            goodTilTimestamp: uint32(block.timestamp) + 20 days,
            signature: new bytes(65)
        });

        (uint8 va, bytes32 ar, bytes32 sa) = vm.sign(
            bidderPkey,
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n96",
                    abi.encode(claim.assetPriceInWei, claim.priceObservedTimestamp, claim.goodTilTimestamp)
                )
            )
        );

        claim.signature = combineSignature(va, ar, sa);
        return claim;
    }

    function _makeDefaultOrder() internal returns (PoolOrders.Order memory) {
        PoolOrders.Property[] memory properties;
        return PoolOrders.Order({
            direction: PoolOrders.OrderDirection.BUY,
            maker: bidder,
            orderExpiry: uint32(block.timestamp) + 2 weeks,
            nonce: 1405,
            size: 1,
            optionType: PoolOrders.OptionType.CALL,
            maxStrikePriceMultiple: 0,
            minOptionDuration: 1 days,
            maxOptionDuration: 80 days,
            maxPriceSignalAge: 0,
            optionMarketAddress: address(calls),
            impliedVolBips: 10000,
            nftProperties: properties,
            skewDecimal: 0,
            riskFreeRateBips: 500
        });
    }

    function _makeOrderClaim(bytes32 orderHash) internal returns (HookBidPool.OrderValidityOracleClaim memory) {
        bytes memory claimEncoded = abi.encode(orderHash, block.timestamp + 30);

        bytes32 claimHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n64", (claimEncoded)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(orderSignerPkey, claimHash);

        return HookBidPool.OrderValidityOracleClaim({
            signature: combineSignature(v, r, s),
            orderHash: orderHash,
            goodTilTimestamp: uint32(block.timestamp) + 30
        });
    }

    function _makeInvalidOrderClaim(bytes32 orderHash) internal returns (HookBidPool.OrderValidityOracleClaim memory) {
        bytes memory claimEncoded = abi.encode(orderHash, block.timestamp + 30);

        bytes32 claimHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(claimEncoded)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bidderPkey, claimHash);

        return HookBidPool.OrderValidityOracleClaim({
            signature: combineSignature(v, r, s),
            orderHash: orderHash,
            goodTilTimestamp: uint32(block.timestamp) + 30
        });
    }

    function testAcceptBid() public {
        vm.warp(block.timestamp + 20 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 30 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);
        assertTrue(calls.ownerOf(optionId) == address(seller), "owner should own the option");

        PoolOrders.Order memory order = _makeDefaultOrder();

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        uint256 initialBalanceBidder = weth.balanceOf(address(bidder));
        uint256 initialBalanceSeller = weth.balanceOf(address(seller));
        uint256 initialBalanceFeeRecipient = weth.balanceOf(address(feeRecipient));
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        uint256 finalBalanceBidder = weth.balanceOf(bidder);
        uint256 finalBalanceSeller = weth.balanceOf(seller);
        uint256 finalBalanceFeeRecipient = weth.balanceOf(address(feeRecipient));

        assertEq(
            finalBalanceFeeRecipient,
            initialBalanceFeeRecipient + 0.0005 ether,
            "fee recipient should have received the 500 bps fee"
        );
        assertEq(finalBalanceBidder, initialBalanceBidder - 0.0105 ether, "bidder should have paid the premium");
        assertEq(finalBalanceSeller, initialBalanceSeller + 0.01 ether, "seller should have received the premium");
        assertTrue(calls.ownerOf(optionId) == address(bidder), "bidder should own the option");
    }

    function testBidTooLow() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        order.impliedVolBips = 5; // set a very low vol for the order
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("order not high enough for the ask");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOrderExpired() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 40 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.impliedVolBips = 10000;
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.warp(block.timestamp + 3 weeks); // 1 week after order expiry

        vm.expectRevert("Order is expired");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.0000001 ether, optionId
        );
    }

    function testNotBuyOrder() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 90 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Property[] memory properties;
        PoolOrders.Order memory order = PoolOrders.Order({
            direction: PoolOrders.OrderDirection.SELL,
            maker: bidder,
            orderExpiry: uint32(block.timestamp) + 2 weeks,
            nonce: 1405,
            size: 1,
            optionType: PoolOrders.OptionType.CALL,
            maxStrikePriceMultiple: 0,
            minOptionDuration: 1 days,
            maxOptionDuration: 80 days,
            maxPriceSignalAge: 0,
            optionMarketAddress: address(calls),
            impliedVolBips: 5000,
            nftProperties: properties,
            skewDecimal: 0,
            riskFreeRateBips: 500
        });

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Order is not a buy order");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOptionExpired() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 2 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        vm.warp(block.timestamp + 1 days + 1 hours); // warp to within 1 day of expiry

        PoolOrders.Order memory order = _makeDefaultOrder();
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Option is too close to or past expiry");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOptionTooCloseToExpiry() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 90 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        // Max option duration is 80 days

        PoolOrders.Order memory order = _makeDefaultOrder();
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Option is too far from expiry");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOptionTooFarFromExpiry() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 90 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        // Max option duration is 80 days

        PoolOrders.Order memory order = _makeDefaultOrder();
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Option is too far from expiry");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testAcceptSkewedBidDefaultBidTooLow() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 30 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        order.impliedVolBips = 3000; // set a low vol (15%) for order
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("order not high enough for the ask");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        order.skewDecimal = 25000 * BPS_TO_DECIMAL; // will increase vol to 20%
        (signature, orderHash) = _signOrder(order, bidderPkey);

        uint256 initialBalanceBidder = weth.balanceOf(address(bidder));
        uint256 initialBalanceSeller = weth.balanceOf(address(seller));
        uint256 initialBalanceFeeRecipient = weth.balanceOf(address(feeRecipient));
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
        uint256 finalBalanceBidder = weth.balanceOf(bidder);
        uint256 finalBalanceSeller = weth.balanceOf(seller);
        uint256 finalBalanceFeeRecipient = weth.balanceOf(address(feeRecipient));

        assertEq(
            finalBalanceFeeRecipient,
            initialBalanceFeeRecipient + 0.0005 ether,
            "fee recipient should have received the 500 bps fee"
        );
        assertEq(finalBalanceBidder, initialBalanceBidder - 0.0105 ether, "bidder should have paid the premium");
        assertEq(finalBalanceSeller, initialBalanceSeller + 0.01 ether, "seller should have received the premium");
        assertTrue(calls.ownerOf(optionId) == address(bidder), "bidder should own the option");
    }

    function testBidTooLowWithFees() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 79 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        order.impliedVolBips = 4625; // set a very low vol for the order
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("order not high enough for the ask");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        vm.stopPrank();
        vm.prank(admin);
        bidPool.setFeeBips(0);

        // should work with no fees
        vm.prank(seller);
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOptionDurationTooShort() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.minOptionDuration = 10 days;

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Option is too close to or past expiry");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOptionDurationTooFar() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 50 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.maxOptionDuration = 10 days;

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Option is too far from expiry");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testPriceSignalTooOld() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 50 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.maxPriceSignalAge = 10;

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Price signal is too old");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testStrikeTooHigh() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 50 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.4 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.maxStrikePriceMultiple = 5e17;

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("option is too far out of the money");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.1 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.35 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOrderIsCanceled() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 50 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.4 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.stopPrank();
        vm.prank(bidder);
        bidPool.cancelOrder(order);

        vm.prank(seller);
        vm.expectRevert("Order is cancelled");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.3 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testOrderSize() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 50 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.4 ether, expiration);
        token.mint(address(seller), underlyingTokenId + 1);
        uint256 optionId1 = calls.mintWithErc721(address(token), underlyingTokenId + 1, 0.4 ether, expiration);
        token.mint(address(seller), underlyingTokenId + 2);
        uint256 optionId2 = calls.mintWithErc721(address(token), underlyingTokenId + 2, 0.4 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        order.size = 2;
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.3 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.29 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId1
        );

        vm.expectRevert("Order is filled");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.3 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId1
        );
    }

    function testInvalidSignature() public {
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(
            address(0x00000000000076A84feF008CDAbe6409d2FE638B),
            abi.encodeWithSelector(
                IDelegationRegistry.checkDelegateForContract.selector,
                address(priceSigner),
                address(bidder),
                address(bidPool)
            ),
            abi.encode(false)
        );
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, priceSignerPkey);

        vm.expectRevert("Order signature is invalid");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testValidDelegate() public {
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(
            address(0x00000000000076A84feF008CDAbe6409d2FE638B),
            abi.encodeWithSelector(
                IDelegationRegistry.checkDelegateForContract.selector,
                address(priceSigner),
                address(bidder),
                address(bidPool)
            ),
            abi.encode(true)
        );
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 30 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, priceSignerPkey);

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testNotSignedByOrderValidityOracle() public {
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(
            address(0x00000000000076A84feF008CDAbe6409d2FE638B),
            abi.encodeWithSelector(
                IDelegationRegistry.checkDelegateForContract.selector,
                address(priceSigner),
                address(bidder),
                address(bidPool)
            ),
            abi.encode(true)
        );
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, priceSignerPkey);

        vm.expectRevert("Claim is not signed by the orderValidityOracle");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeInvalidOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testNotSignedByPriceOracle() public {
        vm.warp(block.timestamp + 1 days);
        vm.mockCall(
            address(0x00000000000076A84feF008CDAbe6409d2FE638B),
            abi.encodeWithSelector(
                IDelegationRegistry.checkDelegateForContract.selector,
                address(priceSigner),
                address(bidder),
                address(bidPool)
            ),
            abi.encode(true)
        );
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Claim is not signed by the priceOracle");
        bidPool.sellOption(
            order, signature, _makeInvalidAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testExpiredOrderValidityOracleSignature() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);
        HookBidPool.OrderValidityOracleClaim memory claim = _makeOrderClaim(orderHash);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("Claim is expired");
        bidPool.sellOption(order, signature, _makeAssetPriceClaim(0.2 ether), claim, 0.01 ether, optionId);
    }

    function testPropertyValidatorReverts() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 5 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        IPropertyValidator validator = new PropertyValidatorReverts();
        order.nftProperties = new PoolOrders.Property[](1);
        order.nftProperties[0] = PoolOrders.Property(validator, abi.encodePacked());
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        vm.expectRevert("Property validation failed for the provided optionId");
        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );
    }

    function testPropertyValidatorSuccess() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 30 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        IPropertyValidator validator = new PropertyValidator1();
        order.nftProperties = new PoolOrders.Property[](1);
        order.nftProperties[0] = PoolOrders.Property(
            validator, abi.encode(0, Types.Operation.Ignore, 0, Types.Operation.Ignore, false, 0, 0)
        );
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        assertEq(calls.ownerOf(optionId), address(bidder), "Option should be transferred to the bidder");
    }

    function testPropertyValidatorSuccessNullValidator() public {
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(seller));
        uint32 expiration = uint32(block.timestamp) + 20 days;
        uint256 optionId = calls.mintWithErc721(address(token), underlyingTokenId, 0.22 ether, expiration);

        PoolOrders.Order memory order = _makeDefaultOrder();

        address validator = address(0x0);
        order.nftProperties = new PoolOrders.Property[](1);
        order.nftProperties[0] = PoolOrders.Property(
            IPropertyValidator(validator), abi.encode(0, Types.Operation.Ignore, 0, Types.Operation.Ignore, false, 0, 0)
        );
        (bytes memory signature, bytes32 orderHash) = _signOrder(order, bidderPkey);

        bidPool.sellOption(
            order, signature, _makeAssetPriceClaim(0.2 ether), _makeOrderClaim(orderHash), 0.01 ether, optionId
        );

        assertEq(calls.ownerOf(optionId), address(bidder), "Option should be transferred to the bidder");
    }


    function testEnsureConstructorDoesNotHaveAdminRole() public {
        assertFalse(bidPool.hasRole(bidPool.DEFAULT_ADMIN_ROLE(), address(this)), "deployer should not have admin role");
    }
}
