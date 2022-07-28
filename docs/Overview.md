# Hook Protocol Overview

Hook is an oracle-free, on-chain option protocol for non-fungible tokens (NFTs). Unlike many popular approaches to NFT DeFi, Hook does not sacrifice the non-fungible nature of NFTs by requiring that they are converted into fungible tokens. NFTs deposited into the Hook protocol only contain unique artistic images and do not contain, reference, represent the price, rate or level of any security, commodity, or financial instrument.

Currently, the protocol only supports covered call options; however, its components are designed to be used elsewhere throughout the protocol.

## Key Protocol Components

### HookProtocol (`HookProtocol.sol`)

The Hook Protocol contract contains the addresses of the vault and instrument factories and implements OpenZeppelin's role-based access control (RBAC) that can be called
by external contracts to verify that specific accounts posses roles across the protocol to take restricted actions.

### Vaults (`IHookVault.sol`, `HookERC721VaultImplV1.sol`, `HookERC712MultiVaultImplV1.sol`)

Vaults hold assets on behalf of users (called `beneficial owners`) while those assets are deposited in the protocol.
Other contracts are able to place a restriction (called an `entitlement`) on a vault that prevents the beneficial owner from removing the asset until a
specific time and allows that entitled contract to change the beneficial owner. Entitlements can only be placed with the permission of a user, either by signing
a specifically formatted message which can be passed by another caller, or by calling a function directly on the contract.

The protocol includes two variants of the vault: one that supports a single ERC-721 token, and another that supports multiple tokenIds within a particular ERC-721 contract.

#### Multi Vaults

The `multi vault` can be deployed for a collection by any account that has a specific role in the protocol utilizing the call factory. It is more gas efficient because the
user does not need to deploy the vault (the vault will already exist when depositing an asset for the first time), and it still allows users to flash loan their assets out of the protocol.
The multi vault does not support any collection with token ids that overflow uint32. Uint32 is used to reduce the number of storage slots that must be allocated to add an asset to the vault;
very few NFT projects based on ERC-721s actually utilize tokenIds outside this range.

#### Solo Vaults

The `solo vault` may be more secure in the event that the vaulted ERC-721 has some interactions between tokens owned by the same account. It also allows the beneficial owner
to send certain transactions from the vault as if it we're their wallet. The solo vault only accepts a specific asset, and designates that asset as assetId 0.

The solo vault implementation simply extends the multi-vault implementation to add this additional functionality.

### Call Option Instrument (`HookCoveredCallImplV1.sol`)

