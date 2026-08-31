#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { createVerify } from "node:crypto";

const options = parseOptions(process.argv.slice(2));
const envelope = JSON.parse(await readFile(options.manifest, "utf8"));
if (envelope.contractVersion !== 1) fail("Signed manifest envelope contractVersion must be 1.");
if (envelope.signature?.algorithm !== "ES256" || !envelope.signature.keyId || !envelope.signature.value) {
  fail("Signed manifest envelope must contain an ES256 signature.");
}
if (typeof envelope.payload !== "string" || envelope.payload.length === 0) {
  fail("Signed manifest envelope payload is missing.");
}

const payload = Buffer.from(envelope.payload, "base64url");
const publicKey = await loadPublicKey(options.publicKeysPlist, envelope.signature.keyId);
const signatureVerifier = createVerify("SHA256");
signatureVerifier.update(payload);
signatureVerifier.end();
if (!signatureVerifier.verify(publicKey, Buffer.from(envelope.signature.value, "base64url"))) {
  fail(`Manifest signature is invalid for key ${envelope.signature.keyId}.`);
}

let manifest;
try {
  manifest = JSON.parse(payload.toString("utf8"));
} catch {
  fail("Signed manifest payload is not valid base64url JSON.");
}
const catalog = JSON.parse(await readFile(options.catalog, "utf8"));

if (manifest.contractVersion !== 1) fail("Audio manifest contractVersion must be 1.");
if (manifest.catalogVersion !== options.version) {
  fail(`Manifest catalogVersion ${manifest.catalogVersion ?? "<missing>"} does not match ${options.version}.`);
}
if (catalog.catalogVersion !== options.version) {
  fail(`Source catalogVersion ${catalog.catalogVersion ?? "<missing>"} does not match ${options.version}.`);
}
if (!Array.isArray(manifest.entries) || manifest.entries.length === 0) fail("Audio manifest has no entries.");
if (!Array.isArray(catalog.entries) || catalog.entries.length === 0) fail("Source catalog has no entries.");

const catalogByCue = new Map(catalog.entries.map((entry) => [entry.cueKey, entry]));
const manifestByKey = new Map();
for (const entry of manifest.entries) {
  const catalogEntry = catalogByCue.get(entry.cueKey);
  if (!catalogEntry) fail(`Manifest contains unknown cue ${entry.cueKey}.`);
  const expectedText = catalogEntry.texts?.[entry.locale];
  if (!expectedText) fail(`Manifest contains unsupported locale ${entry.locale} for ${entry.cueKey}.`);
  if (entry.transcript !== expectedText) fail(`Transcript mismatch for ${entry.cueKey}/${entry.locale}.`);
  if (entry.scriptStyleId !== catalogEntry.scriptStyleId) fail(`Script style mismatch for ${entry.cueKey}/${entry.locale}.`);
  if (entry.approved !== true) fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} is not approved.`);
  if (entry.contentType !== "audio/wav") fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} is not WAV.`);
  if (!/^[a-f0-9]{64}$/.test(entry.sha256 ?? "")) fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} has an invalid SHA-256.`);
  if (!Number.isInteger(entry.byteCount) || entry.byteCount <= 0) fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} has an invalid byte count.`);
  if (!Number.isInteger(entry.durationMilliseconds) || entry.durationMilliseconds <= 0) fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} has an invalid duration.`);
  if (typeof entry.url !== "string" || new URL(entry.url).protocol !== "https:") {
    fail(`Entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId} needs an HTTPS URL.`);
  }
  const key = `${entry.cueKey}\u0000${entry.locale}\u0000${entry.voiceProfileId}`;
  if (manifestByKey.has(key)) fail(`Duplicate manifest entry ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId}.`);
  manifestByKey.set(key, entry);
}

let requiredCount = 0;
for (const catalogEntry of catalog.entries) {
  for (const locale of options.locales) {
    if (!catalogEntry.texts?.[locale]) fail(`Source catalog has no ${locale} text for ${catalogEntry.cueKey}.`);
    for (const voice of options.voices) {
      requiredCount += 1;
      const key = `${catalogEntry.cueKey}\u0000${locale}\u0000${voice}`;
      if (!manifestByKey.has(key)) fail(`Missing required entry ${catalogEntry.cueKey}/${locale}/${voice}.`);
    }
  }
}

console.log(
  `Verified signed manifest ${options.version}: ${manifest.entries.length} approved entries; ${requiredCount} required entries present for ${options.locales.join(",")} and ${options.voices.join(",")}.`,
);

function parseOptions(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const key = values[index];
    if (!key.startsWith("--")) fail(`Unexpected argument ${key}.`);
    const value = values[index + 1];
    if (!value || value.startsWith("--")) fail(`Missing value for ${key}.`);
    parsed[key.slice(2)] = value;
    index += 1;
  }
  for (const required of ["manifest", "catalog", "public-keys-plist", "version", "locales", "voices"]) {
    if (!parsed[required]) fail(`--${required} is required.`);
  }
  return {
    ...parsed,
    publicKeysPlist: parsed["public-keys-plist"],
    locales: parsed.locales.split(",").map((value) => value.trim()).filter(Boolean),
    voices: parsed.voices.split(",").map((value) => value.trim()).filter(Boolean),
  };
}

async function loadPublicKey(plistPath, keyId) {
  const plist = await readFile(plistPath, "utf8");
  const escapedKeyId = keyId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = plist.match(new RegExp(`<key>${escapedKeyId}</key>\\s*<string>([\\s\\S]*?)</string>`));
  if (!match) fail(`Manifest public key ${keyId} is not present in ${plistPath}.`);
  return match[1]
    .replaceAll("&#10;", "\n")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
