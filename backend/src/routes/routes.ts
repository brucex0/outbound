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
const MAX_CANONICAL_ROUTE_POINTS = 100_000;
const MIN_CANONICAL_ROUTE_DISTANCE_M = 10;
const PRIVACY_TRIM_DISTANCE_M = 150;
const MIN_DISTANCE_FOR_PRIVACY_TRIM_M = 600;

const ownerSelect = {
  id: true,
  username: true,
  displayName: true,
  avatarUrl: true,
} as const satisfies Prisma.UserSelect;

function summarySelect(userId: string) {
  return {
    id: true,
    ownerId: true,
    name: true,
    description: true,
    activityType: true,
    visibility: true,
    distanceM: true,
    elevationGainM: true,
    routeShape: true,
    startLatitude: true,
    startLongitude: true,
    bookmarkCount: true,
    completionCount: true,
    createdAt: true,
    updatedAt: true,
    owner: { select: ownerSelect },
    bookmarks: { where: { userId }, select: { id: true } },
  } as const satisfies Prisma.RouteSelect;
}

function detailSelect(userId: string) {
  return {
    ...summarySelect(userId),
    geometry: true,
  } as const satisfies Prisma.RouteSelect;
}

type RouteSummaryRecord = Prisma.RouteGetPayload<{ select: ReturnType<typeof summarySelect> }>;
type RouteDetailRecord = Prisma.RouteGetPayload<{ select: ReturnType<typeof detailSelect> }>;

router.get("/nearby", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const latitude = finiteQuery(c.req.query("latitude"));
  const longitude = finiteQuery(c.req.query("longitude"));
  if (latitude == null || longitude == null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
    return c.json({ error: "A valid latitude and longitude are required." }, 400);
  }
  const radiusKm = Math.min(100, Math.max(1, finiteQuery(c.req.query("radiusKm")) ?? 25));
  const latitudeDelta = radiusKm / 111;
  const longitudeDelta = radiusKm / Math.max(20, 111 * Math.cos(latitude * Math.PI / 180));
  const routes = await getPrismaClient().route.findMany({
    where: {
      visibility: "public", status: "active",
      startLatitude: { gte: latitude - latitudeDelta, lte: latitude + latitudeDelta },
      startLongitude: { gte: longitude - longitudeDelta, lte: longitude + longitudeDelta },
    },
    select: summarySelect(user.id),
    take: 100,
  });
  return c.json({ routes: routes.map((route) => routeSummaryDTO(route, user.id, latitude, longitude)).sort((a, b) => (a.distanceFromSearchM ?? 0) - (b.distanceFromSearchM ?? 0)) });
});

router.get("/search", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const query = (c.req.query("q") ?? "").trim().slice(0, 200);
  const routes = await getPrismaClient().route.findMany({
    where: { visibility: "public", status: "active", ...(query ? { OR: [{ name: { contains: query, mode: "insensitive" } }, { description: { contains: query, mode: "insensitive" } }] } : {}) },
    select: summarySelect(user.id),
    orderBy: [{ bookmarkCount: "desc" }, { completionCount: "desc" }, { updatedAt: "desc" }], take: 100,
  });
  return c.json({ routes: routes.map((route) => routeSummaryDTO(route, user.id)) });
});

router.get("/mine", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const routes = await getPrismaClient().route.findMany({
    where: { OR: [{ ownerId: user.id }, { bookmarks: { some: { userId: user.id } } }], status: "active" },
    select: summarySelect(user.id),
    orderBy: { updatedAt: "desc" },
    take: 100,
  });
  return c.json({ routes: routes.map((route) => routeSummaryDTO(route, user.id)) });
});

