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

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./lib/Entitlements.sol";
import "./lib/BeaconSalts.sol";

import "./interfaces/IHookERC721VaultFactory.sol";
import "./interfaces/IHookVault.sol";
import "./interfaces/IHookCoveredCall.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IWETH.sol";

import "./mixin/PermissionConstants.sol";
import "./mixin/HookInstrumentERC721.sol";

/// @title HookCoveredCallImplV1 an implementation of covered calls on Hook
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
/// @notice See {IHookCoveredCall}.
/// @dev In the context of a single call option, the role of the writer is non-transferrable.
/// @dev This contract is intended to be an implementation referenced by a proxy
contract HookCoveredCallImplV1 is
  IHookCoveredCall,
  HookInstrumentERC721,
  ReentrancyGuard,
  Initializable,
  PermissionConstants
{
  using Counters for Counters.Counter;

  /// @notice The metadata for each covered call option stored within the protocol
  /// @param writer The address of the writer that created the call option
  /// @param expiration The expiration time of the call option
  /// @param assetId the asset id of the underlying within the vault
  /// @param vaultAddress the address of the vault holding the underlying asset
  /// @param strike The strike price to exercise the call option
  /// @param bid is the current high bid in the settlement auction
  /// @param highBidder is the address that made the current winning bid in the settlement auction
  /// @param settled a flag that marks when a settlement action has taken place successfully. Once this flag is set, ETH should not
  /// be sent from the contract related to this particular option
  struct CallOption {
    address writer;
    uint32 expiration;
    uint32 assetId;
    address vaultAddress;
    uint128 strike;
    uint128 bid;
    address highBidder;
    bool settled;
  }

  /// --- Storage

  /// @dev holds the current ID for the last minted option. The optionId also serves as the tokenId for
  /// the associated option instrument NFT.
  Counters.Counter private _optionIds;

  /// @dev the address of the factory in the Hook protocol that can be used to generate ERC721 vaults
  IHookERC721VaultFactory private _erc721VaultFactory;

  /// @dev the address of the deployed hook protocol contract, which has permissions and access controls
  IHookProtocol private _protocol;

  /// @dev storage of all existing options contracts.
  mapping(uint256 => CallOption) public optionParams;

  /// @dev storage of current call active call option for a specific asset
  /// mapping(vaultAddress => mapping(assetId => CallOption))
  // the call option is is referenced via the optionID stored in optionParams
  mapping(IHookVault => mapping(uint32 => uint256)) public assetOptions;

  /// @dev mapping to store the amount of eth in wei that may
  /// be claimed by the current ownerOf the option nft.
  mapping(uint256 => uint256) public optionClaims;

  /// @dev the address of the token contract permitted to serve as underlying assets for this
  /// instrument.
  address public allowedUnderlyingAddress;

  /// @dev the address of WETH on the chain where this contract is deployed
  address public weth;

  /// @dev this is the minimum duration of an option created in this contract instance
  uint256 public minimumOptionDuration;

  /// @dev this is the minimum amount of the current bid that the new bid
  /// must exceed the current bid by in order to be considered valid.
  /// This amount is expressed in basis points (i.e. 1/100th of 1%)
  uint256 public minBidIncrementBips;

  /// @dev this is the amount of time before the expiration of the option
  /// that the settlement auction will begin.
  uint256 public settlementAuctionStartOffset;

  /// @dev this is a flag that can be set to pause this particular
  /// instance of the call option contract.
  /// NOTE: settlement auctions are still enabled in
  /// this case because pausing the market should not change the
  /// financial situation for the holder of the options.
  bool public marketPaused;

  /// @dev Emitted when the market is paused or unpaused
  /// @param paused true if paused false otherwise
  event MarketPauseUpdated(bool paused);

  /// @dev Emitted when the bid increment is updated
  /// @param bidIncrementBips the new bid increment amount in bips
  event MinBidIncrementUpdated(uint256 bidIncrementBips);

  /// @dev emitted when the settlement auction start offset is updated
  /// @param startOffset new number of seconds from expiration when the start offset begins
  event SettlementAuctionStartOffsetUpdated(uint256 startOffset);

  /// @dev emitted when the minimum duration for an option is changed
  /// @param optionDuration new minimum length of an option in seconds.
  event MinOptionDurationUpdated(uint256 optionDuration);

  /// --- Constructor
  // the constructor cannot have arguments in proxied contracts.
  constructor() HookInstrumentERC721("Call") {}

  /// @notice Initializes the specific instance of the instrument contract.
  /// @dev Because the deployed contract is proxied, arguments unique to each deployment
  /// must be passed in an individual initializer. This function is like a constructor.
  /// @param protocol the address of the Hook protocol (which contains configurations)
  /// @param nftContract the address for the ERC-721 contract that can serve as underlying instruments
  /// @param hookVaultFactory the address of the ERC-721 vault registry
  /// @param preApprovedMarketplace the address of the contract which will automatically approved
  /// to transfer option ERC721s owned by any account when they're minted
  function initialize(
    address protocol,
    address nftContract,
    address hookVaultFactory,
    address preApprovedMarketplace
  ) public initializer {
    _protocol = IHookProtocol(protocol);
    _erc721VaultFactory = IHookERC721VaultFactory(hookVaultFactory);
    weth = _protocol.getWETHAddress();
    _preApprovedMarketplace = preApprovedMarketplace;
    allowedUnderlyingAddress = nftContract;
    /// increment the optionId such that id=0 can be treated as the null value
    _optionIds.increment();

    /// Initialize basic configuration.
    /// Even though these are defaults, we cannot set them in the constructor because
    /// each instance of this contract will need to have the storage initialized
    /// to read from these values (this is the implementation contract pointed to by a proxy)
    minimumOptionDuration = 1 days;
    minBidIncrementBips = 50;
    settlementAuctionStartOffset = 1 days;
    marketPaused = false;
  }

  /// ---- Option Writer Functions ---- //

  /// @dev See {IHookCoveredCall-mintWithVault}.
  function mintWithVault(
    address vaultAddress,
    uint32 assetId,
    uint128 strikePrice,
    uint32 expirationTime,
    Signatures.Signature calldata signature
  ) external nonReentrant whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);
    require(
      allowedUnderlyingAddress == vault.assetAddress(assetId),
      "mWV-token not allowed"
    );
    require(vault.getHoldsAsset(assetId), "mWV-asset not in vault");
    require(
      _allowedVaultImplementation(
        vaultAddress,
        allowedUnderlyingAddress,
        assetId
      ),
      "mWV-can only mint with protocol vaults"
    );
    // the beneficial owner is the only one able to impose entitlements, so
    // we need to require that they've done so here.
    address writer = vault.getBeneficialOwner(assetId);

    require(
      msg.sender == writer || msg.sender == vault.getApprovedOperator(assetId),
      "mWV-called by someone other than the owner or operator"
    );

    vault.imposeEntitlement(
      address(this),
      expirationTime,
      assetId,
      signature.v,
      signature.r,
      signature.s
    );

    return
      _mintOptionWithVault(writer, vault, assetId, strikePrice, expirationTime);
  }

  /// @dev See {IHookCoveredCall-mintWithEntitledVault}.
  function mintWithEntitledVault(
    address vaultAddress,
    uint32 assetId,
    uint128 strikePrice,
    uint32 expirationTime
  ) external nonReentrant whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);

    require(
      allowedUnderlyingAddress == vault.assetAddress(assetId),
      "mWEV-token not allowed"
    );
    require(vault.getHoldsAsset(assetId), "mWEV-asset must be in vault");
    (bool active, address operator) = vault.getCurrentEntitlementOperator(
      assetId
    );
    require(
      active && operator == address(this),
      "mWEV-call contract not operator"
    );

    require(
      expirationTime == vault.entitlementExpiration(assetId),
      "mWEV-entitlement expiration different"
    );
    require(
      _allowedVaultImplementation(
        vaultAddress,
        allowedUnderlyingAddress,
        assetId
      ),
      "mWEV-only protocol vaults allowed"
    );

    // the beneficial owner owns the asset so
    // they should receive the option.
    address writer = vault.getBeneficialOwner(assetId);

    require(
      writer == msg.sender || vault.getApprovedOperator(assetId) == msg.sender,
      "mWEV-only owner or operator may mint"
    );

    return
      _mintOptionWithVault(writer, vault, assetId, strikePrice, expirationTime);
  }

  /// @dev See {IHookCoveredCall-mintWithErc721}.
  function mintWithErc721(
    address tokenAddress,
    uint256 tokenId,
    uint128 strikePrice,
    uint32 expirationTime
  ) external nonReentrant whenNotPaused returns (uint256) {
    address tokenOwner = IERC721(tokenAddress).ownerOf(tokenId);
    require(
      allowedUnderlyingAddress == tokenAddress,
      "mWE7-token not on allowlist"
    );

    require(
      msg.sender == tokenOwner ||
        IERC721(tokenAddress).isApprovedForAll(tokenOwner, msg.sender) ||
        IERC721(tokenAddress).getApproved(tokenId) == msg.sender,
      "mWE7-caller not owner or operator"
    );

    // NOTE: we can mint the option since our contract is approved
    // this is to ensure additionally that the msg.sender isn't a unexpected address
    require(
      IERC721(tokenAddress).isApprovedForAll(tokenOwner, address(this)) ||
        IERC721(tokenAddress).getApproved(tokenId) == address(this),
      "mWE7-not approved operator"
    );

    // FIND OR CREATE HOOK VAULT, SET AN ENTITLEMENT
    IHookERC721Vault vault = _erc721VaultFactory.findOrCreateVault(
      tokenAddress,
      tokenId
    );

    uint32 assetId = 0;
    if (
      address(vault) ==
      Create2.computeAddress(
        BeaconSalts.multiVaultSalt(tokenAddress),
        BeaconSalts.ByteCodeHash,
        address(_erc721VaultFactory)
      )
    ) {
      // If the vault is a multi-vault, it requires that the assetId matches the
      // tokenId, instead of having a standard assetI of 0
      assetId = uint32(tokenId);
    }

    uint256 optionId = _mintOptionWithVault(
      tokenOwner,
      IHookVault(vault),
      assetId,
      strikePrice,
      expirationTime
    );

    // transfer the underlying asset into our vault, passing along the entitlement. The entitlement specified
    // here will be accepted by the vault because we are also simultaneously tendering the asset.
    IERC721(tokenAddress).safeTransferFrom(
      tokenOwner,
      address(vault),
      tokenId,
      abi.encode(tokenOwner, address(this), expirationTime)
    );

    // make sure that the vault actually has the asset.
    require(
      IERC721(tokenAddress).ownerOf(tokenId) == address(vault),
      "mWE7-asset not in vault"
    );

    return optionId;
  }

  /// @notice internal use function to record the option and mint it
  /// @dev the vault is completely unchecked here, so the caller must ensure the vault is created,
  /// has a valid entitlement, and has the asset inside it
  /// @param writer the writer of the call option, usually the current owner of the underlying asset
  /// @param vault the address of the IHookVault which contains the underlying asset
  /// @param assetId the id of the underlying asset
  /// @param strikePrice the strike price for this current option, in ETH
  /// @param expirationTime the time after which the option will be considered expired
  function _mintOptionWithVault(
    address writer,
    IHookVault vault,
    uint32 assetId,
    uint128 strikePrice,
    uint32 expirationTime
  ) private returns (uint256) {
    // NOTE: The settlement auction always occurs one day before expiration
    require(
      expirationTime > block.timestamp + minimumOptionDuration,
      "_mOWV-expires sooner than min duration"
    );

    // verify that, if there is a previous option on this asset, it has already settled.
    uint256 prevOptionId = assetOptions[vault][assetId];
    if (prevOptionId != 0) {
      require(
        optionParams[prevOptionId].settled,
        "_mOWV-previous option must be settled"
      );
    }

    // generate the next optionId
    _optionIds.increment();
    uint256 newOptionId = _optionIds.current();

    // save the option metadata
    optionParams[newOptionId] = CallOption({
      writer: writer,
      vaultAddress: address(vault),
      assetId: assetId,
      strike: strikePrice,
      expiration: expirationTime,
      bid: 0,
      highBidder: address(0),
      settled: false
    });

    // send the option NFT to the underlying token owner.
    _safeMint(writer, newOptionId);

    // If msg.sender and tokenOwner are different accounts, approve the msg.sender
    // to transfer the option NFT as it already had the right to transfer the underlying NFT.
    if (msg.sender != writer) {
      _approve(msg.sender, newOptionId);
    }

    assetOptions[vault][assetId] = newOptionId;

    emit CallCreated(
      writer,
      address(vault),
      assetId,
      newOptionId,
      strikePrice,
      expirationTime
    );

    return newOptionId;
  }

  // --- Bidder Functions

  modifier biddingEnabled(uint256 optionId) {
    CallOption memory call = optionParams[optionId];
    require(call.expiration > block.timestamp, "bE-expired");
    require(
      (call.expiration - settlementAuctionStartOffset) <= block.timestamp,
      "bE-bidding starts on last day"
    );
    require(!call.settled, "bE-already settled");
    _;
  }

  /// @dev method to verify that a particular vault was created by the protocol's vault factory
  /// @param vaultAddress location where the vault is deployed
  /// @param underlyingAddress address of underlying asset
  /// @param assetId id of the asset within the vault
  function _allowedVaultImplementation(
    address vaultAddress,
    address underlyingAddress,
    uint32 assetId
  ) internal view returns (bool) {
    // First check if the multiVault is the one to save a bit of gas
    // in the case the user is optimizing for gas savings (by using MultiVault)
    if (
      vaultAddress ==
      Create2.computeAddress(
        BeaconSalts.multiVaultSalt(underlyingAddress),
        BeaconSalts.ByteCodeHash,
        address(_erc721VaultFactory)
      )
    ) {
      return true;
    }

    try IHookERC721Vault(vaultAddress).assetTokenId(assetId) returns (
      uint256 _tokenId
    ) {
      if (
        vaultAddress ==
        Create2.computeAddress(
          BeaconSalts.soloVaultSalt(underlyingAddress, _tokenId),
          BeaconSalts.ByteCodeHash,
          address(_erc721VaultFactory)
        )
      ) {
        return true;
      }
    } catch (bytes memory) {
      return false;
    }

    return false;
  }

  /// @dev See {IHookCoveredCall-bid}.
  function bid(uint256 optionId)
    external
    payable
    nonReentrant
    biddingEnabled(optionId)
  {
    uint128 bidAmt = uint128(msg.value);
    CallOption storage call = optionParams[optionId];

    if (msg.sender == call.writer) {
      /// handle the case where an option writer bids on
      /// an underlying asset that they owned. In this case, as they would be
      /// the recipient of the spread after the auction, they are able to bid
      /// paying only the difference between their bid and the strike.
      bidAmt += call.strike;
    }

    require(
      bidAmt >= call.bid + ((call.bid * minBidIncrementBips) / 10000),
      "b-must overbid by minBidIncrementBips"
    );
    require(bidAmt > call.strike, "b-bid is lower than the strike price");

    _returnBidToPreviousBidder(call);

    // set the new bidder
    call.bid = bidAmt;
    call.highBidder = msg.sender;

    // the new high bidder is the beneficial owner of the asset.
    // The beneficial owner must be set here instead of with a settlement
    // because otherwise the writer will be able to remove the asset from the vault
    // between the expiration and the settlement call, effectively stealing the asset.
    IHookVault(call.vaultAddress).setBeneficialOwner(call.assetId, msg.sender);

    // emit event
    emit Bid(optionId, bidAmt, msg.sender);
  }

  function _returnBidToPreviousBidder(CallOption storage call) internal {
    uint256 unNormalizedHighBid = call.bid;
    if (call.highBidder == call.writer) {
      unNormalizedHighBid -= call.strike;
    }

    // return current bidder's money
    if (unNormalizedHighBid > 0) {
      _safeTransferETHWithFallback(call.highBidder, unNormalizedHighBid);
    }
  }

  /// @dev See {IHookCoveredCall-currentBid}.
  function currentBid(uint256 optionId) external view returns (uint128) {
    return optionParams[optionId].bid;
  }

  /// @dev See {IHookCoveredCall-currentBidder}.
  function currentBidder(uint256 optionId) external view returns (address) {
    return optionParams[optionId].highBidder;
  }

  // ----- END OF OPTION FUNCTIONS ---------//

  /// @dev See {IHookCoveredCall-settleOption}.
  function settleOption(uint256 optionId) external nonReentrant {
    CallOption storage call = optionParams[optionId];
    require(call.highBidder != address(0), "s-bid must be won by someone");
    require(call.expiration < block.timestamp, "s-option must be expired");
    require(!call.settled, "s-the call cannot already be settled");

    uint256 spread = call.bid - call.strike;

    address optionOwner = ownerOf(optionId);

    // set settled to prevent an additional attempt to settle the option
    optionParams[optionId].settled = true;

    // If the option writer is the high bidder they don't receive the strike because they bid on the spread.
    if (call.highBidder != call.writer) {
      // send option writer the strike price
      _safeTransferETHWithFallback(call.writer, call.strike);
    }

    bool claimable = false;
    if (msg.sender == optionOwner) {
      // send option holder their earnings
      _safeTransferETHWithFallback(optionOwner, spread);

      // burn nft
      _burn(optionId);
    } else {
      optionClaims[optionId] = spread;
      claimable = true;
    }
    emit CallSettled(optionId, claimable);
  }

  /// @dev See {IHookCoveredCall-reclaimAsset}.
  function reclaimAsset(uint256 optionId, bool returnNft)
    external
    nonReentrant
  {
    CallOption storage call = optionParams[optionId];
    require(msg.sender == call.writer, "rA-only writer");
    require(!call.settled, "rA-option settled");
    require(call.writer == ownerOf(optionId), "rA-writer must own");
    require(call.expiration > block.timestamp, "rA-option expired");

    // burn the option NFT
    _burn(optionId);

    // settle the option
    call.settled = true;

    if (call.highBidder != address(0)) {
      // return current bidder's money
      if (call.highBidder == call.writer) {
        // handle the case where the writer is reclaiming as option they were the high bidder of
        _safeTransferETHWithFallback(call.highBidder, call.bid - call.strike);
      } else {
        _safeTransferETHWithFallback(call.highBidder, call.bid);
      }

      // if we have a bid, we may have set the bidder, so make sure to revert it here.
      IHookVault(call.vaultAddress).setBeneficialOwner(
        call.assetId,
        call.writer
      );
    }

    if (returnNft) {
      // Because the call is not expired, we should be able to reclaim the asset from the vault
      IHookVault(call.vaultAddress).clearEntitlementAndDistribute(
        call.assetId,
        call.writer
      );
    } else {
      IHookVault(call.vaultAddress).clearEntitlement(call.assetId);
    }

    emit CallReclaimed(optionId);
  }

  /// @dev See {IHookCoveredCall-burnExpiredOption}.
  function burnExpiredOption(uint256 optionId)
    external
    nonReentrant
    whenNotPaused
  {
    CallOption memory call = optionParams[optionId];

    require(block.timestamp > call.expiration, "bEO-option expired");

    require(!call.settled, "bEO-option settled");

    require(call.highBidder == address(0), "bEO-option has bids");

    // burn the option NFT
    _burn(optionId);

    // settle the option
    call.settled = true;

    emit ExpiredCallBurned(optionId);
  }

  /// @dev See {IHookCoveredCall-claimOptionProceeds}
  function claimOptionProceeds(uint256 optionId) external nonReentrant {
    address optionOwner = ownerOf(optionId);
    require(msg.sender == optionOwner, "cOP-owner only");
    uint256 claim = optionClaims[optionId];
    delete optionClaims[optionId];
    if (claim != 0) {
      _burn(optionId);
      emit CallProceedsDistributed(optionId, optionOwner, claim);
      _safeTransferETHWithFallback(optionOwner, claim);
    }
  }

  //// ---- Administrative Fns.

  // forward to protocol-level pauseability
  modifier whenNotPaused() {
    require(!marketPaused, "market paused");
    _protocol.throwWhenPaused();
    _;
  }

  modifier onlyMarketController() {
    require(
      _protocol.hasRole(MARKET_CONF, msg.sender),
      "caller needs MARKET_CONF"
    );
    _;
  }

  /// @dev configures the minimum duration for a newly minted option. Options must be at
  /// least this far away in the future.
  /// @param newMinDuration is the minimum option duration in seconds
  function setMinOptionDuration(uint256 newMinDuration)
    public
    onlyMarketController
  {
    require(settlementAuctionStartOffset < newMinDuration);
    minimumOptionDuration = newMinDuration;
    emit MinOptionDurationUpdated(newMinDuration);
  }

  /// @dev set the minimum overage, in bips, for a new bid compared to the current bid.
  /// @param newBidIncrement the minimum bid increment in basis points (1/100th of 1%)
  function setBidIncrement(uint256 newBidIncrement)
    public
    onlyMarketController
  {
    require(newBidIncrement < 20 * 100);
    minBidIncrementBips = newBidIncrement;
    emit MinBidIncrementUpdated(newBidIncrement);
  }

  /// @dev set the settlement auction start offset. Settlement auctions begin at this time prior to expiration.
  /// @param newSettlementStartOffset in seconds (i.e. block.timestamp increments)
  function setSettlementAuctionStartOffset(uint256 newSettlementStartOffset)
    public
    onlyMarketController
  {
    require(newSettlementStartOffset < minimumOptionDuration);
    settlementAuctionStartOffset = newSettlementStartOffset;
    emit SettlementAuctionStartOffsetUpdated(newSettlementStartOffset);
  }

  /// @dev sets a paused / unpaused state for the market corresponding to this contract
  /// @param paused should the market be set to paused or unpaused
  function setMarketPaused(bool paused) public onlyMarketController {
    require(marketPaused == !paused, "sMP-must change");
    marketPaused = paused;
    emit MarketPauseUpdated(paused);
  }

  //// ------------------------- NFT RELATED FUNCTIONS ------------------------------- ////
  //// These functions are overrides needed by the HookInstrumentNFT library in order   ////
  //// to generate the NFT view for the project.                                       ////

  /// @dev see {IHookCoveredCall-getVaultAddress}.
  function getVaultAddress(uint256 optionId)
    public
    view
    override
    returns (address)
  {
    return optionParams[optionId].vaultAddress;
  }

  /// @dev see {IHookCoveredCall-getOptionIdForAsset}
  function getOptionIdForAsset(address vault, uint32 assetId)
    external
    view
    returns (uint256)
  {
    return assetOptions[IHookVault(vault)][assetId];
  }

  /// @dev see {IHookCoveredCall-getAssetId}.
  function getAssetId(uint256 optionId) public view override returns (uint32) {
    return optionParams[optionId].assetId;
  }

  /// @dev see {IHookCoveredCall-getStrikePrice}.
  function getStrikePrice(uint256 optionId)
    public
    view
    override
    returns (uint256)
  {
    return optionParams[optionId].strike;
  }

  /// @dev see {IHookCoveredCall-getExpiration}.
  function getExpiration(uint256 optionId)
    public
    view
    override
    returns (uint256)
  {
    return optionParams[optionId].expiration;
  }

  //// ----------------------------- ETH TRANSFER UTILITIES --------------------------- ////

  /// @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
  /// @dev this transfer failure could occur if the transferee is a malicious contract
  /// so limiting the gas and persisting on fail helps prevent the impact of these calls.
  function _safeTransferETHWithFallback(address to, uint256 amount) internal {
    if (!_safeTransferETH(to, amount)) {
      IWETH(weth).deposit{value: amount}();
      IWETH(weth).transfer(to, amount);
    }
  }

  /// @notice Transfer ETH and return the success status.
  /// @dev This function only forwards 30,000 gas to the callee.
  /// this prevents malicious contracts from causing the next bidder to run out of gas,
  /// which would prevent them from bidding successfully
  function _safeTransferETH(address to, uint256 value) internal returns (bool) {
    (bool success, ) = to.call{value: value, gas: 30_000}(new bytes(0));
    return success;
  }
}
