import { z } from "zod";

/** Capacity is distinct from completed weekly training. Never multiply these fields into load. */
export const intakeBaselineSchema = z.object({
  recentSessionsPerWeek: z.number().int().min(0).max(6),
  comfortableDurationMinutes: z.number().int().min(1).max(1440),
  recentWeeklyRunMinutes: z.number().int().min(1).max(6000).optional(),
  source: z.enum(["self_reported", "recent_activities"]),
}).strict().refine((value) => value.source !== "self_reported"
  || value.comfortableDurationMinutes >= 10 && value.comfortableDurationMinutes <= 180);

export type IntakeBaseline = z.infer<typeof intakeBaselineSchema>;

export function retainedIntakeBaseline(constraints?: Record<string, unknown>): IntakeBaseline | undefined {
  const parsed = intakeBaselineSchema.safeParse(constraints?.intakeBaseline);
  return parsed.success ? parsed.data : undefined;
}
