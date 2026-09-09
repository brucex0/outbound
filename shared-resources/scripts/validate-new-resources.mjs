#!/usr/bin/env node

import { readFile, readdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { dirname, relative, resolve } from "node:path";
import process from "node:process";

const scriptDir = dirname(new URL(import.meta.url).pathname);
const repo = resolve(scriptDir, "../..");
const configPath = resolve(scriptDir, "../localization/android-modules.json");
const config = JSON.parse(await readFile(configPath, "utf8"));
const catalogPath = resolve(dirname(configPath), config.catalog);
const catalogRelativePath = relative(repo, catalogPath);
const catalog = JSON.parse(await readFile(catalogPath, "utf8"));

function git(...args) {
  return execFileSync("git", args, { cwd: repo, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
}

function baseCatalog() {
  const explicitBase = process.argv.find(argument => argument.startsWith("--base="))?.slice("--base=".length);
  const candidates = explicitBase ? [explicitBase] : ["HEAD"];
  for (const base of candidates) {
    try {
      // The rollout commit is the baseline. Enforce ownership only after the
      // policy itself exists on the comparison branch.
      git("cat-file", "-e", `${base}:shared-resources/scripts/validate-new-resources.mjs`);
      return JSON.parse(git("show", `${base}:${catalogRelativePath}`));
    } catch { /* New policy, new catalog, or shallow checkout. */ }
  }
  return catalog;
}

const previous = baseCatalog();
const modulePrefixes = new Set(config.modules.map(module => module.keyPrefix));
const errors = [];

for (const [key, entry] of Object.entries(catalog.strings)) {
  if (previous.strings?.[key]) continue;
  const prefix = key.split(".", 1)[0];
  if (!modulePrefixes.has(prefix)) continue;
  const comment = entry.comment ?? "";
  if (!comment.includes(`[android:${prefix}]`) && !comment.includes("[platform:ios]")) {
    errors.push(`${key}: new cross-platform-prefix key needs [android:${prefix}] or [platform:ios] in its catalog comment`);
  }
}

const iconConfigPath = resolve(scriptDir, "../icons/platform-icons.json");
const iconConfig = JSON.parse(await readFile(iconConfigPath, "utf8"));
const configuredSources = new Set(iconConfig.icons.map(icon => icon.source));
const iconSourceDir = resolve(scriptDir, "../icons/source");
for (const file of await readdir(iconSourceDir)) {
  if (file.startsWith(".")) continue;
  const source = `source/${file}`;
  if (!configuredSources.has(source)) errors.push(`${source}: shared icon has no platform output mapping`);
}
for (const icon of iconConfig.icons) {
  if (!icon.outputs?.length) errors.push(`${icon.source}: shared icon needs at least one generated platform output`);
}

if (errors.length) {
  process.stderr.write(`Shared-resource policy failed:\n- ${errors.join("\n- ")}\n`);
  process.exitCode = 1;
}
