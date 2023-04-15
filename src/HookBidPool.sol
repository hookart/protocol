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

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./lib/PoolOrders.sol";
import "./lib/Signatures.sol";
import "./lib/lyra/BlackScholes.sol";

import "./mixin/EIP712.sol";

import "./interfaces/IHookProtocol.sol";
import "./interfaces/IHookOption.sol";

import "./interfaces/delegate-cash/IDelegationRegistry.sol";

/// @notice HookBidPools allows users to make off-chain orders in terms of an implied volatility which
/// can later be filled by an option seller. The price of the sell will be computed using the Black-Scholes
/// model at bid time.
/// @title HookBidPool
/// @author Jake Nyquist-j@hook.xyz
/// @dev This contract is directly interacted with by users, and holds approvals for ERC-20 tokens.
///
/// In order for an order to be filled, it must be signed by the maker and the maker must have enough balance
/// to provide the order proceeds and relevant fees. The maximum bid the order maker has offered is computed
/// using the volatility and risk-free rate signed into the order. This information is combined with the NFT
/// floor price provided by the off-chain oracle to compute the maximum bid price.
/// If the amount of consideration requested by the seller + the protocol fees is less than the maximum bid,
/// the order can then be filled. The seller will receive their requested proceeds, the protocol will receive
/// their fees, and the buyer receives their option nft.
///
/// The order must also be signed by the off-chain order validity oracle. This oracle is responsible for allowing
/// the user to make gasless cancellations which take effect as soon as the last outstanding order validity signature
/// expires. Alternatively, the user can make a calculation directly on the contract with their order hash to immediately
/// cancel their order.
contract HookBidPool is EIP712, ReentrancyGuard, AccessControl {
    // use the SafeERC20 library to safely interact with ERC-20 tokens
    using SafeERC20 for IERC20;

    /// @notice The asset price claim is a signed struct used to verify the price of
    /// an underlying asset.
    struct AssetPriceClaim {
        /// @notice All prices are denominated in ETH or ETH-equivalent tokens
        uint256 assetPriceInWei;
        /// @notice The timestamp when this price point was computed or observed (in seconds)
        uint256 priceObservedTimestamp;
        /// @notice the last timestamp where this claim is still valid
        uint256 goodTilTimestamp;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Ensure that the order was not canceled as of some off-chain verified lookback
    /// time or mechanism.
    struct OrderValidityOracleClaim {
        /// @notice the eip712 hash of the corder
        bytes32 orderHash;
        /// @notice the timestamp of the last block (inclusive) where this claim is considered valid
        uint256 goodTilTimestamp;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice event emitted when the paused state of the contract changes\
    ///
    /// @param newState the new paused state of the contract
    event PauseUpdated(bool newState);

    /// @notice event emitted when the fee take rate is updated
    ///
    /// @param feeBips the new fee take rate in bips
    event FeesUpdated(uint64 feeBips);

    /// @notice event emitted when the oracle address is updated
    ///
    /// @param oracle the new oracle address
    event PriceOracleSignerUpdated(address oracle);

    /// @notice event emitted when the protocol fee recipient is updated
    ///
    /// @param recipient the new protocol fee recipient
    event ProtocolFeeRecipientUpdated(address recipient);

    /// @notice event emitted when the order validity oracle is updated
    ///
    /// @param oracle the new order validity oracle
    event OrderValidityOracleSignerUpdated(address oracle);

    /// @notice event emitted when the protocol address is updated
    ///
    /// @param protocol the new protocol address
    event ProtocolAddressSet(address protocol);

    /// @notice event emitted when an option is sold
    ///
    /// @param maker the signer who made the order initially
    /// @param taker the caller who filled the order
    /// @param orderHash the eip-712 hash of the order
    /// @param proceeds the proceeds the seller receives
    /// @param fees the fees the buyer paid, in addition to the proceeds to the sellers
    /// @param optionContract the contract address of the Hook option instrument
    /// @param optionId the id of the option within the optionContract
    event OrderFilled(
        address maker,
        address taker,
        bytes32 orderHash,
        uint256 proceeds,
        uint256 fees,
        address optionContract,
        uint256 optionId
    );

    /// @notice event emitted when an order is canceled
    ///
    /// @param maker the signer who made the order initially
    /// @param orderHash the eip-712 hash of the order
    event OrderCancelled(address maker, bytes32 orderHash);

    /// LOCAL VARIABLES ///

    /// @notice the address of the WETH contract on the deployed network
    address immutable weth;

    /// @notice the address of the HookProtocol contract
    IHookProtocol protocol;

    /// @notice the address of the price oracle signer
    address priceOracleSigner;

    /// @notice the address of the order validity oracle signer
    address orderValidityOracleSigner;

    /// @notice the fee in basis points (1/100th of a percent) that the seller pays to the protocol
    /// this fee is assessed at order fill time using the current value, which could be different
    /// from the time that the order was made
    uint64 feeBips;
    address feeRecipient;
    bool paused;
    mapping(bytes32 => uint256) orderFills;
    mapping(bytes32 => bool) orderCancellations;

    /// CONSTANTS ///

    // 1% = 0.01, 100 bips = 1%, 10000 bps = 100% == 1
    uint256 constant BPS_TO_DECIMAL = 10e14;

    /// https://github.com/delegatecash/delegation-registry
    IDelegationRegistry constant DELEGATE_CASH_REGISTRY =
        IDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);

    /// ROLE CONSTANTS ///

    /// @notice the role that can pause the contract - should be held by a mulitsig
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice the role that can update the protocol address - should be held by a multisig
    bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");

    /// @notice the role that can update the fee amount and recipient, should be held by a timelock
    bytes32 public constant FEES_ROLE = keccak256("FEES_ROLE");

    /// @notice the role that can update the price oracle signer, should be held by a timelock
    /// If an oracle is compromised, the pool should be paused immediately, a new oracle nominated via
    /// the timelock, and the pool unpaused after the timelock delay has passed.
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    /// CONSTRUCTOR ///

    /// @param _weth the address of the WETH contract
    /// @param _priceOracleSigner the public key for the price oracle signer
    /// @param _initialAdmin the initial holder of roles on the contract
    /// @param _orderValidityOracleSigner the public key for the order validity oracle signer
    /// @param _feeBips the initial fee in basis points (1/100th of a percent) that the seller pays to the protocol
    /// @param _feeRecipient the initial address that receives the protocol fees
    /// @param _protocol the address of the HookProtocol contract
    constructor(
        address _weth,
        address _initialAdmin,
        address _priceOracleSigner,
        address _orderValidityOracleSigner,
        uint64 _feeBips,
        address _feeRecipient,
        address _protocol
    ) {
        weth = _weth;
        priceOracleSigner = _priceOracleSigner;
        orderValidityOracleSigner = _orderValidityOracleSigner;
        feeBips = _feeBips;
        feeRecipient = _feeRecipient;
        protocol = IHookProtocol(_protocol);
        setAddressForEipDomain(_protocol);

        /// set the contract to be initially paused after deploy.
        /// it should not be unpaused until the relevant roles have been
        /// already assigned to separate wallets
        paused = true;

        /// SETUP THE ROLES, AND GRANT THEM TO THE INITIAL ADMIN
        /// the holders of these roles should be modified
        /// The role admin is also set to the role itself, such that
        /// the deployer cannot unilaterally reassign the roles.
        _grantRole(ORACLE_ROLE, _initialAdmin);
        _setRoleAdmin(ORACLE_ROLE, ORACLE_ROLE);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _setRoleAdmin(PAUSER_ROLE, PAUSER_ROLE);
        _grantRole(PROTOCOL_ROLE, _initialAdmin);
        _setRoleAdmin(PROTOCOL_ROLE, PROTOCOL_ROLE);
        _grantRole(FEES_ROLE, _initialAdmin);
        _setRoleAdmin(FEES_ROLE, FEES_ROLE);

        /// emit events to make it easier for off chain indexers to
        /// track contract state from inception
        emit PauseUpdated(paused);
        emit FeesUpdated(_feeBips);
        emit ProtocolAddressSet(_protocol);
        emit ProtocolFeeRecipientUpdated(_feeRecipient);
        emit PriceOracleSignerUpdated(_priceOracleSigner);
        emit OrderValidityOracleSignerUpdated(_orderValidityOracleSigner);
    }

    /// PUBLIC/EXTERNAL FUNCTIONS ///

    /// @notice sells a european call option to a bidder
    ///
    /// @param order the order struct from the off-chain orderbook
    /// @param orderSignature the signature of the order struct signed by the maker
    /// @param assetPrice the price of the underlying asset, signed off-chain by the oracle
    /// @param orderValidityOracleClaim the claim that the order is still valid, signed off-chain by the oracle
    /// @param saleProceeds the proceeds from the sale desired by the filler/caller, denominated in the quote asset
    /// @param optionInstrumentAddress the address of the Hook option instrument contract
    /// @param optionId the id of the option token
    ///
    /// @dev the optionInstrumentAddress must be trusted by the orderer (maker) when signing to be related
    /// to their desired market / option terms (i.e. the option must be a european call option on the
    /// correct underlying asset). If the option instrument/market supports many different sub-collections,
    /// as in the case with artblocks or a foundation shared contract, then a corresponding property validator
    /// should be included in the order as to ensure that the underlying asset for the option is the one that
    /// the maker intended.
    ///
    /// The value of the "bid" for a specific order changes (decreases) with each block because the time
    /// until the option expires decreases. Instead of computing the highest possible sale proceeds at
    /// the time of the order, an implementer can compute a slightly lower sale proceeds, perhaps
    /// at a time a few blocks into the future, to ensure that the transaction is still successful.
    /// If they do this, the protocol won't earn extra fees -- that savings is passed on to the buyer.
    function sellOption(
        PoolOrders.Order calldata order,
        Signatures.Signature calldata orderSignature,
        AssetPriceClaim calldata assetPrice,
        OrderValidityOracleClaim calldata orderValidityOracleClaim,
        uint256 saleProceeds,
        address optionInstrumentAddress,
        uint256 optionId
    ) external nonReentrant whenNotPaused {
        // input validity checks
        bytes32 eip712hash = _getEIP712Hash(PoolOrders.getPoolOrderStructHash(order));
        (uint256 expiry, uint256 strikePrice) = _performSellOptionOrderChecks(
            order, eip712hash, orderSignature, assetPrice, orderValidityOracleClaim, optionInstrumentAddress, optionId
        );
        (uint256 ask, uint256 bid) = _computeOptionAskAndBid(order, assetPrice, expiry, strikePrice, saleProceeds);

        require(bid >= ask, "order not high enough for the ask");

        IERC721(optionInstrumentAddress).safeTransferFrom(msg.sender, order.maker, optionId);
        IERC20(weth).safeTransferFrom(order.maker, msg.sender, saleProceeds);
        IERC20(weth).safeTransferFrom(order.maker, feeRecipient, ask - saleProceeds);

        // update order fills
        orderFills[eip712hash] += 1;
        emit OrderFilled(
            order.maker, msg.sender, eip712hash, saleProceeds, ask - saleProceeds, optionInstrumentAddress, optionId
            );
    }

    /// @notice Function to allow a maker to cancel all examples of an order that they've already signed.
    /// If an order has already been filled, but support more than one fill, calling this function cancels
    /// future fills of the order (but not current ones).
    ///
    /// @param order the order struct that should no longer be fillable.
    ///
    /// @dev this function is available even when the pool is paused in case makers want to cancel orders
    /// as a result of the event that motivated the pause.
    function cancelOrder(PoolOrders.Order calldata order) external {
        require(msg.sender == order.maker, "Only the order maker can cancel the order");
        bytes32 eip712hash = _getEIP712Hash(PoolOrders.getPoolOrderStructHash(order));
        orderCancellations[eip712hash] = true;
        emit OrderCancelled(order.maker, eip712hash);
    }

    /// EXTERNAL ACCESS-CONTROLLED FUNCTIONS ///

    function setProtocol(address _protocol) external onlyRole(PROTOCOL_ROLE) {
        setAddressForEipDomain(_protocol);
        protocol = IHookProtocol(_protocol);
        emit ProtocolAddressSet(_protocol);
    }

    function setPriceOracleSigner(address _priceOracleSigner) external onlyRole(ORACLE_ROLE) {
        priceOracleSigner = _priceOracleSigner;
        emit PriceOracleSignerUpdated(_priceOracleSigner);
    }

    function setOrderValidityOracleSigner(address _orderValidityOracleSigner) external onlyRole(ORACLE_ROLE) {
        orderValidityOracleSigner = _orderValidityOracleSigner;
        emit OrderValidityOracleSignerUpdated(_orderValidityOracleSigner);
    }

    function setFeeBips(uint64 _feeBips) external onlyRole(FEES_ROLE) {
        require(_feeBips <= 10000, "Fee bips over 10000");
        feeBips = _feeBips;
        emit FeesUpdated(_feeBips);
    }

    function setFeeRecipient(address _feeRecipient) external onlyRole(FEES_ROLE) {
        feeRecipient = _feeRecipient;
        emit ProtocolFeeRecipientUpdated(_feeRecipient);
    }

    /// @dev sets a paused / unpaused state for this bid pool
    /// @param _paused should the bid pool be set to paused?
    function setPoolPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        require(paused == !_paused, "cannot set to current state");
        paused = _paused;
        emit PauseUpdated(paused);
    }

    /// MODIFIERS ///

    /// @dev modifier to check that the market is not paused
    /// this also includes a check that the overall Hook protocol is
    /// not paused. The Hook Protocol pause is designed to convert the
    /// protocol to a close-only state in the event of a disaster.
    modifier whenNotPaused() {
        require(!paused, "market paused");
        protocol.throwWhenPaused();
        _;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice checks that the validity claim was signed by the oracle, and that the claim is not expired
    ///
    /// NOTE: if the order validity oracle is compromised, the security provided by this check will be invalidated
    /// if a user does not trust the off-chain order validity oracle, they should cancel orders by using the
    /// cancel function provider.
    ///
    /// @param claim the claim to be verified
    /// @param orderHash the hash of the subject order
    /// @dev this function uses an ETHSIGN signature because it makes it much easier to test as many
    /// signers automatically sign messages in this format. It is not technically necessary as standard
    /// wallet providers will not be signing these messages.
    function _validateOrderValidityOracleClaim(OrderValidityOracleClaim calldata claim, bytes32 orderHash)
        internal
        view
    {
        bytes memory claimEncoded = abi.encode(orderHash, claim.goodTilTimestamp);

        bytes32 claimHash = keccak256(claimEncoded);
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", claimHash));

        address signer = ecrecover(prefixedHash, claim.v, claim.r, claim.s);

        require(signer == orderValidityOracleSigner, "Claim is not signed by the orderValidityOracle");
        require(claim.goodTilTimestamp > block.timestamp, "Claim is expired");
    }

    /// @notice checks that the asset price claim was signed by the oracle, and that the claim is not expired
    ///
    /// NOTE: If the price oracle signer is compromised, any claims made by the compromised signer will be
    /// considered valid. This is a security risk, must trust that this oracle has not been compromised and
    /// provides accurate price data in order to utilize this pool. If a user believes that the oracle is
    /// compromised, they should cancel orders by using the cancel function provided. Additionally, the
    /// protocol should be paused in the event of a compromised oracle.
    ///
    /// @param claim the claim to be verified
    function _validateAssetPriceClaim(AssetPriceClaim calldata claim) internal view {
        bytes memory claimEncoded =
            abi.encode(claim.assetPriceInWei, claim.priceObservedTimestamp, claim.goodTilTimestamp);

        bytes32 claimHash = keccak256(claimEncoded);
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", claimHash));

        address signer = ecrecover(prefixedHash, claim.v, claim.r, claim.s);

        require(signer == priceOracleSigner, "Claim is not signed by the priceOracle");
        require(claim.goodTilTimestamp > block.timestamp, "Claim is expired");
    }

    /// @notice validates the EIP-712 signature for the order. If the order maker has
    /// delegated rights for this contract to a different signer, then orders signed by
    /// that signer are also be considered valid.
    ///
    /// @param hash the EIP-721 hash of the order struct
    /// @param maker the maker of the order, who should have signed the order
    /// @param orderSignature the signature of the order
    /// @dev it is essential that the correct order maker is passed in at this step
    function _validateOrderSignature(bytes32 hash, address maker, Signatures.Signature calldata orderSignature)
        internal
        view
    {
        address signer = ecrecover(hash, orderSignature.v, orderSignature.r, orderSignature.s);
        require(signer != address(0), "Order signature is invalid"); // sanity check - maker should not be 0
        if (signer == maker) {
            // if the order maker signed the order, than accept the signer's signature
            return;
        }
        // If the maker has delegated control of this contract to a different signer,
        // then accept this signed order as a valid signature.
        require(
            DELEGATE_CASH_REGISTRY.checkDelegateForContract(signer, maker, address(this)), "Order signature is invalid"
        );
    }

    /// @dev modifies the supplied base implied volatility to account for skew.
    /// @param strikePrice the strike price of the option
    /// @param assetPrice the asset price of the underlying asset
    /// @param order the order to source the volatility and skew
    function _computeVolDecimalWithSkewDecimal(uint256 strikePrice, uint256 assetPrice, PoolOrders.Order memory order)
        internal
        view
        returns (uint256)
    {
        uint256 decimalVol = order.impliedVolBips * BPS_TO_DECIMAL;
        if (order.skewDecimal == 0) {
            return decimalVol;
        }
        uint256 xDistance = Math.abs(int256(strikePrice) - int256(assetPrice));
        uint256 volIncrease = DecimalMath.multiplyDecimal(xDistance, order.skewDecimal);
        uint256 volWithSkew = decimalVol + volIncrease;
        return volWithSkew;
    }

    /// @dev compute the input checks for selling an option.
    /// factored out to resolve a stack space issue.
    function _performSellOptionOrderChecks(
        PoolOrders.Order calldata order,
        bytes32 eip712hash,
        Signatures.Signature calldata orderSignature,
        AssetPriceClaim calldata assetPrice,
        OrderValidityOracleClaim calldata orderValidityOracleClaim,
        address optionInstrumentAddress,
        uint256 optionId
    ) internal returns (uint256 expiry, uint256 strikePrice) {
        /// validate the signature from the order validity oracle
        _validateOrderValidityOracleClaim(orderValidityOracleClaim, eip712hash);
        /// validate that the maker signed their order.
        _validateOrderSignature(eip712hash, order.maker, orderSignature);
        /// validate the asset price claim from the price oracle
        _validateAssetPriceClaim(assetPrice);

        /// verify that the price signal is not too old, or that the order does not
        /// sepcify a maximum price signal age
        require(
            order.maxPriceSignalAge == 0
                || block.timestamp - order.maxPriceSignalAge < assetPrice.priceObservedTimestamp,
            "Price signal is too old"
        );

        // Verify that the order is not cancelled or filled too many times
        require(!orderCancellations[eip712hash], "Order is cancelled");
        require(orderFills[eip712hash] < order.size, "Order is filled");

        require(order.orderExpiry > block.timestamp, "Order is expired");
        require(order.direction == PoolOrders.OrderDirection.BUY, "Order is not a buy order");

        IHookOption hookOption = IHookOption(optionInstrumentAddress);
        strikePrice = hookOption.getStrikePrice(optionId);
        expiry = hookOption.getExpiration(optionId);

        _validateOptionProperties(order, optionInstrumentAddress, optionId);
        /// even if the order technically allows it, make sure this pool cannot be used for trading
        /// expired options.
        require(block.timestamp + order.minOptionDuration < expiry, "Option is too close to expiry");
        require(
            order.maxOptionDuration == 0 || block.timestamp + order.maxOptionDuration > expiry,
            "Option is too far from expiry"
        );

        /// verify that the option is not too far out of the money given the strike price multiple
        /// if one has been specified by the maker
        require(
            order.maxStrikePriceMultiple == 0
                || (strikePrice - assetPrice.assetPriceInWei) * 1e18 / assetPrice.assetPriceInWei
                    < order.maxStrikePriceMultiple,
            "option is too far out of the money"
        );
    }

    function _computeOptionAskAndBid(
        PoolOrders.Order calldata order,
        AssetPriceClaim calldata assetPrice,
        uint256 expiry,
        uint256 strikePrice,
        uint256 saleProceeds
    ) internal view returns (uint256 ask, uint256 bid) {
        ask = (saleProceeds * (10000 + feeBips)) / 10000;
        uint256 decimalVol = _computeVolDecimalWithSkewDecimal(strikePrice, assetPrice.assetPriceInWei, order);
        int256 rateDecimal = int256(order.riskFreeRateBips * BPS_TO_DECIMAL);
        (uint256 callBid, uint256 putBid) = BlackScholes.optionPrices(
            BlackScholes.BlackScholesInputs({
                timeToExpirySec: (expiry - block.timestamp),
                volatilityDecimal: decimalVol,
                spotDecimal: assetPrice.assetPriceInWei, // ETH prices are already 18 decimals
                strikePriceDecimal: strikePrice,
                rateDecimal: rateDecimal
            })
        );
        if (order.optionType == PoolOrders.OptionType.CALL) {
            bid = callBid;
        } else {
            bid = putBid;
        }
    }

    function _validateOptionProperties(PoolOrders.Order memory order, address optionInstrument, uint256 optionId)
        internal
        view
    {
        // If no properties are specified, the order is valid for any instrument.
        if (order.nftProperties.length == 0) {
            return;
        } else {
            // Validate each property
            for (uint256 i = 0; i < order.nftProperties.length; i++) {
                PoolOrders.Property memory property = order.nftProperties[i];
                // `address(0)` is interpreted as a no-op. Any token ID
                // will satisfy a property with `propertyValidator == address(0)`.
                if (address(property.propertyValidator) == address(0)) {
                    continue;
                }

                // Call the property validator and throw a descriptive error
                // if the call reverts.
                try property.propertyValidator.validateProperty(optionInstrument, optionId, property.propertyData) {}
                catch {
                    revert("Property validation failed for the provided optionId");
                }
            }
        }
    }
}
