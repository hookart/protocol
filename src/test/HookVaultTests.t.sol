// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./utils/base.t.sol";
import "../interfaces/IHookERC721VaultFactory.sol";

import "../lib/Entitlements.sol";
import "../lib/Signatures.sol";
import "../mixin/EIP712.sol";

import "./utils/mocks/FlashLoan.sol";

/// @notice Integration tests for the Hook Solo Vault
/// @author Regynald Augustin -- regy@hook.xyz
contract HookVaultTestsBase is HookProtocolTest {
  IHookERC721VaultFactory vault;
  uint32 tokenStartIndex = 300;

  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();
    vault = IHookERC721VaultFactory(protocol.vaultContract());
  }

  function createVaultandAsset()
    internal
    returns (address, uint32)
  {
    vm.startPrank(admin);
    tokenStartIndex += 1;
    uint32 tokenId = tokenStartIndex;
    token.mint(address(writer), tokenId);
    address vaultAddress = address(vault.findOrCreateVault(address(token), tokenId));
    vm.stopPrank();
    return (vaultAddress, tokenId);
  }

  function makeEntitlementAndSignature(
    uint256 ownerPkey,
    address operator,
    address vaultAddress,
    uint32 _expiry
  )
    internal
    returns (
      Entitlements.Entitlement memory,
      Signatures.Signature memory
    )
  {
    address ownerAdd = vm.addr(writerpkey);

    Entitlements.Entitlement memory entitlement = Entitlements.Entitlement({
      beneficialOwner: ownerAdd,
      operator: operator,
      vaultAddress: vaultAddress,
      assetId: 0,
      expiry: _expiry
    });

    bytes32 structHash = Entitlements.getEntitlementStructHash(entitlement);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      ownerPkey,
      _getEIP712Hash(structHash)
    );

    Signatures.Signature memory sig = Signatures.Signature({
      signatureType: Signatures.SignatureType.EIP712,
      v: v,
      r: r,
      s: s
    });
    return (entitlement, sig);
  }
}

contract HookVaultTestFlash is HookVaultTestsBase {
  function testBasicFlashLoan() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanSuccess();

    vm.prank(writer);
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashLoanFailsIfDisabled() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanSuccess();
    vm.prank(admin);
    protocol.setCollectionConfig(
      address(token),
      keccak256("vault.flashLoanDisabled"),
      true
    );
    vm.prank(writer);
    vm.expectRevert(
      "flashLoan -- flashLoan feature disabled for this contract"
    );
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashLoanAlternateApprove() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanApproveForAll();

    vm.prank(writer);
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashCantReturnFalse() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanReturnsFalse();

    vm.prank(writer);
    vm.expectRevert("flashLoan -- the flash loan contract must return true");
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashMustApprove() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanDoesNotApprove();

    vm.prank(writer);
    vm.expectRevert("ERC721: transfer caller is not owner nor approved");
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashCantBurn() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanBurnsAsset();

    vm.prank(writer);
    vm.expectRevert("ERC721: operator query for nonexistent token");
    vaultImpl.flashLoan(0, address(flashLoan), " ");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashCallData() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanVerifyCalldata();

    vm.prank(writer);
    vaultImpl.flashLoan(0, address(flashLoan), "hello world");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashWillRevert() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanVerifyCalldata();

    vm.prank(writer);
    vm.expectRevert("should check helloworld");
    vaultImpl.flashLoan(0, address(flashLoan), "hello world wrong!");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }
}

