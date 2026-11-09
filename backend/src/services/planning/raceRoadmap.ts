/** Broad race progression is independent from the rolling detailed prescriptions. */
export function raceRoadmap(
  goal: { type: string; targetDate: Date | null; createdAt: Date }, currentPhase: string,
  workouts: { scheduledDate: Date; status: string }[],
) {
  if (goal.type !== "eventPreparation" || !goal.targetDate) return null;
  const event = new Date(goal.targetDate.toISOString().slice(0, 10));
  const started = new Date(goal.createdAt.toISOString().slice(0, 10));
  const phaseStarts = [
    { phase: "base", start: started, end: offset(event, -113) },
    { phase: "build", start: offset(event, -112), end: offset(event, -50) },
    { phase: "sharpen", start: offset(event, -49), end: offset(event, -22) },
    { phase: "taper", start: offset(event, -21), end: event },
  ];
  const planned = workouts.filter((workout) => workout.status === "planned");
  return {
    currentPhase,
    detailedFromDate: planned.length ? key(new Date(Math.min(...planned.map((workout) => workout.scheduledDate.getTime())))) : null,
    detailedThroughDate: planned.length ? key(new Date(Math.max(...planned.map((workout) => workout.scheduledDate.getTime())))) : null,
    phases: phaseStarts.filter((phase) => phase.end >= started).map((phase) => ({ phase: phase.phase, startDate: key(phase.start < started ? started : phase.start), endDate: key(phase.end) })),
  };
}
function offset(value: Date, days: number) { return new Date(value.getTime() + days * 86_400_000); }
function key(value: Date) { return value.toISOString().slice(0, 10); }
