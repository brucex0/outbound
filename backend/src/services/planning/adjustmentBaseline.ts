import { createHash } from "node:crypto";

/** Internal proposal fence over the exact current prescription, excluding volatile timestamps. */
export function adjustmentBaseline(workout: Record<string, any>): string {
  const fields = ["id", "planVersionId", "status", "title", "modality", "stimulus", "durationSeconds", "distanceMeters", "targetCalories", "intensityModel", "intensityTarget", "prescription", "isKeyWorkout"];
  const value = Object.fromEntries(fields.map((key) => [key, workout[key] ?? null]));
  value.blocks = (workout.blocks ?? []).map((block: any) => ({ sortOrder: block.sortOrder, blockType: block.blockType, modality: block.modality,
    stimulus: block.stimulus, durationSeconds: block.durationSeconds, distanceMeters: block.distanceMeters, repeats: block.repeats, restSeconds: block.restSeconds, metadata: block.metadata,
    steps: [...block.steps].sort((a: any, b: any) => a.sortOrder - b.sortOrder).map((step: any) => ({ sortOrder: step.sortOrder, label: step.label, kind: step.kind, durationSeconds: step.durationSeconds, distanceMeters: step.distanceMeters, target: step.target, detail: step.detail })) })).sort((a: any, b: any) => a.sortOrder - b.sortOrder);
  return createHash("sha256").update(JSON.stringify(stable(value))).digest("hex");
}
function stable(value: any): any {
  if (Array.isArray(value)) return value.map(stable);
  return value != null && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])])) : value;
}
