import { createMiddleware } from "hono/factory";
import { verifyBearerToken } from "../services/firebaseAuth.js";
import type { AppEnv } from "../types/hono.js";

export const authMiddleware = createMiddleware<AppEnv>(async (c, next) => {
  c.set("auth", null);

  const authHeader = c.req.header("Authorization");
  if (!authHeader) {
    await next();
    return;
  }

  const [scheme, token] = authHeader.split(" ");
  if (scheme !== "Bearer" || !token) {
    return c.json({ error: "Malformed Authorization header." }, 401);
  }

  try {
    const decoded = await verifyBearerToken(token);
    c.set("auth", {
      firebaseUid: decoded.uid,
      email: decoded.email ?? null,
    });
  } catch (error) {
    console.error("[auth] token verification failed", error);
    return c.json({ error: "Invalid auth token." }, 401);
  }

  await next();
});
