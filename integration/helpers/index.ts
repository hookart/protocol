import { ethers } from "hardhat";
import type {
  TypedDataDomain,
  TypedDataField,
} from "@ethersproject/abstract-signer";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export interface Entitlement {
  beneficialOwner: string;
  operator: string;
  vaultAddress: string;
  assetId: string;
  expiry: string;
}

const signTypedData = async (
  domain: TypedDataDomain,
  types: Record<string, TypedDataField[]>,
  value: Record<string, any>,
  signer: SignerWithAddress
) => {
  const rawSignature = await signer._signTypedData(domain, types, value);
  const { v, r, s } = ethers.utils.splitSignature(rawSignature);
  const signature = {
    signatureType: 2, // EIP712 - signature utils 0x
    v,
    r,
    s,
  };
  return signature;
};

function genEntitlementTypedData(
  entitlement: Entitlement,
  verifyingContract: string
) {
  return {
    // All properties on a domain are optional
    domain: {
      name: "Hook",
      version: "1.0.0",
      chainId: 1337, // pulled from hardhat.config.ts
      verifyingContract, // Hook Protocol
    },
    // The named list of all type definitions
    types: {
      Entitlement: [
        { name: "beneficialOwner", type: "address" },
        { name: "operator", type: "address" },
        { name: "vaultAddress", type: "address" },
        { name: "assetId", type: "uint256" },
        { name: "expiry", type: "uint256" },
      ],
    },
    // The data to sign
    value: entitlement,
  };
}

export async function signEntitlement(
  beneficialOwner: string,
  operator: string,
  vaultAddress: string,
  assetId: string,
  expiry: string,
  signer: SignerWithAddress,
  hookProtocol: string // Hook Protocol
) {
  // Sign Entitlement
  const entitlement = {
    beneficialOwner,
    operator,
    vaultAddress,
    assetId,
    expiry,
  };
  const { domain, types, value } = genEntitlementTypedData(
    entitlement,
    hookProtocol
  );
  const signature = await signTypedData(domain, types, value, signer);

  return signature;
}
