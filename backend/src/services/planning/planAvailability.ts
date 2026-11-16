/** Account-local date labels (UTC midnight containers), never travel/device dates. */
export interface PlanAvailability { paused?: boolean; pausedOn?: string; reminderDate?: string | null; unavailableFrom?: string; unavailableThrough?: string; availableDays?: number[] }
export function planAvailability(constraints: unknown): PlanAvailability {
  const raw = constraints && typeof constraints === "object" && !Array.isArray(constraints) ? (constraints as Record<string, unknown>).planAvailability : null;
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw as PlanAvailability : {};
}
export function planDateExcluded(constraints: unknown, date: Date): boolean {
  const state = planAvailability(constraints); const key = date.toISOString().slice(0, 10);
  return (state.paused === true && (!state.pausedOn || key >= state.pausedOn)) || Boolean(state.unavailableFrom && state.unavailableThrough && key >= state.unavailableFrom && key <= state.unavailableThrough && !(state.availableDays ?? []).includes(date.getUTCDay() + 1));
}

export function planPausedOn(constraints: unknown, date: Date): boolean {
 const state = planAvailability(constraints); return state.paused === true && (!state.pausedOn || date.toISOString().slice(0, 10) >= state.pausedOn);
}

/** Quality needs recovery around quality/long work; easy long days remain allowed together. */
export function requiresRecoverySpacing(a: { stimulus: string }, b: { stimulus: string }): boolean {
 const quality = (row: { stimulus: string }) => ["threshold", "speed", "vo2max", "tempo"].includes(row.stimulus);
 return quality(a) && (quality(b) || b.stimulus === "longEndurance") || quality(b) && a.stimulus === "longEndurance";
}

/** Temporary weekday selection changes only the bounded range; never adds catch-up load. */
export function applyPlanAvailability<T extends { scheduledDate: Date; prescription: Record<string, unknown>; stimulus: string }>(constraints: unknown, rows: T[], eventDate?: Date | null, taperDays = 14): T[] {
 const state = planAvailability(constraints);
 if (!state.unavailableFrom || !state.unavailableThrough || !state.availableDays) return rows.filter((row) => !planDateExcluded(constraints, row.scheduledDate));
 const required = rows.filter((row) => row.prescription.optional !== true);
 const earliest = Math.min(...rows.map((row) => row.scheduledDate.getTime()));
 const occupied = new Set(required.filter((row) => !planDateExcluded(constraints, row.scheduledDate)).map((row) => row.scheduledDate.toISOString().slice(0, 10)));
 const mapping = new Map<string, Date | null>();
 for (const row of required) {
  const source = row.scheduledDate.toISOString().slice(0, 10);
  if (!planDateExcluded(constraints, row.scheduledDate)) continue;
  const monday = new Date(row.scheduledDate.getTime() - ((row.scheduledDate.getUTCDay() + 6) % 7) * 86400000);
  let destination: Date | null = null;
  for (let offset = 0; offset < 7; offset++) {
   const candidate = new Date(monday.getTime() + offset * 86400000); const day = candidate.toISOString().slice(0, 10);
   if (candidate.getTime() < earliest || day < state.unavailableFrom || day > state.unavailableThrough || planDateExcluded(constraints, candidate) || occupied.has(day)) continue;
   if (eventDate && (candidate >= eventDate || (row.scheduledDate.getTime() < eventDate.getTime() - taperDays * 86400000) !== (candidate.getTime() < eventDate.getTime() - taperDays * 86400000))) continue;
   if (required.some((other) => other !== row && requiresRecoverySpacing(row, other) && Math.abs((mapping.get(other.scheduledDate.toISOString().slice(0, 10)) ?? other.scheduledDate).getTime() - candidate.getTime()) < 2 * 86400000)) continue;
   destination = candidate; occupied.add(day); break;
  }
  mapping.set(source, destination);
 }
 const movedSupportDays = new Set([...mapping.entries()].filter(([source, target]) => target && rows.some((row) => row.prescription.optional === true && row.scheduledDate.toISOString().slice(0, 10) === source)).map(([, date]) => date!.toISOString().slice(0, 10)));
 return rows.flatMap((row) => {
  const source = row.scheduledDate.toISOString().slice(0, 10);
  if (row.prescription.optional === true && !mapping.has(source) && movedSupportDays.has(source)) return [];
  if (!mapping.has(source)) return planDateExcluded(constraints, row.scheduledDate) ? [] : [row];
  const date = mapping.get(source); return date ? [{ ...row, scheduledDate: date }] : [];
 });
}
