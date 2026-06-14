import { createHash, randomBytes } from "node:crypto";
import { Hono } from "hono";
import type { Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const createLiveShareSchema = z.object({
  activityId: z.string().min(1).max(128).optional(),
  recipientLabel: z.string().trim().min(1).max(80).optional(),
  deliveryTargets: z
    .array(
      z.object({
        channel: z.enum(["sms", "push"]),
        label: z.string().trim().min(1).max(80).optional(),
        address: z.string().trim().min(1).max(160).optional(),
      })
    )
    .max(5)
    .optional(),
  sport: z.string().trim().min(1).max(32).optional(),
  title: z.string().trim().min(1).max(120).optional(),
  expiresInSeconds: z.number().int().min(300).max(8 * 60 * 60).optional(),
});

const liveLocationSchema = z.object({
  recordedAt: z.string(),
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  altitudeM: z.number().finite().optional().nullable(),
  accuracyM: z.number().finite().optional().nullable(),
  elapsedSeconds: z.number().int().min(0),
  distanceM: z.number().finite().min(0),
});

router.post("/live-shares", zValidator("json", createLiveShareSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) {
    return c.json({ error: "Authentication is required." }, 401);
  }

  const body = c.req.valid("json");
  const prisma = getPrismaClient();
  const token = randomToken();
  const startedAt = new Date();
  const expiresAt = new Date(startedAt.getTime() + (body.expiresInSeconds ?? 4 * 60 * 60) * 1000);

  const share = await prisma.safetyLiveShare.create({
    data: {
      userId: user.id,
      activityId: body.activityId,
      tokenHash: hashToken(token),
      recipientLabel: body.recipientLabel,
      sport: body.sport,
      title: body.title,
      startedAt,
      expiresAt,
    },
  });

  const shareURL = publicLiveURL(c.req.url, token);
  const deliveries = await deliverLiveShareStub({
    shareId: share.id,
    shareURL,
    title: share.title ?? "Live run",
    targets: body.deliveryTargets ?? [],
  });

  return c.json(
    {
      id: share.id,
      token,
      shareURL,
      status: share.status,
      startedAt: share.startedAt,
      expiresAt: share.expiresAt,
      deliveries,
    },
    201
  );
});

router.patch("/live-shares/:id/location", zValidator("json", liveLocationSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) {
    return c.json({ error: "Authentication is required." }, 401);
  }

  const prisma = getPrismaClient();
  const share = await prisma.safetyLiveShare.findFirst({
    where: { id: c.req.param("id"), userId: user.id },
  });
  if (!share) return c.json({ error: "Live share not found." }, 404);

  const now = new Date();
  if (share.endedAt || share.status !== "active") {
    return c.json({ error: "Live share is not active." }, 409);
  }
  if (share.expiresAt <= now) {
    await prisma.safetyLiveShare.update({
      where: { id: share.id },
      data: { status: "expired", endedAt: share.endedAt },
    });
    return c.json({ error: "Live share has expired." }, 410);
  }

  const body = c.req.valid("json");
  const recordedAt = new Date(body.recordedAt);
  const point = {
    recordedAt: recordedAt.toISOString(),
    latitude: body.latitude,
    longitude: body.longitude,
    altitudeM: body.altitudeM ?? null,
    accuracyM: body.accuracyM ?? null,
    elapsedSeconds: body.elapsedSeconds,
    distanceM: body.distanceM,
  };
  const routePreview = appendRoutePoint(share.routePreview, point);

  const updated = await prisma.$transaction(async (tx) => {
    await tx.safetyLiveSharePoint.create({
      data: {
        shareId: share.id,
        recordedAt,
        latitude: body.latitude,
        longitude: body.longitude,
        altitudeM: body.altitudeM ?? undefined,
        accuracyM: body.accuracyM ?? undefined,
        elapsedSeconds: body.elapsedSeconds,
        distanceM: body.distanceM,
      },
    });

    return tx.safetyLiveShare.update({
      where: { id: share.id },
      data: {
        lastLocationAt: recordedAt,
        lastLocation: point,
        routePreview,
        elapsedSeconds: body.elapsedSeconds,
        distanceM: body.distanceM,
      },
    });
  });

  return c.json(liveShareAppPayload(updated));
});

router.post("/live-shares/:id/end", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) {
    return c.json({ error: "Authentication is required." }, 401);
  }

  const prisma = getPrismaClient();
  const share = await prisma.safetyLiveShare.findFirst({
    where: { id: c.req.param("id"), userId: user.id },
  });
  if (!share) return c.json({ error: "Live share not found." }, 404);

  const updated = await prisma.safetyLiveShare.update({
    where: { id: share.id },
    data: {
      status: share.status === "active" ? "ended" : share.status,
      endedAt: share.endedAt ?? new Date(),
    },
  });

  return c.json(liveShareAppPayload(updated));
});

