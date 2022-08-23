# Hook Protocol

![Hook](img/hook-protocol-banner.png)

## About

Hook is an oracle-free, on-chain option protocol for non-fungible tokens (NFTs). Unlike many popular approaches to NFT DeFi, Hook does not sacrifice the non-fungible nature of NFTs by requiring that they are converted into fungible tokens.

Note: NFTs deposited into the Hook protocol only contain unique artistic images and do not contain, reference, represent the price, rate or level of any security, commodity or financial instrument.

## Documentation

[Documentation Site](https://docs.hook.xyz/)

[Protocol Overview](docs/Overview.md)

[Definitions](docs/Definitions.md)

[Natspec Generated Docs](docs/generated/index.html)

## Setup

Hook utilizes Foundry for test suites and
`forge install` to install dependencies from git submodules
`npm install` to install hardhat dependencies

The hardhat project is used for coverage testing and deployments
External non-test deps (ie openzeppelin contracts) are added using yarn,
added to the `package.json` file, and then the {remappings.txt} is subsequently
updated. `yarn add -D @openzeppelin/contracts`

## Contract Addresses

See our docs: https://docs.hook.xyz/docs/smart-contract-addresses

## Testing

`forge test` to run all forge tests
`forge test --match-contract <Test Contract Name>` to run tests on a specific contract
`npx hardhat coverage` to run the coverage suite

## Additional Foundry Info

[Foundry](https://github.com/foundry-rs/foundry)

[Foundry Book](https://book.getfoundry.sh)

## Licence

[MIT](LICENCE.md) Copyright 2022 Abstract Labs, Inc.
