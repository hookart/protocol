pragma solidity ^0.8.10;

/// @dev A library for validating signatures from ZeroEx
library Signatures {
  /// @dev Allowed signature types.
  enum SignatureType {
    EIP712,
    ETHSIGN
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

  /// @dev Retrieve the signer of a signature.
  ///      Throws if the signature can't be validated.
  /// @param hash The hash that was signed.
  /// @param signature The signature.
  /// @return recovered The recovered signer address.
  function getSignerOfHash(bytes32 hash, Signature calldata signature)
    internal
    pure
    returns (address recovered)
  {
    // we only support EIP712 sigs
    recovered = ecrecover(hash, signature.v, signature.r, signature.s);

    require(recovered != address(0), "recovered address is null");
  }
}
