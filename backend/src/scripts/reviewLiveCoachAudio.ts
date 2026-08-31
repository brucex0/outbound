import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { audioPackManifestSchema, type AudioPackManifest } from "../services/liveCoach/audioPackManifest.js";
import {
  LIVE_COACH_REJECTION_REASON_CODES,
  liveCoachReviewEntryID,
  normalizeLiveCoachRejectionReason,
  parseLiveCoachReviewProgress,
  type LiveCoachReviewProgress,
  type LiveCoachReviewStatus,
} from "../services/liveCoach/audioReviewFeedback.js";

const args = parseArgs(process.argv.slice(2));
const manifestPath = path.resolve(process.cwd(), args.reviewManifest ?? ".local/live-coach-review/2026-08-30.1/review-manifest.json");
const audioDirectory = path.dirname(manifestPath);
const progressPath = path.join(audioDirectory, "review-progress.json");
let manifest = audioPackManifestSchema.parse(JSON.parse(await readFile(manifestPath, "utf8")));
let progress = await loadProgress();
reconcileProgress();

const server = createServer(async (request, response) => {
  try {
    addSecurityHeaders(response);
    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "127.0.0.1"}`);
    if (request.method === "GET" && url.pathname === "/") return send(response, 200, "text/html; charset=utf-8", reviewPage);
    if (request.method === "GET" && url.pathname === "/api/reviews") return sendJSON(response, 200, reviewState());
    const audioMatch = request.method === "GET" && url.pathname.match(/^\/audio\/(\d+)$/);
    if (audioMatch) return sendAudio(response, Number(audioMatch[1]));
    const reviewMatch = request.method === "POST" && url.pathname.match(/^\/api\/reviews\/(\d+)$/);
    if (reviewMatch) return updateReview(request, response, Number(reviewMatch[1]));
    return sendJSON(response, 404, { error: "Not found." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected review server error.";
    return sendJSON(response, 500, { error: message });
  }
});

server.listen(args.port, "127.0.0.1", () => {
  console.log(`Live-coach review: http://127.0.0.1:${args.port}`);
  console.log(`Manifest: ${manifestPath}`);
  console.log("Shortcuts: Space play/pause, A approve, R reject, Left/Right navigate.");
});

async function sendAudio(response: ServerResponse, index: number): Promise<void> {
  const entry = manifest.entries[index];
  if (!entry?.reviewFileName || !/^[a-f0-9]{64}\.wav$/.test(entry.reviewFileName)) {
    sendJSON(response, 404, { error: "Audio entry not found." });
    return;
  }
  const data = await readFile(path.join(audioDirectory, entry.reviewFileName));
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("Content-Length", String(data.byteLength));
  send(response, 200, "audio/wav", data);
}

async function updateReview(request: IncomingMessage, response: ServerResponse, index: number): Promise<void> {
  const allowedOrigin = `http://127.0.0.1:${args.port}`;
  if (request.headers.origin && request.headers.origin !== allowedOrigin) {
    return sendJSON(response, 403, { error: "Cross-origin review updates are not allowed." });
  }
  const entry = manifest.entries[index];
  if (!entry) return sendJSON(response, 404, { error: "Review entry not found." });
  const body = JSON.parse(await readBody(request)) as {
    sha256?: unknown;
    status?: unknown;
    listened?: unknown;
    rejectionReason?: unknown;
  };
  if (body.sha256 !== entry.sha256) return sendJSON(response, 409, { error: "Audio changed; reload before reviewing." });
  if (!isReviewStatus(body.status)) return sendJSON(response, 400, { error: "Invalid review status." });
  if (body.status !== "unreviewed" && body.listened !== true) {
    return sendJSON(response, 400, { error: "Play the complete clip before reviewing it." });
  }
  const rejectionReason = body.status === "rejected"
    ? normalizeLiveCoachRejectionReason(body.rejectionReason)
    : undefined;
  if (body.status === "rejected" && !rejectionReason) {
    return sendJSON(response, 400, { error: "Select a rejection reason. Other requires a written detail." });
  }
  entry.approved = body.status === "approved";
  progress.entries[entryID(entry)] = {
    sha256: entry.sha256,
    status: body.status,
    ...(body.status === "unreviewed" ? {} : { reviewedAt: new Date().toISOString() }),
    ...(rejectionReason ? { rejectionReason } : {}),
  };
  await persistReview();
  sendJSON(response, 200, reviewState());
}

