import { Hono } from "hono";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const pageShell = ({
  title,
  description,
  path,
  content,
}: {
  title: string;
  description: string;
  path: string;
  content: string;
}) => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <meta name="description" content="${description}">
  <meta name="theme-color" content="#f5f2e9">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Plainstride">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:url" content="https://run.plainstride.com${path}">
  <style>
    :root {
      color-scheme: light;
      --ink: #172019;
      --muted: #667069;
      --paper: #f5f2e9;
      --card: #fffdf8;
      --moss: #315c40;
      --lime: #ddec8a;
      --coral: #eb744c;
      --line: rgba(23, 32, 25, .12);
      font-family: ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-synthesis: none;
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body { margin: 0; background: var(--paper); color: var(--ink); }
    a { color: inherit; }
    .site-nav { width: min(1120px, calc(100% - 40px)); margin: 0 auto; min-height: 78px; display: flex; align-items: center; justify-content: space-between; gap: 24px; }
    .brand { display: inline-flex; align-items: center; gap: 10px; font-size: 1.06rem; font-weight: 760; letter-spacing: -.02em; text-decoration: none; }
    .brand-mark { width: 34px; height: 34px; display: grid; place-items: center; border-radius: 11px; background: var(--ink); color: var(--lime); font-size: 1rem; transform: rotate(-4deg); }
    .nav-links { display: flex; align-items: center; gap: 24px; color: var(--muted); font-size: .92rem; }
    .nav-links a { text-decoration: none; }
    .nav-links a:hover { color: var(--ink); }
    .nav-pill { padding: 10px 16px; border: 1px solid var(--line); border-radius: 999px; background: rgba(255,255,255,.5); color: var(--ink) !important; }
    main { overflow: hidden; }
    .wrap { width: min(1120px, calc(100% - 40px)); margin: 0 auto; }
    .eyebrow { margin: 0 0 15px; color: var(--moss); font-size: .76rem; font-weight: 760; letter-spacing: .12em; text-transform: uppercase; }
    h1, h2, h3, p { margin-top: 0; }
    h1, h2, h3 { letter-spacing: -.045em; }
    h1 { max-width: 770px; margin-bottom: 24px; font-size: clamp(3.35rem, 8vw, 6.8rem); font-weight: 650; line-height: .92; }
    h2 { margin-bottom: 18px; font-size: clamp(2rem, 4.6vw, 3.8rem); font-weight: 620; line-height: 1; }
    h3 { margin-bottom: 10px; font-size: 1.22rem; }
    p { color: var(--muted); line-height: 1.65; }
    .hero { position: relative; padding: 94px 0 112px; }
    .hero::after { content: ""; position: absolute; z-index: -1; width: 480px; height: 480px; right: -120px; top: 0; border-radius: 50%; background: radial-gradient(circle at 35% 35%, var(--lime), rgba(221,236,138,.15) 65%, transparent 66%); }
    .hero-copy { max-width: 700px; }
    .lede { max-width: 610px; margin-bottom: 34px; font-size: clamp(1.08rem, 2vw, 1.3rem); }
    .actions { display: flex; flex-wrap: wrap; gap: 12px; }
    .button { display: inline-flex; min-height: 50px; align-items: center; justify-content: center; padding: 0 21px; border-radius: 999px; background: var(--ink); color: white; font-weight: 700; text-decoration: none; }
    .button.secondary { background: transparent; border: 1px solid var(--line); color: var(--ink); }
    .hero-note { display: inline-flex; align-items: center; gap: 8px; margin-top: 22px; color: var(--muted); font-size: .88rem; }
    .pulse { width: 8px; height: 8px; border-radius: 50%; background: var(--coral); box-shadow: 0 0 0 5px rgba(235,116,76,.13); }
    .moment { display: grid; grid-template-columns: 1.05fr .95fr; gap: 60px; align-items: center; padding: 80px 0 115px; }
    .phone { position: relative; width: min(360px, 88vw); margin: 0 auto; padding: 13px; border-radius: 48px; background: #101512; box-shadow: 0 35px 90px rgba(23,32,25,.2); transform: rotate(-2deg); }
    .phone-screen { min-height: 610px; padding: 28px 20px 22px; border-radius: 37px; background: linear-gradient(165deg, #f9f7ef, #e9eddd); overflow: hidden; }
    .phone-top { display: flex; justify-content: space-between; color: #6b746e; font-size: .76rem; }
    .today-label { margin: 66px 0 7px; color: var(--moss); font-size: .72rem; font-weight: 800; letter-spacing: .12em; text-transform: uppercase; }
    .phone h3 { font-size: 2.05rem; line-height: 1; }
    .workout-card { margin-top: 28px; padding: 20px; border-radius: 24px; background: var(--card); box-shadow: 0 12px 35px rgba(23,32,25,.08); }
    .workout-card small { color: var(--muted); }
    .workout-title { margin: 8px 0 22px; font-size: 1.32rem; font-weight: 720; }
    .workout-row { display: flex; gap: 8px; }
    .metric { flex: 1; padding: 11px; border-radius: 14px; background: #eef1e5; }
    .metric strong, .metric span { display: block; }
    .metric strong { font-size: .96rem; }
    .metric span { margin-top: 3px; color: var(--muted); font-size: .68rem; }
    .start { margin-top: 18px; padding: 14px; border-radius: 16px; background: var(--coral); color: white; font-weight: 750; text-align: center; }
    .quote { max-width: 520px; }
    .quote-mark { font-size: 4.8rem; color: var(--coral); line-height: .6; }
    .quote blockquote { margin: 18px 0 24px; font-size: clamp(1.7rem, 3.4vw, 2.7rem); font-weight: 590; letter-spacing: -.035em; line-height: 1.12; }
    .feature-section { padding: 110px 0; background: var(--ink); color: #f8f5ec; }
    .feature-section p { color: #aeb8b0; }
    .feature-section .eyebrow { color: var(--lime); }
    .feature-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-top: 46px; }
    .feature { min-height: 245px; padding: 26px; border: 1px solid rgba(255,255,255,.12); border-radius: 26px; background: rgba(255,255,255,.035); }
    .feature-num { display: block; margin-bottom: 64px; color: var(--lime); font-size: .78rem; }
    .feature p { margin-bottom: 0; font-size: .94rem; }
    .beta { padding: 110px 0; text-align: center; }
    .beta-card { position: relative; max-width: 840px; margin: 0 auto; padding: clamp(42px, 8vw, 78px); border-radius: 42px; background: var(--lime); overflow: hidden; }
    .beta-card::before { content: ""; position: absolute; width: 220px; height: 220px; left: -70px; bottom: -100px; border: 34px solid rgba(23,32,25,.09); border-radius: 50%; }
    .beta-card p { max-width: 540px; margin: 0 auto 28px; color: #405044; }
    .beta-card .button { position: relative; }
    .legal { max-width: 760px; padding: 76px 0 120px; }
    .legal h1 { font-size: clamp(2.8rem, 7vw, 5rem); }
    .legal h2 { margin-top: 46px; font-size: 1.45rem; letter-spacing: -.025em; }
    .legal h3 { margin-top: 28px; font-size: 1.02rem; letter-spacing: -.015em; }
    .legal li { margin-bottom: 9px; color: var(--muted); line-height: 1.55; }
    .legal-card { margin: 28px 0; padding: 22px 24px; border: 1px solid var(--line); border-radius: 20px; background: var(--card); }
    footer { border-top: 1px solid var(--line); }
    .footer-inner { width: min(1120px, calc(100% - 40px)); min-height: 118px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; gap: 28px; color: var(--muted); font-size: .86rem; }
    .footer-links { display: flex; flex-wrap: wrap; gap: 22px; }
    .footer-links a { text-decoration: none; }
    @media (max-width: 760px) {
      .site-nav { min-height: 66px; }
      .nav-links a:not(.nav-pill) { display: none; }
      .hero { padding: 66px 0 80px; }
      .moment { grid-template-columns: 1fr; padding: 45px 0 85px; }
      .quote { order: -1; }
      .feature-grid { grid-template-columns: 1fr; }
      .feature { min-height: 200px; }
      .feature-num { margin-bottom: 40px; }
      .footer-inner { padding: 28px 0; align-items: flex-start; flex-direction: column; }
    }
  </style>
</head>
<body>
  <header>
    <nav class="site-nav" aria-label="Main navigation">
      <a class="brand" href="/"><span class="brand-mark" aria-hidden="true">P</span>Plainstride</a>
      <div class="nav-links">
        <a href="/#how-it-works">How it works</a>
        <a href="/support">Support</a>
        <a class="nav-pill" href="/#beta">TestFlight beta</a>
      </div>
    </nav>
  </header>
  <main>${content}</main>
  <footer>
    <div class="footer-inner">
      <span>© 2026 Plainstride Labs Inc.</span>
      <div class="footer-links"><a href="/support">Support</a><a href="/privacy">Privacy</a><a href="/health">System status</a></div>
    </div>
  </footer>
</body>
</html>`;

router.get("/", (c) => c.html(pageShell({
  title: "Plainstride — Your adaptive running companion",
  description: "A running companion that adapts today's workout to your goals, readiness, recent training, and real life.",
  path: "/",
  content: `
    <section class="hero wrap">
      <div class="hero-copy">
        <p class="eyebrow">Run the day you're in</p>
        <h1>A coach that keeps pace with real life.</h1>
        <p class="lede">Plainstride turns your goals, readiness, recent training, and available time into one clear answer: what should I do today?</p>
        <div class="actions"><a class="button" href="#how-it-works">See how it works</a><a class="button secondary" href="#beta">Join the beta</a></div>
        <div class="hero-note"><span class="pulse" aria-hidden="true"></span>Private TestFlight beta now underway</div>
      </div>
    </section>
    <section class="moment wrap" id="how-it-works">
      <div class="phone" aria-label="A preview of today's workout in Plainstride">
        <div class="phone-screen">
          <div class="phone-top"><span>9:41</span><span>Plainstride</span></div>
          <p class="today-label">Today</p>
          <h3>Easy miles.<br>Clear head.</h3>
          <div class="workout-card">
            <small>Your adjusted workout</small>
            <div class="workout-title">Easy aerobic run</div>
            <div class="workout-row">
              <div class="metric"><strong>35 min</strong><span>Duration</span></div>
              <div class="metric"><strong>Easy</strong><span>Effort</span></div>
            </div>
            <div class="start">Start run</div>
          </div>
        </div>
      </div>
      <div class="quote">
        <span class="quote-mark" aria-hidden="true">“</span>
        <blockquote>Training should fit your life—not ask your life to fit a spreadsheet.</blockquote>
        <p>Plainstride notices when the week changes, explains the adjustment, and keeps the next step simple enough to start.</p>
      </div>
    </section>
    <section class="feature-section">
      <div class="wrap">
        <p class="eyebrow">One connected rhythm</p>
        <h2>Before, during, and after every run.</h2>
        <div class="feature-grid">
          <article class="feature"><span class="feature-num">01 · TODAY</span><h3>Know what to do</h3><p>Adaptive guidance grounded in your goal, readiness, training history, weather, and actual schedule.</p></article>
          <article class="feature"><span class="feature-num">02 · THE RUN</span><h3>Stay present</h3><p>GPS recording, optional spoken coaching, Live Activities, photos, and private live sharing when you choose.</p></article>
          <article class="feature"><span class="feature-num">03 · PROGRESS</span><h3>See momentum</h3><p>Weekly trends, records, race predictions, gear mileage, and reflections that value consistency over perfection.</p></article>
        </div>
      </div>
    </section>
    <section class="beta wrap" id="beta">
      <div class="beta-card">
        <p class="eyebrow">TestFlight beta</p>
        <h2>Help shape the next mile.</h2>
        <p>Plainstride is currently testing with a small group of runners on iPhone. Invitations are private while we tune the experience.</p>
        <a class="button" href="/support">Beta tester guide</a>
      </div>
    </section>`,
})));

router.get("/support", (c) => c.html(pageShell({
  title: "Plainstride Support",
  description: "Help, feedback, and beta testing guidance for Plainstride.",
  path: "/support",
  content: `
    <article class="legal wrap">
      <p class="eyebrow">Support</p>
      <h1>We're here for the run.</h1>
      <p class="lede">Plainstride is currently in TestFlight beta. Your feedback helps us make every part of the experience clearer and more dependable.</p>
      <div class="legal-card"><h3>Report a bug or suggestion</h3><p>From any main Plainstride screen, shake your iPhone to open <strong>Send feedback</strong>. Describe what happened, optionally annotate the captured screenshot, then share the report. You can also open <strong>Me → Settings → Send feedback</strong>.</p></div>
      <h2>Common beta questions</h2>
      <h3>How do I install Plainstride?</h3><p>Install Apple's TestFlight app, then open the private invitation sent by the Plainstride team. Test builds remain available for up to 90 days.</p>
      <h3>Why is a permission requested?</h3><p>Location records an outdoor activity and can provide local running conditions. Apple Health import and workout saving, camera photos, voice commands, Apple Music, and live sharing are optional and requested only when you use the related feature.</p>
      <h3>How do I delete my account?</h3><p>Open <strong>Me → Settings → Delete Account</strong>. Plainstride may ask you to confirm your Apple or Google identity, then deletes your server account data, clears local Plainstride data, and signs you out.</p>
      <h3>Is Plainstride medical advice?</h3><p>No. Plainstride provides general fitness guidance and is not a medical service. Stop exercising and seek appropriate professional care if you feel unwell or unsafe.</p>
      <h2>TestFlight feedback</h2><p>You can also submit a screenshot and comment directly from the TestFlight app. Crash reports and tester feedback appear privately to the Plainstride team in App Store Connect.</p>
    </article>`,
})));

router.get("/privacy", (c) => c.html(pageShell({
  title: "Plainstride Privacy Policy",
  description: "How Plainstride handles account, fitness, location, health, and feedback data.",
  path: "/privacy",
  content: `
    <article class="legal wrap">
      <p class="eyebrow">Privacy policy</p>
      <h1>Your run is personal.</h1>
      <p class="lede">This policy explains how Plainstride Labs Inc. handles information in the Plainstride iPhone app and related web services during the beta. Last updated August 11, 2026.</p>
      <div class="legal-card"><strong>Plainstride does not sell personal information or use it for third-party advertising.</strong></div>
      <h2>Information we handle</h2>
      <h3>Account information</h3><p>When you sign in with Apple or Google, we receive an account identifier and, when the provider makes it available, your name and email address. We use this information to authenticate you and maintain your Plainstride account.</p>
      <h3>Runner and fitness information</h3><p>Plainstride may process information you provide about goals, experience, availability, readiness, workout feedback, training plans, and completed activities to provide and personalize app functionality.</p>
      <h3>Location and activity routes</h3><p>Precise location is used while recording an outdoor activity. If you explicitly start private live sharing or a live group run, current location updates are sent to our service for that feature. Approximate or one-shot location may be used to provide local weather context. Plainstride does not continuously collect location when these features are not active.</p>
      <h3>Apple Health</h3><p>With your permission, Plainstride can read relevant workout and fitness information from Apple Health and save completed workouts there. Health information stays under Apple's Health permissions and is not used for advertising. You can change access in iOS Settings or the Health app.</p>
      <h3>Photos, voice, and music</h3><p>Activity photos are stored on your device unless you explicitly use a sharing or upload feature. Voice commands may be processed on-device or sent for transcription when a remote transcription feature is used. Apple Music access is used only for the playback features you choose.</p>
      <h3>Feedback and diagnostics</h3><p>If you submit feedback, we receive the text and screenshot you choose to share. Optional diagnostics include the app version, device type, and iOS version; the in-app report does not automatically include health, location, or account data. Apple may separately provide TestFlight crash and usage diagnostics under your Apple settings.</p>
      <h2>How we use information</h2><ul><li>Provide authentication, activity recording, training guidance, progress, sharing, and support.</li><li>Personalize workouts and explain relevant adjustments.</li><li>Maintain security, prevent abuse, diagnose failures, and improve the beta.</li><li>Meet legal obligations and enforce our agreements.</li></ul>
      <h2>Service providers</h2><p>Plainstride relies on service providers including Apple services, Google Firebase and Google Cloud infrastructure, and AI or transcription providers for features you invoke. These providers process information on our behalf under their applicable terms and safeguards.</p>
      <h2>Sharing and visibility</h2><p>Your private plan, health context, and readiness reasons are not shown to other runners. Live location or group-run information is shared only when you explicitly start that feature and with people who receive or join the relevant private link. Avoid forwarding private links to people you do not trust.</p>
      <h2>Retention and deletion</h2><p>We retain account and server-backed app information while your account is active and as reasonably needed to operate and secure the service. Feature-specific temporary data, such as active live-location updates, may be retained for a shorter operational period. You can delete your account in <strong>Me → Settings → Delete Account</strong>; this deletes associated server account data and clears local Plainstride data, subject to limited retention required for security, legal compliance, or resolving disputes.</p>
      <h2>Your choices</h2><p>You can decline optional permissions, stop live sharing, remove locally saved activities, change Apple Health access, sign out, or delete your account. Some features will not work without their related permission.</p>
      <h2>Children</h2><p>Plainstride is not directed to children under 13, and we do not knowingly collect personal information from children under 13.</p>
      <h2>Changes</h2><p>We may update this policy as the beta evolves. We will update the date above and provide additional notice when a change is material.</p>
      <h2>Contact</h2><p>For privacy or support questions during the beta, use <a href="/support">Plainstride Support</a> or the feedback contact included in your TestFlight invitation.</p>
    </article>`,
})));

export default router;
