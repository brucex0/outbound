import assert from "node:assert/strict";
import test from "node:test";
import { encodeActivityRoute } from "./activityRouteCodec.js";
import {
  activityPersonalBestTimes,
  activityRecognitionKey,
  activityRecognitionsForActivities,
} from "./recognition.js";
import { getPrismaClient } from "./prisma.js";

const prisma = getPrismaClient();

test("activity feed recognitions are owner/activity scoped and private unless shareable", async (context) => {
  const originalFindMany = prisma.recognitionAward.findMany;
  let query: unknown;
  const mockFindMany = async (args: unknown) => {
    query = args;
    const where = (args as { where: { OR: Array<{ userId: string; sourceActivityClientId: string; shareEligible?: boolean }> } }).where;
    const rows = [
      { userId: "friend-a", sourceActivityClientId: "activity-a", badgeId: "first5K", shareEligible: true, earnedAt: new Date("2026-01-01T00:00:00Z") },
      { userId: "friend-a", sourceActivityClientId: "activity-a", badgeId: "firstStep", shareEligible: false, earnedAt: new Date("2026-01-01T00:00:00Z") },
      { userId: "friend-a", sourceActivityClientId: "activity-b", badgeId: "firstMarathon", shareEligible: true, earnedAt: new Date("2026-01-02T00:00:00Z") },
      { userId: "friend-b", sourceActivityClientId: "activity-a", badgeId: "firstStep", shareEligible: false, earnedAt: new Date("2026-01-03T00:00:00Z") },
    ];
    return rows.filter((row) => where.OR.some((source) =>
      source.userId === row.userId
      && source.sourceActivityClientId === row.sourceActivityClientId
      && (source.shareEligible === undefined || row.shareEligible)
    ));
  };
  Object.defineProperty(prisma.recognitionAward, "findMany", { configurable: true, value: mockFindMany });
  context.after(() => { Object.defineProperty(prisma.recognitionAward, "findMany", { configurable: true, value: originalFindMany }); });

  const results = await activityRecognitionsForActivities([
    { userId: "friend-a", clientActivityId: "activity-a" },
    { userId: "friend-a", clientActivityId: "activity-a" },
    { userId: "friend-b", clientActivityId: "activity-a" },
  ], "friend-b");

  const ownerActivity = results.get(activityRecognitionKey("friend-a", "activity-a"));
  assert.deepEqual(ownerActivity?.map((award) => award.badgeId), ["first5K"]);
  assert.equal(results.has(activityRecognitionKey("friend-b", "activity-a")), true);
  assert.deepEqual(
    results.get(activityRecognitionKey("friend-b", "activity-a"))?.map((award) => award.badgeId),
    ["firstStep"],
  );
  assert.deepEqual(query, {
    where: {
      OR: [
        { userId: "friend-a", sourceActivityClientId: "activity-a", shareEligible: true },
        { userId: "friend-b", sourceActivityClientId: "activity-a" },
      ],
    },
    select: { userId: true, sourceActivityClientId: true, badgeId: true, earnedAt: true },
  });
});

test("personal bests use GPS windows without bridging paused segments", () => {
  const route = Array.from({ length: 7 }, (_, index) => ({
    timestamp: new Date(index * 300_000).toISOString(),
    latitude: index * 300 / 111_320,
    longitude: 0,
    startsNewSegment: index === 3,
  }));
  const times = activityPersonalBestTimes(encodeActivityRoute(route), { visibility: "private" });
  assert.ok(times.has("personalBest400m"));
  assert.ok(!times.has("personalBest1K"));
  assert.ok(!times.has("personalBest5K"));
});

test("personal best calculation ignores missing and malformed routes", () => {
  assert.equal(activityPersonalBestTimes(null, null).size, 0);
  assert.equal(activityPersonalBestTimes(Buffer.from("invalid"), null).size, 0);
});
