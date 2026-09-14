export {};

type Section = "dashboard" | "codes" | "redemptions" | "referrals" | "users" | "audit";
type PortalPage = "home" | "controls" | "rewards";
type SessionResponse = { accessToken: string; refreshToken: string; user: { displayName: string | null; email: string | null } };
type Admin = { id: string; email: string; displayName: string | null };
type FeatureControls = { paywallEnabled: boolean };
type Page<T> = { items: T[]; total: number; limit: number; offset: number };
type CodeItem = { id: string; label: string; bundle: string; durationDays: number; maxRedemptions: number; redemptionCount: number; status: string; expiresAt: string | null; createdAt: string; updatedAt: string };
type UserItem = { id: string; username: string; displayName: string | null; normalizedEmail: string | null; createdAt: string; _count: { featureEntitlements: number; entitlementCodeRedemptions: number } };
type UserDetail = UserItem & {
  featureEntitlements: Array<{ id: string; capability: string; source: string; status: string; startsAt: string; expiresAt: string | null; createdAt: string }>;
  entitlementGrantLedger: Array<{ id: string; capability: string; source: string; durationDays: number | null; startsAt: string; expiresAt: string | null; revokedAt: string | null; createdAt: string }>;
  entitlementCodeRedemptions: Array<{ id: string; createdAt: string; code: { id: string; label: string; durationDays: number } }>;
  referralClaim: { status?: string } | null;
  referralLink: { code: string; claimCount: number } | null;
};
type GoogleCredential = { credential: string; select_by?: string };

declare global {
  interface Window {
    google?: { accounts: { id: {
      initialize(options: { client_id: string; callback: (response: GoogleCredential) => void; auto_select?: boolean; use_fedcm_for_prompt?: boolean }): void;
      renderButton(element: HTMLElement, options: Record<string, string | number | boolean>): void;
      disableAutoSelect(): void;
    } } };
  }
}

class ApiError extends Error {
  constructor(message: string, readonly status: number, readonly code?: string) { super(message); }
}

const root = requiredElement("app");
const toastRegion = requiredElement("toast-region");
const refreshStorageKey = "plainstride.rewardsAdmin.refresh.v1";
const limit = 25;
let accessToken: string | null = null;
let refreshToken: string | null = sessionStorage.getItem(refreshStorageKey);
let refreshPromise: Promise<boolean> | null = null;
let admin: Admin | null = null;
let activePortalPage: PortalPage = portalPageForPath();
let activeSection: Section = requestedRewardSection();
let activeRequest = 0;
const offsets: Record<Section, number> = { dashboard: 0, codes: 0, redemptions: 0, referrals: 0, users: 0, audit: 0 };
const filters: Record<string, string> = { codeQuery: "", codeStatus: "all", redemptionCodeId: "", redemptionUserId: "", referralStatus: "all", userQuery: "", auditActor: "", auditTargetType: "", auditTargetId: "" };

void start();

async function start() {
  if (refreshToken && await refreshSession()) {
    await verifyAdmin();
    return;
  }
  renderSignIn();
}

async function verifyAdmin() {
  try {
    admin = await api<Admin>("/v1/admin/rewards/me");
    renderShell();
    void telemetry({ event: "portal_loaded", section: activePortalPage });
    await navigatePortal(activePortalPage, false);
  } catch (error) {
    clearSession();
    renderSignIn(errorMessage(error));
  }
}

function renderSignIn(message?: string) {
  root.innerHTML = `<main class="auth-page">
    <section class="auth-story" aria-label="Plainstride administration">
      <div class="wordmark"><div class="brand-mark" aria-hidden="true">P</div><span>Plainstride</span></div>
      <div><p class="eyebrow">Plainstride operations</p><h1>One secure place to operate Plainstride.</h1><p>Use focused administration tools without exposing internal controls to the public product.</p></div>
      <div class="trust-row"><span>Verified administrators only</span><span>First-party sessions</span><span>Audited mutations</span></div>
    </section>
    <section class="auth-panel"><div class="auth-card">
      <p class="eyebrow">Secure access</p><h2>Administrator sign in</h2>
      <p>Use an approved, verified Google account. Access is checked again by the Plainstride backend after sign-in.</p>
      <div id="google-slot" class="google-slot"><div class="spinner" aria-label="Loading Google sign-in"></div></div>
      ${message ? `<div class="auth-error" role="alert">${h(message)}</div>` : ""}
      <div class="auth-note"><span aria-hidden="true">⌁</span><span>Your Google credential is exchanged for a first-party Plainstride session. This portal never contains a shared administrator token.</span></div>
    </div></section>
  </main>`;
  void configureGoogleSignIn();
}

async function configureGoogleSignIn() {
  const slot = document.getElementById("google-slot");
  if (!slot) return;
  try {
    const config = await publicJson<{ configured: boolean; googleClientId: string | null }>("/admin/config");
    if (!config.configured || !config.googleClientId) throw new Error("Google sign-in is not configured for this portal.");
    await loadGoogleIdentity();
    if (!window.google) throw new Error("Google sign-in could not be loaded.");
    slot.innerHTML = "";
    window.google.accounts.id.initialize({
      client_id: config.googleClientId,
      callback: (response) => void exchangeGoogleCredential(response),
      auto_select: false,
      use_fedcm_for_prompt: true,
    });
    window.google.accounts.id.renderButton(slot, { type: "standard", theme: "outline", size: "large", shape: "pill", text: "signin_with", width: Math.min(400, slot.clientWidth || 400) });
  } catch (error) {
    slot.innerHTML = `<div class="auth-error" role="alert">${h(errorMessage(error))}</div><button id="retry-google" class="retry-link">Try again</button>`;
    document.getElementById("retry-google")?.addEventListener("click", () => void configureGoogleSignIn());
  }
}

async function loadGoogleIdentity() {
  if (window.google) return;
  const existing = document.querySelector<HTMLScriptElement>('script[data-google-identity="true"]');
  if (existing) return new Promise<void>((resolve, reject) => {
    existing.addEventListener("load", () => resolve(), { once: true });
    existing.addEventListener("error", () => reject(new Error("Google sign-in could not be loaded.")), { once: true });
  });
  await new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://accounts.google.com/gsi/client";
    script.async = true;
    script.dataset.googleIdentity = "true";
    script.onload = () => resolve();
    script.onerror = () => { script.remove(); reject(new Error("Google sign-in could not be loaded.")); };
    document.head.append(script);
  });
}

async function exchangeGoogleCredential(response: GoogleCredential) {
  const slot = document.getElementById("google-slot");
  if (slot) slot.innerHTML = '<div class="spinner" aria-label="Verifying administrator"></div>';
  try {
    const session = await publicJson<SessionResponse>("/v1/auth/google", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identityToken: response.credential, platform: "web", deviceLabel: "Plainstride administration portal", termsVersion: 2 }),
    });
    setSession(session);
    await verifyAdmin();
  } catch (error) {
    clearSession();
    renderSignIn(errorMessage(error));
  }
}

