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

export enum OrderDirection {
  BUY = 0,
  SELL = 1,
}

export enum OptionType {
  CALL = 0,
  PUT = 1,
}

export interface VolOrderNFTProperties {
  propertyValidator: string;
  propertyData: string;
}

export interface VolOrder {
  direction: OrderDirection;
  maker: string;
  orderExpiry: string;
  nonce: string;
  size: string;
  optionType: OptionType;
  maxStrikePriceMultiple: string;
  minOptionDuration: string;
  maxOptionDuration: string;
  maxPriceSignalAge: string;
  nftProperties: VolOrderNFTProperties[];
  optionMarketAddress: string;
  impliedVolBips: string;
  skewDecimal: string;
  riskFreeRateBips: string;
}

const signTypedData = async (
  domain: TypedDataDomain,
  types: Record<string, TypedDataField[]>,
  value: Record<string, any>,
  signer: SignerWithAddress,
  // TODO: Validate we might not need this for "getSigner" it's optional
  // we need to make sure that it always uses the correct one when not sending.
  address: string
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

export function genVolOrderTypedData(
  order: VolOrder,
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
      Property: [
        { name: "propertyValidator", type: "address" },
        { name: "propertyData", type: "bytes" },
      ],
      Order: [
        { name: "direction", type: "uint8" },
        { name: "maker", type: "address" },
        { name: "orderExpiry", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "size", type: "uint8" },
        { name: "optionType", type: "uint8" },
        { name: "maxStrikePriceMultiple", type: "uint256" },
        { name: "minOptionDuration", type: "uint64" },
        { name: "maxOptionDuration", type: "uint64" },
        { name: "maxPriceSignalAge", type: "uint64" },
        { name: "nftProperties", type: "Property[]" },
        { name: "optionMarketAddress", type: "address" },
        { name: "impliedVolBips", type: "uint64" },
        { name: "skewDecimal", type: "uint64" },
        { name: "riskFreeRateBips", type: "uint64" },
      ],
    },
    // The data to sign
    value: order,
  };
}

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
        { name: "assetId", type: "uint32" },
        { name: "expiry", type: "uint32" },
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
  const signature = await signTypedData(
    domain,
    types,
    value,
    signer,
    beneficialOwner
  );

  return signature;
}

export async function signVolOrder(
  order: VolOrder,
  signer: SignerWithAddress,
  hookProtocol: string // Hook Protocol
) {
  const { domain, types, value } = genVolOrderTypedData(order, hookProtocol);
  const signature = await signTypedData(
    domain,
    types,
    value,
    signer,
    order.maker
  );
  return signature;
}
