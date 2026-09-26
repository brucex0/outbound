import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import {
  activityPhotoThumbnailMaxEdge,
  activityPhotoThumbnailStorageKey,
  createActivityPhotoThumbnail,
} from "./activityPhotoStorage.js";

test("activity photo thumbnail key stays beside the original photo", () => {
  assert.equal(
    activityPhotoThumbnailStorageKey("activity-photos/user/activity/photo.jpg"),
    "activity-photos/user/activity/photo-thumb.jpg",
  );
});

test("activity photo thumbnail is oriented, downscaled, and remains JPEG", async () => {
  const source = await sharp({
    create: {
      width: 1_200,
      height: 800,
      channels: 3,
      background: { r: 220, g: 100, b: 20 },
    },
  }).jpeg().toBuffer();
  const thumbnail = await createActivityPhotoThumbnail(source);
  const metadata = await sharp(thumbnail).metadata();

  assert.equal(metadata.format, "jpeg");
  assert.ok((metadata.width ?? 0) <= activityPhotoThumbnailMaxEdge);
  assert.ok((metadata.height ?? 0) <= activityPhotoThumbnailMaxEdge);
  assert.ok(thumbnail.length < source.length);
});