function renderShell() {
  const name = admin?.displayName?.trim() || "Administrator";
  root.innerHTML = `<div class="app-shell">
    <aside class="sidebar">
      <div class="wordmark"><div class="brand-mark" aria-hidden="true">P</div><span>Plainstride</span></div>
      <nav class="nav" aria-label="Administration">
        ${portalNavButton("home", "⌂", "Overview")}${portalNavButton("controls", "◉", "Feature controls")}${portalNavButton("rewards", "◇", "Rewards")}
      </nav>
      <div class="admin-profile"><div class="admin-name">${h(name)}</div><div class="admin-email">${h(admin?.email || "")}</div><button id="sign-out" class="signout">Sign out</button></div>
    </aside>
    <main id="page" class="main" tabindex="-1"></main>
  </div>`;
  root.querySelectorAll<HTMLButtonElement>("[data-portal-page]").forEach((button) => button.addEventListener("click", () => void navigatePortal(button.dataset.portalPage as PortalPage)));
  document.getElementById("sign-out")?.addEventListener("click", () => void signOut());
  window.addEventListener("popstate", handlePopState, { once: true });
}

function portalNavButton(portalPage: PortalPage, icon: string, label: string) {
  return `<button data-portal-page="${portalPage}" class="${portalPage === activePortalPage ? "active" : ""}"><span class="nav-icon" aria-hidden="true">${icon}</span>${label}</button>`;
}

async function navigatePortal(portalPage: PortalPage, updateHistory = true) {
  activePortalPage = portalPage;
  root.querySelectorAll<HTMLButtonElement>("[data-portal-page]").forEach((button) => button.classList.toggle("active", button.dataset.portalPage === portalPage));
  if (updateHistory) history.pushState({}, "", portalUrl(portalPage));
  void telemetry({ event: "section_viewed", section: portalPage });
  if (portalPage === "home") {
    renderPortalHome();
    return;
  }
  if (portalPage === "controls") {
    const page = requiredElement("page");
    page.innerHTML = loadingState("Fetching current feature controls.");
    page.focus({ preventScroll: true });
    const requestId = ++activeRequest;
    try {
      await renderFeatureControls(page);
    } catch (error) {
      if (requestId === activeRequest) renderPortalPageError(page, error, portalPage);
    }
    return;
  }
  await navigate(activeSection, false);
}

function renderPortalHome() {
  const page = requiredElement("page");
  page.innerHTML = `<header class="page-head"><div><p class="eyebrow">Plainstride administration</p><h1>Overview</h1><p>Choose an operational area to manage.</p></div></header>
    <section class="portal-grid"><button class="portal-card" id="open-controls"><span class="portal-card-icon" aria-hidden="true">◉</span><span><strong>Feature controls</strong><small>Manage server-authoritative product rollout and access controls.</small></span><span class="portal-card-arrow" aria-hidden="true">→</span></button><button class="portal-card" id="open-rewards"><span class="portal-card-icon" aria-hidden="true">◇</span><span><strong>Rewards</strong><small>Manage Plus access, contribution codes, referrals, users, and audit history.</small></span><span class="portal-card-arrow" aria-hidden="true">→</span></button></section>`;
  document.getElementById("open-controls")?.addEventListener("click", () => void navigatePortal("controls"));
  document.getElementById("open-rewards")?.addEventListener("click", () => void navigatePortal("rewards"));
}

function handlePopState() {
  activePortalPage = portalPageForPath();
  const requestedSection = new URLSearchParams(window.location.search).get("section");
  if (isSection(requestedSection)) activeSection = requestedSection;
  void navigatePortal(activePortalPage, false);
  window.addEventListener("popstate", handlePopState, { once: true });
}

function portalPageForPath(): PortalPage {
  if (window.location.pathname === "/admin/feature-controls") return "controls";
  if (window.location.pathname === "/admin/rewards") return "rewards";
  return "home";
}

function portalUrl(portalPage: PortalPage) {
  if (portalPage === "controls") return "/admin/feature-controls";
  if (portalPage === "rewards") return rewardUrl(activeSection);
  return "/admin";
}

function rewardUrl(section: Section) {
  return section === "dashboard" ? "/admin/rewards" : `/admin/rewards?section=${encodeURIComponent(section)}`;
}

function isSection(value: string | null): value is Section {
  return Boolean(value && ["dashboard", "codes", "redemptions", "referrals", "users", "audit"].includes(value));
}

function requestedRewardSection(): Section {
  const value = new URLSearchParams(window.location.search).get("section");
  return isSection(value) ? value : "dashboard";
}

function rewardNavButton(section: Section, label: string) {
  return `<button data-section="${section}" class="${section === activeSection ? "active" : ""}">${label}</button>`;
}

async function navigate(section: Section, updateHistory = true) {
  activePortalPage = "rewards";
  activeSection = section;
  root.querySelectorAll<HTMLButtonElement>("[data-portal-page]").forEach((button) => button.classList.toggle("active", button.dataset.portalPage === "rewards"));
  if (updateHistory) history.pushState({}, "", rewardUrl(section));
  const page = requiredElement("page");
  page.innerHTML = `<header class="workspace-head"><div><p class="eyebrow">Administration</p><h1>Rewards</h1><p>Plus access, contribution programs, and their audit trail.</p></div></header><nav class="subnav" aria-label="Rewards tools">${rewardNavButton("dashboard", "Overview")}${rewardNavButton("codes", "Codes")}${rewardNavButton("redemptions", "Redemptions")}${rewardNavButton("referrals", "Referrals")}${rewardNavButton("users", "Users")}${rewardNavButton("audit", "Audit")}</nav><section id="reward-page">${loadingState()}</section>`;
  page.querySelectorAll<HTMLButtonElement>("[data-section]").forEach((button) => button.addEventListener("click", () => void navigate(button.dataset.section as Section)));
  const rewardPage = requiredElement("reward-page");
  rewardPage.focus({ preventScroll: true });
  const requestId = ++activeRequest;
  void telemetry({ event: "section_viewed", section });
  try {
    if (section === "dashboard") await renderDashboard(rewardPage);
    if (section === "codes") await renderCodes(rewardPage);
    if (section === "redemptions") await renderRedemptions(rewardPage);
    if (section === "referrals") await renderReferrals(rewardPage);
    if (section === "users") await renderUsers(rewardPage);
    if (section === "audit") await renderAudit(rewardPage);
  } catch (error) {
    if (requestId === activeRequest) renderPageError(rewardPage, error, section);
  }
}

