import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../types/hono.js";

export type SupportedLocale = "en" | "es" | "zh-Hans";

export const localeMiddleware: MiddlewareHandler<AppEnv> = async (c, next) => {
  const requested = c.req.header("X-Plainstride-Locale") ?? c.req.header("Accept-Language") ?? "en";
  c.set("locale", normalizeLocale(requested));
  await next();
};

export function normalizeLocale(value: string): SupportedLocale {
  const normalized = value.trim().replaceAll("_", "-").toLowerCase();
  if (normalized.startsWith("zh")) return "zh-Hans";
  if (normalized.startsWith("es")) return "es";
  return "en";
}

export function localeInstruction(locale: SupportedLocale): string {
  switch (locale) {
    case "es":
      return "Respond in natural, concise Spanish. Preserve proper names and numeric values.";
    case "zh-Hans":
      return "Respond in natural, concise Simplified Chinese. Preserve proper names and numeric values.";
    default:
      return "Respond in natural, concise English.";
  }
}
