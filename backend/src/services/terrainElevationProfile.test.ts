import assert from "node:assert/strict";
import test from "node:test";
import { resampleTerrainRoute, smoothTerrainProfile, terrainElevationGain } from "./terrainElevationProfile.js";

const metersPerDegree = 6_371_000 * Math.PI / 180;
const point = (distance: number, startsNewSegment = false) => ({
  latitude: distance / metersPerDegree, longitude: 0, startsNewSegment,
});

// Regression coverage is deliberately pure/offline; no terrain provider or private route data.
test("distance normalization is independent of source cadence", () => {
  const totals = [5, 20, 50, 100].map((spacing) => {
    const input = Array.from({ length: 2_000 / spacing + 1 }, (_, i) => point(i * spacing, i === 0));
    const { points, positions } = resampleTerrainRoute(input);
    assert.equal(positions.length, input.length);
    assert.equal(points.length, 101);
    const elevations = points.map((p) => 50 + p.latitude * metersPerDegree / 100);
    return terrainElevationGain(smoothTerrainProfile(elevations, points), points);
  });
  for (const total of totals) assert.ok(Math.abs(total - 20) < 0.001);
});

test("downhill and sub-threshold noise cannot create ascent", () => {
  const points = [0, 20, 40, 60, 80, 100].map((d, i) => point(d, i === 0));
  assert.equal(terrainElevationGain([100, 99, 98, 97, 96, 95], points), 0);
  assert.equal(terrainElevationGain([10, 10.5, 9.5, 10.5, 9.5, 10], points), 0);
});

test("repeated hills accumulate and an unfinished final climb counts", () => {
  const points = [0, 20, 40, 60, 80, 100].map((d, i) => point(d, i === 0));
  assert.equal(terrainElevationGain([10, 15, 10, 15, 10, 15], points), 15);
});

test("segment gaps never add ascent and endpoints survive normalization", () => {
  const input = [point(0, true), point(25), point(1_000, true), point(1_025)];
  const { points, positions } = resampleTerrainRoute(input);
  assert.equal(points.filter((p) => p.startsNewSegment).length, 2);
  assert.equal(positions.length, 4);
  assert.equal(terrainElevationGain([10, 15, 100, 105], input), 10);
  assert.equal(terrainElevationGain([10, 10, 100, 100], input), 0);
  assert.equal(terrainElevationGain([], []), 0);
});