async function renderDashboard(page: HTMLElement) {
  const summary = await api<Record<string, number>>("/v1/admin/rewards/summary");
  if (activeSection !== "dashboard") return;
  page.innerHTML = `<header class="page-head"><div><p class="eyebrow">Rewards operations</p><h1>Overview</h1><p>A current view of access, participation, and reward activity.</p></div><div class="page-actions"><button class="button primary" id="quick-issue">Issue a code</button></div></header>
    <section class="metrics" aria-label="Reward summary">
      ${metric("Active codes", summary.activeCodes, "Available for redemption")}${metric("Redemptions", summary.totalRedemptions, "All contribution code uses")}${metric("Active entitlements", summary.activeEntitlements, "Capability grants currently effective")}
      ${metric("Pending referrals", summary.pendingReferrals, "Awaiting a qualifying activity")}${metric("Rewarded referrals", summary.rewardedReferrals, "Inviter rewards completed")}${metric("Users", summary.users, "Plainstride accounts")}
    </section>
    <section class="dashboard-grid"><div class="card"><h2>Quick actions</h2><p>Common administrative workflows. Every change requires a reason and is written to the audit history.</p><div class="quick-actions">
      <button class="quick-action" id="dash-controls"><strong>Manage feature controls</strong><span>Review or change Plus paywall enforcement.</span></button>
      <button class="quick-action" id="dash-code"><strong>Issue contribution access</strong><span>Create a bounded, high-entropy redemption code.</span></button>
      <button class="quick-action" id="dash-user"><strong>Find a user</strong><span>Inspect reward state or grant Plus.</span></button>
      <button class="quick-action" id="dash-audit"><strong>Review audit history</strong><span>Trace administrator mutations and reasons.</span></button>
    </div></div><div class="card"><h2>Privacy boundary</h2><p>Operational telemetry contains only bounded page, operation, and success values. It excludes code material, labels, user identifiers, grant references, reasons, and timestamps.</p></div></section>`;
  document.getElementById("quick-issue")?.addEventListener("click", () => openIssueCode());
  document.getElementById("dash-controls")?.addEventListener("click", () => void navigatePortal("controls"));
  document.getElementById("dash-code")?.addEventListener("click", () => openIssueCode());
  document.getElementById("dash-user")?.addEventListener("click", () => void navigate("users"));
  document.getElementById("dash-audit")?.addEventListener("click", () => void navigate("audit"));
}

async function renderFeatureControls(page: HTMLElement) {
  const controls = await api<FeatureControls>("/v1/admin/rewards/feature-controls");
  if (activePortalPage !== "controls") return;
  const enabled = controls.paywallEnabled;
  page.innerHTML = `${pageHeader("Feature controls", "Manage server-authoritative rollout controls for paid capabilities.", "", "Plainstride administration")}
    <section class="control-grid" aria-label="Feature controls">
      <article class="control-card">
        <div class="control-heading"><div><p class="eyebrow">Access enforcement</p><h2>Plus paywall</h2></div><span class="badge ${enabled ? "active" : "revoked"}">${enabled ? "Enabled" : "Disabled"}</span></div>
        <p>${enabled ? "Only users with an effective entitlement receive dynamic AI planning, dynamic live coaching, and original voice cheers." : "All users currently receive Plus capabilities, and clients hide the Plus purchase destination."}</p>
        <div class="warning ${enabled ? "" : "danger-warning"}">${enabled ? "Disabling enforcement grants Plus capabilities to every user and hides purchase entry points." : "Enabling enforcement immediately applies entitlement checks and reveals purchase entry points to users without access."}</div>
        <button class="button ${enabled ? "" : "danger"}" id="change-paywall">${enabled ? "Disable paywall" : "Enable paywall"}</button>
      </article>
      <article class="card"><h2>Audit requirement</h2><p>Every change requires a reason and is recorded in the immutable rewards audit history with the administrator and resulting state.</p><button class="button" id="controls-audit">Review audit history</button></article>
    </section>`;
  document.getElementById("change-paywall")?.addEventListener("click", () => openPaywallChange(enabled));
  document.getElementById("controls-audit")?.addEventListener("click", () => void navigate("audit"));
}

function openPaywallChange(currentlyEnabled: boolean) {
  const enabling = !currentlyEnabled;
  const verb = enabling ? "Enable" : "Disable";
  const confirmation = enabling ? "ENABLE" : "DISABLE";
  openDialog(`<form id="paywall-control-form"><div class="dialog-head"><div><h2>${verb} Plus paywall</h2><p>This changes access enforcement for every Plainstride account.</p></div>${closeButton()}</div><div class="dialog-body"><div class="warning ${enabling ? "danger-warning" : ""}">${enabling ? "Users without an effective entitlement will lose paid capabilities immediately." : "Every user will receive Plus capabilities and purchase entry points will be hidden."}</div>${textAreaField("Reason", "reason", `Why paywall enforcement is being ${enabling ? "enabled" : "disabled"}`, true)}${inputField(`Type “${confirmation}” to confirm`, "confirmation", "", "text", true, "wide", confirmation.length)}</div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button ${enabling ? "danger" : "primary"}">${verb} paywall</button></div></form>`, (dialog) => {
    form("paywall-control-form", dialog)?.addEventListener("submit", async (event) => {
      event.preventDefault();
      const target = event.currentTarget as HTMLFormElement;
      const values = new FormData(target);
      if (values.get("confirmation") !== confirmation) { toast(`Type “${confirmation}” exactly to confirm.`, true); return; }
      setSubmitting(target, true);
      try {
        await api<FeatureControls>("/v1/admin/rewards/feature-controls/paywall", { method: "PUT", body: JSON.stringify({ enabled: enabling, reason: String(values.get("reason")) }) });
        void telemetry({ event: "mutation_result", operation: "paywall_control_update", result: "success" });
        dialog.close();
        toast(`Plus paywall ${enabling ? "enabled" : "disabled"}.`);
        await navigatePortal("controls", false);
      } catch (error) {
        void telemetry({ event: "mutation_result", operation: "paywall_control_update", result: "failure" });
        toast(errorMessage(error), true);
        setSubmitting(target, false);
      }
    });
  });
}

function metric(label: string, value: number, note: string) {
  return `<article class="metric"><div class="metric-label">${h(label)}</div><div class="metric-value">${number(value)}</div><div class="metric-note">${h(note)}</div></article>`;
}

