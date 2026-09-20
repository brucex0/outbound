const avatarPathPattern = /\/v1\/auth\/avatars\/([^/?#]+)$/;

/**
 * API payloads use paths relative to the API base URL for first-party assets.
 * External provider URLs (for example Google profile photos) remain absolute.
 */
export function compactAvatarURL(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith("/")) {
    return trimmed.replace(/^\/v1\/auth\/avatars\//, "/auth/avatars/");
  }

  try {
    const url = new URL(trimmed);
    const match = url.pathname.match(avatarPathPattern);
    if (!match) return value;
    return `/auth/avatars/${match[1]}${url.search}`;
  } catch {
    return value;
  }
}

export function compactPerson<T extends { avatarUrl?: string | null }>(person: T): T {
  return { ...person, avatarUrl: compactAvatarURL(person.avatarUrl) };
}
