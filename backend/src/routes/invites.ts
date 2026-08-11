import { Hono, type Context } from "hono";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const APPLE_TEAM_ID = "WT54K7D7VH";
const IOS_BUNDLE_ID = "plainstride.outbound";
const DEFAULT_IOS_STORE_URL = "https://apps.apple.com/us/search?term=Plainstride";

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

router.get("/invite", inviteLanding);
router.get("/invite/*", inviteLanding);
router.get("/live/group/:token", inviteLanding);

async function inviteLanding(c: Context<AppEnv>) {
  const storeURL = process.env.IOS_APP_STORE_URL?.trim() || DEFAULT_IOS_STORE_URL;
  const userAgent = c.req.header("user-agent") ?? "";
  const showLanding = c.req.query("landing") === "1";

  if (!showLanding && /iPhone|iPad|iPod/i.test(userAgent)) {
    return c.redirect(storeURL, 302);
  }

  const requestedURL = new URL(c.req.url);
  const referralCode = referralCodeFromPath(requestedURL.pathname);
  if (referralCode && process.env.DATABASE_URL) {
    await getPrismaClient().referralLink.updateMany({
      where: { code: referralCode },
      data: { clickCount: { increment: 1 }, lastClickedAt: new Date() },
    });
  }
  const canonicalURL = `https://run.plainstride.com${requestedURL.pathname}`;
  const escapedCanonicalURL = escapeHTML(canonicalURL);
  const escapedStoreURL = escapeHTML(storeURL);

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
    a { display: inline-block; padding: .9rem 1.3rem; border-radius: 999px; background: #171714; color: #fff; font-weight: 650; text-decoration: none; }
    small { display: block; margin-top: 1.25rem; color: #85857b; }
  </style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true">🏃</div>
    <h1>Run together.</h1>
    <p>Open this invitation in Plainstride. If you don't have the app yet, install it from the App Store.</p>
    <a href="${escapedStoreURL}">Get Plainstride for iPhone</a>
    <small>Android support is coming later.</small>
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
