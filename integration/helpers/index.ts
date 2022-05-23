import { ethers } from "hardhat";
import type {
  TypedDataDomain,
  TypedDataField,
} from "@ethersproject/abstract-signer";
import type { Web3Provider } from "@ethersproject/providers";

export interface Entitlement {
  beneficialOwner: string;
  operator: string;
  nftContract: string;
  nftTokenId: string;
  expiry: string;
}

const signTypedData = async (
  domain: TypedDataDomain,
  types: Record<string, TypedDataField[]>,
  value: Record<string, any>,
  provider: Web3Provider,
  // TODO: Validate we might not need this for "getSigner" it's optional
  // we need to make sure that it always uses the correct one when not sending.
  address: string
) => {
  const signer = provider.getSigner(address);
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
  chainId: number,
  verifyingContract: string
) {
  return {
    // All properties on a domain are optional
    domain: {
      name: "Hook",
      version: "1.0.0",
      chainId,
      verifyingContract, // Hook Protocol
    },
    // The named list of all type definitions
    types: {
      Entitlement: [
        { name: "beneficialOwner", type: "address" },
        { name: "operator", type: "address" },
        { name: "nftContract", type: "address" },
        { name: "nftTokenId", type: "uint256" },
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
  nftContract: string,
  nftTokenId: string,
  expiry: string,
  provider: Web3Provider,
  hookProtocol: string // Hook Protocol
) {
  // Sign Entitlement
  const entitlement = {
    beneficialOwner,
    operator,
    nftContract,
    nftTokenId,
    expiry,
  };
  const { domain, types, value } = genEntitlementTypedData(
    entitlement,
    1337, // pulled from hardhat.config.ts
    hookProtocol
  );
  const signature = await signTypedData(
    domain,
    types,
    value,
    provider,
    beneficialOwner
  );

  return signature;
}