function reviewState() {
  return {
    catalogVersion: manifest.catalogVersion,
    entries: manifest.entries.map((entry, index) => ({
      index,
      cueKey: entry.cueKey,
      locale: entry.locale,
      voiceProfileId: entry.voiceProfileId,
      scriptStyleId: entry.scriptStyleId,
      transcript: entry.transcript,
      durationMilliseconds: entry.durationMilliseconds,
      sha256: entry.sha256,
      status: currentStatus(entry),
      rejectionReason: currentRejectionReason(entry),
    })),
    rejectionReasonCodes: LIVE_COACH_REJECTION_REASON_CODES,
  };
}

function currentStatus(entry: AudioPackManifest["entries"][number]): LiveCoachReviewStatus {
  if (entry.approved) return "approved";
  const saved = progress.entries[entryID(entry)];
  return saved?.sha256 === entry.sha256 && saved.status === "rejected" ? "rejected" : "unreviewed";
}

function currentRejectionReason(entry: AudioPackManifest["entries"][number]) {
  const saved = progress.entries[entryID(entry)];
  if (saved?.sha256 !== entry.sha256 || saved.status !== "rejected") return undefined;
  return normalizeLiveCoachRejectionReason(saved.rejectionReason) ?? undefined;
}

function reconcileProgress(): void {
  const currentIDs = new Set<string>();
  for (const entry of manifest.entries) {
    const id = entryID(entry);
    currentIDs.add(id);
    const saved = progress.entries[id];
    if (!saved || saved.sha256 !== entry.sha256) {
      progress.entries[id] = { sha256: entry.sha256, status: entry.approved ? "approved" : "unreviewed" };
    } else if (entry.approved) {
      saved.status = "approved";
    }
  }
  for (const id of Object.keys(progress.entries)) if (!currentIDs.has(id)) delete progress.entries[id];
}

function entryID(entry: AudioPackManifest["entries"][number]): string { return liveCoachReviewEntryID(entry); }

async function loadProgress(): Promise<LiveCoachReviewProgress> {
  try {
    const parsed = parseLiveCoachReviewProgress(
      JSON.parse(await readFile(progressPath, "utf8")),
      manifest.catalogVersion
    );
    if (parsed) return parsed;
  } catch {}
  return { contractVersion: 1, catalogVersion: manifest.catalogVersion, entries: {} };
}

async function persistReview(): Promise<void> {
  manifest = audioPackManifestSchema.parse(manifest);
  await atomicJSONWrite(manifestPath, manifest);
  await atomicJSONWrite(progressPath, progress);
}

async function atomicJSONWrite(filePath: string, value: unknown): Promise<void> {
  const temporaryPath = `${filePath}.review-tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await rename(temporaryPath, filePath);
}

function parseArgs(values: string[]): { reviewManifest?: string; port: number } {
  const result: { reviewManifest?: string; port: number } = { port: 4173 };
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] === "--review-manifest") result.reviewManifest = requiredValue(values, ++index, "--review-manifest");
    else if (values[index] === "--port") {
      const port = Number(requiredValue(values, ++index, "--port"));
      if (!Number.isInteger(port) || port < 1024 || port > 65_535) throw new Error("--port must be an integer from 1024 through 65535.");
      result.port = port;
    } else throw new Error(`Unknown argument: ${values[index]}.`);
  }
  return result;
}

function requiredValue(values: string[], index: number, flag: string): string {
  const value = values[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value.`);
  return value;
}

function isReviewStatus(value: unknown): value is LiveCoachReviewStatus {
  return value === "unreviewed" || value === "approved" || value === "rejected";
}