router.post("/from-activity/:activityId", zValidator("json", publishSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const activity = await prisma.activity.findFirst({ where: { OR: [{ id: c.req.param("activityId") }, { clientActivityId: c.req.param("activityId") }], userId: user.id, deletedAt: null } });
  if (!activity) return c.json({ error: "Only your own saved activity can become a route." }, 404);
  const parsedCoordinates = coordinatesFromActivity(activity.route);
  if (!parsedCoordinates.ok) return c.json({ error: parsedCoordinates.error }, 422);
  const coordinates = parsedCoordinates.coordinates;
  if (polylineDistance(coordinates) < MIN_CANONICAL_ROUTE_DISTANCE_M) {
    return c.json({ error: "This activity does not contain a usable route." }, 422);
  }
  const publicCoordinates = privacyTrimmed(coordinates);
  const bounds = routeBounds(publicCoordinates);
  const distanceM = polylineDistance(publicCoordinates);
  const body = c.req.valid("json");
  const route = await prisma.route.upsert({
    where: { sourceActivityId: activity.id },
    update: { name: body.name, description: body.description, status: "active" },
    create: {
      ownerId: user.id, sourceActivityId: activity.id, name: body.name, description: body.description,
      activityType: activity.type, visibility: "public", geometry: { type: "LineString", coordinates: publicCoordinates } as Prisma.InputJsonValue,
      distanceM, elevationGainM: elevationGain(publicCoordinates), routeShape: classifyShape(publicCoordinates, distanceM), ...bounds,
    },
    select: detailSelect(user.id),
  });
  return c.json(routeDetailDTO(route, user.id), 201);
});

router.get("/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const route = await getPrismaClient().route.findFirst({
    where: { id: c.req.param("id"), status: "active", OR: [{ visibility: "public" }, { ownerId: user.id }] },
    select: detailSelect(user.id),
  });
  return route ? c.json(routeDetailDTO(route, user.id)) : c.json({ error: "Route not found." }, 404);
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

