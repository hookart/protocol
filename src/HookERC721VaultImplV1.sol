pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IHookERC721Vault.sol";
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
    /// ----------------  STORAGE ---------------- ///

    /// @dev these are the NFT contract address and tokenId the vault is covering
    address private _nftContract;
    uint256 private _tokenId;

    /// @dev if airdrops should be disabled to this vault, we mark that here.
    bool private _airdropsAllowed;

    /// @dev the current owner of the asset, who is able to withdrawl it if there are no
    /// entitlements.
    address private beneficialOwner;

    /// @dev these fields mark when there is an active entitlement on this contract. If these
    /// fields are non-null, the beneficial owner is unable to withdrawl until either the entitlement
    /// expires or the fields are cleared.
    Entitlements.Entitlement private _currentEntitlement;

    /// @dev mark if an entitlement has been set.
    bool private _hasEntitlement;

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
        _nftContract = nftContract;
        _hasEntitlement = false;
    }

    /// ---------------- PUBLIC FUNCTIONS ---------------- ///

    /// @notice Withdrawl an unencumbered asset from this vault
    /// @dev withdrawals can only be performed by the beneficial owner if there are no entitlements
    function withdrawalAsset() public {
        // require(msg.sender == beneficialOwner, "the beneficial owner is the only one able to withdrawl");
        require(
            !hasActiveEntitlement(),
            "withdrawalAsset -- the asset canot be withdrawn with an active entitlement"
        );

        IERC721(_nftContract).safeTransferFrom(
            address(this),
            beneficialOwner,
            _tokenId
        );

        emit assetWithdrawn(msg.sender, beneficialOwner);
    }

    /// @notice Add an entitlement claim to the asset held within the contract
    /// @dev The entitlement must be signed by the current beneficial owner of the contract. Anyone can submit the 
    /// entitlement
    /// @param entitlement The entitlement to impose onto the contract
    /// @param signature an EIP-712 signauture of the entitlement struct signed by the beneficial owner
    function imposeEntitlement(
        Entitlements.Entitlement memory entitlement,
        Signatures.Signature memory signature
    ) public {
        require(
            beneficialOwner != address(0),
            "imposeEntitlement -- beneficial owner must be set to impose an entitlement"
        );

        // the beneficial owner of an asset is able to set any entitlement on their own asset
        // as long as it has not already been committed to someone else.
        _verifyAndRegisterEntitlement(entitlement, signature, beneficialOwner);

        /// TODO(HOOK-800): Evaluate if we should require the msg.sender to be the contract gaining the entitlement to 
        /// prevent phishing attacks where people accidentally entitle random contracts while interacting with a valid 
        /// one.
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator, // this arg is the address of the operator
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public virtual override returns (bytes4) {
        /// We should make sure that the owner of an asset never changes simply as a result of someone sending
        /// a NFT into this contract.
        ///
        /// (1) If the contract is specified to hold a specific NFT, and that NFT is sent to the contract.
        /// set the beneficial owner of this vault to be current owner of the asset getting sent.
        ///
        /// (2) If another nft is sent to the contract, we should verify that airdrops are allowed to this vault;
        /// if they are disabled, we should not return the selector, otherwise we can allow them.
        ///
        /// IMPORTANT: If an unrelated contract is currently holding the asset on behalf of an owner and then
        /// subsequently transfers the asset into the contract, it needs to manually call (setBeneficialOwner)
        /// after making this call to ensure that the true owner of the asset is known to the vault. Otherwise,
        /// the owner will lose the ability to reclaim their asset.
        ///
        /// ALSO IMPORTANT: Checking here that the method is called by the acutal token contract, not anyone
        /// else.
        if (msg.sender == _nftContract && tokenId == _tokenId) {
            // There is no need to check if we currently have this token or an entitlement set.
            // Even if the contract were able to get into this state, it should still accept the asset
            // which will allow it to enforce the entitlement.
            _setBeneficialOwner(from);

            // If additional data is sent with the transfer, we attempt to parse an entitlement from it.
            // this allows the entitlement to be registered ahead of time.
            if (data.length > 0) {
                // Decode the order, signature from `data`. If `data` does not encode such parameters, this
                // will throw.
                (
                    Entitlements.Entitlement memory entitlement,
                    Signatures.Signature memory signature
                ) = abi.decode(
                        data,
                        (Entitlements.Entitlement, Signatures.Signature)
                    );
                _verifyAndRegisterEntitlement(
                    entitlement,
                    signature,
                    beneficialOwner
                );
            }
        } else {
            // If we're recieving an airdrop or other asset uncovered by escrow to this address, we should ensure
            // that this is allowed by our current settings.
            require(
                _airdropsAllowed,
                "onERC721Received -- non-escrow asset returned when airdrops are disabled"
            );
        }
        emit assetReceived(from, operator, msg.sender, tokenId);
        return this.onERC721Received.selector;
    }

    /// @dev Allows a beneficial owner to send an arbitrary call from this wallet as long as the underlying NFT
    /// is still owned by us after the transaction. The ether value sent is forwarded. Return value is suppressed.
    /// @param to Destination address of transaction.
    /// @param data Data payload of transaction.
    /// @return success if the call was successful.
    function execTransaction(address to, bytes memory data)
        public
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
            to != _nftContract,
            "execTransaction -- cannot send transactions to the NFT contract itself"
        );

        /***
         *
         * TODO(HOOK-804) - MIGRATE THIS TO A FLASHLOAN ARCHITECTURE.
         * The current implementation here causes too many security risks
         * where arbitrary unknown code can be executed as the holder, meaning
         * that people may be able to extract the asset while they are the beneficial
         * owner. By requiring that the asset is transfered to another contract to perform
         * these calls, and then returned before the end of the block, we can be
         * much more sure that extranous approvals have not been performed in the meantime.
         *
         ***/

        // Execute transaction without further confirmations.
        (success, ) = address(to).call{value: msg.value}(data);

        require(IERC721(_nftContract).ownerOf(_tokenId) == address(this));
    }

    /// @notice Looks up the address of the currently entitled operator
    /// @dev returns the null address if there is no active entitlement
    /// @return operator the address of the current operator
    function entitledOperatorContract() public view returns (address operator) {
        if (!hasActiveEntitlement()) {
            return address(0);
        } else {
            _currentEntitlement.operator;
        }
    }

    /// @notice Looks up the expiration timestamp of the current entitlement
    /// @dev returns the 0 if no entitlement is set
    /// @return expiry the block timestamp after which the entitlement expires
    function entitlementExpiration() public view returns (uint256 expiry) {
        if (!hasActiveEntitlement()) {
            return 0;
        } else {
            _currentEntitlement.expiry;
        }
    }

    /// @notice looks up the current beneficial owner of the underlying asset
    function getBeneficialOwner() public view returns (address) {
        return beneficialOwner;
    }

    /// @notice checks if the asset is currently stored in the vault
    function holdsAsset() public view returns (bool holdsAsset) {
        return IERC721(_nftContract).ownerOf(_tokenId) == address(this);
    }

    /// @notice setBeneficialOwner updates the current address that can claim the asset when it is free of entitlements.
    /// @dev setBeneficialOwner can only be called by the entitlementContract if there is an activeEntitlement.
    /// @param _newBeneficialOwner the account of the person who is able to withdrawl when there are no entitlements.
    function setBeneficialOwner(address _newBeneficialOwner) public {
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
        _setBeneficialOwner(_newBeneficialOwner);
    }

    /// @notice Allowes the entitled address to release their claim on the asset
    /// @dev This can only be called if an entitlement currently exists, otherwise it would be a no-op
    function clearEntitlement() public {
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

    /// @notice Removes the active entitlement from a vault and returns the asset to the beneficial owner
    /// @dev The entitlement must be exist, and must be called by the {operator}. The operator can specify a
    /// intended reciever, which should match the beneficialOwner. The function will throw if
    /// the reciever and owner do not match.
    /// @param reciever the intended reciever of the asset
    function clearEntitlementAndDistribute(address reciever)
        public
        nonReentrant
    {
        require(
            beneficialOwner == reciever,
            "clearEntitlementAndDistribute -- Only the beneficial owner can recieve the asset"
        );
        clearEntitlement();
        IERC721(_nftContract).safeTransferFrom(
            address(this),
            reciever,
            _tokenId
        );
        emit assetWithdrawn(msg.sender, beneficialOwner);
    }

    /// @dev Get the EIP-712 hash of an Entitlement.
    /// @param entitlement The entitlement to hash
    /// @return entitlementHash The hash of the entitlement.
    function getEntitlementHash(Entitlements.Entitlement memory entitlement)
        public
        view
        returns (bytes32 entitlementHash)
    {
        return
            _getEIP712Hash(Entitlements.getEntitlementStructHash(entitlement));
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

    /// ---------------- INTERNAL/PRIVATE FUNCTIONS ---------------- ///

    /// @notice Verify that an entitlement is properly signed and apply it to the asset if able.
    /// @dev The entitlement must be signed by the beneficial owner of the asset in order for it to be considered valid
    /// @param entitlement the entitlement to impose on the asset
    /// @param signature the EIP-712 signed entitlement by the beneficial owner
    /// @param _beneficialOwner the beneficial owner signing the entitlement.
    function _verifyAndRegisterEntitlement(
        Entitlements.Entitlement memory entitlement,
        Signatures.Signature memory signature,
        address _beneficialOwner
    ) private {
        validateEntitlementSignature(entitlement, signature);
        require(
            !hasActiveEntitlement(),
            "_verifyAndRegisterEntitlement -- existing entitlement must be cleared before registering a new one"
        );
        require(
            entitlement.beneficialOwner == _beneficialOwner,
            "_verifyAndRegisterEntitlement -- beneficialOwner does not match the entitlement"
        );
        require(
            entitlement.nftContract == _nftContract,
            "_verifyAndRegisterEntitlement -- the entitled contract must match the vault contract"
        );
        require(
            entitlement.nftTokenId == _tokenId,
            "_verifyAndRegisterEntitlement -- the entitlement tokenId must match the vault tokenId"
        );
        _currentEntitlement = entitlement;
        _hasEntitlement = true;
        emit entitlementImposed(
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
            0,
            0
        );
        _hasEntitlement = false;
        emit entitlementCleared(beneficialOwner);
    }

    function hasActiveEntitlement() public view returns (bool) {
        return
            block.timestamp < _currentEntitlement.expiry &&
            _hasEntitlement == true;
    }

    function _setBeneficialOwner(address _newBeneficialOwner) private {
        beneficialOwner = _newBeneficialOwner;
        emit beneficialOwnerSet(_newBeneficialOwner, msg.sender);
    }
}
