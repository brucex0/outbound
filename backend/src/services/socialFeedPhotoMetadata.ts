import { activityPhotoOrder, orderedActivityPhotos } from "./activityPhotoOrder.js";

export const socialFeedPhotoMetadataLimit = 2;

export interface SocialFeedPhotoRecord {
  id: string;
  clientPhotoId: string;
  takenAt: Date;
  paceAtShot: number | null;
  hrAtShot: number | null;
  distAtShot: number | null;
  lat: number | null;
  lng: number | null;
  captureContext: string | null;
}

export function socialFeedPhotoMetadata(
  photos: SocialFeedPhotoRecord[],
  totalPhotoCount: number,
  maxPhotos = socialFeedPhotoMetadataLimit,
  clientData?: unknown,
) {
  const ordered = orderedActivityPhotos(photos, clientData);
  const cover = activityPhotoOrder(clientData)[0];
  // Do not temporarily promote a later upload while the intentional cover is pending.
  const coverReady = !cover || ordered[0]?.clientPhotoId.toLowerCase() === cover;
  return {
    photoCount: totalPhotoCount,
    photos: (coverReady ? ordered : []).slice(0, maxPhotos).map((photo) => ({
      id: photo.id,
      clientPhotoId: photo.clientPhotoId,
      url: `/media/activity-photos/${photo.id}/content`,
      thumbnailUrl: `/media/activity-photos/${photo.id}/thumbnail`,
      takenAt: photo.takenAt,
      paceAtShot: photo.paceAtShot,
      hrAtShot: photo.hrAtShot,
      distAtShot: photo.distAtShot,
      latitude: photo.lat,
      longitude: photo.lng,
      captureContext: photo.captureContext,
    })),
  };
}
