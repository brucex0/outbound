#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import process from "node:process";

const scriptDir = dirname(new URL(import.meta.url).pathname);
const repo = resolve(scriptDir, "../..");
const configPath = resolve(scriptDir, "../localization/android-modules.json");
const config = JSON.parse(await readFile(configPath, "utf8"));
const catalogPath = resolve(dirname(configPath), config.catalog);
const catalog = JSON.parse(await readFile(catalogPath, "utf8"));
const check = process.argv.includes("--check");
const adopt = process.argv.includes("--adopt-existing");
const moduleFilter = process.argv.find(argument => argument.startsWith("--module="))?.slice("--module=".length);
const outputModules = moduleFilter ? config.modules.filter(module => module.keyPrefix === moduleFilter) : config.modules;

function decodeXML(value) {
  return value.replaceAll("\\'", "'").replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&quot;", '"').replaceAll("&amp;", "&");
}

function encodeXML(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("'", "\\'");
}

function appleFormat(value) {
  return decodeXML(value)
    .replace(/%(\d+)\$([sd])/g, (_, _position, type) => type === "s" ? "%@" : "%d")
    .replace(/%(\d+)\$([.0-9]*)([f])/g, (_, _position, precision, type) => `%${precision}${type}`);
}

function androidFormat(value) {
  let position = 0;
  return encodeXML(value.replace(/%(?:lld|ld|d|@|(?:[.0-9]*)f)/g, match => {
    position += 1;
    if (match === "%@") return `%${position}$s`;
    if (match === "%lld" || match === "%ld" || match === "%d") return `%${position}$d`;
    return `%${position}$${match.slice(1)}`;
  }));
}

function placeholders(value) {
  return [...value.matchAll(/%(?:\d+\$)?(?:lld|ld|d|s|@|(?:[.0-9]*)f)/g)].map(match => match[0].replace(/%\d+\$/, "%").replace("%@", "%s").replace(/%l?ld/, "%d"));
}

function catalogKey(module, androidName) {
  const source = [...sourceDefinitions(module)]
    .sort((left, right) => right.androidPrefix.length - left.androidPrefix.length)
    .find(candidate => androidName.startsWith(candidate.androidPrefix))
    ?? { keyPrefix: module.keyPrefix, androidPrefix: module.androidPrefix };
  const stem = androidName.startsWith(source.androidPrefix) ? androidName.slice(source.androidPrefix.length) : androidName;
  return `${source.keyPrefix}.${stem.replaceAll("_", ".")}`;
}

const ownershipMarker = keyPrefix => `[android:${keyPrefix}]`;

function sourceDefinitions(module) {
  return module.sources ?? [{ keyPrefix: module.keyPrefix, androidPrefix: module.androidPrefix }];
}

function androidName(source, key) {
  return source.androidPrefix + key.slice(source.keyPrefix.length + 1).replaceAll(".", "_");
}

function parseResources(xml) {
  const result = new Map();
  for (const match of xml.matchAll(/<string\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/string>/g)) {
    result.set(match[1], { type: "string", value: appleFormat(match[2]) });
  }
  for (const match of xml.matchAll(/<plurals\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/plurals>/g)) {
    const forms = {};
    for (const item of match[2].matchAll(/<item\s+quantity="([^"]+)">([\s\S]*?)<\/item>/g)) forms[item[1]] = appleFormat(item[2]);
    result.set(match[1], { type: "plural", forms });
  }
  return result;
}

async function adoptExisting() {
  for (const module of config.modules) {
    for (const [appleLocale, directory] of Object.entries(config.locales)) {
      const path = join(repo, module.resourceRoot, directory, module.file);
      const resources = parseResources(await readFile(path, "utf8"));
      for (const [name, resource] of resources) {
        const key = catalogKey(module, name);
        const entry = catalog.strings[key] ??= { localizations: {} };
        const marker = ownershipMarker(module.keyPrefix);
        if (!entry.comment?.includes(marker)) entry.comment = `${entry.comment ? `${entry.comment} ` : ""}${marker} Generated Android name: ${name}.`;
        entry.localizations ??= {};
        if (resource.type === "string") {
          entry.localizations[appleLocale] = { stringUnit: { state: "translated", value: resource.value } };
        } else {
          const plural = {};
          for (const [quantity, value] of Object.entries(resource.forms)) plural[quantity] = { stringUnit: { state: "translated", value } };
          entry.localizations[appleLocale] = { variations: { plural } };
        }
      }
    }
  }
  await writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
}

function localized(entry, locale, key) {
  const localization = entry.localizations?.[locale];
  if (!localization) throw new Error(`Missing ${locale} translation: ${key}`);
  if (localization.stringUnit?.state === "translated" && localization.stringUnit.value !== undefined) return { type: "string", value: localization.stringUnit.value };
  const plural = localization.variations?.plural;
  if (plural) return { type: "plural", forms: Object.fromEntries(Object.entries(plural).map(([quantity, item]) => {
    if (item.stringUnit?.state !== "translated") throw new Error(`Unreviewed ${locale} plural (${quantity}): ${key}`);
    return [quantity, item.stringUnit.value];
  })) };
  throw new Error(`Unsupported or unreviewed ${locale} catalog entry: ${key}`);
}

function validatePlaceholders(resources, key) {
  const signatures = resources.flatMap(resource => resource.type === "string"
    ? [placeholders(resource.value).join(",")]
    : Object.values(resource.forms).map(value => placeholders(value).join(",")));
  if (new Set(signatures).size !== 1) throw new Error(`Placeholder mismatch across locales: ${key} (${signatures.join(" / ")})`);
}

function render(module, locale) {
  const rows = [];
  const ownedKeys = sourceDefinitions(module).flatMap(source => {
    const prefix = `${source.keyPrefix}.`;
    return Object.keys(catalog.strings)
      .filter(key => key.startsWith(prefix) && catalog.strings[key].comment?.includes(ownershipMarker(module.keyPrefix)))
      .map(key => ({ key, source }));
  }).sort((left, right) => left.key.localeCompare(right.key));
  for (const { key, source } of ownedKeys) {
    const entry = catalog.strings[key];
    const resource = localized(entry, locale, key);
    const allLocales = Object.keys(config.locales).map(candidate => localized(entry, candidate, key));
    validatePlaceholders(allLocales, key);
    const name = androidName(source, key);
    if (resource.type === "string") rows.push(`    <string name="${name}">${androidFormat(resource.value)}</string>`);
    else {
      rows.push(`    <plurals name="${name}">`);
      for (const [quantity, value] of Object.entries(resource.forms)) rows.push(`        <item quantity="${quantity}">${androidFormat(value)}</item>`);
      rows.push("    </plurals>");
    }
  }
  return ['<?xml version="1.0" encoding="utf-8"?>', "<!-- Generated from ios/Outbound/Outbound/Localizable.xcstrings. Do not edit by hand. -->", "<resources>", ...rows, "</resources>", ""].join("\n");
}

if (adopt) await adoptExisting();

let stale = false;
for (const module of outputModules) {
  for (const [appleLocale, directory] of Object.entries(config.locales)) {
    const output = join(repo, module.resourceRoot, directory, module.file);
    const expected = render(module, appleLocale);
    let actual = "";
    try { actual = await readFile(output, "utf8"); } catch (error) { if (error.code !== "ENOENT") throw error; }
    if (actual === expected) continue;
    stale = true;
    process.stderr.write(`${check ? "stale" : "updated"}: ${output}\n`);
    if (!check) { await mkdir(dirname(output), { recursive: true }); await writeFile(output, expected); }
  }
}
if (check && stale) process.exitCode = 1;
