import { Hono, type Context } from "hono";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const APPLE_TEAM_ID = "WT54K7D7VH";
const IOS_BUNDLE_ID = "plainstride.outbound";
const DEFAULT_IOS_STORE_URL = "https://apps.apple.com/us/search?term=Plainstride";
const DEFAULT_ANDROID_STORE_URL = "https://play.google.com/store/search?q=Plainstride&c=apps";

router.get("/.well-known/apple-app-site-association", (c) => {
  return c.json({
    applinks: {
      apps: [],
      details: [
        {
          appID: `${APPLE_TEAM_ID}.${IOS_BUNDLE_ID}`,
          components: [
            { "/": "/invite", comment: "Plainstride app invitation" },
            { "/": "/invite/*", comment: "Plainstride run invitations" },
            { "/": "/live/group/*", comment: "Plainstride live group invitations" },
          ],
        },
      ],
    },
  });
});

router.get("/apple-app-site-association", (c) => {
  return c.redirect("/.well-known/apple-app-site-association", 308);
});

router.get("/.well-known/assetlinks.json", (c) => {
  const packageName = process.env.ANDROID_PACKAGE_NAME?.trim();
  const fingerprints = process.env.ANDROID_SHA256_CERT_FINGERPRINTS
    ?.split(",")
    .map((value) => value.trim())
    .filter(Boolean) ?? [];
  if (!packageName || fingerprints.length === 0) return c.json([]);
  return c.json([{
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: packageName,
      sha256_cert_fingerprints: fingerprints,
    },
  }]);
});

router.get("/invite", inviteLanding);
router.get("/invite/*", inviteLanding);
router.get("/live/group/:token", inviteLanding);

async function inviteLanding(c: Context<AppEnv>) {
  const iosStoreURL = process.env.IOS_APP_STORE_URL?.trim() || DEFAULT_IOS_STORE_URL;
  const androidStoreURL = process.env.ANDROID_PLAY_STORE_URL?.trim() || DEFAULT_ANDROID_STORE_URL;
  const iosBetaURL = process.env.IOS_BETA_URL?.trim();
  const androidBetaURL = process.env.ANDROID_BETA_URL?.trim();
  const userAgent = c.req.header("user-agent") ?? "";
  const requestedURL = new URL(c.req.url);
  const referralCode = referralCodeFromPath(requestedURL.pathname);
  if (referralCode && process.env.DATABASE_URL) {
    try {
      await getPrismaClient().referralLink.updateMany({
        where: { code: referralCode },
        data: { clickCount: { increment: 1 }, lastClickedAt: new Date() },
      });
    } catch (error) {
      console.error("Plainstride referral click tracking failed; continuing to destination.", error);
    }
  }

  const canonicalURL = `https://run.plainstride.com${requestedURL.pathname}`;
  const escapedCanonicalURL = escapeHTML(canonicalURL);
  const isApple = /iPhone|iPad|iPod|Macintosh/i.test(userAgent);
  const isAndroid = /Android/i.test(userAgent);
  const productionLinks = isAndroid
    ? [{ label: "Get it on Google Play", url: androidStoreURL }]
    : isApple
      ? [{ label: "Download on the App Store", url: iosStoreURL }]
      : [
          { label: "Download on the App Store", url: iosStoreURL },
          { label: "Get it on Google Play", url: androidStoreURL },
        ];
  const betaLinks = isAndroid
    ? (androidBetaURL ? [{ label: "Join the Android beta", url: androidBetaURL }] : [])
    : isApple
      ? (iosBetaURL ? [{ label: "Join the iOS beta", url: iosBetaURL }] : [])
      : [
          ...(iosBetaURL ? [{ label: "Join the iOS beta", url: iosBetaURL }] : []),
          ...(androidBetaURL ? [{ label: "Join the Android beta", url: androidBetaURL }] : []),
        ];
  const storeButtons = productionLinks
    .map(({ label, url }) => `<a class="button" href="${escapeHTML(url)}">${escapeHTML(label)}</a>`)
    .join("");
  const betaButtons = betaLinks.length > 0
    ? `<div class="beta"><span>Testing Plainstride?</span>${betaLinks
        .map(({ label, url }) => `<a class="beta-link" href="${escapeHTML(url)}">${escapeHTML(label)}</a>`)
        .join("")}</div>`
    : "";

  return c.html(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Join me on Plainstride</title>
  <meta name="description" content="Run together with Plainstride.">
  <meta property="og:title" content="Join me on Plainstride">
  <meta property="og:description" content="Run together with Plainstride.">
  <meta property="og:url" content="${escapedCanonicalURL}">
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f2f1ec; color: #171714; }
    main { width: min(30rem, calc(100% - 3rem)); padding: 2.5rem; border-radius: 2rem; background: #fff; box-shadow: 0 1.5rem 5rem #29291f1a; text-align: center; }
    .mark { margin: 0 auto 1.25rem; width: 4rem; height: 4rem; display: grid; place-items: center; border-radius: 1.25rem; background: #e5ef9a; font-size: 2rem; }
    h1 { margin: 0; font-size: 2rem; letter-spacing: -.04em; }
    p { margin: .8rem 0 1.8rem; color: #66665e; line-height: 1.5; }
    .stores { display: flex; flex-wrap: wrap; justify-content: center; gap: .7rem; }
    a.button { display: inline-block; padding: .9rem 1.3rem; border-radius: 999px; background: #171714; color: #fff; font-weight: 650; text-decoration: none; }
    .beta { margin-top: 1.5rem; display: grid; gap: .55rem; }
    .beta span { color: #85857b; font-size: .85rem; }
    .beta-link { color: #394800; font-weight: 650; text-underline-offset: .2rem; }
    small { display: block; margin-top: 1.25rem; color: #85857b; }
  </style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true">🏃</div>
    <h1>Run together.</h1>
    <p>Open this invitation in Plainstride. If you don't have the app yet, choose the version for your device.</p>
    <div class="stores">${storeButtons}</div>
    ${betaButtons}
    <small>This same invitation works after you install or update the app.</small>
  </main>
</body>
</html>`);
}

function referralCodeFromPath(pathname: string) {
  const match = pathname.match(/^\/invite\/r\/([A-Za-z0-9_-]{8,64})$/);
  return match?.[1] ?? null;
}

function escapeHTML(value: string) {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character] ?? character);
}

export default router;
