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
    * { box-sizing: border-box; }
    body { margin: 0; background: #f3f0ea; color: #171512; }
    main { max-width: 760px; margin: 0 auto; padding: 14px; }
    .hero { background: #fffdfa; border-radius: 20px; padding: 14px; box-shadow: 0 12px 36px rgba(30,24,16,.10); }
    .topbar { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 12px; align-items: start; padding: 4px 2px 12px; }
    .status { display: inline-flex; gap: 8px; align-items: center; justify-self: end; padding: 7px 11px; border-radius: 999px; background: #fff0df; color: #a94700; font-weight: 750; font-size: 13px; white-space: nowrap; }
    .status.live { background: #ecfdf3; color: #08743a; }
    .status.ended { background: #eeeeec; color: #5f5a53; }
    h1 { margin: 0 0 5px; font-size: clamp(28px, 7vw, 42px); line-height: .98; letter-spacing: 0; }
    .muted { color: #706b64; font-size: 15px; }
    .map { height: min(62vh, 540px); min-height: 420px; border-radius: 18px; background: #e7e1d7; position: relative; overflow: hidden; border: 1px solid rgba(30,24,16,.08); }
    .map::before {
      content: "";
      position: absolute;
      inset: 0;
      background:
        linear-gradient(18deg, transparent 0 31%, rgba(255,255,255,.34) 31.3% 32.4%, transparent 32.7% 100%),
        linear-gradient(106deg, transparent 0 44%, rgba(255,255,255,.28) 44.2% 45.4%, transparent 45.7% 100%),
        linear-gradient(154deg, transparent 0 62%, rgba(255,255,255,.24) 62.2% 63.1%, transparent 63.4% 100%),
        radial-gradient(circle at 20% 18%, rgba(105,132,92,.16), transparent 24%),
        radial-gradient(circle at 82% 68%, rgba(91,117,142,.12), transparent 26%);
    }
    svg { width: 100%; height: 100%; display: block; position: relative; z-index: 1; }
    .metrics { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1px; margin: 12px 0 0; overflow: hidden; border-radius: 14px; border: 1px solid rgba(30,24,16,.06); background: rgba(30,24,16,.06); }
    .tile { background: #f7f3ed; padding: 10px 12px; min-width: 0; }
    .value { font-weight: 850; font-size: clamp(18px, 5vw, 25px); line-height: 1.05; overflow-wrap: anywhere; }
    .label { color: #746e66; font-size: 12px; margin-top: 3px; }
    .footer { font-size: 12px; line-height: 1.35; margin: 11px 2px 0; color: #77716a; }
    @media (max-width: 520px) {
      main { padding: 10px; }
      .hero { padding: 12px; border-radius: 18px; }
      .topbar { grid-template-columns: 1fr; gap: 9px; }
      .status { justify-self: start; order: -1; }
      .map { height: 56vh; min-height: 390px; }
      .metrics { grid-template-columns: 1fr 1fr; }
      .tile:first-child { grid-column: span 2; }
    }
  </style>
</head>
<body>
  <main>
    <section class="hero">
      <div class="topbar">
        <div>
          <h1 id="title">Outbound live run</h1>
          <div class="muted" id="subtitle">Waiting for the first location update.</div>
        </div>
        <div class="status" id="status">Live</div>
      </div>
      <div class="map"><svg id="map" viewBox="0 0 100 100" preserveAspectRatio="none"></svg></div>
      <div class="metrics">
        <div class="tile"><div class="value" id="distance">--</div><div class="label">Distance</div></div>
        <div class="tile"><div class="value" id="elapsed">--</div><div class="label">Elapsed</div></div>
        <div class="tile"><div class="value" id="updated">--</div><div class="label">Last update</div></div>
      </div>
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
    function validPoint(point) {
      return point && Number.isFinite(point.latitude) && Number.isFinite(point.longitude);
    }
    function mapPoints(next) {
      const preview = Array.isArray(next.routePreview) ? next.routePreview.filter(validPoint) : [];
      if (preview.length > 0) return preview;
      return validPoint(next.lastLocation) ? [next.lastLocation] : [];
    }
    function svgElement(name, attributes) {
      const element = document.createElementNS("http://www.w3.org/2000/svg", name);
      Object.entries(attributes).forEach(([key, value]) => element.setAttribute(key, String(value)));
      return element;
    }
    function renderMap(points) {
      const svg = document.getElementById("map");
      svg.innerHTML = "";
      if (!Array.isArray(points) || points.length === 0) {
        svg.appendChild(svgElement("text", { x: 50, y: 50, "text-anchor": "middle", fill: "#77716a", "font-size": 4.4, "font-weight": 700 }));
        svg.lastChild.textContent = "Waiting for location";
        return;
      }
      const lats = points.map(p => p.latitude);
      const lngs = points.map(p => p.longitude);
      const minLat = Math.min(...lats), maxLat = Math.max(...lats);
      const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
      const pad = 10;
      const rawSpanLat = maxLat - minLat;
      const rawSpanLng = maxLng - minLng;
      const centerLat = (minLat + maxLat) / 2;
      const centerLng = (minLng + maxLng) / 2;
      const spanLat = Math.max(rawSpanLat, 0.0008);
      const spanLng = Math.max(rawSpanLng, 0.0008);
      const scale = Math.min((100 - pad * 2) / spanLng, (100 - pad * 2) / spanLat);
      const project = p => {
        const x = 50 + (p.longitude - centerLng) * scale;
        const y = 50 - (p.latitude - centerLat) * scale;
        return [Math.max(pad, Math.min(100 - pad, x)), Math.max(pad, Math.min(100 - pad, y))];
      };
      const projected = points.map(project);
      const coords = projected.map(([x, y]) => x.toFixed(2) + "," + y.toFixed(2)).join(" ");
      if (projected.length > 1) {
        svg.appendChild(svgElement("polyline", {
          points: coords,
          fill: "none",
          stroke: "rgba(255,255,255,.85)",
          "stroke-width": 6.8,
          "stroke-linecap": "round",
          "stroke-linejoin": "round"
        }));
        svg.appendChild(svgElement("polyline", {
          points: coords,
          fill: "none",
          stroke: "#f26d21",
          "stroke-width": 4.2,
          "stroke-linecap": "round",
          "stroke-linejoin": "round"
        }));
      }
      const first = projected[0];
      svg.appendChild(svgElement("circle", { cx: first[0], cy: first[1], r: 1.65, fill: "#ffffff", stroke: "#f26d21", "stroke-width": 1.1 }));
      const last = projected.at(-1);
      svg.appendChild(svgElement("circle", { cx: last[0], cy: last[1], r: 4.5, fill: "rgba(17,24,39,.14)" }));
      svg.appendChild(svgElement("circle", { cx: last[0], cy: last[1], r: 2.25, fill: "#101828", stroke: "#ffffff", "stroke-width": .9 }));
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
      status.className = "status " + (state.status === "active" && !state.stale ? "live" : state.status !== "active" ? "ended" : "");
      document.getElementById("subtitle").textContent = state.lastLocationAt ? "Last update " + formatAgo(state.lastLocationAt) : "Waiting for the first location update.";
      renderMap(mapPoints(state));
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