async function renderCodes(page: HTMLElement) {
  const query = params({ limit, offset: offsets.codes, status: filters.codeStatus, query: filters.codeQuery });
  const data = await api<Page<CodeItem>>(`/v1/admin/rewards/codes?${query}`);
  if (activeSection !== "codes") return;
  page.innerHTML = `${pageHeader("Contribution codes", "Issue and manage bounded Plus access.", '<button class="button primary" id="issue-code">Issue code</button>')}
    <form id="code-filter" class="toolbar"><div class="field grow"><label for="code-query">Search labels</label><input id="code-query" name="query" value="${ha(filters.codeQuery)}" maxlength="100" placeholder="Contributor or campaign label"></div><div class="field"><label for="code-status">Status</label><select id="code-status" name="status">${options(["all", "active", "revoked"], filters.codeStatus)}</select></div><button class="button" type="submit">Apply</button></form>
    ${data.items.length ? codeTable(data.items) : emptyState("No codes found", "Issue a contribution code or adjust the current filters.")}${pagination("codes", data)}`;
  document.getElementById("issue-code")?.addEventListener("click", openIssueCode);
  form("code-filter")?.addEventListener("submit", (event) => { event.preventDefault(); const values = new FormData(event.currentTarget as HTMLFormElement); filters.codeQuery = String(values.get("query") || "").trim(); filters.codeStatus = String(values.get("status") || "all"); offsets.codes = 0; void telemetry({ event: "search_performed", section: "codes" }); void navigate("codes"); });
  wirePagination(page, "codes", data);
  page.querySelectorAll<HTMLButtonElement>("[data-edit-code]").forEach((button) => button.addEventListener("click", () => openEditCode(data.items.find((item) => item.id === button.dataset.editCode)!)));
  page.querySelectorAll<HTMLButtonElement>("[data-code-status]").forEach((button) => button.addEventListener("click", () => {
    const item = data.items.find((candidate) => candidate.id === button.dataset.codeId);
    if (item) openCodeStatus(item, button.dataset.codeStatus as "revoke" | "activate");
  }));
}

function codeTable(items: CodeItem[]) {
  return `<div class="table-wrap"><table class="data-table"><thead><tr><th>Label</th><th>Grant</th><th>Usage</th><th>Status</th><th>Expires</th><th>Created</th><th>Actions</th></tr></thead><tbody>${items.map((item) => `<tr>
    <td><span class="primary-cell">${h(item.label)}</span><span class="secondary">${h(shortId(item.id))}</span></td><td>${item.durationDays} days<span class="secondary">${h(item.bundle)}</span></td><td>${number(item.redemptionCount)} / ${number(item.maxRedemptions)}</td><td>${badge(item.status)}</td><td>${date(item.expiresAt)}</td><td>${date(item.createdAt)}</td><td><div class="actions"><button class="button small" data-edit-code="${ha(item.id)}">Edit</button>${item.status === "active" ? `<button class="button small danger" data-code-status="revoke" data-code-id="${ha(item.id)}">Revoke</button>` : `<button class="button small" data-code-status="activate" data-code-id="${ha(item.id)}" ${isExpired(item.expiresAt) ? "disabled title=\"Expired codes cannot be activated\"" : ""}>Reactivate</button>`}</div></td>
  </tr>`).join("")}</tbody></table></div>`;
}

function openIssueCode() {
  openDialog(`<form id="issue-form"><div class="dialog-head"><div><h2>Issue contribution code</h2><p>The redeemable code is displayed once after creation.</p></div>${closeButton()}</div><div class="dialog-body"><div class="warning">Do not place the resulting code in logs, analytics, or support transcripts.</div><div class="dialog-grid">
    ${inputField("Label", "label", "Approved contribution", "text", true, "wide", 100)}${inputField("Plus duration (days)", "durationDays", "90", "number", true, "", undefined, "1", "3650")}${inputField("Maximum redemptions", "maxRedemptions", "1", "number", true, "", undefined, "1", "100000")}${inputField("Expiration", "expiresAt", "", "datetime-local", false, "wide", undefined, minimumFutureLocalDate())}${textAreaField("Reason", "reason", "Why this reward was approved", true, "wide")}
    </div></div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button primary">Issue code</button></div></form>`, (dialog) => {
      form("issue-form", dialog)?.addEventListener("submit", async (event) => {
        event.preventDefault(); const target = event.currentTarget as HTMLFormElement; setSubmitting(target, true);
        const values = new FormData(target); const expires = localDateToIso(String(values.get("expiresAt") || ""));
        try {
          const result = await api<{ code: string; item: CodeItem }>("/v1/admin/rewards/codes", { method: "POST", body: JSON.stringify({ label: String(values.get("label")), durationDays: Number(values.get("durationDays")), maxRedemptions: Number(values.get("maxRedemptions")), expiresAt: expires, reason: String(values.get("reason")) }) });
          void telemetry({ event: "mutation_result", operation: "code_issue", result: "success" }); dialog.close(); showOneTimeCode(result.code); toast("Contribution code issued."); if (activeSection === "codes" || activeSection === "dashboard") void navigate(activeSection);
        } catch (error) { void telemetry({ event: "mutation_result", operation: "code_issue", result: "failure" }); toast(errorMessage(error), true); setSubmitting(target, false); }
      });
    });
}

function openEditCode(item: CodeItem) {
  openDialog(`<form id="edit-code-form"><div class="dialog-head"><div><h2>Edit contribution code</h2><p>${h(item.label)}</p></div>${closeButton()}</div><div class="dialog-body"><div class="dialog-grid">
    ${inputField("Label", "label", item.label, "text", true, "wide", 100)}${inputField("Maximum redemptions", "maxRedemptions", String(item.maxRedemptions), "number", true, "", undefined, String(Math.max(1, item.redemptionCount)), "100000")}${inputField("Expiration", "expiresAt", toLocalDate(item.expiresAt), "datetime-local", false)}${textAreaField("Reason", "reason", "Why this code is being changed", true, "wide")}
    </div></div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button primary">Save changes</button></div></form>`, (dialog) => {
      form("edit-code-form", dialog)?.addEventListener("submit", async (event) => {
        event.preventDefault(); const target = event.currentTarget as HTMLFormElement; setSubmitting(target, true); const values = new FormData(target);
        const label = String(values.get("label")); const maxRedemptions = Number(values.get("maxRedemptions")); const expirationInput = String(values.get("expiresAt") || "");
        const update: { reason: string; label?: string; maxRedemptions?: number; expiresAt?: string | null } = { reason: String(values.get("reason")) };
        if (label !== item.label) update.label = label;
        if (maxRedemptions !== item.maxRedemptions) update.maxRedemptions = maxRedemptions;
        if (expirationInput !== toLocalDate(item.expiresAt)) update.expiresAt = localDateToIso(expirationInput);
        if (Object.keys(update).length === 1) { toast("Change at least one code field.", true); setSubmitting(target, false); return; }
        try { await api(`/v1/admin/rewards/codes/${encodeURIComponent(item.id)}`, { method: "PATCH", body: JSON.stringify(update) }); void telemetry({ event: "mutation_result", operation: "code_update", result: "success" }); dialog.close(); toast("Code details updated."); void navigate("codes"); }
        catch (error) { void telemetry({ event: "mutation_result", operation: "code_update", result: "failure" }); toast(errorMessage(error), true); setSubmitting(target, false); }
      });
    });
}

