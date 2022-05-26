pragma solidity ^0.8.10;

/// @dev A library for validating signatures from ZeroEx
library Signatures {
  /// @dev Allowed signature types.
  enum SignatureType {
    EIP712
  }

  /// @dev Encoded EC signature.
  struct Signature {
    // How to validate the signature.
    SignatureType signatureType;
    // EC Signature data.
    uint8 v;
    // EC Signature data.
    bytes32 r;
    // EC Signature data.
    bytes32 s;
  }
}
