import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import activities from "./routes/activities.js";
import assistant from "./routes/assistant.js";
import coach from "./routes/coach.js";
import social from "./routes/social.js";
import media from "./routes/media.js";
import auth from "./routes/auth.js";

const app = new Hono();

app.use("*", logger());
app.use("*", cors({ origin: "*" }));

app.get("/health", (c) => c.json({ status: "ok", version: "0.1.0" }));

app.route("/v1/auth", auth);
app.route("/v1/activities", activities);
app.route("/v1/assistant", assistant);
app.route("/v1/coach", coach);
app.route("/v1/social", social);
app.route("/v1/media", media);

const port = Number(process.env.PORT ?? 3000);
console.log(`Outbound API running on port ${port}`);

export default { port, fetch: app.fetch };
