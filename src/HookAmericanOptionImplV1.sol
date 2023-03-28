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

import "./interfaces/IHookOptionExercisableVaultValidator.sol";
import "./interfaces/IHookVault.sol";
import "./interfaces/IHookCoveredCall.sol";
import "./interfaces/IHookProtocol.sol";
import "./interfaces/IWETH.sol";

import "./mixin/PermissionConstants.sol";
import "./mixin/HookInstrumentERC721.sol";

/// @title HookAmericanOptionImplV1 is an implementation of an Option on Hook
/// @author Jake Nyquist-j@hook.xyz
/// @custom:coauthor Regynald Augustin-regy@hook.xyz
/// @dev This contract is intended to be an implementation referenced by a proxy
contract HookAmericanOptionImplV1 is
  // IHookCoveredCall,
  HookInstrumentERC721,
  ReentrancyGuard,
  Initializable,
  PermissionConstants
{
  using Counters for Counters.Counter;

  /// @notice The metadata for each option in the protocol
  /// @param writer The address of the writer that created the put option
  /// @param expiration The expiration time of the put option
  /// @param assetId the asset id of the cash within the vault. This cash is the strike price
  /// @param vaultAddress the address of the vault holding the cash securing the put
  /// @param exercisableAssetAddress the address of the asset that can be used to exercise the put
  /// @param exercisableAssetIdStart the first token id that can be used to exercise the put (inclusive)
  /// @param exercisableAssetIdEnd the last token id that can be used to exercise the put (inclusive)
  /// @param settled a flag that marks when a settlement action has taken place successfully. Once this flag is set, ETH should not
  /// be sent from the contract related to this particular option
  struct Option {
    address writer;
    uint32 expiration;
    address considerationAssetVaultAddress;
    uint32 considerationAssetVaultId;
    bytes32 exercisableAssetVaultParameter;
    bool settled;
  }

  /// --- Storage

  /// @dev holds the current ID for the last minted option. The optionId also serves as the tokenId for
  /// the associated option instrument NFT.
  Counters.Counter private _optionIds;

  /// @dev the address of the deployed hook protocol contract, which has permissions and access controls
  IHookProtocol private _protocol;

  /// @dev storage of all existing options contracts.
  mapping(uint256 => Option) public optionParams;

  address public collateralAssetAddress;
    
  address public exercisableAssetAddress;

  /// @dev storage of current active put option secured by a specific asset
  /// mapping(vaultAddress => mapping(assetId => Options))
  // the put option is is referenced via the optionID stored in optionParams
  mapping(IHookVault => mapping(uint32 => uint256)) public assetOptions;

  /// @dev exercising vault validator
  IHookOptionExercisableVaultValidator public vaultValidator;

  /// @dev this is the minimum duration of an option created in this contract instance
  uint256 public minimumOptionDuration;

  /// @dev this is a flag that can be set to pause this particular
  /// instance of the call option contract.
  /// NOTE: settlement auctions are still enabled in
  /// this case because pausing the market should not change the
  /// financial situation for the holder of the options.
  bool public marketPaused;

  /// @dev Emitted when the market is paused or unpaused
  /// @param paused true if paused false otherwise
  event MarketPauseUpdated(bool paused);

  /// @dev emitted when the minimum duration for an option is changed
  /// @param optionDuration new minimum length of an option in seconds.
  event MinOptionDurationUpdated(uint256 optionDuration);

  /// --- Constructor
  // the constructor cannot have arguments in proxied contracts.
  constructor() HookInstrumentERC721("Option") {}

  /// @notice Initializes the specific instance of the instrument contract.
  function initialize(
    address protocol,
    address _collateralAssetAddress,
    address _exercisableAssetAddress,
    address validator,
    address preApprovedMarketplace
  ) public initializer {
    _protocol = IHookProtocol(protocol);
    _preApprovedMarketplace = preApprovedMarketplace;
    vaultValidator = IHookOptionExercisableVaultValidator(validator); 
    collateralAssetAddress = _collateralAssetAddress;
    exercisableAssetAddress = _exercisableAssetAddress;

    /// Initialize basic configuration.
    /// Even though these are defaults, we cannot set them in the constructor because
    /// each instance of this contract will need to have the storage initialized
    /// to read from these values (this is the implementation contract pointed to by a proxy)
    minimumOptionDuration = 1 days;
    marketPaused = false;
  }

  /// ---- Option Writer Functions ---- //

  function mintWithVault(
    address vaultAddress,
    uint32 assetId,
    bytes32 vaultValidatorParams,
    uint32 expirationTime,
    Signatures.Signature calldata signature
  ) external nonReentrant whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);
    require(
      collateralAssetAddress == vault.assetAddress(assetId),
      "mWV-token not allowed"
    );
    require(vault.getHoldsAsset(assetId), "mWV-asset not in vault");
    require(
      _allowedVaultImplementation(
        vaultAddress,
        collateralAssetAddress
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
      _mintOptionWithVault(writer, vault, assetId, vaultValidatorParams, expirationTime);
  }

  function mintWithEntitledVault(
    address vaultAddress,
    uint32 assetId,
    bytes32 vaultValidatorParams,
    uint32 expirationTime
  ) external nonReentrant whenNotPaused returns (uint256) {
    IHookVault vault = IHookVault(vaultAddress);

    require(
      collateralAssetAddress == vault.assetAddress(assetId),
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
        collateralAssetAddress
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
      _mintOptionWithVault(writer, vault, assetId, vaultValidatorParams, expirationTime);
  }

  /// @notice internal use function to record the option and mint it
  /// @dev the vault is completely unchecked here, so the caller must ensure the vault is created,
  /// has a valid entitlement, and has the asset inside it
  /// @param writer the writer of the call option, usually the current owner of the underlying asset
  /// @param vault the address of the IHookVault which contains the underlying assetd
  /// @param assetId the id of the underlying asset
  /// @param expirationTime the time after which the option will be considered expired
  function _mintOptionWithVault(
    address writer,
    IHookVault vault,
    uint32 assetId,
    bytes32 param,
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
    optionParams[newOptionId] = Option({
      writer: writer,
      expiration: expirationTime,
      considerationAssetVaultAddress: address(vault),
      considerationAssetVaultId: assetId,
      exercisableAssetVaultParameter: param,
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

    // emit PutCreated(
    //   writer,
    //   address(vault),
    //   assetId,
    //   newOptionId,
    //   strikePrice,
    //   expirationTime
    // );

    return newOptionId;
  }

  /// @dev method to verify that a particular vault was created by the protocol's vault factory
  /// @param vaultAddress location where the vault is deployed
  /// @param underlyingAddress address of underlying asset
  function _allowedVaultImplementation(
    address vaultAddress,
    address underlyingAddress
  ) internal view returns (bool) {
    // First check if the multiVault is the one to save a bit of gas
    // in the case the user is optimizing for gas savings (by using MultiVault)
//     if (
// //todo: create an erc20 vault
//       // vaultAddress ==
//       // Create2.computeAddress(
//       //   BeaconSalts.erc20VaultSalt(underlyingAddress),
//       //   BeaconSalts.ByteCodeHash,
//       //   address(_erc20VaultFactory)
//       // )
//     ) {
//       return true;
//     }

//     return false;
return true;
  }


  // ----- END OF OPTION FUNCTIONS ---------//

  function exercisePut(uint256 optionId, address exerciseAssetVaultAddress, uint32 assetId)
    external
    nonReentrant
  {
    Option storage put = optionParams[optionId];
    require(put.expiration > block.timestamp, "e-option must not be expired");
    require(!put.settled, "e-the put cannot already be excercised");

    address optionOwner = ownerOf(optionId);
    require (msg.sender == optionOwner, "e-only the option owner can exercise");

/// TODO: use validator to ensure that the excercise vault is good
/// TODO: validate that excercise vault is a protocol vault
/// TODO: validate that the underlying asset in the vault is valid.
    // require(put.exerciseAssetAddress == exerciseAsset, "e-asset must match");
    // require(put.exerciseAssetIdLow >= tokenId, "e-asset id must be in range");
    // require(put.exerciseAssetIdHigh <= tokenId, "e-asset id must be in range");
    
    // Send the option writer the underlying asset
    IHookVault(exerciseAssetVaultAddress).setBeneficialOwner(assetId, put.writer);
    // TODO: should the entitlements be cleared somehow? Should we just be distributing the assets
    IHookVault(put.considerationAssetVaultAddress).setBeneficialOwner(put.considerationAssetVaultId, optionOwner);

    // burn the option NFT
    _burn(optionId);

    // set settled to prevent an additional attempt to exercise the option
    optionParams[optionId].settled = true;

  // TODO: settled event
    // emit PutSettled(optionId);
  }

  /// @dev See {IHookCoveredCall-burnExpiredOption}.
  function burnExpiredOption(
    uint256 optionId
  ) external nonReentrant whenNotPaused {
    Option storage option = optionParams[optionId];

    require(block.timestamp > option.expiration, "bEO-option not expired");

    require(!option.settled, "bEO-option settled");

    // burn the option NFT
    _burn(optionId);

    // settle the option
    option.settled = true;

    //todo: expired put burn event
    // emit ExpiredPutBurned(optionId);
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
  function setMinOptionDuration(
    uint256 newMinDuration
  ) public onlyMarketController {
    minimumOptionDuration = newMinDuration;
    emit MinOptionDurationUpdated(newMinDuration);
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
  function getVaultAddress(
    uint256 optionId
  ) public view override returns (address) {
    return optionParams[optionId].considerationAssetVaultAddress;
  }

  /// @dev see {IHookCoveredCall-getOptionIdForAsset}
  function getOptionIdForAsset(
    address vault,
    uint32 assetId
  ) external view returns (uint256) {
    return assetOptions[IHookVault(vault)][assetId];
  }

  /// @dev see {IHookCoveredCall-getAssetId}.
  function getAssetId(uint256 optionId) public view override returns (uint32) {
    return optionParams[optionId].considerationAssetVaultId;
  }


  /// @dev see {IHookCoveredCall-getExpiration}.
  function getExpiration(
    uint256 optionId
  ) public view override returns (uint256) {
    return optionParams[optionId].expiration;
  }

  function getStrikePrice(uint256 optionId)
    external
    view
    override
    returns (uint256) {
      return 0;
    }
}