function openCodeStatus(item: CodeItem, action: "revoke" | "activate") {
  const operation = action === "revoke" ? "code_revoke" : "code_activate";
  const verb = action === "revoke" ? "Revoke" : "Reactivate";
  openDialog(`<form id="code-status-form"><div class="dialog-head"><div><h2>${verb} code</h2><p>${h(item.label)}</p></div>${closeButton()}</div><div class="dialog-body">${action === "revoke" ? '<div class="warning danger-warning">Existing user grants remain active. This only prevents future redemption.</div>' : ""}${textAreaField("Reason", "reason", `Why this code is being ${action === "revoke" ? "revoked" : "reactivated"}`, true)}</div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button ${action === "revoke" ? "danger" : "primary"}">${verb}</button></div></form>`, (dialog) => {
    form("code-status-form", dialog)?.addEventListener("submit", async (event) => {
      event.preventDefault(); const target = event.currentTarget as HTMLFormElement; setSubmitting(target, true); const reason = String(new FormData(target).get("reason"));
      try { await api(`/v1/admin/rewards/codes/${encodeURIComponent(item.id)}/${action}`, { method: "POST", body: JSON.stringify({ reason }) }); void telemetry({ event: "mutation_result", operation, result: "success" }); dialog.close(); toast(`Code ${action === "revoke" ? "revoked" : "reactivated"}.`); void navigate("codes"); }
      catch (error) { void telemetry({ event: "mutation_result", operation, result: "failure" }); toast(errorMessage(error), true); setSubmitting(target, false); }
    });
  });
}

function showOneTimeCode(code: string) {
  openDialog(`<div class="dialog-head"><div><h2>Copy this code now</h2><p>Plainstride cannot display it again.</p></div></div><div class="dialog-body"><div class="warning">Store or deliver this code through an approved secure channel. Closing this window permanently removes it from the portal.</div><code class="one-time-code" id="issued-code">${h(code)}</code></div><div class="dialog-actions"><button class="button" id="copy-code">Copy code</button><button class="button primary" data-close-dialog>I have stored it</button></div>`, (dialog) => {
    document.getElementById("copy-code")?.addEventListener("click", async () => { try { await navigator.clipboard.writeText(code); toast("Code copied."); } catch { toast("Copy failed. Select the code and copy it manually.", true); } });
    dialog.addEventListener("cancel", (event) => { event.preventDefault(); });
  }, false);
}

async function renderRedemptions(page: HTMLElement) {
  const data = await api<Page<Record<string, any>>>(`/v1/admin/rewards/redemptions?${params({ limit, offset: offsets.redemptions, codeId: filters.redemptionCodeId, userId: filters.redemptionUserId })}`);
  if (activeSection !== "redemptions") return;
  page.innerHTML = `${pageHeader("Redemptions", "Inspect contribution code usage without exposing code material.")}${dualIdFilter("redemption-filter", "Code ID", "codeId", filters.redemptionCodeId, "User ID", "userId", filters.redemptionUserId)}${data.items.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Code</th><th>User</th><th>Email</th><th>Redeemed</th><th>Record</th></tr></thead><tbody>${data.items.map((item) => `<tr><td><span class="primary-cell">${h(item.code.label)}</span><span class="secondary">${item.code.durationDays} days</span></td><td>${h(item.user.displayName || item.user.username)}<span class="secondary">${h(item.user.username)}</span></td><td>${h(item.user.normalizedEmail || "—")}</td><td>${date(item.createdAt)}</td><td>${h(shortId(item.id))}</td></tr>`).join("")}</tbody></table></div>` : emptyState("No redemptions found", "No code usage matches these filters.")}${pagination("redemptions", data)}`;
  form("redemption-filter")?.addEventListener("submit", (event) => { event.preventDefault(); const values = new FormData(event.currentTarget as HTMLFormElement); filters.redemptionCodeId = String(values.get("codeId") || "").trim(); filters.redemptionUserId = String(values.get("userId") || "").trim(); offsets.redemptions = 0; void telemetry({ event: "search_performed", section: "redemptions" }); void navigate("redemptions"); });
  wirePagination(page, "redemptions", data);
}

async function renderReferrals(page: HTMLElement) {
  const data = await api<Page<Record<string, any>>>(`/v1/admin/rewards/referrals?${params({ limit, offset: offsets.referrals, status: filters.referralStatus })}`);
  if (activeSection !== "referrals") return;
  page.innerHTML = `${pageHeader("Referrals", "Track claimed invitations and qualified inviter rewards.")}<form id="referral-filter" class="toolbar"><div class="field"><label for="referral-status">Status</label><select id="referral-status" name="status">${options(["all", "claimed", "rewarded"], filters.referralStatus)}</select></div><button class="button" type="submit">Apply</button></form>
    ${data.items.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Invitee</th><th>Inviter</th><th>Status</th><th>Reward</th><th>Claimed</th><th>Qualified</th><th>Rewarded</th></tr></thead><tbody>${data.items.map((item) => `<tr><td>${person(item.claimant)}</td><td>${person(item.referralLink.creator)}</td><td>${badge(item.status)}</td><td>${number(item.rewardDays)} days</td><td>${date(item.claimedAt)}</td><td>${date(item.qualifiedAt)}</td><td>${date(item.rewardedAt)}</td></tr>`).join("")}</tbody></table></div>` : emptyState("No referrals found", "No invitation claims match this status.")}${pagination("referrals", data)}`;
  form("referral-filter")?.addEventListener("submit", (event) => { event.preventDefault(); filters.referralStatus = String(new FormData(event.currentTarget as HTMLFormElement).get("status") || "all"); offsets.referrals = 0; void navigate("referrals"); }); wirePagination(page, "referrals", data);
}

