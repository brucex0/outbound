import { zValidator } from "@hono/zod-validator";
import { Prisma } from "@prisma/client";
import { Hono } from "hono";
import { z } from "zod";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();
const publishSchema = z.object({
  name: z.string().trim().min(1).max(100),
  description: z.string().trim().max(500).optional().nullable(),
});
const updateSchema = publishSchema.partial();

type Coordinate = [number, number, number?];

router.get("/nearby", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const latitude = finiteQuery(c.req.query("latitude"));
  const longitude = finiteQuery(c.req.query("longitude"));
  if (latitude == null || longitude == null) return c.json({ error: "A valid latitude and longitude are required." }, 400);
  const radiusKm = Math.min(100, Math.max(1, finiteQuery(c.req.query("radiusKm")) ?? 25));
  const latitudeDelta = radiusKm / 111;
  const longitudeDelta = radiusKm / Math.max(20, 111 * Math.cos(latitude * Math.PI / 180));
  const routes = await getPrismaClient().route.findMany({
    where: {
      visibility: "public", status: "active",
      startLatitude: { gte: latitude - latitudeDelta, lte: latitude + latitudeDelta },
      startLongitude: { gte: longitude - longitudeDelta, lte: longitude + longitudeDelta },
    },
    include: { owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } }, bookmarks: { where: { userId: user.id }, select: { id: true } } },
    take: 100,
  });
  return c.json({ routes: routes.map((route) => routeDTO(route, user.id, latitude, longitude)).sort((a, b) => (a.distanceFromSearchM ?? 0) - (b.distanceFromSearchM ?? 0)) });
});

router.get("/search", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const query = (c.req.query("q") ?? "").trim();
  const routes = await getPrismaClient().route.findMany({
    where: { visibility: "public", status: "active", ...(query ? { OR: [{ name: { contains: query, mode: "insensitive" } }, { description: { contains: query, mode: "insensitive" } }] } : {}) },
    include: { owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } }, bookmarks: { where: { userId: user.id }, select: { id: true } } },
    orderBy: [{ bookmarkCount: "desc" }, { completionCount: "desc" }, { updatedAt: "desc" }], take: 100,
  });
  return c.json({ routes: routes.map((route) => routeDTO(route, user.id)) });
});

router.get("/mine", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const routes = await getPrismaClient().route.findMany({
    where: { OR: [{ ownerId: user.id }, { bookmarks: { some: { userId: user.id } } }], status: "active" },
    include: { owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } }, bookmarks: { where: { userId: user.id }, select: { id: true } } }, orderBy: { updatedAt: "desc" },
  });
  return c.json({ routes: routes.map((route) => routeDTO(route, user.id)) });
});

router.post("/from-activity/:activityId", zValidator("json", publishSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const activity = await prisma.activity.findFirst({ where: { OR: [{ id: c.req.param("activityId") }, { clientActivityId: c.req.param("activityId") }], userId: user.id, deletedAt: null } });
  if (!activity) return c.json({ error: "Only your own saved activity can become a route." }, 404);
  const coordinates = coordinatesFromActivity(activity.route);
  if (coordinates.length < 2) return c.json({ error: "This activity does not contain a usable route." }, 422);
  const publicCoordinates = privacyTrimmed(coordinates);
  const bounds = routeBounds(publicCoordinates);
  const body = c.req.valid("json");
  const route = await prisma.route.upsert({
    where: { sourceActivityId: activity.id },
    update: { name: body.name, description: body.description, status: "active" },
    create: {
      ownerId: user.id, sourceActivityId: activity.id, name: body.name, description: body.description,
      activityType: activity.type, visibility: "public", geometry: { type: "LineString", coordinates: publicCoordinates } as Prisma.InputJsonValue,
      distanceM: polylineDistance(publicCoordinates), elevationGainM: elevationGain(publicCoordinates), routeShape: classifyShape(publicCoordinates), ...bounds,
    },
    include: { owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } }, bookmarks: { where: { userId: user.id }, select: { id: true } } },
  });
  return c.json(routeDTO(route, user.id), 201);
});

router.get("/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const route = await getPrismaClient().route.findFirst({
    where: { id: c.req.param("id"), status: "active", OR: [{ visibility: "public" }, { ownerId: user.id }] },
    include: { owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } }, bookmarks: { where: { userId: user.id }, select: { id: true } } },
  });
  return route ? c.json(routeDTO(route, user.id)) : c.json({ error: "Route not found." }, 404);
});

