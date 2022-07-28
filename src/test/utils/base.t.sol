// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./tokens/TestERC721.sol";
import "./tokens/WETH.sol";
import "../../HookUpgradeableBeacon.sol";
import "../../HookCoveredCallFactory.sol";
import "../../HookCoveredCallImplV1.sol";
import "../../HookUpgradeableBeacon.sol";
import "../../HookERC721VaultFactory.sol";
import "../../HookERC721VaultImplV1.sol";
import "../../HookERC721MultiVaultImplV1.sol";
import "../../HookUpgradeableBeacon.sol";
import "../../HookProtocol.sol";

import "../../lib/Entitlements.sol";
import "../../lib/Signatures.sol";
import "../../mixin/EIP712.sol";
import "../../mixin/PermissionConstants.sol";

import "../../interfaces/IHookProtocol.sol";
import "../../interfaces/IHookCoveredCall.sol";

/// @notice Utils to setup the protocol to build various test cases
/// @author Regynald Augustin -- regy@hook.xyz
contract HookProtocolTest is Test, EIP712, PermissionConstants {
  address internal admin;
  address internal buyer;
  uint256 internal writerpkey;
  address internal writer;
  address internal firstBidder;
  address internal secondBidder;
  IHookCoveredCall calls;
  // can use this identifier to call fns not on the interface
  HookCoveredCallImplV1 callInternal;
  TestERC721 internal token;
  WETH internal weth;
  uint256 internal underlyingTokenId;
  address internal protocolAddress;
  HookProtocol protocol;
  uint256 internal optionTokenId;
  address internal preApprovedOperator;
  HookERC721VaultFactory vaultFactory;

  event CallCreated(
    address writer,
    address vaultAddress,
    uint256 assetId,
    uint256 optionId,
    uint256 strikePrice,
    uint256 expiration
  );

  event CallSettled(uint256 optionId);

  event CallReclaimed(uint256 optionId);

  event ExpiredCallBurned(uint256 optionId);

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

  function setUpFullProtocol() public {
    weth = new WETH();
    protocol = new HookProtocol(
      admin,
      admin,
      admin,
      admin,
      admin,
      admin,
      address(weth)
    );
    protocolAddress = address(protocol);
    // set the operator to a new protocol to make it a contract
    preApprovedOperator = address(weth);
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

    vaultFactory = new HookERC721VaultFactory(
      protocolAddress,
      address(vaultBeacon),
      address(multiVaultBeacon)
    );
    vm.prank(address(admin));
    protocol.setVaultFactory(address(vaultFactory));

    // Deploy a new Covered Call Factory
    HookCoveredCallImplV1 callImpl = new HookCoveredCallImplV1();
    HookUpgradeableBeacon callBeacon = new HookUpgradeableBeacon(
      address(callImpl),
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
    vm.prank(address(admin));

    // make a call insturment for our token
    calls = IHookCoveredCall(callFactory.makeCallInstrument(address(token)));
    callInternal = HookCoveredCallImplV1(address(calls));
  }

  function setUpMintOption() public {
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
    optionTokenId = calls.mintWithErc721(
      address(token),
      underlyingTokenId,
      1000,
      expiration
    );

    // Assume that the writer somehow sold the option NFT to the buyer.
    // Outside of the scope of these tests.
    calls.safeTransferFrom(writer, buyer, optionTokenId);
    vm.stopPrank();
  }

  function setUpOptionBids() public {
    vm.deal(address(firstBidder), 1 ether);

    vm.deal(address(secondBidder), 1 ether);

    vm.warp(block.timestamp + 2.1 days);

    vm.prank(firstBidder);
    calls.bid{value: 0.1 ether}(optionTokenId);

    vm.prank(secondBidder);
    calls.bid{value: 0.2 ether}(optionTokenId);

    // Fast forward to beyond the expiration date.
    vm.warp(block.timestamp + 3.1 days);
  }

  function makeSignature(
    uint256 tokenId,
    uint32 expiry,
    address _writer
  ) internal returns (Signatures.Signature memory) {
    address va = address(
      vaultFactory.findOrCreateVault(address(token), tokenId)
    );

    uint32 assetId = 0;
    if (
      va ==
      Create2.computeAddress(
        BeaconSalts.multiVaultSalt(address(token)),
        BeaconSalts.ByteCodeHash,
        address(vaultFactory)
      )
    ) {
      // If the vault is a multi-vault, it requires that the assetId matches the
      // tokenId, instead of having a standard assetI of 0
      assetId = uint32(tokenId);
    }

    bytes32 structHash = Entitlements.getEntitlementStructHash(
      Entitlements.Entitlement({
        beneficialOwner: address(_writer),
        operator: address(calls),
        vaultAddress: va,
        assetId: assetId,
        expiry: expiry
      })
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      writerpkey,
      _getEIP712Hash(structHash)
    );
    Signatures.Signature memory sig = Signatures.Signature({
      signatureType: Signatures.SignatureType.EIP712,
      v: v,
      r: r,
      s: s
    });
    return sig;
  }
}
