/** The accepted activity snapshot owns order, independently of media upload completion. */
export function activityPhotoOrder(clientData: unknown): string[] {
  const value = clientData && typeof clientData === "object" && "photoOrder" in clientData
    ? (clientData as { photoOrder?: unknown }).photoOrder : undefined;
  return Array.isArray(value) ? value.filter((id): id is string => typeof id === "string").map(id => id.toLowerCase()) : [];
}

export function orderedActivityPhotos<T extends { clientPhotoId: string; takenAt: Date }>(photos: T[], clientData: unknown): T[] {
  const order = new Map<string, number>();
  activityPhotoOrder(clientData).forEach((id, index) => {
    if (!order.has(id)) order.set(id, index);
  });
  return [...photos].sort((a, b) => {
    const first = order.get(a.clientPhotoId.toLowerCase());
    const second = order.get(b.clientPhotoId.toLowerCase());
    if (first !== undefined || second !== undefined) {
      if (first === undefined) return 1;
      if (second === undefined) return -1;
      if (first !== second) return first - second;
    }
    const time = a.takenAt.getTime() - b.takenAt.getTime();
    return time || a.clientPhotoId.toLowerCase().localeCompare(b.clientPhotoId.toLowerCase());
  });
}
