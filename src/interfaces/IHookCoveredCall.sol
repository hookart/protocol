pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../lib/Signatures.sol";

interface IHookCoveredCall is IERC721 {
  // TODO(HOOK-802) Migrate natspec docs to interfaces instead of implementations, inherit on implementations
  event CallCreated(
    address writer,
    address tokenContract,
    uint256 tokenId,
    uint256 optionId,
    uint256 strikePrice,
    uint256 expiration
  );

  event CallDestroyed(uint256 optionId);

  event Bid(uint256 optionId, uint256 bidAmount, address bidder);

  function mint(
    address _tokenAddress,
    uint256 _tokenId,
    uint256 _strikePriceWei,
    uint256 _expirationTime,
    Signatures.Signature memory signature
  ) external returns (uint256);

  function mintWithVault(
    address _vaultAddress,
    uint256 _strikePrice,
    uint256 _expirationTime,
    Signatures.Signature memory signature
  ) external returns (uint256);

  function bid(uint256 optionId) external payable;

  function currentBid(uint256 optionId) external view returns (uint256);

  function currentBidder(uint256 optionId) external view returns (address);

  function reclaimAsset(uint256 optionId, bool returnAsset) external;

  function settleOption(uint256 optionId, bool returnAsset) external;
}
