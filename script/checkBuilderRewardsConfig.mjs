#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const CHAIN_CONFIG = {
  1: { alias: "mainnet", label: "ethereum-mainnet" },
  10: { alias: "optimism", label: "optimism-mainnet" },
  8453: { alias: "base", label: "base-mainnet" },
  11155111: { alias: "sepolia", label: "ethereum-sepolia" },
  11155420: { alias: "optimism_sepolia", label: "optimism-sepolia" },
  84532: { alias: "base_sepolia", label: "base-sepolia" },
  7777777: { alias: "zora", label: "zora-mainnet" },
  999999999: { alias: "zora_sepolia", label: "zora-sepolia" },
};

const ADDRESS_RE = /^0x[a-fA-F0-9]{40}$/;

function parseArgs(argv) {
  const args = { write: false, chainIds: [] };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--write") {
      args.write = true;
      continue;
    }

    if (arg.startsWith("--chain-ids=")) {
      const value = arg.split("=")[1] || "";
      args.chainIds = value
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      continue;
    }

    if (arg === "--chain-ids") {
      const next = argv[i + 1] || "";
      args.chainIds = next
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      i++;
      continue;
    }
  }

  return args;
}

function castCall(address, signature, rpcAlias) {
  try {
    return execFileSync("cast", ["call", address, signature, "--rpc-url", rpcAlias], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 30000,
    }).trim();
  } catch (error) {
    const details = error?.stderr?.toString()?.trim() || error?.message || "unknown error";
    throw new Error(
      `cast call failed (address=${address}, signature=${signature}, rpcAlias=${rpcAlias}): ${details}`
    );
  }
}

function getBuilderRewardsRecipient(manager, rpcAlias) {
  const out = castCall(manager, "builderRewardsRecipient()(address)", rpcAlias);
  if (!ADDRESS_RE.test(out)) {
    throw new Error(`invalid recipient response: ${out}`);
  }
  return out;
}

function getBps(auctionImpl, rpcAlias) {
  const builder = castCall(auctionImpl, "builderRewardsBPS()(uint16)", rpcAlias);
  const referral = castCall(auctionImpl, "referralRewardsBPS()(uint16)", rpcAlias);
  return { builder, referral };
}

function run() {
  const { write, chainIds } = parseArgs(process.argv.slice(2));
  const repoRoot = process.cwd();
  const addressesDir = path.join(repoRoot, "addresses");

  const selectedChains = (chainIds.length ? chainIds : Object.keys(CHAIN_CONFIG)).filter(
    (id) => CHAIN_CONFIG[id]
  );
  const skipped = chainIds.filter((id) => !CHAIN_CONFIG[id]);

  if (skipped.length > 0) {
    console.log(`Skipping unsupported chain ids: ${skipped.join(", ")}`);
  }

  let checked = 0;
  let changed = 0;

  for (const chainId of selectedChains) {
    const cfg = CHAIN_CONFIG[chainId];
    const filePath = path.join(addressesDir, `${chainId}.json`);

    if (!existsSync(filePath)) {
      console.log(`[${chainId}] ${cfg.label}: addresses file not found, skipping`);
      continue;
    }

    const parsed = JSON.parse(readFileSync(filePath, "utf8"));
    const manager = parsed.Manager;
    const auctionImpl = parsed.Auction;
    const configuredRecipient = parsed.BuilderRewardsRecipient;

    if (!ADDRESS_RE.test(manager || "")) {
      console.log(`[${chainId}] ${cfg.label}: invalid Manager address, skipping`);
      continue;
    }
    if (!ADDRESS_RE.test(auctionImpl || "")) {
      console.log(`[${chainId}] ${cfg.label}: invalid Auction address, skipping`);
      continue;
    }

    let onchainRecipient = null;
    let recipientStatus = "UNAVAILABLE";
    let bpsOutput = "N/A";

    try {
      onchainRecipient = getBuilderRewardsRecipient(manager, cfg.alias);
      recipientStatus =
        ADDRESS_RE.test(configuredRecipient || "") &&
        configuredRecipient.toLowerCase() === onchainRecipient.toLowerCase()
          ? "MATCH"
          : "MISMATCH";

      if (write && recipientStatus === "MISMATCH") {
        parsed.BuilderRewardsRecipient = onchainRecipient;
        writeFileSync(filePath, `${JSON.stringify(parsed, null, 2)}\n`, "utf8");
        changed++;
      }
    } catch (error) {
      recipientStatus = "UNAVAILABLE";
      console.log(
        `[${chainId}] ${cfg.label}: builderRewardsRecipient unavailable (${error.message})`
      );
    }

    try {
      const bps = getBps(auctionImpl, cfg.alias);
      bpsOutput = `${bps.builder}/${bps.referral}`;
    } catch (error) {
      bpsOutput = "N/A";
      console.log(`[${chainId}] ${cfg.label}: reward BPS unavailable (${error.message})`);
    }

    checked++;
    console.log(
      `[${chainId}] ${cfg.label}: recipient=${configuredRecipient || "<missing>"} onchain=${
        onchainRecipient || "<unavailable>"
      } status=${recipientStatus} bps(builder/referral)=${bpsOutput}`
    );
  }

  console.log(`\nChecked ${checked} chain(s), ${changed} file(s) updated.`);
  if (!write && changed > 0) {
    process.exitCode = 1;
  }
}

run();