The call option instrument contract implements the logic of the call option (see [Call Option Flow](#call-option-flow)).

The implemented call option is similar to a european call option with a particular cash settlement method designed to reduce the need
for a market maker to exist in the market who would repurchase options close to expiry accept physical delivery and sell the underlying asset.

At a predetermined time prior to the option expiration (one day by default) bidders can begin to place bids in excess of the strike price on
the underlying asset. If such a bid is received, the protocol sells the asset to the high bidder for the high bid. The protocol uses the proceeds
to pay the option writer the strike price and pay the current option holder the remainder of the high bid (i.e. high bid - strike price).

The option instrument is represented in the system as a ERC-721 token that can be transferred. The owner of this particular
token receives the economic value of the call option at settlement.

Only one call option can be outstanding at a given time for a specific underlying asset. The contract stores a mapping from the vault and assetId to the current optionId. If that optionId is 0, it means there is no current outstanding option backed by that asset in the specified vault, so an option may be written. No valid option may have optionId 0.

### Factories & Beacon Pattern

One call option instrument is deployed for each asset contract. All NFTs minted from the instrument appear to be in a single "collection" by NFT aggregators.
Similarly, one multi-vault may be deployed for each asset contract, and one single vault can be deployed per (erc-721 address, tokenId) pair.

#### HookCoveredCallFactory (`HookCoveredCallFactory.sol`)

The covered call factory stores a list of previously deployed call instruments and contains the method to deploy more via Create2. Call instruments are
deployed at deterministic addresses and initialized afterwards.

#### HookERC721VaultFactory (`HookERC721VaultFactory.sol`)

The vaults are deployed from this factory. The factory also contains state recording all the deployed vaults, and is able to findOrCreate the best relevant vault for
a specific tokenId (checking if there is a solo or multi vault, and if not deploying a new solo vault.)

#### Beacon Pattern (`HookUpgradeableBeacon.sol`, `HookBeaconProxy.sol`)

Vaults and Factories are both upgradeable via the beacon pattern. There is a beacon each for the Solo Vault, Multi Vault, and Call Instrument implementation
which may be upgraded to upgrade all instances of these contracts at once. Each individual instance is a HookBeaconProxy which delegates all calls to the implementation that
is currently specified by the proxy. The factories contain the beacon addresses and deploy new proxies with the configuration to make them point to the correct implementation.

No other contracts in the protocol are upgradeable.

## Call Option Flow

![Diagram](/img/option-flow-diagram.svg)

### Minting

Minting can happen via 3 methods:

- `mintWithEntitledVault` Mints an option based on a vault where an entitlement entitling the option instrument that expires at the option expiration is already in place.
- `mintWithVault` Mints an option with an asset placed in a vault serves as the underlying. The signature allowing the option instrument to place a relevant entitlement on the vault
  is passed by the caller.
- `mintWithErc721` is a convenience method that allows the user to approve the call option to transfer a NFT and then the protocol manages the creation of the option and the
  entitlement on their behalf.

When the option is minted, the internal state is updated to track the parameters of the option, and an option NFT is minted into the writer's wallet.

### Trading

The protocol does not address how option NFTs are traded between accounts. In particular, a user may want to sell the option NFT minted to their wallet when they mint the option
in order to earn a premium for selling that right.

### Successful Auction

At a configurable time prior to expiration, the settlement process begins by allowing anyone to submit bids for the underlying asset. The bids must be higher than the
strike price.

If these bids are received, anyone can permissionlessly after expiration call the settlement function. This function will distribute the auction proceeds (strike price to
the writer, (high bid - strike price) to current instrument NFT holder) and burn the option instrument nft.

At this point, the new beneficial owner of the asset can withdrawal that asset from the vault or utilize the `mintWithVault` function to mint a new option based on the
already vaulted asset.

### Reclaim active Auction

If the writer wishes to withdraw the underlying asset from an active option, they first must obtain the option instrument NFT and transfer it to the writer account.
Then, they may call the `reclaim` function, which will release the entitlement on the vault, return any active bids to the bidder, and burn the option NFT.
They may then either withdrawal the asset from the vault or mint a new option with it.

### Failed Auction

If the option expires with no bids, the owner is still the beneficial owner of the underlying asset contained in the vault. They may withdrawal the asset, or they may mint a new option
using the `mintWithVault` function.

## Protocol Permissions

- `ADMIN_ROLE` The holder of this role is able to set the factory addresses at the protocol level
- `ALLOWLISTER_ROLE` The holder of this role can create new call option markets and new multi-vaults
- `PAUSER_ROLE` the holder of this role can pause the protocol at the protocol level
- `VAULT_UPGRADER` the holder of this role can upgrade the implementation pointed to by the vault beacons
- `CALL_UPGRADER` the holder of this role can upgrade the implementation pointed to by the call instrument beacon
- `MARKET_CONF` the holder of this role can make changes to the market configurations on any call option instrument
- `COLLECTION_CONF` the holder of this role can make changes to collection configurations on the protocol level. These configurations may be referenced by any vault (or, technically, any call option) which supports a specific ERC-721 contract address

## Protocol considerations

### Instrument NFT Marketplace

The 0x v4 protocol is pre-approved to transfer instrument NFTs minted in the protocol, and the metadata placed on the NFTs has been created with these orders in mind.

Any protocol designed to be utilized as a marketplace for ERC-721 tokens could potentially be used to facilitate the sale of options.

### Complex order types, collections on orders

Some users may want to create and sign an order that can be filled by an option that is not yet minted. For example, it could be useful to show the market that a
user is willing to pay a specific price for any option from a collection with a strike price less than an amount and an expiration after a certain time.

The call option exposes certain methods to read metadata like expiration time and strike price. The 0x protocol implements a [property validator](https://protocol.0x.org/en/latest/basics/orders.html#nft-order-property) interface that allows the offerer to create a contract that reads this call option metadata to ensure it is within the required range and
accept any tokens, including ones not minted at order creation time, that match those parameters.

### Fees

The protocol does not charge fees on the protocol level

### NFT Royalties

The protocol does not pay out NFT royalties

### Pausing

The protocol can be paused in the event that an incident occurs. When the protocol is paused, no new options can be minted, no new assets can be deposited into any vault.
However, in order to preserve the economic implications even in the event of a protocol pause, the settlement auctions may still occur. This is because options are time-sensitive; i.e.
the value of the option is determined at a very specific time. If that time can be arbitrarily changed, it is difficult to assess the value of the option asset.