export async function liveShareViewer(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const token = c.req.param("token");
  if (!token) {
    return c.html(notFoundHTML(), 404);
  }
  const payload = await publicLiveSharePayload(token);
  if (!payload) {
    return c.html(notFoundHTML(), 404);
  }

  if (c.req.query("format") === "json") {
    return c.json(payload);
  }

  return c.html(liveShareHTML(token, payload));
}

async function publicLiveSharePayload(token: string) {
  const prisma = getPrismaClient();
  const share = await prisma.safetyLiveShare.findUnique({
    where: { tokenHash: hashToken(token) },
  });
  if (!share) return null;

  const now = new Date();
  const computedStatus =
    share.status === "active" && share.expiresAt <= now ? "expired" : share.status;
  const lastLocationAt = share.lastLocationAt?.toISOString() ?? null;
  const stale =
    computedStatus === "active" &&
    Boolean(share.lastLocationAt) &&
    now.getTime() - (share.lastLocationAt?.getTime() ?? 0) > 90_000;

  return {
    id: share.id,
    status: computedStatus,
    stale,
    title: share.title ?? "Live run",
    sport: share.sport ?? "run",
    startedAt: share.startedAt.toISOString(),
    expiresAt: share.expiresAt.toISOString(),
    endedAt: share.endedAt?.toISOString() ?? null,
    lastLocationAt,
    lastLocation: share.lastLocation,
    routePreview: share.routePreview,
    elapsedSeconds: share.elapsedSeconds,
    distanceM: share.distanceM,
  };
}

function liveShareAppPayload(share: {
  id: string;
  status: string;
  startedAt: Date;
  expiresAt: Date;
  endedAt: Date | null;
  lastLocationAt: Date | null;
}) {
  return {
    id: share.id,
    status: share.status,
    startedAt: share.startedAt,
    expiresAt: share.expiresAt,
    endedAt: share.endedAt,
    lastLocationAt: share.lastLocationAt,
  };
}

function randomToken() {
  return randomBytes(32).toString("base64url");
}

