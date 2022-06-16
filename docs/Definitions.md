# Definitions relevant for the Hook Protocol

## General

| term                 | definition                                                                                                           |
| -------------------- | -------------------------------------------------------------------------------------------------------------------- |
| european call option | the right, but not the obligation, to buy an underlying asset for a specific price at a specific time in the future  |
| underlying asset     | the specific asset upon which the option contract is based                                                           |
| option holder        | the person that holds the right but not the obligation to buy a specific underlying asset                            |
| strike price         | the price for which, at the end of a european call option, an underlying asset can be purchased by the option holder |
| covered option       | an option where the underlying asset is posted as collateral                                                         |
| account              | either a smart contract or EOA (externally owned account, i.e. private key) on a EVM-compatible blockchain           |

## Hook Vault

The Vault holds an asset on behalf of the owner. The owner is able to post this asset as collateral to other accounts by creating an "entitlement", that gives a specific account the ability to change the beneficial owner of the asset. While the asset is held within the vault, any account set as the beneficial owner is able to make external contract calls to benefit from the utility of the asset.

| term             | definition                                                                                                                                                                              |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| beneficial owner | The account on behalf of which a vault holds an asset                                                                                                                                   |
| entitlement      | An entitlement grants a specific entitled account (contract or EOA) to change the beneficial owner of an asset contained in a vault until the entitlement either expires or is removed. |

## Covered Call Options

Terms defined within the scope of a Hook Protocol Covered Call Option

| term               | definition                                                                        |
| ------------------ | --------------------------------------------------------------------------------- |
| settlement auction | the process by which the fair market value for the underlying asset is determined |
| option holder      | the account that holds the ERC-721 representing the call option                   |
| strike price       | the price in wei at which the protocol can purchase the underlying asset          |
