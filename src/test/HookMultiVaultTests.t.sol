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

contract HookMultiVaultTests is HookProtocolTest {
  IHookERC721VaultFactory vault;
  uint256 tokenStartIndex = 300;

  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();
    vault = IHookERC721VaultFactory(protocol.vaultContract());
  }

  function createVaultandAsset()
    internal
    returns (address vaultAddress, uint256 tokenId)
  {
    vm.startPrank(admin);
    tokenStartIndex += 1;
    tokenId = tokenStartIndex;
    token.mint(address(writer), tokenId);
    vault.makeMultiVault(address(token));
    vaultAddress = address(vault.findOrCreateVault(address(token), tokenId));
    vm.stopPrank();
    return (vaultAddress, tokenId);
  }

  function makeEntitlementAndSignature(
    uint256 ownerPkey,
    address operator,
    address vaultAddress,
    uint256 tokenId,
    uint256 _expiry
  )
    internal
    returns (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory signature
    )
  {
    address ownerAdd = vm.addr(writerpkey);

    entitlement = Entitlements.Entitlement({
      beneficialOwner: ownerAdd,
      operator: operator,
      vaultAddress: vaultAddress,
      assetId: tokenId,
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

  function testImposeEntitlmentOnTransferIn() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    assertTrue(
      vaultImpl.getHoldsAsset(tokenId),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner(tokenId) == writer,
      "writer should be the beneficial owner"
    );
    (bool active, address operator) = vaultImpl.getCurrentEntitlementOperator(
      tokenId
    );
    assertTrue(active, "there should be an active entitlement");
    assertTrue(
      operator == mockContract,
      "active entitlement is to correct person"
    );
  }

  function testBasicFlashLoan() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanSuccess();

    vm.prank(writer);
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashLoanFailsIfDisabled() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
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
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashLoanAlternateApprove() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanApproveForAll();

    vm.prank(writer);
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashCantReturnFalse() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanReturnsFalse();

    vm.prank(writer);
    vm.expectRevert("flashLoan -- the flash loan contract must return true");
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashMustApprove() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanDoesNotApprove();

    vm.prank(writer);
    vm.expectRevert("ERC721: transfer caller is not owner nor approved");
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testBasicFlashCantBurn() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanBurnsAsset();

    vm.prank(writer);
    vm.expectRevert("ERC721: operator query for nonexistent token");
    vaultImpl.flashLoan(tokenId, address(flashLoan), " ");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashCallData() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanVerifyCalldata();

    vm.prank(writer);
    vaultImpl.flashLoan(tokenId, address(flashLoan), "hello world");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testFlashWillRevert() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    IERC721FlashLoanReceiver flashLoan = new FlashLoanVerifyCalldata();

    vm.prank(writer);
    vm.expectRevert("should check helloworld");
    vaultImpl.flashLoan(tokenId, address(flashLoan), "hello world wrong!");
    // operation reverted, so we can still mess with the asset
    assertTrue(
      token.ownerOf(tokenId) == vaultAddress,
      "good flashloan should work"
    );
  }

  function testImposeEntitlementAfterInitialTransfer() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(writer, vaultAddress, tokenId);

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    // impose the entitlement onto the vault
    vm.prank(mockContract);
    vaultImpl.imposeEntitlement(entitlement, sig);

    assertTrue(
      vaultImpl.getHoldsAsset(tokenId),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner(tokenId) == writer,
      "writer should be the beneficial owner"
    );
    (bool active, address operator) = vaultImpl.getCurrentEntitlementOperator(
      tokenId
    );
    assertTrue(active, "there should be an active entitlement");
    assertTrue(
      operator == mockContract,
      "active entitlement is to correct person"
    );

    // verify that beneficial owner cannot withdrawl
    // during an active entitlement.
    vm.expectRevert(
      "withdrawalAsset -- the asset canot be withdrawn with an active entitlement"
    );
    vm.prank(writer);
    vaultImpl.withdrawalAsset(tokenId);
  }

  function testEntitlementGoesAwayAfterExpiration() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    (bool active, address operator) = vaultImpl.getCurrentEntitlementOperator(
      tokenId
    );
    assertTrue(active, "there should be an active entitlement");
    assertTrue(
      operator == mockContract,
      "active entitlement is to correct person"
    );
    vm.warp(block.timestamp + 2 days);

    (active, operator) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(!active, "there should not be an active entitlement");

    vm.prank(writer);
    vaultImpl.withdrawalAsset(tokenId);
    assertTrue(
      !vaultImpl.getHoldsAsset(tokenId),
      "the token should not be owned by the vault"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "token should be owned by the writer"
    );
  }

  function testEntitlementCanBeClearedByOperator() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    vm.prank(mockContract);
    vaultImpl.clearEntitlement(tokenId);

    (bool active, ) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(!active, "there should not be an active entitlement");

    // check that the owner can actually withdrawl
    vm.prank(writer);
    vaultImpl.withdrawalAsset(tokenId);
    assertTrue(
      !vaultImpl.getHoldsAsset(tokenId),
      "the token should not be owned by the vault"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "token should be owned by the writer"
    );
  }

  function testNewEntitlementPossibleAferExpiredEntitlement() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    (bool active, address operator) = vaultImpl.getCurrentEntitlementOperator(
      tokenId
    );
    assertTrue(active, "there should be an active entitlement");

    vm.warp(block.timestamp + 2 days);

    (active, operator) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(!active, "there should not be an active entitlement");

    // asset is not withdrawn, try to add a new entitlement
    uint256 expiration2 = block.timestamp + 10 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration2
      );
    vaultImpl.imposeEntitlement(entitlement2, sig2);
    (active, operator) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(active, "there should be an active entitlement");
  }

  function testNewEntitlementPossibleAfterClearedEntitlement() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    (bool active, address operator) = vaultImpl.getCurrentEntitlementOperator(
      tokenId
    );
    assertTrue(active, "there should be an active entitlement");
    vm.prank(mockContract);
    vaultImpl.clearEntitlement(tokenId);

    (active, operator) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(!active, "there should not be an active entitlement");

    uint256 expiration2 = block.timestamp + 3 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration2
      );

    vaultImpl.imposeEntitlement(entitlement2, sig2);
    (active, operator) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(active, "there should  be an active entitlement");
  }

  function testOnlyOneEntitlementAllowed() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(3333);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    // transfer in with first entitlement
    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    address mockContract2 = address(35553445);
    (bool active, ) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(active, "there should  be an active entitlement");

    uint256 expiration2 = block.timestamp + 3 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract2,
        vaultAddress,
        tokenId,
        expiration2
      );

    vm.prank(mockContract2);
    vm.expectRevert(
      "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
    );

    vaultImpl.imposeEntitlement(entitlement2, sig2);
  }

  function testBeneficialOwnerCannotClearEntitlement() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69420);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    // transfer in with first entitlement
    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    (bool active, ) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(active, "there should  be an active entitlement");

    vm.prank(writer);
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement(tokenId);

    vm.prank(address(55566677788899911));
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement(tokenId);
  }

  function testClearAndDistributeReturnsNFT2() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );

    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);
    vaultImpl.getBeneficialOwner(tokenId);
    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(tokenId, writer);

    (bool active, ) = vaultImpl.getCurrentEntitlementOperator(tokenId);
    assertTrue(!active, "there should not be an active entitlement");

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
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        vaultAddress,
        tokenId,
        expiration
      );

    vm.prank(writer);
    token.safeTransferFrom(
      writer,
      vaultAddress,
      tokenId,
      abi.encode(entitlement, sig)
    );
    IHookERC721Vault vaultImpl = IHookERC721Vault(vaultAddress);

    vm.expectRevert(
      "clearEntitlementAndDistribute -- Only the beneficial owner can receive the asset"
    );
    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(0, address(0x033333344545));
  }
}
