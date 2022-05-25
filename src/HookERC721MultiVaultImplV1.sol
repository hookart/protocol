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


/// @title  HookMultiVault -- implementation of a Vault for multiple assets within a NFT collection, with entitlements.
/// @author Jake Nyquist - j@hook.xyz
/// @notice HookVault holds a multiple NFT asset in escrow on behalf of multiple beneficial owners. Other contracts
/// are able to register "entitlements" for a fixed period of time on the asset, which give them the ability to
/// change the vault's owner.
/// @dev This contract implements ERC721Receiver
/// This contract views the tokenId for the asset on the ERC721 contract as the corresponding assetId for that asset
/// when deposited into the vault
contract HookERC721MultiVaultImplV1 is
  IHookERC721Vault,
  EIP712,
  Initializable,
  ReentrancyGuard
{
  /// ----------------  STORAGE ---------------- ///

  /// @dev these are the NFT contract address and tokenId the vault is covering
  IERC721 private _nftContract;

  struct Asset {
    address beneficialOwner;
    address operator;
    uint128 expiry;
  }

  /// @dev the current entitlement applied to each asset, which includes the beneficialOwner
  /// for the asset
  /// if the entitled operator field is non-null, it means an unreleased entitlement has been
  /// applied; however, that entitlement could still be expired (if block.timestamp > entitlement.expiry)
  mapping(uint256 => Asset) private assets;

  IHookProtocol private _hookProtocol;

  /// Upgradeable Implementations cannot have a constructor, so we call the initialize instead;
  constructor() {}

  /// -- constructor
  function initialize(address nftContract, address hookAddress)
    public
    initializer
  {
    setAddressForEipDomain(hookAddress);
    _nftContract = IERC721(nftContract);
    _hookProtocol = IHookProtocol(hookAddress);
  }

  /// ---------------- PUBLIC FUNCTIONS ---------------- ///

  ///
  /// @dev See {IERC165-supportsInterface}.
  ///
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    returns (bool)
  {
    return
      interfaceId == type(IHookERC721Vault).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  /// @dev See {IHookERC721Vault-withdrawalAsset}.
  /// @dev withdrawals can only be performed to the beneficial owner if there are no entitlements
  function withdrawalAsset(uint256 assetId) external {
    require(
      !hasActiveEntitlement(assetId),
      "withdrawalAsset -- the asset cannot be withdrawn with an active entitlement"
    );

    _nftContract.safeTransferFrom(
      address(this),
      assets[assetId].beneficialOwner,
      assetId
    );

    emit AssetWithdrawn(assetId, msg.sender, assets[assetId].beneficialOwner);
  }

  /// @dev See {IHookERC721Vault-imposeEntitlement}.
  /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the
  /// entitlement
  function imposeEntitlement(
    address operator,
    uint128 expiry,
    uint128 assetId,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    // check that the asset has a current beneficial owner
    // before creating a new entitlement
    require(
      assets[assetId].beneficialOwner != address(0),
      "imposeEntitlement -- beneficial owner must be set to impose an entitlement"
    );

    // the beneficial owner of an asset is able to set any entitlement on their own asset
    // as long as it has not already been committed to someone else.
    _verifyAndRegisterEntitlement(operator, expiry, assetId, v, r, s);
  }

  /// @dev See {IHookERC721Vault-grantEntitlement}.
  /// @dev The entitlement must be sent by the current beneficial owner
  function grantEntitlement(Entitlements.Entitlement calldata entitlement)
    external
  {
    require(
      assets[entitlement.assetId].beneficialOwner == msg.sender,
      "grantEntitlement -- only the beneficial owner can grant an entitlement"
    );

    // the beneficial owner of an asset is able to directly set any entitlement on their own asset
    // as long as it has not already been committed to someone else.

    _registerEntitlement(
      entitlement.assetId,
      entitlement.operator,
      uint128(entitlement.expiry),
      msg.sender
    );
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
    /// (1) When receiving a nft from the ERC-721 contract this vault covers, create a new entitlement entry
    /// with the sender as the beneficial owner to track the asset within the vault.
    ///
    /// (1a) If the transfer additionally specifies data (i.e. an abi-encoded entitlement), the entitlement will
    /// be imposed via that transfer, including a new beneficial owner.
    ///     NOTE: this is an opinionated approach, however, the authors believe that anyone with the ability to
    ///     transfer the asset into this contract could also trivially transfer the asset to another address
    ///     they control and then deposit, so allowing this method of setting the beneficial owner simply
    ///     saves gas and has no practical impact on the rights a hypothetical sender has regarding the asset.
    ///
    /// (2) If another nft is sent to the contract, we should verify that airdrops are allowed to this vault;
    /// if they are disabled, we should not return the selector, otherwise we can allow them.
    ///
    /// IMPORTANT: If an unrelated contract is currently holding the asset on behalf of an owner and then
    /// subsequently transfers the asset into the contract, it needs to manually call (setBeneficialOwner)
    /// after making this call to ensure that the true owner of the asset is known to the vault. Otherwise,
    /// the owner will lose the ability to reclaim their asset. Alternatively, they could pass an entitlement
    /// in pre-populated with the correct beneficial owner, which will give that owner the ability to reclaim
    /// the asset.
    if (msg.sender == address(_nftContract)) {
      // There is no need to check if we currently have this token or an entitlement set.
      // Even if the contract were able to get into this state, it should still accept the asset
      // which will allow it to enforce the entitlement.

      // If additional data is sent with the transfer, we attempt to parse an entitlement from it.
      // this allows the entitlement to be registered ahead of time.
      if (data.length > 0) {
        // Decode the order, signature from `data`. If `data` does not encode such parameters, this
        // will throw.
        (
          address beneficialOwner,
          address entitledOperator,
          uint128 expirationTime
        ) = abi.decode(data, (address, address, uint128));

        // if someone has the asset, they should be able to set whichever beneficial owner they'd like.
        // equally, they could transfer the asset first to themselves and subsequently grant a specific
        // entitlement, which is equivalent to this.
        _registerEntitlement(
          tokenId,
          entitledOperator,
          expirationTime,
          beneficialOwner
        );
      } else {
        _setBeneficialOwner(tokenId, from);
      }
    } else {
      // If we're receiving an airdrop or other asset uncovered by escrow to this address, we should ensure
      // that this is allowed by our current settings.
      require(
        !_hookProtocol.getCollectionConfig(
          address(_nftContract),
          keccak256("vault.airdropsProhibited")
        ),
        "onERC721Received -- non-escrow asset returned when airdrops are disabled"
      );
    }
    emit AssetReceived(from, operator, msg.sender, tokenId);
    return this.onERC721Received.selector;
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
    require(receiverAddress != address(0), "flashLoan -- zero address");
    require(
      _nftContract.ownerOf(assetId) == address(this),
      "flashLoan -- asset not in vault"
    );
    require(
      msg.sender == assets[assetId].beneficialOwner,
      "flashLoan -- not called by the asset owner"
    );

    require(
      !_hookProtocol.getCollectionConfig(
        address(_nftContract),
        keccak256("vault.flashLoanDisabled")
      ),
      "flashLoan -- flashLoan feature disabled for this contract"
    );

    // (1) store a hash of our current entitlement state as a snapshot to diff
    bytes32 startState = keccak256(abi.encode(assets[assetId]));

    // (2) send the flashloan contract the vaulted NFT
    _nftContract.safeTransferFrom(address(this), receiverAddress, assetId);

    // (3) call the flashloan contract, giving it a chance to do whatever it wants
    // NOTE: The flashloan contract MUST approve this vault contract as an operator
    // for the nft, such that we're able to make sure it has arrived.
    require(
      receiver.executeOperation(
        address(_nftContract),
        assetId,
        msg.sender,
        address(this),
        params
      ),
      "flashLoan -- the flash loan contract must return true"
    );

    // (4) return the nft back into the vault
    //        Use transferFrom instead of safeTransfer from because transferFrom
    //        would modify our state ( it calls erc721Receiver ). and because we know
    //        for sure that this contract can handle ERC-721s.
    _nftContract.transferFrom(receiverAddress, address(this), assetId);

    // (5) sanity check to ensure the asset was actually returned to the vault.
    // this is a concern because its possible that the safeTransferFrom implemented by
    // some contract fails silently
    require(_nftContract.ownerOf(assetId) == address(this));

    // (6) additional sanity check to ensure that the internal state of
    // the entitlement has not somehow been modified during the flash loan, for example
    // via some re-entrancy attack or by sending the asset back into the contract
    // prematurely
    require(
      startState == keccak256(abi.encode(assets[assetId])),
      "flashLoan -- entitlement state cannot be modified"
    );

    // (7) emit an event to record the flashloan
    emit AssetFlashLoaned(
      assets[assetId].beneficialOwner,
      assetId,
      receiverAddress
    );
  }

  /// @dev See {IHookVault-entitlementExpiration}.
  function entitlementExpiration(uint256 assetId)
    external
    view
    returns (uint256 expiry)
  {
    if (!hasActiveEntitlement(assetId)) {
      return 0;
    } else {
      return assets[assetId].expiry;
    }
  }

  /// @dev See {IHookERC721Vault-getBeneficialOwner}.
  function getBeneficialOwner(uint256 assetId) external view returns (address) {
    return assets[assetId].beneficialOwner;
  }

  /// @dev See {IHookERC721Vault-getHoldsAsset}.
  function getHoldsAsset(uint256 assetId)
    external
    view
    returns (bool holdsAsset)
  {
    return _nftContract.ownerOf(assetId) == address(this);
  }

  function assetAddress(uint256) external view returns (address) {
    return address(_nftContract);
  }

  /// @dev returns the underlying token ID for a given asset. In this case
  /// the tokenId == the assetId
  function assetTokenId(uint256 assetId) external pure returns (uint256) {
    return assetId;
  }

  /// @dev See {IHookERC721Vault-setBeneficialOwner}.
  /// setBeneficialOwner can only be called by the entitlementContract if there is an activeEntitlement.
  function setBeneficialOwner(uint256 assetId, address newBeneficialOwner)
    external
  {
    if (hasActiveEntitlement(assetId)) {
      require(
        msg.sender == assets[assetId].operator,
        "setBeneficialOwner -- only the contract with the active entitlement can update the beneficial owner"
      );
    } else {
      require(
        msg.sender == assets[assetId].beneficialOwner,
        "setBeneficialOwner -- only the current owner can update the beneficial owner"
      );
    }
    _setBeneficialOwner(assetId, newBeneficialOwner);
  }

  /// @dev See {IHookERC721Vault-clearEntitlement}.
  /// @dev This can only be called if an entitlement currently exists, otherwise it would be a no-op
  function clearEntitlement(uint256 assetId) public {
    require(
      hasActiveEntitlement(assetId),
      "clearEntitlement -- an active entitlement must exist"
    );
    require(
      msg.sender == assets[assetId].operator,
      "clearEntitlement -- only the entitled address can clear the entitlement"
    );
    _clearEntitlement(assetId);
  }

  /// @dev See {IHookERC721Vault-clearEntitlementAndDistribute}.
  /// @dev The entitlement must be exist, and must be called by the {operator}. The operator can specify a
  /// intended receiver, which should match the beneficialOwner. The function will throw if
  /// the receiver and owner do not match.
  /// @param assetId the id of the specific vaulted asset
  /// @param receiver the intended receiver of the asset
  function clearEntitlementAndDistribute(uint256 assetId, address receiver)
    external
    nonReentrant
  {
    require(
      assets[assetId].beneficialOwner == receiver,
      "clearEntitlementAndDistribute -- Only the beneficial owner can receive the asset"
    );
    clearEntitlement(assetId);
    IERC721(_nftContract).safeTransferFrom(address(this), receiver, assetId);
    emit AssetWithdrawn(assetId, msg.sender, assets[assetId].beneficialOwner);
  }

  /// @dev Validates that a specific signature is actually the entitlement
  /// EIP-712 signed by the beneficial owner specified in the entitlement.
  function validateEntitlementSignature(
    address operator,
    uint128 expiry,
    uint128 assetId,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public view {
    bytes32 entitlementHash = _getEIP712Hash(
      Entitlements.getEntitlementStructHash(
        Entitlements.Entitlement({
          beneficialOwner: assets[assetId].beneficialOwner,
          expiry: expiry,
          operator: operator,
          assetId: assetId,
          vaultAddress: address(this)
        })
      )
    );
    address signer = ecrecover(entitlementHash, v, r, s);

    require(signer != address(0), "recovered address is null");
    require(
      signer == assets[assetId].beneficialOwner,
      "validateEntitlementSignature --- not signed by beneficialOwner"
    );
  }

  /// ---------------- INTERNAL/PRIVATE FUNCTIONS ---------------- ///

  /// @notice Verify that an entitlement is properly signed and apply it to the asset if able.
  /// @dev The entitlement must be signed by the beneficial owner of the asset in order for it to be considered valid
  /// @param operator the operator to entitle
  /// @param expiry the duration of the entitlement
  /// @param assetId the id of the asset within the vault
  /// @param v sig v
  /// @param r sig r
  /// @param s sig s
  function _verifyAndRegisterEntitlement(
    address operator,
    uint128 expiry,
    uint128 assetId,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) private {
    validateEntitlementSignature(operator, expiry, assetId, v, r, s);
    _registerEntitlement(
      assetId,
      operator,
      expiry,
      assets[assetId].beneficialOwner
    );
  }

  function _registerEntitlement(
    uint256 assetId,
    address operator,
    uint128 expiry,
    address beneficialOwner
  ) private {
    require(
      !hasActiveEntitlement(assetId),
      "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
    );

    require(
      expiry > block.timestamp,
      "_verifyAndRegisterEntitlement -- entitlement must expire in the future"
    );
    assets[assetId] = Asset({
      operator: operator,
      expiry: expiry,
      beneficialOwner: beneficialOwner
    });
    emit EntitlementImposed(assetId, operator, expiry, beneficialOwner);
  }

  function _clearEntitlement(uint256 assetId) private {
    assets[assetId].expiry = 0;
    assets[assetId].operator = address(0);
    emit EntitlementCleared(assetId, assets[assetId].beneficialOwner);
  }

  function hasActiveEntitlement(uint256 assetId) public view returns (bool) {
    /// Although we do clear the expiry in _clearEntitlement, making the second half of the AND redundant,
    /// we choose to include it here because we rely on this field being null to clear an entitlement.
    return
      block.timestamp < assets[assetId].expiry &&
      assets[assetId].operator != address(0);
  }

  function getCurrentEntitlementOperator(uint256 assetId)
    external
    view
    returns (bool isActive, address operator)
  {
    isActive = hasActiveEntitlement(assetId);
    operator = assets[assetId].operator;
  }

  function _setBeneficialOwner(uint256 assetId, address newBeneficialOwner)
    private
  {
    require(
      newBeneficialOwner != address(0),
      "_setBeneficialOwner -- new owner is the zero address"
    );
    assets[assetId].beneficialOwner = newBeneficialOwner;
    emit BeneficialOwnerSet(assetId, newBeneficialOwner, msg.sender);
  }
}