function hashToken(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

function publicLiveURL(requestURL: string, token: string) {
  const configured = process.env.PUBLIC_WEB_BASE_URL?.trim();
  const origin = configured && configured.length > 0 ? configured : new URL(requestURL).origin;
  return `${origin.replace(/\/$/, "")}/live/${encodeURIComponent(token)}`;
}

async function deliverLiveShareStub(input: {
  shareId: string;
  shareURL: string;
  title: string;
  targets: Array<{ channel: "sms" | "push"; label?: string; address?: string }>;
}) {
  return input.targets.map((target, index) => ({
    id: `${input.shareId}-${target.channel}-${index + 1}`,
    channel: target.channel,
    label: target.label ?? null,
    addressLast4: target.address ? target.address.slice(-4) : null,
    status: "stubbed",
    message:
      target.channel === "sms"
        ? "SMS delivery is stubbed until the provider is configured."
        : "Push delivery is stubbed until recipient devices are registered.",
    shareURL: input.shareURL,
  }));
}

function appendRoutePoint(routePreview: unknown, point: Record<string, unknown>) {
  const points = Array.isArray(routePreview) ? routePreview : [];
  return [...points, point].slice(-720);
}

function liveShareHTML(token: string, initialPayload: unknown) {
  const initialJSON = JSON.stringify(initialPayload).replace(/</g, "\\u003c");
  const escapedToken = JSON.stringify(token);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Outbound Live Run</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #f6f4ef; color: #161412; }
    main { max-width: 680px; margin: 0 auto; padding: 22px; }
    .hero { background: #fff; border-radius: 18px; padding: 20px; box-shadow: 0 10px 30px rgba(0,0,0,.08); }
    .status { display: inline-flex; gap: 8px; align-items: center; padding: 7px 10px; border-radius: 999px; background: #fff3e6; color: #a34800; font-weight: 700; font-size: 13px; }
    h1 { margin: 14px 0 6px; font-size: clamp(28px, 8vw, 44px); line-height: 1; }
    .muted { color: #6f6a63; }
    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 18px 0; }
    .tile { background: #f6f4ef; border-radius: 12px; padding: 12px; }
    .value { font-weight: 800; font-size: 20px; }
    .label { color: #77716a; font-size: 12px; margin-top: 2px; }
    .map { height: 340px; border-radius: 16px; background: #e7e2da; position: relative; overflow: hidden; border: 1px solid rgba(0,0,0,.06); }
    svg { width: 100%; height: 100%; display: block; }
    .footer { font-size: 12px; margin-top: 14px; color: #77716a; }
    @media (max-width: 520px) { .grid { grid-template-columns: 1fr; } main { padding: 14px; } .map { height: 280px; } }
  </style>
</head>
<body>
  <main>
    <section class="hero">
      <div class="status" id="status">Live</div>
      <h1 id="title">Outbound live run</h1>
      <div class="muted" id="subtitle">Waiting for the first location update.</div>
      <div class="grid">
        <div class="tile"><div class="value" id="distance">--</div><div class="label">Distance</div></div>
        <div class="tile"><div class="value" id="elapsed">--</div><div class="label">Elapsed</div></div>
        <div class="tile"><div class="value" id="updated">--</div><div class="label">Last update</div></div>
      </div>
      <div class="map"><svg id="map" viewBox="0 0 100 100" preserveAspectRatio="none"></svg></div>
      <div class="footer">Only this active shared session is visible. Photos, profile, and past activities are not shared.</div>
    </section>
  </main>
  <script>
    const token = ${escapedToken};
    let state = ${initialJSON};
    function formatElapsed(seconds) {
      const h = Math.floor(seconds / 3600);
      const m = Math.floor((seconds % 3600) / 60);
      const s = Math.floor(seconds % 60);
      return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0") : m + ":" + String(s).padStart(2, "0");
    }
    function formatAgo(iso) {
      if (!iso) return "--";
      const seconds = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
      if (seconds < 60) return seconds + "s ago";
      return Math.round(seconds / 60) + "m ago";
    }
    function renderMap(points) {
      const svg = document.getElementById("map");
      svg.innerHTML = "";
      if (!Array.isArray(points) || points.length === 0) return;
      const lats = points.map(p => p.latitude);
      const lngs = points.map(p => p.longitude);
      const minLat = Math.min(...lats), maxLat = Math.max(...lats);
      const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
      const pad = 8;
      const spanLat = Math.max(maxLat - minLat, 0.0005);
      const spanLng = Math.max(maxLng - minLng, 0.0005);
      const coords = points.map(p => {
        const x = pad + ((p.longitude - minLng) / spanLng) * (100 - pad * 2);
        const y = 100 - pad - ((p.latitude - minLat) / spanLat) * (100 - pad * 2);
        return x.toFixed(2) + "," + y.toFixed(2);
      }).join(" ");
      const poly = document.createElementNS("http://www.w3.org/2000/svg", "polyline");
      poly.setAttribute("points", coords);
      poly.setAttribute("fill", "none");
      poly.setAttribute("stroke", "#f97316");
      poly.setAttribute("stroke-width", "3.2");
      poly.setAttribute("stroke-linecap", "round");
      poly.setAttribute("stroke-linejoin", "round");
      svg.appendChild(poly);
      const last = coords.split(" ").at(-1).split(",");
      const dot = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      dot.setAttribute("cx", last[0]);
      dot.setAttribute("cy", last[1]);
      dot.setAttribute("r", "2.4");
      dot.setAttribute("fill", "#111827");
      svg.appendChild(dot);
    }
    function render(next) {
      state = next;
      document.getElementById("title").textContent = state.title || "Outbound live run";
      document.getElementById("distance").textContent = ((state.distanceM || 0) / 1000).toFixed(2) + " km";
      document.getElementById("elapsed").textContent = formatElapsed(state.elapsedSeconds || 0);
      document.getElementById("updated").textContent = formatAgo(state.lastLocationAt);
      const status = document.getElementById("status");
      const label = state.status === "active" ? (state.stale ? "Signal stale" : "Live") : state.status;
      status.textContent = label;
      document.getElementById("subtitle").textContent = state.lastLocationAt ? "Last update " + formatAgo(state.lastLocationAt) : "Waiting for the first location update.";
      renderMap(state.routePreview || []);
    }
    async function poll() {
      try {
        const response = await fetch("/live/" + encodeURIComponent(token) + "?format=json", { cache: "no-store" });
        if (response.ok) render(await response.json());
      } catch (_) {}
    }
    render(state);
    setInterval(poll, 10000);
  </script>
</body>
</html>`;
}

function notFoundHTML() {
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Live run unavailable</title></head><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;padding:32px"><h1>Live run unavailable</h1><p>This live share is expired, ended, or the link is invalid.</p></body></html>`;
}

export default router;
