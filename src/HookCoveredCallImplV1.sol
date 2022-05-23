// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./lib/Entitlements.sol";

import "./interfaces/IHookERC721VaultFactory.sol";
import "./interfaces/IHookVault.sol";
import "./interfaces/IHookCoveredCall.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IWETH.sol";

import "./mixin/PermissionConstants.sol";
import "./mixin/HookInstrumentERC721.sol";

/// @title HookCoveredCallImplV1 an implementation of covered calls on Hook
/// @author Jake Nyquist -- j@hook.xyz
/// @notice Covered call options use this logic to
/// @dev Explain to a developer any extra details
contract HookCoveredCallImplV1 is
  IHookCoveredCall,
  HookInsturmentERC721,
  ReentrancyGuard,
  Initializable,
  PermissionConstants
{
  using Counters for Counters.Counter;

  /// @notice The metadata for each covered call option
  /// @param writer The address of the writer that created the call option
  /// @param owner The address of the current owner of the underlying, updated as bidding occurs
  /// @param vaultAddress the address of the vault holding the underlying asset
  /// @param assetId the asset id of the underlying within the vault
  /// @param strike The strike price to exercise the call option
  /// @param expiration The expiration time of the call option
  /// @param settled a flag that marks when a settlement action has taken place successfully
  /// @param bid is the current high bid in the settlement auction
  /// @param highBidder is the address that made the current winning bid in the settlement auction
  struct CallOption {
    address writer;
    address vaultAddress;
    uint256 assetId;
    uint256 strike;
    uint256 expiration;
    uint256 bid;
    address highBidder;
    bool settled;
  }

  /// --- Storage

  /// @dev holds the current ID for the last minted option. This is also the tokenID of the
  // option NFT
  Counters.Counter private _optionIds;

  /// @dev the address of the factory in the Hook protocol that can be used to generate ERC721 vaults
  IHookERC721VaultFactory private _erc721VaultFactory;

  /// @dev the address of the deployed hook protocol contract, which has permissions and access controls
  IHookProtocol private _protocol;

  /// @dev storage of all existing options contracts.
  mapping(uint256 => CallOption) public optionParams;

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

  /// @dev emitted when the minimun duration for an option is changed
  /// @param optionDuration new minimum length of an option in seconds.
  event MinOptionDurationUpdated(uint256 optionDuration);

  /// --- Constructor
  // the constructor cannot have arugments in proxied contracts.
  constructor() HookInsturmentERC721("Call") {}

  /// @notice Initializes the specific instance of the instrument contract.
  /// @dev Because the deployed contract is proxied, arguments unique to each deployment
  /// must be passed in an individual initializer. This function is like a consturctor.
  /// @param protocol the address of the Hook protocol (which contains configurations)
  /// @param nftContract the address for the ERC-721 contract that can serve as underlying instruments
  /// @param hookVaultFactory the address of the ERC-721 vault registry
  function initialize(
    address protocol,
    address nftContract,
    address hookVaultFactory,
    address preapprovedMarketplace
  ) public initializer {
    _protocol = IHookProtocol(protocol);
    _erc721VaultFactory = IHookERC721VaultFactory(hookVaultFactory);
    weth = _protocol.getWETHAddress();
    _preapprovedMarketplace = preapprovedMarketplace;
    allowedUnderlyingAddress = nftContract;

    /// Initialize basic configuration.
    /// Even though these are defaults, we cannot set them in the constructor because
    /// each instance of this contract will need to have the storage initialized
    /// to read from these values
    minimumOptionDuration = 1 days;
    minBidIncrementBips = 0;
    settlementAuctionStartOffset = 1 days;
    marketPaused = false;
  }

  /// ---- Option Writer Functions ---- //

  /// @dev See {IHookCoveredCall-mintWithVault}.
  function mintWithVault(
    address vaultAddress,
    uint256 assetId,
    uint256 strikePrice,
    uint256 expirationTime,
    Signatures.Signature calldata signature
  ) external whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);

    require(
      allowedUnderlyingAddress == vault.assetAddress(assetId),
      "mintWithVault -- token must be on the project allowlist"
    );
    require(
      vault.getHoldsAsset(assetId),
      "mintWithVault-- asset must be in vault"
    );

    // the beneficial owner is the only one able to impose entitlements, so
    // we need to require that they've done so here.
    address writer = vault.getBeneficialOwner(assetId);
    Entitlements.Entitlement memory entitlement = Entitlements.Entitlement({
      beneficialOwner: writer,
      operator: address(this),
      vaultAddress: address(vault),
      assetId: assetId,
      expiry: expirationTime
    });

    vault.imposeEntitlement(entitlement, signature);

    return
      _mintOptionWithVault(writer, vault, assetId, strikePrice, expirationTime);
  }

  /// @dev See {IHookCoveredCall-mintWithEntitledVault}.
  function mintWithEntitledVault(
    address vaultAddress,
    uint256 assetId,
    uint256 strikePrice,
    uint256 expirationTime
  ) external whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);

    require(
      allowedUnderlyingAddress == vault.assetAddress(assetId),
      "mintWithVault -- token must be on the project allowlist"
    );
    require(
      vault.getHoldsAsset(assetId),
      "mintWithVault-- asset must be in vault"
    );
    (bool active, address operator) = vault.getCurrentEntitlementOperator(
      assetId
    );
    require(
      active && operator == address(this),
      "mintWithVault -- call contact must be the entitled operator"
    );

    require(
      expirationTime == vault.entitlementExpiration(assetId),
      "mintWithVault -- entitlement expiration must match call expiration"
    );

    // the beneficial owner owns the asset so
    // they should recieve the option.
    address writer = vault.getBeneficialOwner(assetId);

    return
      _mintOptionWithVault(writer, vault, assetId, strikePrice, expirationTime);
  }

  /// @dev See {IHookCoveredCall-mintWithErc721}.
  function mintWithErc721(
    address tokenAddress,
    uint256 tokenId,
    uint256 strikePrice,
    uint256 expirationTime
  ) external whenNotPaused returns (uint256) {
    address tokenOwner = IERC721(tokenAddress).ownerOf(tokenId);
    uint256 assetId = tokenId; /// assume that the token is using an individual vault.
    require(
      allowedUnderlyingAddress == tokenAddress,
      "mintWithErc721 -- token must be on the project allowlist"
    );

    // NOTE: we can mint the option since our contract is approved
    // this is to ensure additionally that the msg.sender isn't a unexpected address
    require(
      msg.sender == tokenOwner ||
        IERC721(tokenAddress).isApprovedForAll(tokenOwner, msg.sender),
      "mintWithErc721 -- caller must be token owner or operator"
    );
    require(
      IERC721(tokenAddress).isApprovedForAll(tokenOwner, address(this)),
      "mintWithErc721 -- HookCoveredCall must be operator"
    );

    // FIND OR CREATE HOOK VAULT, SET AN ENTITLEMENT
    IHookERC721Vault vault = _erc721VaultFactory.findOrCreateVault(
      tokenAddress,
      tokenId
    );

    /// IMPORTANT: the entitlement entitles the user to this contract address. That means that even if this
    // implementation code were upgraded, the contract at this address (i.e. with the new implementation) would
    // retain the entitlement.
    Entitlements.Entitlement memory entitlement = Entitlements.Entitlement({
      beneficialOwner: tokenOwner,
      operator: address(this),
      vaultAddress: address(vault),
      assetId: assetId, /// assume that the asset within the vault has assetId 0
      expiry: expirationTime
    });

    // transfer the underlying asset into our vault, passing along the entitlement. The entitlement specified
    // here will be accepted by the vault because we are also simultaneously tendering the asset.
    IERC721(tokenAddress).safeTransferFrom(
      tokenOwner,
      address(vault),
      tokenId,
      abi.encode(entitlement)
    );

    // make sure that the vault actually has the asset.
    require(
      vault.getHoldsAsset(assetId),
      "mintWithErc712 -- asset must be in vault"
    );

    return
      _mintOptionWithVault(
        tokenOwner,
        IHookVault(vault),
        assetId,
        strikePrice,
        expirationTime
      );
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
    uint256 assetId,
    uint256 strikePrice,
    uint256 expirationTime
  ) private returns (uint256) {
    // NOTE: The settlement auction always occurs one day before expiration
    require(
      expirationTime > block.timestamp + minimumOptionDuration,
      "_mintOptionWithVault -- expirationTime must be more than one day in the future time"
    );

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
    // msg.sendto transfer the option NFT as it already had the right to transfer the underlying NFT.
    if (msg.sender != writer) {
      _approve(msg.sender, newOptionId);
    }

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
    require(
      call.expiration > block.timestamp,
      "biddingEnabled -- option already expired"
    );
    require(
      (call.expiration - settlementAuctionStartOffset) <= block.timestamp,
      "biddingEnabled -- bidding starts on last day"
    );
    require(
      !call.settled,
      "biddingEnabled -- the owner has already settled the call option"
    );
    _;
  }

  /// @dev See {IHookCoveredCall-bid}.
  function bid(uint256 optionId)
    external
    payable
    nonReentrant
    biddingEnabled(optionId)
  {
    uint256 bidAmt = msg.value;
    CallOption storage call = optionParams[optionId];

    if (msg.sender == call.writer) {
      /// handle the case where an option writer bids on
      /// an underlying asset that they owned. In this case, as they would be
      /// the recipient of the spread after the auction, they are able to bid
      /// paying only the difference between their bid and the strike.
      bidAmt = msg.value + call.strike;
    }

    require(
      bidAmt >= call.bid + ((call.bid * minBidIncrementBips) / 10000),
      "bid - bid is lower than the current bid + minBidIncrementBips"
    );
    require(bidAmt > call.strike, "bid - bid is lower than the strike price");

    _returnBidToPreviousBidder(call);

    // set the new bidder
    call.bid = bidAmt;
    call.highBidder = msg.sender;

    // the new high bidder is the beneficial owner of the asset.
    // The beneficial owner must be set here instead of with a final bid
    // because the ability to
    IHookVault(call.vaultAddress).setBeneficialOwner(call.assetId, msg.sender);

    // emit event
    emit Bid(optionId, bidAmt, msg.sender);
  }

  function _returnBidToPreviousBidder(CallOption storage call) internal {
    uint256 unnormalizedHighBid = call.bid;
    if (call.highBidder == call.writer) {
      unnormalizedHighBid -= call.strike;
    }

    // return current bidder's money
    _safeTransferETHWithFallback(call.highBidder, unnormalizedHighBid);
  }

  /// @dev See {IHookCoveredCall-currentBid}.
  function currentBid(uint256 optionId) external view returns (uint256) {
    return optionParams[optionId].bid;
  }

  /// @dev See {IHookCoveredCall-currentBidder}.
  function currentBidder(uint256 optionId) external view returns (address) {
    return optionParams[optionId].highBidder;
  }

  // ----- END OF OPTION FUNCTIONS ---------//

  /// @dev See {IHookCoveredCall-settleOption}.
  function settleOption(uint256 optionId, bool returnNft)
    external
    nonReentrant
  {
    CallOption storage call = optionParams[optionId];
    require(
      call.highBidder != address(0),
      "settle -- bid must be won by someone"
    );
    require(
      call.expiration < block.timestamp,
      "settle -- option must be expired"
    );
    require(!call.settled, "settle -- the call cannot already be settled");

    uint256 spread = call.bid - call.strike;

    // If the option writer is the high bidder they don't recieve the strike because they bid on the spread.
    if (call.highBidder != call.writer) {
      // send option writer the strike price
      _safeTransferETHWithFallback(call.writer, call.strike);
    }

    // return send option holder their earnings
    _safeTransferETHWithFallback(ownerOf(optionId), spread);

    if (returnNft) {
      IHookVault(call.vaultAddress).withdrawalAsset(call.assetId);
    }

    // burn nft
    _burn(optionId);

    // set settled to prevent an additional attemt to settle the option
    optionParams[optionId].settled = true;

    emit CallDestroyed(optionId);
  }

  /// @dev See {IHookCoveredCall-reclaimAsset}.
  function reclaimAsset(uint256 optionId, bool returnNft)
    external
    nonReentrant
  {
    CallOption storage call = optionParams[optionId];
    require(
      msg.sender == call.writer,
      "reclaimAsset -- asset can only be reclaimed by the writer"
    );
    require(
      !call.settled,
      "reclaimAsset -- the option has already been settled"
    );

    if (call.writer != ownerOf(optionId)) {
      // if the writer holds the option nft, there are more cases where they're able to reclaim.
      require(
        call.highBidder == address(0),
        "reclaimAsset -- cannot reclaim a sold asset if the option is not writer-owned."
      );
      require(
        call.expiration < block.timestamp,
        "reclaimAsset -- the option must expired unless writer-owned"
      );
    }

    if (call.expiration <= block.timestamp) {
      require(
        call.highBidder == address(0),
        "reclaimAsset -- cannot reclaim a sold asset"
      );
      // send the call back to the owner (because we've refunded the high bidder)
    }

    if (call.highBidder != address(0)) {
      // return current bidder's money
      _safeTransferETHWithFallback(call.highBidder, call.bid);

      // if we have a bid, we may have set the bidder, so make sure to revert it here.
      IHookVault(call.vaultAddress).setBeneficialOwner(
        call.assetId,
        call.writer
      );
    }

    if (returnNft) {
      // Because the call is not expired, we should be able to reclaim the asset from the vault
      if (call.expiration > block.timestamp) {
        IHookVault(call.vaultAddress).clearEntitlementAndDistribute(
          call.assetId,
          call.writer
        );
      } else {
        IHookVault(call.vaultAddress).withdrawalAsset(call.assetId);
      }
    }

    // burn the option NFT
    _burn(optionId);

    // settle the option
    call.settled = true;
    emit CallDestroyed(optionId);

    /// WARNING:
    /// Currently, if the owner writes an option, and never sells that option, a settlement auction will exist on
    /// the protocol. Bidders could bid in this settlement auction, and in the middle of the auction the writer
    /// could call this reclaim method. If they do that, they'll get their nft back _however_ there is no way for
    /// the current bidder to reclaim their money.
  }

  //// ---- Administrative Fns.

  // forward to protocol pausability
  modifier whenNotPaused() {
    require(!marketPaused, "whenNotPaused -- market is paused");
    _protocol.throwWhenPaused();
    _;
  }

  modifier onlyMarketController() {
    require(
      _protocol.hasRole(MARKET_CONF, msg.sender),
      "onlyMarketController -- caller does not have the MARKET_CONF protocol role"
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
    minimumOptionDuration = newMinDuration;
    emit MinOptionDurationUpdated(newMinDuration);
  }

  /// @dev set the minimum overage, in bips, for a new bid compared to the current bid.
  /// @param newBidIncrement the minimum bid increment in basis points (1/100th of 1%)
  function setBidIncrement(uint256 newBidIncrement)
    public
    onlyMarketController
  {
    minBidIncrementBips = newBidIncrement;
    emit MinBidIncrementUpdated(newBidIncrement);
  }

  /// @dev set the settlment auction start offset. Settlement auctions begin at this time prior to expiration.
  /// @param newSettlementStartOffset in seconds (i.e. block.timestamp increments)
  function setSettlementAuctionStartOffset(uint256 newSettlementStartOffset)
    public
    onlyMarketController
  {
    require(
      newSettlementStartOffset < minimumOptionDuration,
      "the settlement auctions cannot start sooner than an option expired"
    );
    settlementAuctionStartOffset = newSettlementStartOffset;
    emit SettlementAuctionStartOffsetUpdated(newSettlementStartOffset);
  }

  /// @dev sets a paused / unpaused state for the market corresponding to this contract
  /// @param paused should the market be set to paused or unpaused
  function setMarketPaused(bool paused) public onlyMarketController {
    marketPaused = paused;
    emit MarketPauseUpdated(paused);
  }

  //// ------------------------- NFT RELATED FUNCTIONS ------------------------------- ////
  //// These fuctions are overrides needed by the HookInstrumentNFT library in order   ////
  //// to generate the NFT view for the project.                                       ////

  function getVaultAddress(uint256 optionId)
    public
    view
    override
    returns (address)
  {
    return optionParams[optionId].vaultAddress;
  }

  function getAssetId(uint256 optionId) public view override returns (uint256) {
    return optionParams[optionId].assetId;
  }

  function getStrikePrice(uint256 optionId)
    public
    view
    override
    returns (uint256)
  {
    return optionParams[optionId].strike;
  }

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
  /// so limiting the gas and persisting on fail helps prevent the impace of these calls.
  function _safeTransferETHWithFallback(address to, uint256 amount) internal {
    if (!_safeTransferETH(to, amount)) {
      IWETH(weth).deposit{value: amount}();
      IWETH(weth).transfer(to, amount);
    }
  }

  /// @notice Transfer ETH and return the success status.
  /// @dev This function only forwards 30,000 gas to the callee.
  function _safeTransferETH(address to, uint256 value) internal returns (bool) {
    (bool success, ) = to.call{value: value, gas: 30_000}(new bytes(0));
    return success;
  }
}
