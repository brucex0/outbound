#!/usr/bin/env node

import { copyFile, mkdir, readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repo = resolve(scriptDir, "../..");
const configPath = resolve(scriptDir, "../icons/platform-icons.json");
const config = JSON.parse(await readFile(configPath, "utf8"));
const check = process.argv.includes("--check");
const sourceFilters = process.argv
  .filter(argument => argument.startsWith("--source="))
  .map(argument => argument.slice("--source=".length));
const icons = sourceFilters.length === 0
  ? config.icons ?? []
  : (config.icons ?? []).filter(icon => sourceFilters.includes(icon.source));
let stale = false;

for (const icon of icons) {
  if (!icon.source || !Array.isArray(icon.outputs) || icon.outputs.length === 0) {
    throw new Error(`Invalid platform icon entry: ${JSON.stringify(icon)}`);
  }

  const source = resolve(repo, "shared-resources/icons", icon.source);
  await stat(source);

  for (const relativeOutput of icon.outputs) {
    const output = resolve(repo, relativeOutput);
    const expected = await readFile(source);
    let actual;
    try {
      actual = await readFile(output);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    if (actual?.equals(expected)) continue;

    stale = true;
    process.stderr.write(`${check ? "stale" : "updated"}: ${output}\n`);
    if (!check) {
      await mkdir(dirname(output), { recursive: true });
      await copyFile(source, output);
    }
  }
}

if (check && stale) process.exitCode = 1;
