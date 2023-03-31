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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IHookERC20Vault.sol";
import "./interfaces/IHookProtocol.sol";
import "./lib/Entitlements.sol";
import "./lib/Signatures.sol";
import "./mixin/EIP712.sol";

/// @title Hook ERC-20 Vault Implementation
/// @author Jake Nyquist - j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
/// @notice Hook Vault for ERC20s holds a single ERC20 asset on behalf of multiple users. A user can keep a balance within the contract
/// and may withdraw up to their total entitlement amount.
contract HookErc20VaultImplV1 is IHookERC20Vault, EIP712, Initializable, ReentrancyGuard {
    /// ----------------  STORAGE ---------------- ///

    /// @dev these are the NFT contract address and tokenId the vault is covering
    IERC20 internal _tokenContract;

    struct Asset {
        address beneficialOwner;
        address operator;
        uint256 amount;
        uint32 expiry;
        //TODO: make an invariant test showing that the asset is indeed depostied
        bool deposited;
    }

    /// @dev the current entitlement applied to each asset, which includes the beneficialOwner
    /// for the asset
    /// if the entitled operator field is non-null, it means an unreleased entitlement has been
    /// applied; however, that entitlement could still be expired (if block.timestamp > entitlement.expiry)
    mapping(uint32 => Asset) internal assets;

    // Mapping from asset ID to approved address
    mapping(uint32 => address) private _assetApprovals;

    IHookProtocol internal _hookProtocol;

    /// Upgradeable Implementations cannot have a constructor, so we call the initialize instead;
    constructor() {}

    ///-constructor
    function initialize(address tokenContract, address hookAddress) public initializer {
        setAddressForEipDomain(hookAddress);
        _tokenContract = IERC20(tokenContract);
        _hookProtocol = IHookProtocol(hookAddress);
    }

    /// ---------------- PUBLIC FUNCTIONS ---------------- ///

    ///
    /// @dev See {IERC165-supportsInterface}.
    ///
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IHookERC20Vault).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev See {IHookERC20Vault-withdrawalAsset}.
    /// @dev withdrawals can only be performed to the beneficial owner if there are no entitlements
    function withdrawalAsset(uint32 assetId) public virtual nonReentrant {
        require(
            !hasActiveEntitlement(assetId), "withdrawalAsset-the asset cannot be withdrawn with an active entitlement"
        );
        require(
            assets[assetId].beneficialOwner == msg.sender,
            "withdrawalAsset-only the beneficial owner can withdrawal an asset"
        );

        _tokenContract.transferFrom(address(this), assets[assetId].beneficialOwner, assets[assetId].amount);

        emit AssetWithdrawn(assetId, msg.sender, assets[assetId].beneficialOwner);
    }

    /// @dev See {IHookERC721Vault-imposeEntitlement}.
    /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the
    /// entitlement
    function imposeEntitlement(address operator, uint32 expiry, uint32 assetId, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        // check that the asset has a current beneficial owner
        // before creating a new entitlement
        require(
            assets[assetId].beneficialOwner != address(0),
            "imposeEntitlement-beneficial owner must be set to impose an entitlement"
        );

        // the beneficial owner of an asset is able to set any entitlement on their own asset
        // as long as it has not already been committed to someone else.
        _verifyAndRegisterEntitlement(operator, expiry, assetId, v, r, s);
    }

    /// @dev See {IHookERC721Vault-grantEntitlement}.
    /// @dev The entitlement must be sent by the current beneficial owner
    function grantEntitlement(Entitlements.Entitlement calldata entitlement) external {
        require(
            assets[entitlement.assetId].beneficialOwner == msg.sender
                || _assetApprovals[entitlement.assetId] == msg.sender,
            "grantEntitlement-only the beneficial owner or approved operator can grant an entitlement"
        );

        // the beneficial owner of an asset is able to directly set any entitlement on their own asset
        // as long as it has not already been committed to someone else.

        _registerEntitlement(entitlement.assetId, entitlement.operator, entitlement.expiry, msg.sender);
    }

    /// @dev See {IHookVault-entitlementExpiration}.
    function entitlementExpiration(uint32 assetId) external view returns (uint32) {
        if (!hasActiveEntitlement(assetId)) {
            return 0;
        } else {
            return assets[assetId].expiry;
        }
    }

    /// @dev See {IHookERC721Vault-getBeneficialOwner}.
    function getBeneficialOwner(uint32 assetId) external view returns (address) {
        return assets[assetId].beneficialOwner;
    }

    /// @dev See {IHookERC721Vault-getHoldsAsset}.
    function getHoldsAsset(uint32 assetId) external view returns (bool) {
        return assets[assetId].deposited == true;
        // return _assetOwner(assetId) == address(this);
    }

    function assetAddress(uint32) external view returns (address) {
        return address(_tokenContract);
    }

    /// @dev returns the balance of the erc20 token held within this vault segment
    function assetBalance(uint32 assetId) external view returns (uint256) {
        // todo, implement this
        return 0;
    }

    /// @dev See {IHookERC721Vault-setBeneficialOwner}.
    /// setBeneficialOwner can only be called by the entitlementContract if there is an activeEntitlement.
    function setBeneficialOwner(uint32 assetId, address newBeneficialOwner) public virtual {
        if (hasActiveEntitlement(assetId)) {
            require(
                msg.sender == assets[assetId].operator,
                "setBeneficialOwner-only the contract with the active entitlement can update the beneficial owner"
            );
        } else {
            require(
                msg.sender == assets[assetId].beneficialOwner,
                "setBeneficialOwner-only the current owner can update the beneficial owner"
            );
        }
        _setBeneficialOwner(assetId, newBeneficialOwner);
    }

    /// @dev See {IHookERC721Vault-clearEntitlement}.
    /// @dev This can only be called if an entitlement currently exists, otherwise it would be a no-op
    function clearEntitlement(uint32 assetId) public {
        require(hasActiveEntitlement(assetId), "clearEntitlement-an active entitlement must exist");
        require(
            msg.sender == assets[assetId].operator,
            "clearEntitlement-only the entitled address can clear the entitlement"
        );
        _clearEntitlement(assetId);
    }

    /// @dev See {IHookERC20Vault-clearEntitlementAndDistribute}.
    /// @dev The entitlement must be exist, and must be called by the {operator}. The operator can specify a
    /// intended receiver, which should match the beneficialOwner. The function will revert if
    /// the receiver and owner do not match.
    /// @param assetId the id of the specific vaulted asset
    /// @param receiver the intended receiver of the asset
    function clearEntitlementAndDistribute(uint32 assetId, address receiver) external nonReentrant {
        require(
            assets[assetId].beneficialOwner == receiver,
            "clearEntitlementAndDistribute-Only the beneficial owner can receive the asset"
        );
        require(receiver != address(0), "clearEntitlementAndDistribute-assets cannot be sent to null address");
        clearEntitlement(assetId);
        IERC20(_tokenContract).transferFrom(address(this), receiver, assets[assetId].amount);
        emit AssetWithdrawn(assetId, receiver, assets[assetId].beneficialOwner);
    }

    /// @dev Validates that a specific signature is actually the entitlement
    /// EIP-712 signed by the beneficial owner specified in the entitlement.
    function validateEntitlementSignature(
        address operator,
        uint32 expiry,
        uint32 assetId,
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
            signer == assets[assetId].beneficialOwner, "validateEntitlementSignature --- not signed by beneficialOwner"
        );
    }

    ///
    /// @dev See {IHookVault-approveOperator}.
    ///
    function approveOperator(address to, uint32 assetId) public virtual override {
        address beneficialOwner = assets[assetId].beneficialOwner;

        require(to != beneficialOwner, "approve-approval to current beneficialOwner");

        require(msg.sender == beneficialOwner, "approve-approve caller is not current beneficial owner");

        _approve(to, assetId);
    }

    /// @dev See {IHookVault-getApprovedOperator}.
    function getApprovedOperator(uint32 assetId) public view virtual override returns (address) {
        return _assetApprovals[assetId];
    }

    /// @dev Approve `to` to operate on `tokenId`
    ///
    /// Emits an {Approval} event.
    /// @param to the address to approve
    /// @param assetId the assetId on which the address will be approved
    function _approve(address to, uint32 assetId) internal virtual {
        _assetApprovals[assetId] = to;
        emit Approval(assets[assetId].beneficialOwner, to, assetId);
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
        uint32 expiry,
        uint32 assetId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        validateEntitlementSignature(operator, expiry, assetId, v, r, s);
        _registerEntitlement(assetId, operator, expiry, assets[assetId].beneficialOwner);
    }

    function _registerEntitlement(uint32 assetId, address operator, uint32 expiry, address beneficialOwner) internal {
        require(
            !hasActiveEntitlement(assetId),
            "_registerEntitlement-existing entitlement must be cleared before registering a new one"
        );

        require(expiry > block.timestamp, "_registerEntitlement-entitlement must expire in the future");
        assets[assetId] = Asset({
            operator: operator,
            expiry: expiry,
            amount: assets[assetId].amount,
            deposited: assets[assetId].deposited,
            beneficialOwner: beneficialOwner
        });
        emit EntitlementImposed(assetId, operator, expiry, beneficialOwner);
    }

    function _clearEntitlement(uint32 assetId) private {
        assets[assetId].expiry = 0;
        assets[assetId].operator = address(0);
        emit EntitlementCleared(assetId, assets[assetId].beneficialOwner);
    }

    function hasActiveEntitlement(uint32 assetId) public view returns (bool) {
        /// Although we do clear the expiry in _clearEntitlement, making the second half of the AND redundant,
        /// we choose to include it here because we rely on this field being null to clear an entitlement.
        return block.timestamp < assets[assetId].expiry && assets[assetId].operator != address(0);
    }

    function getCurrentEntitlementOperator(uint32 assetId) external view returns (bool, address) {
        bool isActive = hasActiveEntitlement(assetId);
        address operator = assets[assetId].operator;

        return (isActive, operator);
    }

    /// @dev get the token id based on an asset's ID
    ///
    /// this function can be overridden if the assetId -> tokenId mapping is modified.
    function _assetTokenId(uint32 assetId) internal view virtual returns (uint256) {
        return assetId;
    }

    /// @dev sets the new beneficial owner for a particular asset within the vault
    function _setBeneficialOwner(uint32 assetId, address newBeneficialOwner) internal {
        require(newBeneficialOwner != address(0), "_setBeneficialOwner-new owner is the zero address");
        assets[assetId].beneficialOwner = newBeneficialOwner;
        _approve(address(0), assetId);
        emit BeneficialOwnerSet(assetId, newBeneficialOwner, msg.sender);
    }
}