router.patch("/:id", zValidator("json", updateSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const updated = await getPrismaClient().route.updateMany({ where: { id: c.req.param("id"), ownerId: user.id }, data: c.req.valid("json") });
  return updated.count ? c.json({ ok: true }) : c.json({ error: "Route not found." }, 404);
});

router.delete("/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const updated = await getPrismaClient().route.updateMany({ where: { id: c.req.param("id"), ownerId: user.id }, data: { status: "archived" } });
  return updated.count ? c.json({ ok: true }) : c.json({ error: "Route not found." }, 404);
});

router.put("/:id/bookmark", async (c) => bookmark(c, true));
router.delete("/:id/bookmark", async (c) => bookmark(c, false));

async function bookmark(c: any, add: boolean) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const route = await prisma.route.findFirst({ where: { id: c.req.param("id"), visibility: "public", status: "active" }, select: { id: true } });
  if (!route) return c.json({ error: "Route not found." }, 404);
  await prisma.$transaction(async (tx) => {
    if (add) await tx.routeBookmark.upsert({ where: { userId_routeId: { userId: user.id, routeId: route.id } }, update: {}, create: { userId: user.id, routeId: route.id } });
    else await tx.routeBookmark.deleteMany({ where: { userId: user.id, routeId: route.id } });
    const count = await tx.routeBookmark.count({ where: { routeId: route.id } });
    await tx.route.update({ where: { id: route.id }, data: { bookmarkCount: count } });
  });
  return c.json({ ok: true, bookmarked: add });
}

function coordinatesFromActivity(value: unknown): Coordinate[] {
  const route = value as { geometry?: { coordinates?: unknown[] } } | null;
  return (route?.geometry?.coordinates ?? []).flatMap((raw) => {
    if (!Array.isArray(raw) || raw.length < 2) return [];
    const longitude = Number(raw[0]); const latitude = Number(raw[1]); const altitude = raw[2] == null ? undefined : Number(raw[2]);
    return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 ? [[longitude, latitude, Number.isFinite(altitude) ? altitude : undefined] as Coordinate] : [];
  });
}
function privacyTrimmed(points: Coordinate[]) {
  const total = polylineDistance(points); if (total < 600) return points;
  let start = 0; while (start + 1 < points.length && polylineDistance(points.slice(0, start + 2)) < 150) start++;
  let end = points.length - 1; while (end > start + 1 && polylineDistance(points.slice(end - 1)) < 150) end--;
  return points.slice(start, end + 1);
}
function routeBounds(points: Coordinate[]) { const latitudes = points.map((p) => p[1]); const longitudes = points.map((p) => p[0]); return { startLatitude: points[0][1], startLongitude: points[0][0], minLatitude: Math.min(...latitudes), maxLatitude: Math.max(...latitudes), minLongitude: Math.min(...longitudes), maxLongitude: Math.max(...longitudes) }; }
function polylineDistance(points: Coordinate[]) { return points.slice(1).reduce((sum, point, index) => sum + haversine(points[index], point), 0); }
function haversine(a: Coordinate, b: Coordinate) { const rad = Math.PI / 180, dLat = (b[1] - a[1]) * rad, dLon = (b[0] - a[0]) * rad, x = Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dLon / 2) ** 2; return 12_742_000 * Math.asin(Math.sqrt(x)); }
function elevationGain(points: Coordinate[]) { let gain = 0, samples = 0; for (let i = 1; i < points.length; i++) if (points[i][2] != null && points[i - 1][2] != null) { gain += Math.max(0, points[i][2]! - points[i - 1][2]!); samples++; } return samples ? gain : null; }
function classifyShape(points: Coordinate[]) { return haversine(points[0], points.at(-1)!) < Math.min(250, polylineDistance(points) * 0.08) ? "loop" : "point_to_point"; }
function finiteQuery(value?: string) { const number = Number(value); return value != null && Number.isFinite(number) ? number : null; }
function routeDTO(route: any, userId: string, latitude?: number, longitude?: number) { const geometry = route.geometry as { coordinates?: Coordinate[] }; return { id: route.id, name: route.name, description: route.description, activityType: route.activityType, visibility: route.visibility, geometry: { type: "LineString", coordinates: geometry.coordinates ?? [] }, distanceM: route.distanceM, elevationGainM: route.elevationGainM, routeShape: route.routeShape, bookmarkCount: route.bookmarkCount, completionCount: route.completionCount, isBookmarked: route.bookmarks.length > 0, isOwnedByCurrentUser: route.ownerId === userId, owner: route.owner, createdAt: route.createdAt, updatedAt: route.updatedAt, distanceFromSearchM: latitude == null || longitude == null ? null : haversine([longitude, latitude], [route.startLongitude, route.startLatitude]) }; }

export default router;
