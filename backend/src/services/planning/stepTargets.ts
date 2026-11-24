/** Normalize saved scalar effort without changing range targets or other coaching keys. */
export function normalizeStepTarget<T>(target: T): T {
  if (!target || typeof target !== "object" || Array.isArray(target)) return target;
  const value = target as Record<string, unknown>;
  if (typeof value.rpe !== "number" || !Number.isFinite(value.rpe)) return target;
  return { ...value, rpe: [value.rpe, value.rpe] } as T;
}

/** Apply at the shared planning response boundary, including retained historical workouts. */
export function normalizeWorkoutStepTargets<T extends { blocks: { steps: { target: unknown }[] }[] }>(workout: T): T {
  return { ...workout, blocks: workout.blocks.map((block) => ({ ...block,
    steps: block.steps.map((step) => ({ ...step, target: normalizeStepTarget(step.target) })),
  })) };
}
