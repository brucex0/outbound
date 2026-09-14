import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { authMiddleware } from "./middleware/auth.js";
import activities from "./routes/activities.js";
import assistant from "./routes/assistant.js";
import guide from "./routes/guide.js";
import social from "./routes/social.js";
import media from "./routes/media.js";
import auth from "./routes/auth.js";
import live from "./routes/live.js";
import planning from "./routes/planning.js";
import personalization from "./routes/personalization.js";
import companion from "./routes/companion.js";
import notifications from "./routes/notifications.js";
import safety from "./routes/safety.js";
import invites from "./routes/invites.js";
import marketing from "./routes/marketing.js";
import feedback from "./routes/feedback.js";
import routes from "./routes/routes.js";
import liveCoach from "./routes/liveCoach.js";
import recognition from "./routes/recognition.js";
import circles from "./routes/circles.js";
import weather from "./routes/weather.js";
import elevation from "./routes/elevation.js";
import rewards from "./routes/rewards.js";
import rewardsAdmin from "./routes/rewardsAdmin.js";
import revenueCatWebhooks from "./routes/revenueCatWebhooks.js";
import rewardsAdminPortal from "./routes/rewardsAdminPortal.js";
import type { AppEnv } from "./types/hono.js";
import { localeMiddleware } from "./middleware/locale.js";
import { rateLimit } from "./middleware/rateLimit.js";
import { assertLiveCoachConfiguration } from "./services/liveCoach/liveCoachFeatureConfig.js";
import { configuredCircleMemberLimit } from "./services/circles.js";
import { assertGoogleAuthConfiguration } from "./services/googleAuth.js";
import { assertRewardsAdminPortalConfiguration } from "./services/rewardsAdminPortal.js";

const app = new Hono<AppEnv>();

if (process.env.NODE_ENV === "production" && process.env.AUTH_ENABLE_DEBUG_PERSONAS === "true") {
  throw new Error("AUTH_ENABLE_DEBUG_PERSONAS must not be enabled in production");
}

assertLiveCoachConfiguration();
configuredCircleMemberLimit();
assertGoogleAuthConfiguration();
assertRewardsAdminPortalConfiguration();

app.use("*", cors({ origin: "*" }));
app.use("*", localeMiddleware);
app.use("/v1/*", rateLimit({ name: "api", limit: 300, windowMs: 60_000, key: "ip" }));
app.use("/v1/*", authMiddleware);
app.use("/v1/auth/*", rateLimit({ name: "auth", limit: 30, windowMs: 60_000 }));
app.use("/v1/auth/google", rateLimit({ name: "auth-google", limit: 10, windowMs: 60_000, key: "ip" }));
app.use("/v1/auth/link/google", rateLimit({ name: "auth-google-link", limit: 10, windowMs: 60_000, key: "identity" }));
app.use("/v1/auth/link-intents", rateLimit({ name: "auth-link-intent", limit: 5, windowMs: 60_000, key: "identity" }));
app.use("/v1/auth/link-intents/redeem/google", rateLimit({ name: "auth-link-redeem", limit: 5, windowMs: 60_000, key: "ip" }));
app.use("/v1/auth/refresh", rateLimit({ name: "auth-refresh", limit: 10, windowMs: 60_000, key: "ip" }));
app.use("/v1/assistant/*", rateLimit({ name: "assistant", limit: 20, windowMs: 60_000 }));
app.use("/v1/companion/*", rateLimit({ name: "companion", limit: 20, windowMs: 60_000 }));
app.use("/v1/guide/*", rateLimit({ name: "guide-ai", limit: 20, windowMs: 60_000 }));
app.use("/v1/live-coach/*", rateLimit({ name: "live-coach", limit: 30, windowMs: 60_000, key: "identity" }));
app.use("/v1/weather/*", rateLimit({ name: "weather", limit: 10, windowMs: 60_000, key: "identity" }));
app.use("/v1/elevation/*", rateLimit({ name: "elevation", limit: 10, windowMs: 60_000, key: "identity" }));
app.use("/v1/rewards/*", rateLimit({ name: "rewards", limit: 20, windowMs: 60_000, key: "identity" }));
app.use("/v1/admin/rewards/*", rateLimit({ name: "rewards-admin", limit: 120, windowMs: 60_000, key: "identity" }));
app.use("/v1/feedback/*", rateLimit({ name: "feedback", limit: 10, windowMs: 60_000 }));
app.use("/v1/transcribe/*", rateLimit({ name: "transcribe", limit: 10, windowMs: 60_000 }));
app.use("/waitlist/*", rateLimit({ name: "public-waitlist", limit: 5, windowMs: 60_000, key: "ip" }));
app.use("/webhooks/revenuecat", rateLimit({ name: "revenuecat-webhook", limit: 120, windowMs: 60_000, key: "ip" }));

app.get("/health", (c) => c.json({ status: "ok", version: "0.1.0" }));
app.route("/", marketing);
app.route("/", invites);
app.route("/webhooks/revenuecat", revenueCatWebhooks);
app.get("/admin/", (c) => c.redirect("/admin", 308));
app.get("/admin/rewards/", (c) => c.redirect("/admin/rewards", 308));
app.route("/admin", rewardsAdminPortal);

app.route("/v1/auth", auth);
app.route("/v1/activities", activities);
app.route("/v1/assistant", assistant);
import transcribeRoutes from "./routes/transcribe.js";
app.route("/v1/guide", guide);
app.route("/v1/planning", planning);
app.route("/v1/personalization", personalization);
app.route("/v1/companion", companion);
app.route("/v1/notifications", notifications);
app.route("/v1/social", social);
app.route("/v1/media", media);
app.route("/v1/safety", safety);
app.route("/v1/live", live);
app.route("/v1/transcribe", transcribeRoutes);
app.route("/v1/feedback", feedback);
app.route("/v1/routes", routes);
app.route("/v1/live-coach", liveCoach);
app.route("/v1/recognition", recognition);
app.route("/v1/circles", circles);
app.route("/v1/weather", weather);
app.route("/v1/elevation", elevation);
app.route("/v1/rewards", rewards);
app.route("/v1/admin/rewards", rewardsAdmin);

const port = Number(process.env.PORT ?? 3000);
console.log(`Plainstride API running on port ${port}`);

serve({ fetch: app.fetch, port });
