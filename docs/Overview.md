# Hook Protocol Overview

Hook is an oracle-free, on-chain option protocol for non-fungible tokens (NFTs). Unlike many popular approaches to NFT DeFi, Hook does not sacrifice the non-fungible nature of NFTs by requiring that they are converted into fungible tokens. NFTs deposited into the Hook protocol only contain unique artistic images and do not contain, reference, represent the price, rate or level of any security, commodity or financial instrument.

Currently, the protocol only supports covered call options; however, it's components are designed to be used elsewhere throughout the protocol.

## Key Protocol Components

### HookProtocol (`HookProtocol.sol`)

### Vaults (`IHookVault.sol`, `HookERC721VaultImplV1.sol`, `HookERC712MultiVaultImplV1.sol`)

#### Multi Vaults

#### Solo Vaults

### Call Option Instrument (`HookCoveredCallImplV1.sol`)

### Factories & Beacon Pattern

#### HookCoveredCallFactory (`HookCoveredCallFactory.sol`)

#### HookERC721VaultFactory (`HookERC721VaultFactory.sol`)

#### Beacon Pattern (`HookUpgradeableBeacon.sol`, `HookBeaconProxy.sol`)

## Call Option Flow Diagram

![Diagram](/img/option-flow-diagram.svg)
