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
) {
  return {
    photoCount: totalPhotoCount,
    photos: photos.slice(0, socialFeedPhotoMetadataLimit).map((photo) => ({
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
