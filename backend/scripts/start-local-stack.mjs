import { access } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import EmbeddedPostgres from "embedded-postgres";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const dataDir = path.join(backendDir, ".local", "postgres");
const dbPort = Number(process.env.OUTBOUND_PG_PORT ?? 54329);
const dbUser = process.env.OUTBOUND_PG_USER ?? "outbound";
const dbPassword = process.env.OUTBOUND_PG_PASSWORD ?? "outbound";
const dbName = process.env.OUTBOUND_PG_DATABASE ?? "outbound";
const databaseUrl =
  process.env.DATABASE_URL ??
  `postgresql://${dbUser}:${dbPassword}@127.0.0.1:${dbPort}/${dbName}?schema=public`;

loadEnvFileIfPresent(path.join(backendDir, ".env"));
loadEnvFileIfPresent(path.join(backendDir, ".env.local"));

process.env.DATABASE_URL = databaseUrl;

const postgres = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: dbUser,
  password: dbPassword,
  port: dbPort,
  persistent: true,
  onLog: (message) => logLine("[embedded-pg]", message),
  onError: (message) => logLine("[embedded-pg][error]", message),
});

console.log(`[local-stack] DATABASE_URL=${databaseUrl}`);

if (!(await exists(path.join(dataDir, "PG_VERSION")))) {
  console.log("[local-stack] Initializing embedded Postgres cluster...");
  await postgres.initialise();
}

console.log("[local-stack] Starting embedded Postgres...");
await postgres.start();
await ensureDatabase(postgres, dbName);
await runPrisma(["db", "push", "--skip-generate"]);

console.log("[local-stack] Starting Outbound API...");
await import("../dist/index.js");

async function ensureDatabase(instance, name) {
  const client = instance.getPgClient("postgres", "127.0.0.1");
  await client.connect();
  try {
    const result = await client.query("SELECT 1 FROM pg_database WHERE datname = $1", [name]);
    if (result.rowCount === 0) {
      await client.query(`CREATE DATABASE "${name.replaceAll("\"", "\"\"")}"`);
      console.log(`[local-stack] Created database "${name}".`);
    } else {
      console.log(`[local-stack] Database "${name}" already exists.`);
    }
  } finally {
    await client.end();
  }
}

async function runPrisma(args) {
  console.log(`[local-stack] Running prisma ${args.join(" ")}...`);

  await new Promise((resolve, reject) => {
    const child = spawn("./node_modules/.bin/prisma", args, {
      cwd: backendDir,
      env: process.env,
      stdio: "inherit",
      shell: false,
    });

    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Prisma exited with code ${code ?? "null"}`));
      }
    });
    child.on("error", reject);
  });
}

function loadEnvFileIfPresent(filePath) {
  if (!process.loadEnvFile) {
    return;
  }

  try {
    process.loadEnvFile(filePath);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }
}

async function exists(filePath) {
  try {
    await access(filePath, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function logLine(prefix, message) {
  const text = typeof message === "string" ? message : String(message);
  for (const line of text.split(/\r?\n/).filter(Boolean)) {
    console.log(`${prefix} ${line}`);
  }
}
