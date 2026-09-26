import assert from "node:assert/strict";
import test from "node:test";
import { socialFeedPhotoMetadata, socialFeedPhotoMetadataLimit } from "./socialFeedPhotoMetadata.js";

const photos = Array.from({ length: 5 }, (_, index) => ({
  id: `photo-${index + 1}`,
  clientPhotoId: `client-photo-${index + 1}`,
  takenAt: new Date(`2026-09-0${index + 1}T12:00:00Z`),
  paceAtShot: 350 + index,
  hrAtShot: 140 + index,
  distAtShot: 1_000 * (index + 1),
  lat: 37.7 + index / 1_000,
  lng: -122.4 - index / 1_000,
  captureContext: "active",
}));

test("social feed sends at most two photo records and keeps the total photo count", () => {
  const payload = socialFeedPhotoMetadata(photos, photos.length);

  assert.equal(socialFeedPhotoMetadataLimit, 2);
  assert.equal(payload.photoCount, 5);
  assert.deepEqual(payload.photos.map((photo) => photo.id), ["photo-1", "photo-2"]);
  assert.equal(payload.photos[0].thumbnailUrl, "/media/activity-photos/photo-1/thumbnail");
});

test("social feed photo metadata remains compatible with included photos and no-count fixtures", () => {
  const payload = socialFeedPhotoMetadata(photos.slice(0, 1), 1);

  assert.equal(payload.photoCount, 1);
  assert.equal(payload.photos.length, 1);
});
