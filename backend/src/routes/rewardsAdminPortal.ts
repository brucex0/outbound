import { readFile } from "node:fs/promises";
import { Hono } from "hono";
import type { AppEnv } from "../types/hono.js";
import { configuredRewardsAdminGoogleClientId } from "../services/rewardsAdminPortal.js";
import { rewardsAdminPortalStyles } from "../adminRewardsPortal/styles.js";

const router = new Hono<AppEnv>();
const clientPath = new URL("../adminRewardsPortal/client.js", import.meta.url);

router.use("*", async (c, next) => {
  c.header("Cache-Control", "no-store");
  c.header("Content-Security-Policy", [
    "default-src 'self'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "script-src 'self' https://accounts.google.com/gsi/client",
    "style-src 'self' https://accounts.google.com/gsi/style",
    "connect-src 'self' https://accounts.google.com/gsi/",
    "frame-src https://accounts.google.com/gsi/ https://accounts.google.com/o/fedcm/",
    "img-src 'self' data: https://lh3.googleusercontent.com",
  ].join("; "));
  c.header("Cross-Origin-Opener-Policy", "same-origin-allow-popups");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  c.header("X-Content-Type-Options", "nosniff");
  c.header("X-Frame-Options", "DENY");
  await next();
});

router.get("/", (c) => c.html(portalHtml));
router.get("/feature-controls", (c) => c.html(portalHtml));
router.get("/rewards", (c) => c.html(portalHtml));
router.get("/config", (c) => {
  const googleClientId = configuredRewardsAdminGoogleClientId();
  return c.json({ configured: Boolean(googleClientId), googleClientId });
});
router.get("/styles.css", (c) => c.body(rewardsAdminPortalStyles, 200, { "Content-Type": "text/css; charset=utf-8" }));
router.get("/app.js", async (c) => c.body(await readFile(clientPath, "utf8"), 200, { "Content-Type": "text/javascript; charset=utf-8" }));

const portalHtml = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light">
  <meta name="robots" content="noindex,nofollow,noarchive">
  <title>Administration · Plainstride</title>
  <link rel="stylesheet" href="/admin/styles.css">
</head>
<body>
  <div id="app" aria-live="polite">
    <main class="boot"><div class="brand-mark" aria-hidden="true">P</div><p>Preparing administration…</p></main>
  </div>
  <div id="toast-region" class="toast-region" aria-live="assertive" aria-atomic="true"></div>
  <script type="module" src="/admin/app.js"></script>
</body>
</html>`;

export default router;
