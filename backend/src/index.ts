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
import safety, { liveShareViewer } from "./routes/safety.js";
import invites from "./routes/invites.js";
import marketing from "./routes/marketing.js";
import type { AppEnv } from "./types/hono.js";
import { localeMiddleware } from "./middleware/locale.js";
import { rateLimit } from "./middleware/rateLimit.js";

const app = new Hono<AppEnv>();

app.use("*", cors({ origin: "*" }));
app.use("*", localeMiddleware);
app.use("/v1/*", rateLimit({ name: "api", limit: 300, windowMs: 60_000, key: "ip" }));
app.use("/v1/*", authMiddleware);
app.use("/v1/auth/*", rateLimit({ name: "auth", limit: 30, windowMs: 60_000 }));
app.use("/v1/assistant/*", rateLimit({ name: "assistant", limit: 20, windowMs: 60_000 }));
app.use("/v1/companion/*", rateLimit({ name: "companion", limit: 20, windowMs: 60_000 }));
app.use("/v1/guide/*", rateLimit({ name: "guide-ai", limit: 20, windowMs: 60_000 }));
app.use("/v1/transcribe/*", rateLimit({ name: "transcribe", limit: 10, windowMs: 60_000 }));

app.get("/health", (c) => c.json({ status: "ok", version: "0.1.0" }));
app.get("/live/:token", liveShareViewer);
app.route("/", marketing);
app.route("/", invites);

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

const port = Number(process.env.PORT ?? 3000);
console.log(`Plainstride API running on port ${port}`);

serve({ fetch: app.fetch, port });
