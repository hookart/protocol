// SPDX-License-Identifier: MIT
//
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        █████████████▌                                        ▐█████████████
//        ██████████████                                        ██████████████
//        ██████████████          ▄▄████████████████▄▄         ▐█████████████▌
//        ██████████████    ▄█████████████████████████████▄    ██████████████
//         ██████████▀   ▄█████████████████████████████████   ██████████████▌
//          ██████▀   ▄██████████████████████████████████▀  ▄███████████████
//           ███▀   ██████████████████████████████████▀   ▄████████████████
//            ▀▀  ████████████████████████████████▀▀   ▄█████████████████▌
//              █████████████████████▀▀▀▀▀▀▀      ▄▄███████████████████▀
//             ██████████████████▀    ▄▄▄█████████████████████████████▀
//            ████████████████▀   ▄█████████████████████████████████▀  ██▄
//          ▐███████████████▀  ▄██████████████████████████████████▀   █████▄
//          ██████████████▀  ▄█████████████████████████████████▀   ▄████████
//         ██████████████▀   ███████████████████████████████▀   ▄████████████
//        ▐█████████████▌     ▀▀▀▀████████████████████▀▀▀▀      █████████████▌
//        ██████████████                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████
//        █████████████▌                                        ██████████████

pragma solidity ^0.8.10;

import "./HookERC721MultiVaultImplV1.sol";

