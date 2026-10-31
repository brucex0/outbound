import assert from "node:assert/strict";
import test from "node:test";
import { Hono } from "hono";
import social from "./social.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv, AuthContext } from "../types/hono.js";

test("profile lookup supports reconnecting without exposing connection-only data", async (context) => {
  const originalDatabaseURL = process.env.DATABASE_URL;
  process.env.DATABASE_URL = "postgresql://unused:unused@localhost:1/unused";
  const prisma = getPrismaClient();
  const originals = {
    person: prisma.user.findUnique,
    blocks: prisma.socialBlock.findMany,
    relationship: prisma.connection.findFirst,
    awards: prisma.recognitionAward.findMany,
  };
  const viewer = { id: "viewer", displayName: "Viewer", username: "viewer", avatarUrl: null };
  const person = { id: "runner", displayName: "Runner", username: "runner", avatarUrl: null };
  let relationship: { id: string; status: string; requesterId: string; addresseeId: string } | null = null;
  let blocks: Array<{ blockerId: string; blockedId: string }> = [];
  let awardQueries = 0;
  prisma.user.findUnique = (async (args: { where: { id: string } }) =>
    args.where.id === viewer.id ? viewer : args.where.id === person.id ? person : null
  ) as unknown as typeof prisma.user.findUnique;
  prisma.socialBlock.findMany = (async () => blocks) as typeof prisma.socialBlock.findMany;
  prisma.connection.findFirst = (async () => relationship) as typeof prisma.connection.findFirst;
  prisma.recognitionAward.findMany = (async (args: unknown) => {
    assert.equal((args as { where: { shareEligible: boolean } }).where.shareEligible, true);
    awardQueries++;
    return [];
  }) as typeof prisma.recognitionAward.findMany;
  const auth: AuthContext = {
    subject: viewer.id, authenticationKind: "plainstride", provider: "plainstride",
    providerSubject: viewer.id, internalUserId: viewer.id, sessionId: "fixture-session",
    email: null, emails: [], emailVerified: false, name: null, picture: null,
    phoneNumber: null, phoneNumbers: [],
  };
  const app = new Hono<AppEnv>();
  app.use("*", async (c, next) => { c.set("auth", auth); await next(); });
  app.route("/social", social);
  try {
    await context.test("accepted profile then disconnect and reopen", async () => {
      relationship = { id: "connection", status: "accepted", requesterId: viewer.id, addresseeId: person.id };
      const connected = await app.request("/social/users/runner/profile");
      assert.equal(connected.status, 200);
      assert.deepEqual((await connected.json()).person.relationship, { id: "connection", status: "accepted", direction: "outgoing" });
      assert.equal(awardQueries, 1);
      relationship = null; // Successful disconnect removes the relationship row.
      const reopened = await app.request("/social/users/runner/profile");
      assert.equal(reopened.status, 200);
      assert.deepEqual(await reopened.json(), { person: { ...person, relationship: null }, recognitions: [] });
      assert.equal(awardQueries, 1, "disconnected lookup must not even query milestones");
    });
    for (const direction of ["outgoing", "incoming"] as const) {
      await context.test(`${direction} pending profile reopens with current request state`, async () => {
        relationship = { id: "request", status: "pending", requesterId: direction === "outgoing" ? viewer.id : person.id, addresseeId: direction === "outgoing" ? person.id : viewer.id };
        const response = await app.request("/social/users/runner/profile");
        assert.equal(response.status, 200);
        const body = await response.json();
        assert.deepEqual(body.person.relationship, { id: "request", status: "pending", direction });
        assert.deepEqual(body.recognitions, []);
        assert.equal(awardQueries, 1);
      });
    }
    for (const block of [{ blockerId: viewer.id, blockedId: person.id }, { blockerId: person.id, blockedId: viewer.id }]) {
      await context.test(`block by ${block.blockerId} remains indistinguishable from missing profile`, async () => {
        blocks = [block];
        const blocked = await app.request("/social/users/runner/profile");
        blocks = [];
        const missing = await app.request("/social/users/missing/profile");
        assert.equal(blocked.status, 404);
        assert.equal(missing.status, 404);
        assert.deepEqual(await blocked.json(), await missing.json());
        assert.equal(awardQueries, 1);
      });
    }
    await context.test("self profile retains shareable milestone lookup", async () => {
      const response = await app.request("/social/users/viewer/profile");
      assert.equal(response.status, 200);
      assert.equal((await response.json()).person.relationship, null);
      assert.equal(awardQueries, 2);
    });
    await context.test("unauthenticated lookup is rejected", async () => {
      const unauthenticated = new Hono<AppEnv>();
      unauthenticated.use("*", async (c, next) => { c.set("auth", null); await next(); });
      unauthenticated.route("/social", social);
      assert.equal((await unauthenticated.request("/social/users/runner/profile")).status, 401);
    });
  } finally {
    prisma.user.findUnique = originals.person;
    prisma.socialBlock.findMany = originals.blocks;
    prisma.connection.findFirst = originals.relationship;
    prisma.recognitionAward.findMany = originals.awards;
    if (originalDatabaseURL === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = originalDatabaseURL;
    await prisma.$disconnect();
  }
});
