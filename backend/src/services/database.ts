import type { Context } from "hono";

export function requireDatabase(c: Context): Response | null {
  if (process.env.DATABASE_URL) {
    return null;
  }

  return c.json(
    {
      error: "Database is not configured for this deployment.",
    },
    503
  );
}
