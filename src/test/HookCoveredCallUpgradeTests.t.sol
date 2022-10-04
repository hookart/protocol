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
    // Upgrade to call impl 2
    useImplV2();
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

    // mint second call option - should be successful
    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 3, 1000, expiration2);
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }

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

    // Attempt to burn expired option again
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

    // mint second call option - should be successful
    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 3, 1000, expiration2);
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }

  function testExpirement3() public {
    // Upgrade to call impl 2
    useImplV2();

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

    // burn call option
    ERC721Burnable(address(calls)).burn(optionId);

    // call option #1 expires
    vm.warp(afterExpiration);
    calls.burnExpiredOption(optionId);

    vm.stopPrank();
  }
  
  function testExpirement4() public {
    // Upgrade to call impl 2
    useImplV2();

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
    vm.expectEmit(true, true, true, true);
    emit CallCreated(address(writer), address(vault), 0, 3, 1000, expiration2);
    calls.mintWithEntitledVault(address(vault), 0, 1000, expiration2);
    vm.stopPrank();
  }
}