function coordinatesFromActivity(value: unknown): { ok: true; coordinates: Coordinate[] } | { ok: false; error: string } {
  const route = value as { geometry?: { coordinates?: unknown[] } } | null;
  const rawCoordinates = route?.geometry?.coordinates;
  if (!Array.isArray(rawCoordinates) || rawCoordinates.length < 2) {
    return { ok: false, error: "This activity does not contain a usable route." };
  }
  if (rawCoordinates.length > MAX_CANONICAL_ROUTE_POINTS) {
    return { ok: false, error: `Routes may contain at most ${MAX_CANONICAL_ROUTE_POINTS.toLocaleString("en-US")} points.` };
  }

  const coordinates: Coordinate[] = [];
  for (const raw of rawCoordinates) {
    if (!Array.isArray(raw) || raw.length < 2 || raw.length > 3) {
      return { ok: false, error: "This activity contains invalid route coordinates." };
    }
    const longitude = raw[0];
    const latitude = raw[1];
    if (
      typeof latitude !== "number"
      || typeof longitude !== "number"
      || !Number.isFinite(latitude)
      || !Number.isFinite(longitude)
      || Math.abs(latitude) > 90
      || Math.abs(longitude) > 180
    ) {
      return { ok: false, error: "This activity contains invalid route coordinates." };
    }
    let altitude: number | undefined;
    if (raw[2] != null) {
      if (typeof raw[2] !== "number" || !Number.isFinite(raw[2])) {
        return { ok: false, error: "This activity contains invalid route coordinates." };
      }
      altitude = raw[2];
    }
    coordinates.push(altitude == null ? [longitude, latitude] : [longitude, latitude, altitude]);
  }
  return { ok: true, coordinates };
}
function privacyTrimmed(points: Coordinate[]) {
  const cumulativeDistances = new Float64Array(points.length);
  for (let index = 1; index < points.length; index++) {
    cumulativeDistances[index] = cumulativeDistances[index - 1] + haversine(points[index - 1], points[index]);
  }
  const total = cumulativeDistances[cumulativeDistances.length - 1];
  if (total < MIN_DISTANCE_FOR_PRIVACY_TRIM_M) return points;

  const start = pointAtDistance(points, cumulativeDistances, PRIVACY_TRIM_DISTANCE_M);
  const end = pointAtDistance(points, cumulativeDistances, total - PRIVACY_TRIM_DISTANCE_M);
  const trimmed: Coordinate[] = [start.coordinate];
  for (let index = start.segmentIndex + 1; index <= end.segmentIndex; index++) {
    appendDistinct(trimmed, points[index]);
  }
  appendDistinct(trimmed, end.coordinate);
  return trimmed;
}
function pointAtDistance(points: Coordinate[], cumulativeDistances: Float64Array, targetDistance: number) {
  let low = 1;
  let high = cumulativeDistances.length - 1;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (cumulativeDistances[middle] < targetDistance) low = middle + 1;
    else high = middle;
  }
  const segmentIndex = Math.max(0, low - 1);
  const segmentStartDistance = cumulativeDistances[segmentIndex];
  const segmentDistance = cumulativeDistances[segmentIndex + 1] - segmentStartDistance;
  const fraction = segmentDistance > 0 ? Math.max(0, Math.min(1, (targetDistance - segmentStartDistance) / segmentDistance)) : 0;
  return { segmentIndex, coordinate: interpolate(points[segmentIndex], points[segmentIndex + 1], fraction) };
}
function interpolate(start: Coordinate, end: Coordinate, fraction: number): Coordinate {
  let longitudeDelta = end[0] - start[0];
  if (longitudeDelta > 180) longitudeDelta -= 360;
  else if (longitudeDelta < -180) longitudeDelta += 360;
  let longitude = start[0] + longitudeDelta * fraction;
  if (longitude > 180) longitude -= 360;
  else if (longitude < -180) longitude += 360;
  const latitude = start[1] + (end[1] - start[1]) * fraction;
  if (start[2] == null || end[2] == null) return [longitude, latitude];
  return [longitude, latitude, start[2] + (end[2] - start[2]) * fraction];
}
function appendDistinct(points: Coordinate[], coordinate: Coordinate) {
  const last = points.at(-1);
  if (!last || last[0] !== coordinate[0] || last[1] !== coordinate[1] || last[2] !== coordinate[2]) points.push(coordinate);
}
function routeBounds(points: Coordinate[]) {
  let minLatitude = points[0][1], maxLatitude = points[0][1], minLongitude = points[0][0], maxLongitude = points[0][0];
  for (let index = 1; index < points.length; index++) {
    minLatitude = Math.min(minLatitude, points[index][1]);
    maxLatitude = Math.max(maxLatitude, points[index][1]);
    minLongitude = Math.min(minLongitude, points[index][0]);
    maxLongitude = Math.max(maxLongitude, points[index][0]);
  }
  return { startLatitude: points[0][1], startLongitude: points[0][0], minLatitude, maxLatitude, minLongitude, maxLongitude };
}
function polylineDistance(points: Coordinate[]) { let distance = 0; for (let index = 1; index < points.length; index++) distance += haversine(points[index - 1], points[index]); return distance; }
function haversine(a: Coordinate, b: Coordinate) { const rad = Math.PI / 180, dLat = (b[1] - a[1]) * rad, dLon = (b[0] - a[0]) * rad, x = Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dLon / 2) ** 2; return 12_742_000 * Math.asin(Math.sqrt(Math.min(1, x))); }
function elevationGain(points: Coordinate[]) { let gain = 0, samples = 0; for (let i = 1; i < points.length; i++) if (points[i][2] != null && points[i - 1][2] != null) { gain += Math.max(0, points[i][2]! - points[i - 1][2]!); samples++; } return samples ? gain : null; }
function classifyShape(points: Coordinate[], distanceM: number) { return haversine(points[0], points.at(-1)!) < Math.min(250, distanceM * 0.08) ? "loop" : "point_to_point"; }
function finiteQuery(value?: string) { const number = Number(value); return value != null && Number.isFinite(number) ? number : null; }
function routeSummaryDTO(route: RouteSummaryRecord, userId: string, latitude?: number, longitude?: number) { return { id: route.id, name: route.name, description: route.description, activityType: route.activityType, visibility: route.visibility, distanceM: route.distanceM, elevationGainM: route.elevationGainM, routeShape: route.routeShape, bookmarkCount: route.bookmarkCount, completionCount: route.completionCount, isBookmarked: route.bookmarks.length > 0, isOwnedByCurrentUser: route.ownerId === userId, owner: route.owner, createdAt: route.createdAt, updatedAt: route.updatedAt, distanceFromSearchM: latitude == null || longitude == null ? null : haversine([longitude, latitude], [route.startLongitude, route.startLatitude]) }; }
function routeDetailDTO(route: RouteDetailRecord, userId: string) { const geometry = route.geometry as { coordinates?: Coordinate[] }; return { ...routeSummaryDTO(route, userId), geometry: { type: "LineString", coordinates: geometry.coordinates ?? [] } }; }

export default router;