async function renderUsers(page: HTMLElement) {
  const data = await api<Page<UserItem>>(`/v1/admin/rewards/users?${params({ limit, offset: offsets.users, query: filters.userQuery })}`);
  if (activeSection !== "users") return;
  page.innerHTML = `${pageHeader("Users", "Find an account, inspect reward state, or administer Plus access.")}<form id="user-filter" class="toolbar"><div class="field grow"><label for="user-query">Search users</label><input id="user-query" name="query" value="${ha(filters.userQuery)}" maxlength="100" placeholder="Username, display name, or email"></div><button class="button" type="submit">Search</button></form>
    ${data.items.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>User</th><th>Email</th><th>Entitlements</th><th>Redemptions</th><th>Joined</th><th></th></tr></thead><tbody>${data.items.map((item) => `<tr><td>${person(item)}</td><td>${h(item.normalizedEmail || "—")}</td><td>${number(item._count.featureEntitlements)}</td><td>${number(item._count.entitlementCodeRedemptions)}</td><td>${date(item.createdAt)}</td><td><button class="button small" data-view-user="${ha(item.id)}">View details</button></td></tr>`).join("")}</tbody></table></div>` : emptyState(filters.userQuery ? "No users found" : "No users yet", filters.userQuery ? "Try a broader username, name, or email search." : "Accounts will appear here after signup.")}${pagination("users", data)}`;
  form("user-filter")?.addEventListener("submit", (event) => { event.preventDefault(); filters.userQuery = String(new FormData(event.currentTarget as HTMLFormElement).get("query") || "").trim(); offsets.users = 0; void telemetry({ event: "search_performed", section: "users" }); void navigate("users"); }); wirePagination(page, "users", data);
  page.querySelectorAll<HTMLButtonElement>("[data-view-user]").forEach((button) => button.addEventListener("click", () => void openUserDetail(button.dataset.viewUser!)));
}

async function openUserDetail(userId: string) {
  const dialog = openDialog(`<div class="dialog-head"><div><h2>User details</h2><p>Loading reward state…</p></div>${closeButton()}</div><div class="dialog-body">${loadingState()}</div>`, undefined, true);
  try {
    const user = await api<UserDetail>(`/v1/admin/rewards/users/${encodeURIComponent(userId)}`);
    dialog.innerHTML = `<div class="dialog-head"><div><h2>${h(user.displayName || user.username)}</h2><p>${h(user.normalizedEmail || user.username)}</p></div>${closeButton()}</div><div class="dialog-body">
      <div class="detail-summary"><div class="detail-stat"><span>Username</span><strong>${h(user.username)}</strong></div><div class="detail-stat"><span>Personal invitation</span><strong>${h(user.referralLink?.code || "None")}</strong></div><div class="detail-stat"><span>Invitation claims</span><strong>${number(user.referralLink?.claimCount || 0)}</strong></div></div>
      <button class="button primary" id="grant-user">Grant Plus</button><h3 class="section-title">Effective entitlements</h3>
      <div class="entitlement-list">${user.featureEntitlements.length ? user.featureEntitlements.map((item) => `<div class="entitlement"><div class="entitlement-meta"><strong>${h(capabilityName(item.capability))}</strong><span class="secondary">${badge(item.status)} · ${h(item.source)} · ${item.expiresAt ? `ends ${date(item.expiresAt)}` : "permanent"}</span></div>${item.status === "active" ? `<button class="button small danger" data-revoke-entitlement="${ha(item.id)}">Revoke</button>` : ""}</div>`).join("") : '<p class="secondary">No effective entitlement records.</p>'}</div>
      <h3 class="section-title">Grant ledger</h3>${user.entitlementGrantLedger.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Capability</th><th>Source</th><th>Duration</th><th>Created</th><th>Revoked</th></tr></thead><tbody>${user.entitlementGrantLedger.map((item) => `<tr><td>${h(capabilityName(item.capability))}</td><td>${h(item.source)}</td><td>${item.durationDays == null ? "Permanent" : `${item.durationDays} days`}</td><td>${date(item.createdAt)}</td><td>${date(item.revokedAt)}</td></tr>`).join("")}</tbody></table></div>` : '<p class="secondary">No grants recorded.</p>'}
      <h3 class="section-title">Code redemptions</h3>${user.entitlementCodeRedemptions.length ? user.entitlementCodeRedemptions.map((item) => `<div class="entitlement"><div class="entitlement-meta"><strong>${h(item.code.label)}</strong><span class="secondary">${item.code.durationDays} days · ${date(item.createdAt)}</span></div></div>`).join("") : '<p class="secondary">No code redemptions.</p>'}
    </div>`;
    wireDialogClose(dialog);
    document.getElementById("grant-user")?.addEventListener("click", () => { dialog.close(); openGrant(user); });
    dialog.querySelectorAll<HTMLButtonElement>("[data-revoke-entitlement]").forEach((button) => button.addEventListener("click", () => { dialog.close(); openEntitlementRevoke(user, button.dataset.revokeEntitlement!); }));
  } catch (error) { dialog.querySelector<HTMLElement>(".dialog-body")!.innerHTML = errorState(errorMessage(error)); }
}

function openGrant(user: UserDetail) {
  openDialog(`<form id="grant-form"><div class="dialog-head"><div><h2>Grant Plus</h2><p>${h(user.displayName || user.username)}</p></div>${closeButton()}</div><div class="dialog-body"><div class="dialog-grid"><div class="field wide"><label for="grant-kind">Grant duration</label><select id="grant-kind" name="kind"><option value="bounded">Bounded duration</option><option value="permanent">Permanent</option></select></div>${inputField("Duration (days)", "durationDays", "30", "number", true, "wide", undefined, "1", "3650")}${textAreaField("Reason", "reason", "Why this Plus access is being granted", true, "wide")}</div></div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button primary">Grant Plus</button></div></form>`, (dialog) => {
    const kind = dialog.querySelector<HTMLSelectElement>("[name=kind]")!; const duration = dialog.querySelector<HTMLInputElement>("[name=durationDays]")!;
    kind.addEventListener("change", () => { duration.disabled = kind.value === "permanent"; duration.required = kind.value !== "permanent"; });
    form("grant-form", dialog)?.addEventListener("submit", async (event) => { event.preventDefault(); const target = event.currentTarget as HTMLFormElement; setSubmitting(target, true); const values = new FormData(target); const days = String(values.get("kind")) === "permanent" ? null : Number(values.get("durationDays"));
      try { await api(`/v1/admin/rewards/users/${encodeURIComponent(user.id)}/grants`, { method: "POST", body: JSON.stringify({ durationDays: days, reason: String(values.get("reason")) }) }); void telemetry({ event: "mutation_result", operation: "plus_grant", result: "success" }); dialog.close(); toast("Plus access granted."); void openUserDetail(user.id); }
      catch (error) { void telemetry({ event: "mutation_result", operation: "plus_grant", result: "failure" }); toast(errorMessage(error), true); setSubmitting(target, false); }
    });
  });
}

