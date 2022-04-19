pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title A covered call instrument
/// @author Jake Nyquist -- j@hook.xyz
/// @notice This contract implements a "Covered Call Option". A call option gives the holder the right, but not
/// the obligation to purchase an asset at a fixed time in the future (the expiry) for a fixed price (the strike).
/// The call option implementation here is similar to a european call option because the asset can only be purchased
/// at the expiration. The call option is "covered"
/// because the underlying asset, (in this case a NFT), must be held in escrow for the entire duration of the
/// option. In the context of a single call option from this implementation contract, the role of the writer
/// is non-transferrable. There are three phases to the call option:
///
/// (1) WRITING:
/// The owner of the NFT can mint an option by calling the "mint" function using the parameters of the subject ERC-721; specifying
/// additionally their preferred strike price and expiration. An "insturment nft" is minted to the writer's address,
/// where the holder of this ERC-721 will recieve the economic benefit of holding the option.
///
/// (2) SALE:
/// The sale occurs outside of the context of this contract; however, the ZeroEx market contracts are pre-approved to transfer the
/// tokens. By Selling the instrument NFT, the writer earns a "premium" for selling their option. The option may be sold and re-sold
/// multiple times.
///
/// (3) SETTLEMENT:
/// One day prior to the expiration, and auction begins. People are able to call bid() for more than the strike price to place a bid.
/// If, at settlement, the high bid is greater than the strike, (bid - strike) is transferred to the holder of the insturment NFT,
/// the strike price is transferred to the writer. The high bid is transferred to the holder of the option.
///
/// @dev The HookCoveredCall is a BeaconProxy, which allows the implemenation of the protocol to be upgraded in the future.
/// Further, each covered call is mapped to a specific ERC-721 contract address -- meaning there is one covered call contract
/// per collection.
contract HookCoveredCall is BeaconProxy {
    // TODO(HOOK-789)[GAS]: Explore implemeting the initialize function by setting storage slots on the
    // newly deployed contract to avoid additional method calls.
    constructor(
        address beacon,
        address nftAddress,
        address protocol,
        address hookVaultFactory
    )
        BeaconProxy(
            beacon,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                protocol,
                nftAddress,
                hookVaultFactory
            )
        )
    {}
}
