pragma solidity ^0.8.10;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title ERC721 Vault -- a vault designed to contain a single ERC721 asset to be used as escrow.
/// @author Jake Nyquist -- j@hook.xyz
/// @notice The ERC721Vault holds an asset on behalf of the owner. The owner is able to post this
/// asset as collateral to other protocols by signing a messsage, called an "entitlement", that gives
/// a specific account the ability to change the owner. While the asset is held within the vault,
/// any account set as the beneficial owner is able to make external contract calls to benefit from
/// the utility of the asset. Specifically, that means this structure should not be used in order to
/// hold assets in escrow away from owner to benefit an owner for a short period of time.
///
/// ENTITLEMENTS -
///     (1) only one entitlement can be placed at a time.
///     (2) entitlements must expire, but can also be cleared by the entitled party
///     (3) if an entitlement expires, the current beneficial owner gains immediate sole control over the
///        asset
///     (4) the entitled entity can modify the beneficial owner of the asset, but cannot withdrawal.
///     (5) the beneficial owner cannot modify the beneficial owner while an entitlement is in place
///
///
/// SEND TRANSACTION (FLASH LOAN) -
///     (1) owners are able to forward transactions to this vault to other wallets
///     (2) calls to the ERC-721 address are blocked to prevent approvals from being set on the
///         NFT while in escrow, which could allow for theft
///     (3) At the end of each transaction, the ownerOf the vaulted token must still be the vault
///
/// @dev Generally, EOAs should not be specified as the entitled account in an Entitlement because
/// users will be unable to verify the behavior of those accounts as they are non-deterministic.
contract HookERC721Vault is BeaconProxy {
  constructor(
    address beacon,
    address nftAddress,
    uint256 nftTokenId,
    address hookProtocolAddress
  )
    BeaconProxy(
      beacon,
      abi.encodeWithSignature(
        "initialize(address,uint256,address)",
        nftAddress,
        nftTokenId,
        hookProtocolAddress
      )
    )
  {}
}