function openEntitlementRevoke(user: UserDetail, entitlementId: string) {
  const entitlement = user.featureEntitlements.find((item) => item.id === entitlementId);
  openDialog(`<form id="revoke-entitlement-form"><div class="dialog-head"><div><h2>Revoke entitlement</h2><p>${h(entitlement ? capabilityName(entitlement.capability) : "Plus capability")}</p></div>${closeButton()}</div><div class="dialog-body"><div class="warning danger-warning">This takes effect immediately. If the grant has linked ledger records, they will also be marked revoked.</div>${textAreaField("Reason", "reason", "Why this entitlement must be revoked", true)}${inputField('Type “REVOKE” to confirm', "confirmation", "", "text", true, "wide", 6)}</div><div class="dialog-actions"><button type="button" class="button" data-close-dialog>Cancel</button><button type="submit" class="button danger">Revoke entitlement</button></div></form>`, (dialog) => {
    form("revoke-entitlement-form", dialog)?.addEventListener("submit", async (event) => { event.preventDefault(); const target = event.currentTarget as HTMLFormElement; const values = new FormData(target); if (values.get("confirmation") !== "REVOKE") { toast('Type “REVOKE” exactly to confirm.', true); return; } setSubmitting(target, true);
      try { await api(`/v1/admin/rewards/users/${encodeURIComponent(user.id)}/entitlements/${encodeURIComponent(entitlementId)}/revoke`, { method: "POST", body: JSON.stringify({ reason: String(values.get("reason")) }) }); void telemetry({ event: "mutation_result", operation: "entitlement_revoke", result: "success" }); dialog.close(); toast("Entitlement revoked."); void openUserDetail(user.id); }
      catch (error) { void telemetry({ event: "mutation_result", operation: "entitlement_revoke", result: "failure" }); toast(errorMessage(error), true); setSubmitting(target, false); }
    });
  });
}

async function renderAudit(page: HTMLElement) {
  const data = await api<Page<Record<string, any>>>(`/v1/admin/rewards/audit?${params({ limit, offset: offsets.audit, actorUserId: filters.auditActor, targetType: filters.auditTargetType, targetId: filters.auditTargetId })}`);
  if (activeSection !== "audit") return;
  page.innerHTML = `${pageHeader("Audit history", "Immutable administrator actions, targets, and stated reasons.")}<form id="audit-filter" class="toolbar"><div class="field"><label for="audit-actor">Actor user ID</label><input id="audit-actor" name="actor" value="${ha(filters.auditActor)}"></div><div class="field"><label for="audit-type">Target type</label><input id="audit-type" name="type" value="${ha(filters.auditTargetType)}" maxlength="100"></div><div class="field grow"><label for="audit-target">Target ID</label><input id="audit-target" name="target" value="${ha(filters.auditTargetId)}"></div><button class="button" type="submit">Apply</button></form>
    ${data.items.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Action</th><th>Actor</th><th>Target</th><th>Reason</th><th>Metadata</th><th>Time</th></tr></thead><tbody>${data.items.map((item) => `<tr><td><span class="primary-cell">${h(actionName(item.action))}</span></td><td>${h(item.actor?.displayName || item.actor?.normalizedEmail || "Unknown")}<span class="secondary">${h(item.actor?.normalizedEmail || "")}</span></td><td>${h(item.targetType)}<span class="secondary">${h(shortId(item.targetId))}</span></td><td>${h(item.reason || "—")}</td><td><div class="audit-meta">${h(item.metadata ? JSON.stringify(item.metadata, null, 2) : "—")}</div></td><td>${date(item.createdAt)}</td></tr>`).join("")}</tbody></table></div>` : emptyState("No audit events found", "No administrator mutations match these filters.")}${pagination("audit", data)}`;
  form("audit-filter")?.addEventListener("submit", (event) => { event.preventDefault(); const values = new FormData(event.currentTarget as HTMLFormElement); filters.auditActor = String(values.get("actor") || "").trim(); filters.auditTargetType = String(values.get("type") || "").trim(); filters.auditTargetId = String(values.get("target") || "").trim(); offsets.audit = 0; void telemetry({ event: "search_performed", section: "audit" }); void navigate("audit"); }); wirePagination(page, "audit", data);
}

function pageHeader(title: string, description: string, actions = "", eyebrow = "Rewards administration") { return `<header class="page-head"><div><p class="eyebrow">${h(eyebrow)}</p><h1>${h(title)}</h1><p>${h(description)}</p></div>${actions ? `<div class="page-actions">${actions}</div>` : ""}</header>`; }
function dualIdFilter(id: string, labelA: string, nameA: string, valueA: string, labelB: string, nameB: string, valueB: string) { return `<form id="${id}" class="toolbar">${inputField(labelA, nameA, valueA, "text", false)}${inputField(labelB, nameB, valueB, "text", false, "grow")}<button class="button" type="submit">Apply</button></form>`; }
function person(value: { username: string; displayName?: string | null; normalizedEmail?: string | null }) { return `${h(value.displayName || value.username)}<span class="secondary">@${h(value.username)}${value.normalizedEmail ? ` · ${h(value.normalizedEmail)}` : ""}</span>`; }
function badge(status: string) { return `<span class="badge ${ha(status)}">${h(status.replaceAll("_", " "))}</span>`; }
function options(values: string[], selected: string) { return values.map((value) => `<option value="${ha(value)}" ${value === selected ? "selected" : ""}>${h(value[0]!.toUpperCase() + value.slice(1))}</option>`).join(""); }
function params(values: Record<string, string | number>) { const result = new URLSearchParams(); Object.entries(values).forEach(([key, value]) => { if (value !== "") result.set(key, String(value)); }); return result.toString(); }
function pagination(section: Section, page: Page<unknown>) { if (page.total <= page.limit && page.offset === 0) return ""; const from = page.total === 0 ? 0 : page.offset + 1; const to = Math.min(page.offset + page.items.length, page.total); return `<div class="pagination"><span>Showing ${number(from)}–${number(to)} of ${number(page.total)}</span><div class="pagination-buttons"><button class="button small" data-page="previous" ${page.offset === 0 ? "disabled" : ""}>Previous</button><button class="button small" data-page="next" ${page.offset + page.items.length >= page.total ? "disabled" : ""}>Next</button></div></div>`; }
function wirePagination(container: HTMLElement, section: Section, page: Page<unknown>) { container.querySelectorAll<HTMLButtonElement>("[data-page]").forEach((button) => button.addEventListener("click", () => { offsets[section] = button.dataset.page === "next" ? page.offset + page.limit : Math.max(0, page.offset - page.limit); void navigate(section); })); }
function loadingState(message = "Fetching current rewards data.") { return `<div class="state-card"><div class="spinner" aria-label="Loading"></div><h2>Loading</h2><p>${h(message)}</p></div>`; }
function emptyState(title: string, message: string) { return `<div class="state-card"><div aria-hidden="true">◇</div><h2>${h(title)}</h2><p>${h(message)}</p></div>`; }
function errorState(message: string) { return `<div class="state-card"><div aria-hidden="true">!</div><h2>Unable to load</h2><p>${h(message)}</p></div>`; }
function renderPageError(page: HTMLElement, error: unknown, section: Section) { page.innerHTML = `${pageHeader(sectionName(section), "Rewards administration")}<div class="state-card"><div aria-hidden="true">!</div><h2>Unable to load this page</h2><p>${h(errorMessage(error))}</p><button class="button" id="retry-page">Try again</button></div>`; document.getElementById("retry-page")?.addEventListener("click", () => void navigate(section)); }
function renderPortalPageError(page: HTMLElement, error: unknown, portalPage: PortalPage) { page.innerHTML = `${pageHeader("Feature controls", "Plainstride administration", "", "Plainstride administration")}<div class="state-card"><div aria-hidden="true">!</div><h2>Unable to load this page</h2><p>${h(errorMessage(error))}</p><button class="button" id="retry-page">Try again</button></div>`; document.getElementById("retry-page")?.addEventListener("click", () => void navigatePortal(portalPage, false)); }
function sectionName(section: Section) { return ({ dashboard: "Overview", codes: "Contribution codes", redemptions: "Redemptions", referrals: "Referrals", users: "Users", audit: "Audit history" })[section]; }

function openDialog(markup: string, ready?: (dialog: HTMLDialogElement) => void, drawer = false) {
  const dialog = document.createElement("dialog"); if (drawer) dialog.className = "drawer-dialog"; dialog.innerHTML = markup; document.body.append(dialog); wireDialogClose(dialog); dialog.addEventListener("close", () => dialog.remove(), { once: true }); dialog.showModal(); ready?.(dialog); return dialog;
}
function wireDialogClose(dialog: HTMLDialogElement) { dialog.querySelectorAll<HTMLElement>("[data-close-dialog]").forEach((button) => button.addEventListener("click", () => dialog.close())); }
function closeButton() { return '<button type="button" class="close-button" aria-label="Close" data-close-dialog>×</button>'; }
function inputField(label: string, name: string, value: string, type = "text", required = false, className = "", maxlength?: number, min?: string, max?: string) { return `<div class="field ${className}"><label for="field-${ha(name)}">${h(label)}</label><input id="field-${ha(name)}" name="${ha(name)}" type="${ha(type)}" value="${ha(value)}" ${required ? "required" : ""} ${maxlength ? `maxlength="${maxlength}"` : ""} ${min ? `min="${ha(min)}"` : ""} ${max ? `max="${ha(max)}"` : ""}></div>`; }
function textAreaField(label: string, name: string, placeholder: string, required = false, className = "") { return `<div class="field ${className}"><label for="field-${ha(name)}">${h(label)}</label><textarea id="field-${ha(name)}" name="${ha(name)}" maxlength="500" placeholder="${ha(placeholder)}" ${required ? "required" : ""}></textarea></div>`; }
function form(id: string, container: ParentNode = document) { return container.querySelector<HTMLFormElement>(`#${id}`); }
function setSubmitting(formElement: HTMLFormElement, submitting: boolean) { formElement.querySelectorAll<HTMLButtonElement>("button").forEach((button) => button.disabled = submitting); }

