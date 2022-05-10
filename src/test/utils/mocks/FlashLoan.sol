pragma solidity ^0.8.10;

import "src/interfaces/IERC721FlashLoanReceiver.sol";
import "../tokens/TestERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FlashLoanSuccess is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata
  ) external returns (bool) {
    IERC721(nftContract).approve(vault, tokenId);
    return IERC721(nftContract).ownerOf(tokenId) == address(this);
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

contract FlashLoanDoesNotApprove is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata
  ) external returns (bool) {
    // skip this:
    // IERC721(nftContract).approve(vault, tokenId);
    return IERC721(nftContract).ownerOf(tokenId) == address(this);
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

contract FlashLoanReturnsFalse is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata
  ) external returns (bool) {
    IERC721(nftContract).approve(vault, tokenId);
    return false;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

contract FlashLoanApproveForAll is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata
  ) external returns (bool) {
    IERC721(nftContract).setApprovalForAll(vault, true);
    return IERC721(nftContract).ownerOf(tokenId) == address(this);
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

contract FlashLoanBurnsAsset is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata
  ) external returns (bool) {
    IERC721(nftContract).setApprovalForAll(vault, true);
    TestERC721(nftContract).burn(tokenId);
    return true;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}

contract FlashLoanVerifyCalldata is IERC721FlashLoanReceiver {
  constructor() {}

  function executeOperation(
    address nftContract,
    uint256 tokenId,
    address,
    address vault,
    bytes calldata params
  ) external returns (bool) {
    require(
      keccak256(params) == keccak256("hello world"),
      "should check helloworld"
    );
    IERC721(nftContract).setApprovalForAll(vault, true);
    return true;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) public pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }
}
