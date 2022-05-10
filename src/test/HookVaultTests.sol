// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Test.sol";

import "./utils/base.sol";
import "../interfaces/IHookERC721VaultFactory.sol";

import "../lib/Entitlements.sol";
import "../lib/Signatures.sol";
import "../mixin/EIP712.sol";

contract HookVaultTests is HookProtocolTest {
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
    address vaultAddress = vault.makeVault(address(token), tokenId);
    vm.stopPrank();
    return (vaultAddress, tokenId);
  }

  function makeEntitlementAndSignature(
    uint256 ownerPkey,
    address operator,
    address nftToken,
    uint256 _tokenId,
    uint256 _expiry
  )
    internal
    returns (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory signature
    )
  {
    address ownerAdd = vm.addr(writerpkey);

    Entitlements.Entitlement memory entitlement = Entitlements.Entitlement({
      beneficialOwner: ownerAdd,
      operator: operator,
      nftContract: nftToken,
      nftTokenId: _tokenId,
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
        address(token),
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

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);
    assertTrue(
      vaultImpl.assetInVault(),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner() == writer,
      "writer should be the beneficial owner"
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
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
        address(token),
        tokenId,
        expiration
      );

    vm.prank(writer);

    token.safeTransferFrom(writer, vaultAddress, tokenId);

    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    // impose the entitlement onto the vault
    vm.prank(mockContract);
    vaultImpl.imposeEntitlement(entitlement, sig);

    assertTrue(
      vaultImpl.assetInVault(),
      "the token should be owned by the vault"
    );
    assertTrue(
      vaultImpl.getBeneficialOwner() == writer,
      "writer should be the beneficial owner"
    );
    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    // verify that beneficial owner cannot withdrawl
    // during an active entitlement.
    vm.expectRevert(
      "withdrawalAsset -- the asset canot be withdrawn with an active entitlement"
    );
    vm.prank(writer);
    vaultImpl.withdrawalAsset();
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    vm.warp(block.timestamp + 2 days);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(),
      "there should not be any active entitlements"
    );

    vm.prank(writer);
    vaultImpl.withdrawalAsset();
    assertTrue(
      !vaultImpl.assetInVault(),
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.prank(mockContract);
    vaultImpl.clearEntitlement();

    assertTrue(
      !vaultImpl.hasActiveEntitlement(),
      "there should not be any active entitlements"
    );

    // check that the owner can actually withdrawl
    vm.prank(writer);
    vaultImpl.withdrawalAsset();
    assertTrue(
      !vaultImpl.assetInVault(),
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    vm.warp(block.timestamp + 2 days);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(),
      "there should not be any active entitlements"
    );

    // asset is not withdrawn, try to add a new entitlement
    uint256 expiration2 = block.timestamp + 10 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        address(token),
        tokenId,
        expiration2
      );
    vaultImpl.imposeEntitlement(entitlement2, sig2);
    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be a new active entitlement"
    );
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    vm.prank(mockContract);
    vaultImpl.clearEntitlement();

    assertTrue(
      !vaultImpl.hasActiveEntitlement(),
      "there should not be any active entitlements"
    );

    uint256 expiration2 = block.timestamp + 3 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        address(token),
        tokenId,
        expiration2
      );

    vaultImpl.imposeEntitlement(entitlement2, sig2);
    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be a new active entitlement"
    );
  }

  function testOnlyOneEntitlementAllowed() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    address mockContract2 = address(35553445);
    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    uint256 expiration2 = block.timestamp + 3 days;

    (
      Entitlements.Entitlement memory entitlement2,
      Signatures.Signature memory sig2
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract2,
        address(token),
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    assertTrue(
      vaultImpl.hasActiveEntitlement(),
      "there should be an active entitlement"
    );

    vm.prank(writer);
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement();

    vm.prank(address(55566677788899911));
    vm.expectRevert(
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    vaultImpl.clearEntitlement();
  }

  function testClearAndDistributeReturnsNFT() public {
    (address vaultAddress, uint256 tokenId) = createVaultandAsset();

    address mockContract = address(69);
    uint256 expiration = block.timestamp + 1 days;

    (
      Entitlements.Entitlement memory entitlement,
      Signatures.Signature memory sig
    ) = makeEntitlementAndSignature(
        writerpkey,
        mockContract,
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(writer);

    assertTrue(
      !vaultImpl.hasActiveEntitlement(),
      "there should not be any active entitlements"
    );

    assertTrue(
      token.ownerOf(tokenId) == writer,
      "Token should be returned to the owner"
    );
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
        address(token),
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
    HookERC721VaultImplV1 vaultImpl = HookERC721VaultImplV1(vaultAddress);

    vm.expectRevert(
      "clearEntitlementAndDistribute -- Only the beneficial owner can recieve the asset"
    );
    vm.prank(mockContract);
    vaultImpl.clearEntitlementAndDistribute(address(0x033333344545));
  }
}
