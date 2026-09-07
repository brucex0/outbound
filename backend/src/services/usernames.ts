import { Prisma } from "@prisma/client";

export const USERNAME_CHANGE_COOLDOWN_DAYS = 30;
const USERNAME_CHANGE_COOLDOWN_MS = USERNAME_CHANGE_COOLDOWN_DAYS * 24 * 60 * 60 * 1_000;

const RESERVED_USERNAMES = new Set([
  "admin",
  "administrator",
  "help",
  "moderator",
  "outbound",
  "plainstride",
  "security",
  "staff",
  "support",
]);

export function normalizeUsername(username: string) {
  return username.trim().toLowerCase();
}

export function isReservedUsername(username: string) {
  const normalized = normalizeUsername(username);
  return RESERVED_USERNAMES.has(normalized)
    || normalized.startsWith("plainstride-")
    || normalized.startsWith("outbound-");
}

export async function changeUsername(
  tx: Prisma.TransactionClient,
  user: { id: string; username: string; usernameChangedAt: Date | null },
  requestedUsername: string,
  now = new Date(),
) {
  const username = normalizeUsername(requestedUsername);
  if (username === user.username) return null;
  if (isReservedUsername(username)) throw new UsernameChangeError("username_reserved");

  if (user.usernameChangedAt) {
    const retryAt = new Date(user.usernameChangedAt.getTime() + USERNAME_CHANGE_COOLDOWN_MS);
    if (retryAt > now) throw new UsernameChangeError("username_change_too_soon", retryAt);
  }

  await tx.usernameReservation.deleteMany({ where: { expiresAt: { lte: now } } });
  const [owner, reservation] = await Promise.all([
    tx.user.findUnique({ where: { username }, select: { id: true } }),
    tx.usernameReservation.findUnique({ where: { username }, select: { userId: true } }),
  ]);
  if ((owner && owner.id !== user.id) || (reservation && reservation.userId !== user.id)) {
    throw new UsernameChangeError("username_taken");
  }

  await tx.usernameReservation.upsert({
    where: { username: user.username },
    create: { username: user.username, userId: user.id, expiresAt: new Date(now.getTime() + USERNAME_CHANGE_COOLDOWN_MS) },
    update: { userId: user.id, expiresAt: new Date(now.getTime() + USERNAME_CHANGE_COOLDOWN_MS) },
  });
  return { username, usernameChangedAt: now };
}

export class UsernameChangeError extends Error {
  constructor(readonly code: "username_taken" | "username_reserved" | "username_change_too_soon", readonly retryAt?: Date) {
    super(code);
  }
}
