// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./lib/HookStrings.sol";
import "./lib/Entitlements.sol";

import "./interfaces/IHookERC721VaultFactory.sol";
import "./interfaces/IHookERC721Vault.sol";
import "./interfaces/IHookCoveredCall.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IWETH.sol";

/// @title HookCoveredCallImplV1 an implementation of covered calls on Hook
/// @author Jake Nyquist -- j@hook.xyz
/// @notice Covered call options use this logic to
/// @dev Explain to a developer any extra details
contract HookCoveredCallImplV1 is
  IHookCoveredCall,
  ERC721Burnable,
  ReentrancyGuard,
  Initializable
{
  using Counters for Counters.Counter;

  /**
   * @notice The metadata for each covered call option
   * @param writer The address of the writer that created the call option
   * @param owner The address of the current owner of the underlying, updated as bidding occurs
   * @param tokenAddress The address of the NFT that the option is on
   * @param tokenId The tokenId of the NFT that the option is on
   * @param strike The strike price to exercise the call option
   * @param expiration The expiration time of the call option
   * @param settled a flag that marks when a settlement action has taken place successfully
   * @param bid is the current high bid in the settlement auction
   * @param highBidder is the address that made the current winning bid in the settlement auction
   */
  struct CallOption {
    address writer;
    address tokenAddress;
    uint256 tokenId;
    address vaultAddress;
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

  /// @dev the address of the ERC-721 contract that can serve as underlying assets for this
  /// instrument.
  address public allowedNftContract;

  /// @dev the address of WETH on the chain where this contract is deployed
  address public weth;

  /// --- Constructor
  // the constructor cannot have arugments in proxied contracts.
  constructor() ERC721("CallOption", "CALL") {}

  /// @notice Initializes the specific instance of the instrument contract.
  /// @dev Because the deployed contract is proxied, arguments unique to each deployment
  /// must be passed in an individual initializer. This function is like a consturctor.
  /// @param protocol the address of the Hook protocol (which contains configurations)
  /// @param nftContract the address for the ERC-721 contract that can serve as underlying instruments
  /// @param hookVaultFactory the address of the ERC-721 vault registry
  function initialize(
    address protocol,
    address nftContract,
    address hookVaultFactory
  ) public initializer {
    _protocol = IHookProtocol(protocol);
    _erc721VaultFactory = IHookERC721VaultFactory(hookVaultFactory);
    weth = _protocol.getWETHAddress();
    allowedNftContract = nftContract;
  }

  /// ---- Option Writer Functions ---- //

  /**
   * @dev Mints a new call option for the assets deposited in a particular vault given strike price and expiration.
   * @param _vaultAddress the contract address of the vault currently holding the call option
   * @param _strikePrice the strike price for the call option being written
   * @param _expirationTime time the timestamp after which the option will be expired
   * @param signature the signature used to place the entitlement onto the vault
   */
  function mintWithVault(
    address _vaultAddress,
    uint256 _strikePrice,
    uint256 _expirationTime,
    Signatures.Signature memory signature
  ) external whenNotPaused returns (uint256) {
    /**
     *
     * ************** NOT YET IMPLEMENTED **************
     * TODO(HOOK-798) Create a mint call option based on existing vaults.
     * SCOPE: Implement this method, create an interface for abstract vaults that reveals which assets are within
     * the vault update the signed entitlements to account for both generic assets and specific vault addresses.
     *
     */
    return 0;
  }

  /**
   * @dev Mints a new call option for a particular "underlying" ERC-721 NFT with a given strike price and expiration.
   * @param tokenAddress the contract address of the ERC-721 token that serves as the underlying asset for the call
   * option
   * @param tokenId the tokenId of the underlying ERC-721 token
   * @param strikePrice the strike price for the call option being written
   * @param expirationTime time the timestamp after which the option will be expired
   * @param signature the signature used to place the entitlement onto the vault
   */
  function mint(
    address tokenAddress,
    uint256 tokenId,
    uint256 strikePrice,
    uint256 expirationTime,
    Signatures.Signature memory signature
  ) external whenNotPaused returns (uint256) {
    address tokenOwner = IERC721(tokenAddress).ownerOf(tokenId);
    require(
      allowedNftContract == tokenAddress,
      "mint -- token must be on the project allowlist"
    );

    // NOTE: we can mint the option since our contract is approved
    // this is to ensure additionally that the msg.sender isn't a unexpected address
    require(
      msg.sender == tokenOwner ||
        IERC721(tokenAddress).isApprovedForAll(tokenOwner, msg.sender),
      "mint -- caller must be token owner or operator"
    );
    require(
      IERC721(tokenAddress).isApprovedForAll(tokenOwner, address(this)),
      "mint -- HookCoveredCall must be operator"
    );

    // NOTE: The settlement auction always occurs one day before expiration
    require(
      expirationTime > block.timestamp + 1 days,
      "mint -- expirationTime must be more than one day in the future time"
    );
    _optionIds.increment();

    // FIND OR CREATE HOOK VAULT, SET AN ENTITLEMENT
    address vault = _erc721VaultFactory.getVault(tokenAddress, tokenId);
    if (vault == address(0)) {
      vault = _erc721VaultFactory.makeVault(tokenAddress, tokenId);
    }

    /// IMPORTANT: the entitlement entitles the user to this contract address. That means that even if this
    // implementation code were upgraded, the contract at this address (i.e. with the new implementation) would
    // retain the entitlement.
    Entitlements.Entitlement memory entitlement = Entitlements.Entitlement({
      beneficialOwner: tokenOwner,
      operator: address(this),
      nftContract: tokenAddress,
      nftTokenId: tokenId,
      expiry: expirationTime
    });

    // generate the next optionId
    uint256 newOptionId = _optionIds.current();

    // save the option metadata
    optionParams[newOptionId] = CallOption({
      writer: tokenOwner,
      tokenAddress: tokenAddress,
      tokenId: tokenId,
      vaultAddress: vault,
      strike: strikePrice,
      expiration: expirationTime,
      bid: 0,
      highBidder: address(0),
      settled: false
    });

    // transfer the underlying asset into our vault, passing along the entitlement and signature that allows us
    // to control the token in the vault.
    IERC721(tokenAddress).safeTransferFrom(
      tokenOwner,
      vault,
      tokenId,
      abi.encode(entitlement, signature)
    );

    // send the option NFT to the underlying token owner.
    _safeMint(tokenOwner, newOptionId);

    // If msg.sender and tokenOwner are different accounts, approve the msg.sender
    // msg.sendto transfer the option NFT as it already had the right to transfer the underlying NFT.
    if (msg.sender != tokenOwner) {
      _approve(msg.sender, newOptionId);
    }

    emit CallCreated(
      tokenOwner,
      tokenAddress,
      tokenId,
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
      call.expiration - 1 days <= block.timestamp,
      "biddingEnabled -- bidding starts on last day"
    );
    require(
      !call.settled,
      "biddingEnabled -- the owner has already settled the call option"
    );
    _;
  }

  /**
   * @dev bid in the settlement auction for an option. The paid amount is the bid,
   * and the bidder is required to escrow this amount until either the auction ends or another bidder bids higher
   * @param optionId the optionId corresponding to the settlement to bid on.
   */
  function bid(uint256 optionId)
    external
    payable
    nonReentrant
    biddingEnabled(optionId)
  {
    uint256 bidAmt = msg.value;
    CallOption storage call = optionParams[optionId];

    if (msg.sender == call.writer) {
      _writerBid(call, optionId);
    } else {
      _generalBid(call);
    }

    // the new high bidder is the beneficial owner of the asset.
    // The beneficial owner must be set here instead of with a final bid
    // because the ability to
    IHookERC721Vault(call.vaultAddress).setBeneficialOwner(msg.sender);

    // emit event
    emit Bid(optionId, bidAmt, msg.sender);
  }

  function _writerBid(CallOption storage call, uint256 optionId) internal {
    uint256 bidAmt = msg.value + call.strike;

    require(bidAmt > call.bid, "bid - bid is lower than the current bid");
    require(bidAmt > call.strike, "bid - bid is lower than the strike price");

    _returnBidToPreviousBidder(call);

    // set the new bidder
    call.bid = bidAmt;
    call.highBidder = msg.sender;
  }

  function _generalBid(CallOption storage call) internal {
    uint256 bidAmt = msg.value;

    require(bidAmt > call.bid, "bid - bid is lower than the current bid");
    require(bidAmt > call.strike, "bid - bid is lower than the strike price");

    _returnBidToPreviousBidder(call);

    // set the new bidder
    call.bid = bidAmt;
    call.highBidder = msg.sender;
  }

  function _returnBidToPreviousBidder(CallOption storage call) internal {
    uint256 unnormalizedHighBid = call.bid;
    if (call.highBidder == call.writer) {
        unnormalizedHighBid -= call.strike;
    }

    // return current bidder's money
    _safeTransferETHWithFallback(call.highBidder, unnormalizedHighBid);
  }

  /**
   * @dev view function to get the current high settlement bid of an option, or 0 if there is no high bid
   * @param optionId of the option to check
   */
  function currentBid(uint256 optionId) external view returns (uint256) {
    return optionParams[optionId].bid;
  }

  /**
   * @dev view function to get the current high bidder for an option settlement auction, or the null address if no
   * high bidder exists
   * @param optionId of the option to check
   */
  function currentBidder(uint256 optionId) external view returns (address) {
    return optionParams[optionId].highBidder;
  }

  // ----- END OF OPTION FUNCTIONS ---------//

  /**
   * @notice Permissionlessly settle an expired option when the option expires in the money, distributing
   * the proceeds to the Writer, Holder, and Bidder as follows:
   *
   * WRITER (who originally called mint() and owned underlying asset) - recieves the `strike`
   * HOLDER (ownerOf(optionId)) - recieves `bid - strike`
   * HIGH BIDDER (call.highBidder) - becomes ownerOf NFT, pays `bid`.
   *
   * @dev the return nft param allows the underlying asset to remain in its vault. This saves gas
   * compared to first distributing it and then re-depositing it. No royalities or other payments
   * are subtracted from the distribtion amounts.
   *
   * @param optionId of the option to settle.
   * @param returnNft true if token should be withdrawn from vault, false to leave token in the vault.
   */
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
    require(
      !call.settled,
      "settle -- the call cannot already be settled"
    );

    uint256 spread = call.bid - call.strike;

    // return send option holder their earnings
    _safeTransferETHWithFallback(ownerOf(optionId), spread);

    // send option writer the strike price
    _safeTransferETHWithFallback(call.writer, call.strike);

    if (returnNft) {
      IHookERC721Vault(call.vaultAddress).withdrawalAsset();
    }

    // burn nft
    _burn(optionId);

    // set settled to prevent an additional attemt to settle the option
    optionParams[optionId].settled = true;

    emit CallDestroyed(optionId);
  }

  /**
   * @notice Allows the writer to reclaim an entitled asset. This is possible both if they are also the holder of the
   * option NFT or if the option expired early.
   * @dev Allows the writer to reclaim a NFT, either if the option expired OTM or if they also hold the option NFT.
   * @param optionId the asset to reclaim after the auction.
   * @param returnNft true if token should be withdrawn from vault, false to leave token in the vault.
   */
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
      IHookERC721Vault(call.vaultAddress).setBeneficialOwner(call.writer);
    }

    if (returnNft) {
      // Because the call is not expired, we should be able to reclaim the asset from the vault
      if (call.expiration > block.timestamp) {
        IHookERC721Vault(call.vaultAddress).clearEntitlementAndDistribute(
          call.writer
        );
      } else {
        IHookERC721Vault(call.vaultAddress).withdrawalAsset();
      }
    }

    // burn the option NFT
    _burn(optionId);

    // settle the option
    call.settled = true;
    emit CallDestroyed(optionId);

    /**
            WARNING: 
            Currently, if the owner writes an option, and never sells that option, a settlement auction will exist on 
            the protocol. Bidders could bid in this settlement auction, and in the middle of the auction the writer 
            could call this reclaim method. If they do that, they'll get their nft back _however_ there is no way for 
            the current bidder to reclaim their money.

            TODO: To fix this, we're specifically sending that high bidder's money back; however, we should verify that 
            there are not patterns we need to watch here.   
         */
  }

  //// ---- Administrative Fns.

  // forward to protocol pausability
  modifier whenNotPaused() {
    _protocol.throwWhenPaused();
    _;
  }

  //// ------------------------- NFT RELATED FUNCTIONS ------------------------------- ///

  //TODO(HOOK-801) Migrate Instrument NFT to an abstract contract
  /**
   * @dev this is a basic token URI that will show the underlying contract address as well as the
   * token ID in an svg (ripped off from LOOT PROJECT)
   */
  function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
  {
    string[5] memory parts;
    parts[
      0
    ] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>'
    '.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill='
    '"black" /><text x="10" y="20" class="base">';

    parts[1] = HookStrings.toAsciiString(optionParams[tokenId].tokenAddress);

    parts[2] = '</text><text x="10" y="40" class="base">';

    parts[3] = HookStrings.toString(optionParams[tokenId].tokenId);

    parts[4] = "</text></svg>";

    string memory output = string(
      abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4])
    );

    string memory json = Base64.encode(
      bytes(
        string(
          abi.encodePacked(
            '{"name": "Option Id',
            HookStrings.toString(tokenId),
            '", "description": "Hook powers fully on-chain covered call options", "image": '
            '"data:image/svg+xml;base64,',
            Base64.encode(bytes(output)),
            '"}'
          )
        )
      )
    );
    output = string(abi.encodePacked("data:application/json;base64,", json));

    return output;
  }

  /**
   * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
   * @dev this transfer failure could occur if the transferee is a malicious contract
   * so limiting the gas and persisting on fail helps prevent the impace of these calls.
   */
  function _safeTransferETHWithFallback(address to, uint256 amount) internal {
    if (!_safeTransferETH(to, amount)) {
      IWETH(weth).deposit{value: amount}();
      IWETH(weth).transfer(to, amount);
    }
  }

  /**
   * @notice Transfer ETH and return the success status.
   * @dev This function only forwards 30,000 gas to the callee.
   */
  function _safeTransferETH(address to, uint256 value) internal returns (bool) {
    (bool success, ) = to.call{value: value, gas: 30_000}(new bytes(0));
    return success;
  }
}