async function readBody(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  let byteCount = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteCount += buffer.byteLength;
    if (byteCount > 16 * 1024) throw new Error("Request body is too large.");
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function addSecurityHeaders(response: ServerResponse): void {
  response.setHeader("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; media-src 'self'; connect-src 'self'");
  response.setHeader("Cache-Control", "no-store");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("Referrer-Policy", "no-referrer");
}

function sendJSON(response: ServerResponse, status: number, value: unknown): void {
  send(response, status, "application/json; charset=utf-8", `${JSON.stringify(value)}\n`);
}

function send(response: ServerResponse, status: number, contentType: string, body: string | Buffer): void {
  response.statusCode = status;
  response.setHeader("Content-Type", contentType);
  response.end(body);
}

const reviewPage = String.raw`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Plainstride voice review</title>
  <style>
    :root { color-scheme: dark; font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #111512; color: #f4f6f1; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; background: radial-gradient(circle at top, #263127 0, #111512 48%); }
    main { width: min(980px, calc(100% - 32px)); margin: 0 auto; padding: 34px 0 60px; }
    header { display: flex; justify-content: space-between; gap: 20px; align-items: end; margin-bottom: 22px; }
    h1 { margin: 0; font-size: clamp(28px, 5vw, 44px); letter-spacing: -0.04em; }
    .eyebrow { color: #adc4ac; text-transform: uppercase; letter-spacing: .14em; font-size: 12px; font-weight: 700; }
    .summary { color: #c7d0c4; text-align: right; line-height: 1.5; }
    .toolbar, .card { border: 1px solid #344037; background: rgba(24, 30, 25, .94); box-shadow: 0 22px 70px rgba(0,0,0,.28); }
    .toolbar { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; border-radius: 18px; padding: 14px; margin-bottom: 14px; }
    label { display: grid; gap: 6px; color: #aeb9ab; font-size: 12px; font-weight: 700; }
    select { width: 100%; border: 1px solid #46534a; border-radius: 10px; padding: 10px; background: #101411; color: #f4f6f1; font: inherit; }
    .card { border-radius: 24px; overflow: hidden; }
    .card-head { display: flex; justify-content: space-between; gap: 20px; padding: 24px 26px; border-bottom: 1px solid #344037; }
    .cue { font-size: 24px; font-weight: 750; letter-spacing: -.02em; }
    .meta { color: #9faa9d; margin-top: 7px; }
    .status { align-self: start; border-radius: 999px; padding: 7px 11px; font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: .08em; }
    .status.unreviewed { background: #343a35; color: #d1d7cf; }
    .status.approved { background: #1f5b3b; color: #bdf1ce; }
    .status.rejected { background: #6a2928; color: #ffd0ca; }
    .content { padding: 30px 26px; }
    .transcript { font-size: clamp(24px, 4vw, 37px); line-height: 1.25; letter-spacing: -.025em; min-height: 96px; margin-bottom: 26px; }
    audio { width: 100%; margin-bottom: 16px; }
    .listen-note { color: #d2b883; min-height: 24px; }
    .rejection-fields { display: grid; grid-template-columns: .8fr 1.2fr; gap: 12px; margin-top: 14px; }
    textarea { width: 100%; min-height: 72px; resize: vertical; border: 1px solid #46534a; border-radius: 10px; padding: 10px; background: #101411; color: #f4f6f1; font: inherit; }
    .actions { display: grid; grid-template-columns: 1fr 1.4fr 1.4fr 1fr; gap: 10px; margin-top: 18px; }
    button { border: 1px solid #4a574e; border-radius: 12px; padding: 13px 14px; background: #252c27; color: #f4f6f1; font: inherit; font-weight: 750; cursor: pointer; }
    button:hover:not(:disabled) { filter: brightness(1.15); }
    button:disabled { opacity: .34; cursor: not-allowed; }
    #approve { background: #2e744d; border-color: #4c9a6d; }
    #reject { background: #793936; border-color: #a95751; }
    .footer { display: flex; justify-content: space-between; gap: 20px; align-items: center; padding: 18px 26px; border-top: 1px solid #344037; color: #aeb9ab; font-size: 13px; }
    .footer label { display: flex; align-items: center; gap: 8px; }
    kbd { border: 1px solid #526057; border-bottom-width: 2px; border-radius: 5px; padding: 2px 6px; color: #dce4da; }
    .empty { padding: 50px; text-align: center; color: #b8c2b5; }
    @media (max-width: 700px) { header { align-items: start; flex-direction: column; } .summary { text-align: left; } .toolbar, .rejection-fields { grid-template-columns: 1fr; } .actions { grid-template-columns: 1fr 1fr; } .footer { align-items: start; flex-direction: column; } }
  </style>
</head>
<body>
<main>
  <header><div><div class="eyebrow">Fixed audio pack</div><h1>Voice review</h1></div><div id="summary" class="summary">Loading…</div></header>
  <section class="toolbar">
    <label>Status<select id="status-filter"><option value="unreviewed">Unreviewed</option><option value="rejected">Rejected</option><option value="approved">Approved</option><option value="all">All</option></select></label>
    <label>Language<select id="locale-filter"><option value="all">All languages</option></select></label>
    <label>Voice<select id="voice-filter"><option value="all">All voices</option></select></label>
  </section>
  <section id="card" class="card">
    <div class="card-head"><div><div id="cue" class="cue"></div><div id="meta" class="meta"></div></div><div id="status" class="status unreviewed"></div></div>
    <div class="content"><div id="transcript" class="transcript"></div><audio id="audio" controls preload="metadata"></audio><div id="listen-note" class="listen-note"></div><div class="rejection-fields"><label>Reason if rejected<select id="rejection-reason"><option value="">Select a reason…</option><option value="pronunciation">Pronunciation</option><option value="too_fast">Too fast</option><option value="too_slow">Too slow</option><option value="unnatural_pacing">Unnatural pacing or pauses</option><option value="wrong_tone">Wrong tone</option><option value="wrong_emphasis">Wrong emphasis</option><option value="audio_artifact">Audio artifact or clipping</option><option value="transcript_mismatch">Spoken words do not match</option><option value="other">Other</option></select></label><label>Detail for regeneration<textarea id="rejection-detail" maxlength="500" placeholder="Optional except for Other. Note the word, sound, tone, pause, or artifact to correct."></textarea></label></div><div class="actions"><button id="previous">← Previous</button><button id="reject" disabled>Reject · R</button><button id="approve" disabled>Approve · A</button><button id="next">Next →</button></div></div>
    <div class="footer"><span><kbd>Space</kbd> play · <kbd>A</kbd> approve · <kbd>R</kbd> reject · <kbd>←</kbd><kbd>→</kbd> navigate</span><label><input id="autoplay" type="checkbox" checked> Autoplay next clip</label></div>
  </section>
</main>
<script>
  const elements = Object.fromEntries(["summary","card","cue","meta","status","transcript","audio","listen-note","rejection-reason","rejection-detail","previous","reject","approve","next","status-filter","locale-filter","voice-filter","autoplay"].map(function (id) { return [id, document.getElementById(id)]; }));
  let entries = [];
  let filtered = [];
  let cursor = 0;
  let listened = false;

  fetch("/api/reviews").then(function (response) { return response.json(); }).then(function (state) {
    entries = state.entries;
    fillFilter(elements["locale-filter"], unique(entries.map(function (entry) { return entry.locale; })));
    fillFilter(elements["voice-filter"], unique(entries.map(function (entry) { return entry.voiceProfileId; })));
    applyFilters();
  }).catch(function (error) { elements.card.innerHTML = '<div class="empty">' + error.message + '</div>'; });

  function unique(values) { return Array.from(new Set(values)).sort(); }
  function fillFilter(select, values) { values.forEach(function (value) { const option = document.createElement("option"); option.value = value; option.textContent = value; select.appendChild(option); }); }
  function applyFilters(preferredIndex) {
    filtered = entries.filter(function (entry) {
      return (elements["status-filter"].value === "all" || entry.status === elements["status-filter"].value)
        && (elements["locale-filter"].value === "all" || entry.locale === elements["locale-filter"].value)
        && (elements["voice-filter"].value === "all" || entry.voiceProfileId === elements["voice-filter"].value);
    });
    cursor = Math.max(0, preferredIndex === undefined ? 0 : filtered.findIndex(function (entry) { return entry.index === preferredIndex; }));
    render();
  }
  function render(autoplay) {
    const counts = { approved: 0, rejected: 0, unreviewed: 0 };
    entries.forEach(function (entry) { counts[entry.status] += 1; });
    const missingReasons = entries.filter(function (entry) { return entry.status === "rejected" && !entry.rejectionReason; }).length;
    elements.summary.textContent = counts.approved + " approved · " + counts.rejected + " rejected" + (missingReasons ? " (" + missingReasons + " need reasons)" : "") + " · " + counts.unreviewed + " remaining";
    if (!filtered.length) { elements.card.style.display = "none"; return; }
    elements.card.style.display = "block";
    const entry = filtered[cursor];
    listened = entry.status === "rejected";
    elements.cue.textContent = entry.cueKey;
    elements.meta.textContent = entry.locale + " · " + entry.voiceProfileId + " · " + (entry.durationMilliseconds / 1000).toFixed(2) + "s · " + (cursor + 1) + "/" + filtered.length;
    elements.status.textContent = entry.status;
    elements.status.className = "status " + entry.status;
    elements.transcript.textContent = entry.transcript;
    elements["rejection-reason"].value = entry.rejectionReason ? entry.rejectionReason.code : "";
    elements["rejection-detail"].value = entry.rejectionReason && entry.rejectionReason.detail ? entry.rejectionReason.detail : "";
    elements.audio.src = "/audio/" + entry.index + "?sha=" + entry.sha256;
    elements.audio.load();
    elements["listen-note"].textContent = entry.status === "rejected"
      ? (entry.rejectionReason ? "Rejection feedback is saved and will guide regeneration." : "Add the reason this previously reviewed clip was rejected.")
      : "Listen through the complete clip to unlock approve/reject.";
    updateReviewControls();
    elements.previous.disabled = cursor === 0;
    elements.next.disabled = cursor === filtered.length - 1;
    if (autoplay && elements.autoplay.checked) elements.audio.play().catch(function () {});
  }
  function validRejectionReason() { return Boolean(elements["rejection-reason"].value) && (elements["rejection-reason"].value !== "other" || Boolean(elements["rejection-detail"].value.trim())); }
  function updateReviewControls() { elements.approve.disabled = !listened; elements.reject.disabled = !listened || !validRejectionReason(); }
  function move(delta, autoplay) { const next = cursor + delta; if (next >= 0 && next < filtered.length) { cursor = next; render(autoplay); } }
  async function review(status) {
    if (!listened || !filtered.length || (status === "rejected" && !validRejectionReason())) return;
    const entry = filtered[cursor];
    const rejectionReason = status === "rejected" ? { code: elements["rejection-reason"].value, detail: elements["rejection-detail"].value.trim() } : undefined;
    const response = await fetch("/api/reviews/" + entry.index, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sha256: entry.sha256, status: status, listened: true, rejectionReason: rejectionReason }) });
    const state = await response.json();
    if (!response.ok) { elements["listen-note"].textContent = state.error || "Review update failed."; return; }
    entries = state.entries;
    const nextEntry = filtered[cursor + 1] || filtered[cursor - 1];
    applyFilters(nextEntry && nextEntry.index);
    if (filtered.length && elements.autoplay.checked) elements.audio.play().catch(function () {});
  }
  elements.audio.addEventListener("ended", function () { listened = true; updateReviewControls(); elements["listen-note"].textContent = "Playback complete. Approve, or select a reason and reject this exact recording."; });
  elements.previous.addEventListener("click", function () { move(-1, false); });
  elements.next.addEventListener("click", function () { move(1, false); });
  elements.approve.addEventListener("click", function () { review("approved"); });
  elements.reject.addEventListener("click", function () { review("rejected"); });
  elements["rejection-reason"].addEventListener("change", updateReviewControls);
  elements["rejection-detail"].addEventListener("input", updateReviewControls);
  [elements["status-filter"], elements["locale-filter"], elements["voice-filter"]].forEach(function (select) { select.addEventListener("change", function () { applyFilters(); }); });
  document.addEventListener("keydown", function (event) {
    if (event.target && ["SELECT", "INPUT", "TEXTAREA"].includes(event.target.tagName)) return;
    if (event.code === "Space") { event.preventDefault(); if (elements.audio.paused) elements.audio.play(); else elements.audio.pause(); }
    else if (event.key === "a" || event.key === "A") review("approved");
    else if (event.key === "r" || event.key === "R") review("rejected");
    else if (event.key === "ArrowLeft") move(-1, false);
    else if (event.key === "ArrowRight") move(1, false);
  });
</script>
</body>
</html>`;
