pragma solidity ^0.8.10;

import "./base.t.sol";
import "../../interfaces/IHookERC721Vault.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

contract HookVaultStorageTest is HookProtocolTest {
  uint32 tokenStartIndex = 300;

  address vaultProxy;
  uint256 initTokenId;

  function setUp() public {
    setUpAddresses();
    setUpFullProtocol();

    (vaultProxy, ) = createVaultandAsset();
    initTokenId = tokenStartIndex;
  }

  function createVaultandAsset() internal returns (address, uint32) {
    vm.startPrank(admin);
    tokenStartIndex += 1;
    uint32 tokenId = tokenStartIndex;
    token.mint(address(writer), tokenId);
    address vaultAddress = address(
      vaultFactory.findOrCreateVault(address(token), tokenId)
    );
    vm.stopPrank();
    return (vaultAddress, tokenId);
  }

  function getTokenId() internal returns (uint256 tokenId) {
    // VmEx cheatcodes cannot be used in setUp()
    uint256 tokenIdSlot = vmEx.getVarSlotIndex(address(vaultImpl), "_tokenId");
    tokenId = vmEx.readUintBySlot(vaultProxy, tokenIdSlot);
  }

  function testTokenId() public {
    uint256 tokenId = getTokenId();
    require(tokenId == tokenStartIndex, "_tokenId is wrong");
  }

  function invariantTokenIdNotChanged() public {
    uint256 tokenId = getTokenId();
    require(tokenId == initTokenId, "_tokenId is changed");
  }
}