/// @title HookVault-implementation of a Vault for a single NFT asset, with entitlements.
/// @author Jake Nyquist - j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
/// @notice HookVault holds a single NFT asset in escrow on behalf of a user. Other contracts are able
/// to register "entitlements" for a fixed period of time on the asset, which give them the ability to
/// change the vault's owner.
/// @dev This contract implements ERC721Receiver and extends the MultiVault, simply treating the stored
/// asset as assetId 0 in all cases.
///
/// SEND TRANSACTION -
///     (1) owners are able to forward transactions to this vault to other wallets
///     (2) calls to the ERC-721 address are blocked to prevent approvals from being set on the
///         NFT while in escrow, which could allow for theft
///     (3) At the end of each transaction, the ownerOf the vaulted token must still be the vault
contract HookERC721VaultImplV1 is HookERC721MultiVaultImplV1 {
  uint32 private constant ASSET_ID = 0;

  /// ----------------  STORAGE ---------------- ///

  /// @dev this is the only tokenID the vault covers.
  uint256 internal _tokenId;

  /// Upgradeable Implementations cannot have a constructor, so we call the initialize instead;
  constructor() HookERC721MultiVaultImplV1() {}

  ///-constructor
  function initialize(
    address nftContract,
    uint256 tokenId,
    address hookAddress
  ) public {
    _tokenId = tokenId;
    // the super function calls "Initialize"
    super.initialize(nftContract, hookAddress);
  }

  /// ---------------- PUBLIC/EXTERNAL FUNCTIONS ---------------- ///

  /// @dev See {IHookERC721Vault-withdrawalAsset}.
  /// @dev withdrawals can only be performed by the beneficial owner if there are no entitlements
  function withdrawalAsset(uint32 assetId)
    public
    override
    assetIdIsZero(assetId)
  {
    super.withdrawalAsset(assetId);
  }

  /// @dev See {IHookERC721Vault-imposeEntitlement}.
  /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone may call this
  /// function and successfully impose the entitlement as long as the signature is valid.
  function imposeEntitlement(
    address operator,
    uint32 expiry,
    uint32 assetId,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public override assetIdIsZero(assetId) {
    super.imposeEntitlement(operator, expiry, assetId, v, r, s);
  }

  /// @dev See {IERC721Receiver-onERC721Received}.
  ///
  /// Always returns `IERC721Receiver.onERC721Received.selector`.
  ///
  /// This method requires an override implementation because the the arguments must be embedded in the body of the
  /// function
  function onERC721Received(
    address operator, // this arg is the address of the operator
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external virtual override returns (bytes4) {
    /// (1) If the contract is specified to hold a specific NFT, and that NFT is sent to the contract,
    /// set the beneficial owner of this vault to be current owner of the asset getting sent. Alternatively,
    /// the sender can specify an entitlement which contains a different beneficial owner. We accept this because
    /// that same sender could alternatively first send the token, become the beneficial owner, and then set it
    /// the beneficial owner to someone else and finally specify an entitlement.
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
    if (msg.sender == address(_nftContract) && tokenId == _tokenId) {
      // There is no need to check if we currently have this token or an entitlement set.
      // Even if the contract were able to get into this state, it should still accept the asset
      // which will allow it to enforce the entitlement.
      _setBeneficialOwner(ASSET_ID, from);

      // If additional data is sent with the transfer, we attempt to parse an entitlement from it.
      // this allows the entitlement to be registered ahead of time.
      if (data.length > 0) {
        // Decode the order, signature from `data`. If `data` does not encode such parameters, this
        // will throw.
        (
          address _beneficialOwner,
          address entitledOperator,
          uint32 expirationTime
        ) = abi.decode(data, (address, address, uint32));
        // if someone has the asset, they should be able to set whichever beneficial owner they'd like.
        // equally, they could transfer the asset first to themselves and subsequently grant a specific
        // entitlement, which is equivalent to this.
        _setBeneficialOwner(ASSET_ID, _beneficialOwner);
        _registerEntitlement(
          ASSET_ID,
          entitledOperator,
          expirationTime,
          assets[ASSET_ID].beneficialOwner
        );
      }
      emit AssetReceived(
        this.getBeneficialOwner(uint32(ASSET_ID)),
        operator,
        msg.sender,
        ASSET_ID
      );
    } else {
      // If we're receiving an airdrop or other asset uncovered by escrow to this address, we should ensure
      // that this is allowed by our current settings.
      require(
        !_hookProtocol.getCollectionConfig(
          address(_nftContract),
          keccak256("vault.airdropsProhibited")
        ),
        "onERC721Received-non-escrow asset returned when airdrops are disabled"
      );
    }
    return this.onERC721Received.selector;
  }

  /// @dev See {IHookERC721Vault-execTransaction}.
  /// @dev Allows a beneficial owner to send an arbitrary call from this wallet as long as the underlying NFT
  /// is still owned by us after the transaction. The ether value sent is forwarded. Return value is suppressed.
  ///
  /// Because this contract holds only a single asset owned by a single address, it supports calling exec
  /// transaction from this address because such calls are unlikely to impact other owner's assets.
  function execTransaction(address to, bytes memory data)
    external
    payable
    virtual
    returns (bool)
  {
    // Only the beneficial owner can make this call
    require(
      msg.sender == assets[ASSET_ID].beneficialOwner,
      "execTransaction-only the beneficial owner can use the transaction"
    );

    // block transactions to the NFT contract to ensure that people cant set approvals as the owner.
    require(
      to != address(_nftContract),
      "execTransaction-cannot send transactions to the NFT contract itself"
    );

    // block transactions to the vault to mitigate reentrancy vulnerabilities
    require(
      to != address(this),
      "execTransaction-cannot call the vault contract"
    );

    require(
      !_hookProtocol.getCollectionConfig(
        address(_nftContract),
        keccak256("vault.execTransactionDisabled")
      ),
      "execTransaction-feature is disabled for this collection"
    );

    // Execute transaction without further confirmations.
    (bool success, ) = address(to).call{value: msg.value}(data);

    require(_assetOwner(ASSET_ID) == address(this));

    return success;
  }

  /// @dev See {IHookERC721Vault-setBeneficialOwner}.
  function setBeneficialOwner(uint32 assetId, address newBeneficialOwner)
    public
    override
    assetIdIsZero(assetId)
  {
    super.setBeneficialOwner(assetId, newBeneficialOwner);
  }

  /// @dev modifier used to ensure that only the valid asset id
  /// may be passed into this vault.
  modifier assetIdIsZero(uint256 assetId) {
    require(
      assetId == ASSET_ID,
      "assetIdIsZero-this vault only supports asset id 0"
    );
    _;
  }

  /// @dev override the assetOwner method to ensure the allowed
  /// token in this vault is checked on the ERC-721 contract
  function _assetTokenId(uint32 assetId)
    internal
    view
    override
    assetIdIsZero(assetId)
    returns (uint256)
  {
    return _tokenId;
  }
}