contract HookVaultTestEntitlement is HookVaultTestsBase {
  function testImposeEntitlmentOnTransferIn() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    assertTrue(
      vaultImpl.getHoldsAsset(0),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner(0) == writer,
      "writer should be the beneficial owner"
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );
  }

  function testImposeEntitlementAfterInitialTransfer() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(writer, vaultAddress, tokenId);

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    // impose the entitlement onto the vault
    vm.prank(mockContract);
    vaultImpl.imposeEntitlement(
      entitlement.operator,
      uint32(entitlement.expiry),
      uint32(entitlement.assetId),
      sig.v,
      sig.r,
      sig.s
    );

    assertTrue(
      vaultImpl.getHoldsAsset(0),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner(0) == writer,
      "writer should be the beneficial owner"
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    // verify that beneficial owner cannot withdrawl
    // during an active entitlement.
    vm.expectRevert(
      "withdrawalAsset -- the asset cannot be withdrawn with an active entitlement"
    );
    vm.prank(writer);
    vaultImpl.withdrawalAsset(0);
  }

  function testEntitlementGoesAwayAfterExpiration() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    vm.warp(block.timestamp + 2 days);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(0),
      "there should not be any active entitlements"
    );

    vm.prank(writer);
    vaultImpl.withdrawalAsset(0);
    assertTrue(
      !vaultImpl.getHoldsAsset(0),
      "the token should not be owned by the vault"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "token should be owned by the writer"
    );
  }

  function testEntitlementCanBeClearedByOperator() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.prank(mockContract);
    vaultImpl.clearEntitlement(0);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(0),
      "there should not be any active entitlements"
    );

    // check that the owner can actually withdrawl
    vm.prank(writer);
    vaultImpl.withdrawalAsset(0);
    assertTrue(
      !vaultImpl.getHoldsAsset(0),
      "the token should not be owned by the vault"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "token should be owned by the writer"
    );
  }

  function testNewEntitlementPossibleAferExpiredEntitlement() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    vm.warp(block.timestamp + 2 days);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(0),
      "there should not be any active entitlements"
    );

    // asset is not withdrawn, try to add a new entitlement
    uint32 expiration2 = uint32(block.timestamp + 10 days);

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        expiration2
      );
    vaultImpl.imposeEntitlement(
      entitlement2.operator,
      uint32(entitlement2.expiry),
      uint32(entitlement2.assetId),
      sig2.v,
      sig2.r,
      sig2.s
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be a new active entitlement"
    );
  }

  function testNewEntitlementPossibleAfterClearedEntitlement() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    vm.prank(mockContract);
    vaultImpl.clearEntitlement(0);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(0),
      "there should not be any active entitlements"
    );

    uint32 expiration2 = uint32(block.timestamp + 3 days);

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        expiration2
      );

    vaultImpl.imposeEntitlement(
      entitlement2.operator,
      uint32(entitlement2.expiry),
      uint32(entitlement2.assetId),
      sig2.v,
      sig2.r,
      sig2.s
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be a new active entitlement"
    );
  }

  function testOnlyOneEntitlementAllowed() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(3333);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    // transfer in with first entitlement
    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    address mockContract2 = address(35553445);
    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    uint32 expiration2 = uint32(block.timestamp + 3 days);

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract2,
        vaultAddress,
        expiration2
      );

    vm.prank(mockContract2);
    vm.expectRevert(
      "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
    );

    vaultImpl.imposeEntitlement(
      entitlement2.operator,
      uint32(entitlement2.expiry),
      uint32(entitlement2.assetId),
      sig2.v,
      sig2.r,
      sig2.s
    );
  }

  function testBeneficialOwnerCannotClearEntitlement() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69420);
    uint32 expiration = uint32(block.timestamp) + 1 days;
    // transfer in with first entitlement
    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(0),
      "there should be an active entitlement"
    );

    vm.prank(writer);
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement(0);

    vm.prank(address(55566677788899911));
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement(0);
  }
}

contract HookVaultTestsDistribution is HookVaultTestsBase {
  function testClearAndDistributeReturnsNFT() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(0, writer);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(0),
      "there should not be any active entitlements"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "Token should be returned to the owner"
    );
  }

  function testAirdropsCanBeDisbled() public {
    (address vaultAddress, ) = createVaultandAsset();

    vm.prank(admin);
    protocol.setCollectionConfig(
      address(token),
      keccak256("vault.airdropsProhibited"),
      true
    );

    TestERC721 token2 = new TestERC721();
    vm.expectRevert(
      "onERC721Received -- non-escrow asset returned when airdrops are disabled"
    );
    token2.mint(vaultAddress, 0);
  }

  function testAirdropsAllowedWhenEnabled() public {
    (address vaultAddress, ) = createVaultandAsset();

    vm.prank(admin);
    protocol.setCollectionConfig(
      address(token),
      keccak256("vault.airdropsProhibited"),
      false
    );

    TestERC721 token2 = new TestERC721();
    token2.mint(vaultAddress, 0);
    assertTrue(token2.ownerOf(0) == vaultAddress, "vault should hold airdrop");
  }

  function testClearAndDistributeDoesNotReturnToWrongPerson() public {
    (address vaultAddress, uint32 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint32 expiration = uint32(block.timestamp) + 1 days;

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(writer, mockContract, expiration)
    );
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.expectRevert(
      "clearEntitlementAndDistribute -- Only the beneficial owner can receive the asset"
    );
    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(0, address(0x033333344545));
  }
}