async function api<T = unknown>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  if (!accessToken && !(await refreshSession())) throw new ApiError("Your session has expired. Sign in again.", 401, "session_expired");
  const headers = new Headers(init.headers); headers.set("Authorization", `Bearer ${accessToken}`); if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...init, headers, credentials: "same-origin" });
  if (response.status === 401 && retry && await refreshSession()) return api<T>(path, init, false);
  if (!response.ok) throw await responseError(response);
  return response.status === 204 ? undefined as T : await response.json() as T;
}

async function publicJson<T>(path: string, init: RequestInit = {}): Promise<T> { const response = await fetch(path, { ...init, credentials: "same-origin" }); if (!response.ok) throw await responseError(response); return response.json() as Promise<T>; }
async function responseError(response: Response) { let payload: { error?: string; code?: string } = {}; try { payload = await response.json() as typeof payload; } catch { /* use status fallback */ } return new ApiError(payload.error || `Request failed (${response.status}).`, response.status, payload.code); }
async function refreshSession() {
  if (!refreshToken) return false;
  if (refreshPromise) return refreshPromise;
  refreshPromise = (async () => { try { const session = await publicJson<SessionResponse>("/v1/auth/refresh", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refreshToken }) }); setSession(session); return true; } catch { clearSession(); return false; } finally { refreshPromise = null; } })();
  return refreshPromise;
}
function setSession(session: SessionResponse) { accessToken = session.accessToken; refreshToken = session.refreshToken; sessionStorage.setItem(refreshStorageKey, session.refreshToken); }
function clearSession() { accessToken = null; refreshToken = null; admin = null; sessionStorage.removeItem(refreshStorageKey); }
async function signOut() { try { if (accessToken || refreshToken) await fetch("/v1/auth/logout", { method: "POST", headers: { "Content-Type": "application/json", ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}) }, body: JSON.stringify(refreshToken ? { refreshToken } : {}) }); } finally { window.google?.accounts.id.disableAutoSelect(); clearSession(); renderSignIn(); } }
async function telemetry(payload: Record<string, string>) { try { await api("/v1/admin/rewards/telemetry", { method: "POST", body: JSON.stringify(payload) }); } catch { /* Telemetry must never block administration. */ } }

function toast(message: string, error = false) { const element = document.createElement("div"); element.className = `toast${error ? " error" : ""}`; element.setAttribute("role", error ? "alert" : "status"); element.textContent = message; toastRegion.append(element); window.setTimeout(() => element.remove(), 4200); }
function requiredElement(id: string) { const element = document.getElementById(id); if (!element) throw new Error(`Missing #${id}`); return element; }
function errorMessage(error: unknown) { if (error instanceof ApiError && error.code === "admin_access_required") return "This Google account is authenticated but is not approved for rewards administration."; if (error instanceof ApiError && error.code === "admin_not_configured") return "Rewards administration is not enabled on this server."; return error instanceof Error ? error.message : "An unexpected error occurred."; }
function h(value: unknown) { return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]!); }
function ha(value: unknown) { return h(value); }
function number(value: number) { return new Intl.NumberFormat().format(value || 0); }
function date(value: string | null | undefined) { if (!value) return "—"; const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? "—" : new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(parsed); }
function toLocalDate(value: string | null) { if (!value) return ""; const parsed = new Date(value); const local = new Date(parsed.getTime() - parsed.getTimezoneOffset() * 60_000); return local.toISOString().slice(0, 16); }
function localDateToIso(value: string) { return value ? new Date(value).toISOString() : null; }
function minimumFutureLocalDate() { const date = new Date(Date.now() + 60_000); date.setSeconds(0, 0); return toLocalDate(date.toISOString()); }
function isExpired(value: string | null) { return Boolean(value && new Date(value) <= new Date()); }
function shortId(value: string) { return value.length > 18 ? `${value.slice(0, 8)}…${value.slice(-5)}` : value; }
function capabilityName(value: string) { return ({ ai_planning_dynamic: "Dynamic AI planning", live_coach_dynamic: "Dynamic live coach", live_cheer_voice: "Original voice cheers" } as Record<string, string>)[value] || value.replaceAll("_", " "); }
function actionName(value: string) { return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
