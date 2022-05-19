// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IERC721FlashLoanReceiver.sol";
import "./interfaces/IHookProtocol.sol";
import "./lib/Entitlements.sol";
import "./lib/Signatures.sol";
import "./mixin/EIP712.sol";

/// @title  HookVault -- implemenation of a Vault for a single NFT asset, with entitlements.
/// @author Jake Nyquist - j@hook.xyz
/// @notice HookVault holds a single NFT asset in escrow on behalf of a user. Other contracts are able
/// to register "entitlements" for a fixed period of time on the asset, which give them the ability to
/// change the vault's owner.
/// @dev This contract implements ERC721Reciever and
contract HookERC721VaultImplV1 is
  IHookERC721Vault,
  EIP712,
  Initializable,
  ReentrancyGuard
{
  uint256 private constant ASSET_ID = 0;

  /// ----------------  STORAGE ---------------- ///

  /// @dev these are the NFT contract address and tokenId the vault is covering
  IERC721 private _nftContract;
  uint256 private _tokenId;

  /// @dev the current owner of the asset, who is able to withdrawl it if there are no
  /// entitlements.
  address private beneficialOwner;

  /// @dev these fields mark when there is an active entitlement on this contract. If these
  /// fields are non-null, the beneficial owner is unable to withdrawl until either the entitlement
  /// expires or the fields are cleared.
  Entitlements.Entitlement private _currentEntitlement;

  /// @dev mark if an entitlement has been set.
  bool private _hasEntitlement;

  IHookProtocol private _hookProtocol;

  /// Upgradeable Implementations cannot have a contructor, so we call the initialize instead;
  constructor() {}

  /// -- constructor
  function initialize(
    address nftContract,
    uint256 tokenId,
    address hookAddress
  ) public initializer {
    setAddressForEipDomain(hookAddress);
    _tokenId = tokenId;
    _nftContract = IERC721(nftContract);
    _hookProtocol = IHookProtocol(hookAddress);
    _hasEntitlement = false;
  }

  /// ---------------- PUBLIC FUNCTIONS ---------------- ///

  /// @dev See {IHookERC721Vault-withdrawalAsset}.
  /// @dev withdrawals can only be performed by the beneficial owner if there are no entitlements
  function withdrawalAsset(uint256) external {
    // require(msg.sender == beneficialOwner, "the beneficial owner is the only one able to withdrawl");
    require(
      !hasActiveEntitlement(),
      "withdrawalAsset -- the asset canot be withdrawn with an active entitlement"
    );

    _nftContract.safeTransferFrom(address(this), beneficialOwner, _tokenId);

    emit AssetWithdrawn(ASSET_ID, msg.sender, beneficialOwner);
  }

  /// @dev See {IHookERC721Vault-imposeEntitlement}.
  /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the
  /// entitlement
  function imposeEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) external {
    require(
      beneficialOwner != address(0),
      "imposeEntitlement -- beneficial owner must be set to impose an entitlement"
    );

    // the beneficial owner of an asset is able to set any entitlement on their own asset
    // as long as it has not already been committed to someone else.
    _verifyAndRegisterEntitlement(entitlement, signature);
  }

  /// @dev See {IHookERC721Vault-grantEntitlement}.
  /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the
  /// entitlement
  function grantEntitlement(Entitlements.Entitlement memory entitlement)
    external
  {
    require(
      beneficialOwner == msg.sender,
      "grantEntitlement -- only the beneficial owner can grant an entitlement"
    );

    // the beneficial owner of an asset is able to directly set any entitlement on their own asset
    // as long as it has not already been committed to someone else.
    _registerEntitlement(entitlement);
  }

  /// @dev See {IERC721Receiver-onERC721Received}.
  ///
  /// Always returns `IERC721Receiver.onERC721Received.selector`.
  function onERC721Received(
    address operator, // this arg is the address of the operator
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external virtual override returns (bytes4) {
    /// We should make sure that the owner of an asset never changes simply as a result of someone sending
    /// a NFT into this contract.
    ///
    /// (1) If the contract is specified to hold a specific NFT, and that NFT is sent to the contract,
    /// set the beneficial owner of this vault to be current owner of the asset getting sent.
    ///
    /// (2) If another nft is sent to the contract, we should verify that airdrops are allowed to this vault;
    /// if they are disabled, we should not return the selector, otherwise we can allow them.
    ///
    /// IMPORTANT: If an unrelated contract is currently holding the asset on behalf of an owner and then
    /// subsequently transfers the asset into the contract, it needs to manually call (setBeneficialOwner)
    /// after making this call to ensure that the true owner of the asset is known to the vault. Otherwise,
    /// the owner will lose the ability to reclaim their asset. Alternatively, they could pass an entitlement
    /// in prepopulated with the correct beneficial owner, which will give that owner the ability to reclaim
    /// the asseet.
    if (msg.sender == address(_nftContract) && tokenId == _tokenId) {
      // There is no need to check if we currently have this token or an entitlement set.
      // Even if the contract were able to get into this state, it should still accept the asset
      // which will allow it to enforce the entitlement.
      _setBeneficialOwner(from);

      // If additional data is sent with the transfer, we attempt to parse an entitlement from it.
      // this allows the entitlement to be registered ahead of time.
      if (data.length > 0) {
        // Decode the order, signature from `data`. If `data` does not encode such parameters, this
        // will throw.
        Entitlements.Entitlement memory entitlement = abi.decode(
          data,
          (Entitlements.Entitlement)
        );
        // if someone has the asset, they should be able to set whichever beneficial owner they'd like.
        // equally, they could transfer the asset first to themselves and subsequently grant a specific
        // entitlement, which is equivalent to this.
        _setBeneficialOwner(entitlement.beneficialOwner);
        _registerEntitlement(entitlement);
      }
    } else {
      // If we're recieving an airdrop or other asset uncovered by escrow to this address, we should ensure
      // that this is allowed by our current settings.
      require(
        !_hookProtocol.getCollectionConfig(
          address(_nftContract),
          keccak256("vault.airdropsProhibited")
        ),
        "onERC721Received -- non-escrow asset returned when airdrops are disabled"
      );
    }
    emit AssetReceived(from, operator, msg.sender, ASSET_ID);
    return this.onERC721Received.selector;
  }

  /// @dev See {IHookERC721Vault-execTransaction}.
  /// @dev Allows a beneficial owner to send an arbitrary call from this wallet as long as the underlying NFT
  /// is still owned by us after the transaction. The ether value sent is forwarded. Return value is suppressed.
  function execTransaction(address to, bytes memory data)
    external
    payable
    virtual
    returns (bool success)
  {
    // Only the beneficial owner can make this call
    require(
      msg.sender == beneficialOwner,
      "execTransaction -- only the beneficial owner can use the transaction"
    );

    // block transactions to the NFT contract ot ensure that people cant set approvals as the owner.
    require(
      to != address(_nftContract),
      "execTransaction -- cannot send transactions to the NFT contract itself"
    );

    require(
      !_hookProtocol.getCollectionConfig(
        address(_nftContract),
        keccak256("vault.execTransactionDisabled")
      ),
      "execTransaction -- feature is disabled for this collection"
    );

    // Execute transaction without further confirmations.
    (success, ) = address(to).call{value: msg.value}(data);

    require(_nftContract.ownerOf(_tokenId) == address(this));
  }

  /// @dev See {IHookERC721Vault-flashLoan}.
  function flashLoan(
    uint256 assetId,
    address receiverAddress,
    bytes calldata params
  ) external override nonReentrant {
    IERC721FlashLoanReceiver receiver = IERC721FlashLoanReceiver(
      receiverAddress
    );
    require(assetId == ASSET_ID, "flashLoan -- invalid asset id");
    require(receiverAddress != address(0), "flashLoan -- zero address");
    require(
      msg.sender == beneficialOwner,
      "flashLoan -- not called by the asset owner"
    );

    require(
      !_hookProtocol.getCollectionConfig(
        address(_nftContract),
        keccak256("vault.flashLoanDisabled")
      ),
      "flashLoan -- flashLoan feature disabled for this contract"
    );

    // (1) send the flashloan contract the vaulted NFT
    _nftContract.safeTransferFrom(address(this), receiverAddress, _tokenId);

    // (2) call the flashloan contract, giving it a chance to do whatever it wants
    // NOTE: The flashloan contract MUST approve this vault contract as an operator
    // for the nft, such that we're able to make sure it has arrived.
    require(
      receiver.executeOperation(
        address(_nftContract),
        _tokenId,
        msg.sender,
        address(this),
        params
      ),
      "flashLoan -- the flash loan contract must return true"
    );

    // (3) return the nft back into the vault
    _nftContract.safeTransferFrom(receiverAddress, address(this), _tokenId);

    // (4) sanity check to ensure the asset was actually returned to the vault.
    // this is a concern because its possible that the safeTransferFrom implemented by
    // some contract fails silently
    require(_nftContract.ownerOf(_tokenId) == address(this));

    // (5) emit an event to record the flashloan
    emit AssetFlashLoaned(beneficialOwner, _tokenId, receiverAddress);
  }

  /// @dev See {IHookVault-entitlementExpiration}.
  function entitlementExpiration(uint256)
    external
    view
    returns (uint256 expiry)
  {
    if (!hasActiveEntitlement()) {
      return 0;
    } else {
      _currentEntitlement.expiry;
    }
  }

  /// @dev See {IHookERC721Vault-getBeneficialOwner}.
  function getBeneficialOwner(uint256) external view returns (address) {
    return beneficialOwner;
  }

  /// @dev See {IHookERC721Vault-getHoldsAsset}.
  function getHoldsAsset(uint256) external view returns (bool holdsAsset) {
    return _nftContract.ownerOf(_tokenId) == address(this);
  }

  function assetAddress(uint256) external view returns (address) {
    return address(_nftContract);
  }

  function assetTokenId(uint256) external view returns (uint256) {
    return _tokenId;
  }

  /// @dev See {IHookERC721Vault-setBeneficialOwner}.
  /// setBeneficialOwner can only be called by the entitlementContract if there is an activeEntitlement.
  function setBeneficialOwner(uint256 assetId, address newBeneficialOwner)
    external
  {
    if (hasActiveEntitlement()) {
      require(
        msg.sender == _currentEntitlement.operator,
        "setBeneficialOwner -- only the contract with the active entitlement can update the beneficial owner"
      );
    } else {
      require(
        msg.sender == beneficialOwner,
        "setBeneficialOwner -- only the current owner can update the beneficial owner"
      );
    }
    require(
      assetId == ASSET_ID,
      "setBeneficialOwner -- this contract only contains one asset"
    );
    _setBeneficialOwner(newBeneficialOwner);
  }

  /// @dev See {IHookERC721Vault-clearEntitlement}.
  /// @dev This can only be called if an entitlement currently exists, otherwise it would be a no-op
  function clearEntitlement(uint256) public {
    require(
      hasActiveEntitlement(),
      "clearEntitlement -- an active entitlement must exist"
    );
    require(
      msg.sender == _currentEntitlement.operator,
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    _clearEntitlement();
  }

  /// @dev See {IHookERC721Vault-clearEntitlementAndDistribute}.
  /// @dev The entitlement must be exist, and must be called by the {operator}. The operator can specify a
  /// intended reciever, which should match the beneficialOwner. The function will throw if
  /// the reciever and owner do not match.
  /// @param reciever the intended reciever of the asset
  function clearEntitlementAndDistribute(uint256, address reciever)
    external
    nonReentrant
  {
    require(
      beneficialOwner == reciever,
      "clearEntitlementAndDistribute -- Only the beneficial owner can recieve the asset"
    );
    clearEntitlement(ASSET_ID);
    IERC721(_nftContract).safeTransferFrom(address(this), reciever, _tokenId);
    emit AssetWithdrawn(ASSET_ID, msg.sender, beneficialOwner);
  }

  /// @dev Get the EIP-712 hash of an Entitlement.
  /// @param entitlement The entitlement to hash
  /// @return entitlementHash The hash of the entitlement.
  function getEntitlementHash(Entitlements.Entitlement memory entitlement)
    public
    view
    returns (bytes32 entitlementHash)
  {
    return _getEIP712Hash(Entitlements.getEntitlementStructHash(entitlement));
  }

  function validateEntitlementSignature(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) public view {
    bytes32 entitlementHash = getEntitlementHash(entitlement);
    address signer = Signatures.getSignerOfHash(entitlementHash, signature);
    require(
      signer == entitlement.beneficialOwner,
      "validateEntitlementSignature --- not signed by beneficialOwner"
    );
  }

  function tokenAssetId(uint256) external pure returns (uint32) {
    return uint32(ASSET_ID);
  }

  /// ---------------- INTERNAL/PRIVATE FUNCTIONS ---------------- ///

  /// @notice Verify that an entitlement is properly signed and apply it to the asset if able.
  /// @dev The entitlement must be signed by the beneficial owner of the asset in order for it to be considered valid
  /// @param entitlement the entitlement to impose on the asset
  /// @param signature the EIP-712 signed entitlement by the beneficial owner
  function _verifyAndRegisterEntitlement(
    Entitlements.Entitlement memory entitlement,
    Signatures.Signature memory signature
  ) private {
    validateEntitlementSignature(entitlement, signature);
    _registerEntitlement(entitlement);
  }

  function _registerEntitlement(Entitlements.Entitlement memory entitlement)
    private
  {
    require(
      !hasActiveEntitlement(),
      "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
    );
    require(
      entitlement.beneficialOwner == beneficialOwner,
      "_verifyAndRegisterEntitlement -- only the current beneficial owner can make an entitlement"
    );
    require(
      entitlement.vaultAddress == address(this),
      "_verifyAndRegisterEntitlement -- the entitled contract must match the vault contract"
    );
    require(
      entitlement.assetId == ASSET_ID,
      "_verifyAndRegisterEntitlement -- the entitled contract must match the vault contract"
    );
    _currentEntitlement = entitlement;
    _hasEntitlement = true;
    emit EntitlementImposed(
      ASSET_ID,
      entitlement.operator,
      entitlement.expiry,
      beneficialOwner
    );
  }

  function _clearEntitlement() private {
    _currentEntitlement = Entitlements.Entitlement(
      address(0),
      address(0),
      address(0),
      ASSET_ID,
      0
    );
    _hasEntitlement = false;
    emit EntitlementCleared(ASSET_ID, beneficialOwner);
  }

  function hasActiveEntitlement() public view returns (bool) {
    return block.timestamp < _currentEntitlement.expiry && _hasEntitlement;
  }

  function getCurrentEntitlementOperator(uint256)
    external
    view
    returns (bool isActive, address operator)
  {
    isActive = hasActiveEntitlement();
    operator = _currentEntitlement.operator;
  }

  function _setBeneficialOwner(address newBeneficialOwner) private {
    require(
      newBeneficialOwner != address(0),
      "_setBeneficialOwner -- new owner is the zero address"
    );
    beneficialOwner = newBeneficialOwner;
    emit BeneficialOwnerSet(ASSET_ID, newBeneficialOwner, msg.sender);
  }
}
