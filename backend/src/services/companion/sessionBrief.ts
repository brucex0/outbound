import type { PrismaClient } from "@prisma/client";
import { loadAuthoritativeRunnerState } from "./domainToolGateway.js";

export async function buildSessionBrief(prisma: PrismaClient, userId: string, workoutId?: string) {
  const state = await loadAuthoritativeRunnerState(prisma, userId);
  const workout = workoutId
    ? state.nextWorkouts.find((candidate) => candidate.id === workoutId)
    : state.nextWorkouts[0];
  const beliefs = await prisma.runnerBelief.findMany({
    where: { userId, status: { in: ["confirmed", "hypothesis"] }, kind: { in: ["effort", "preference", "recovery"] } },
    orderBy: [{ consequenceLevel: "desc" }, { confidence: "desc" }],
    take: 6,
  });
  return {
    version: 1,
    runnerModelVersion: state.runnerModelVersion,
    workout: workout ? {
      id: workout.id,
      title: workout.title,
      purpose: workout.stimulus,
      durationSeconds: workout.durationSeconds,
      intensityTarget: workout.intensityTarget,
      prescription: workout.prescription,
    } : null,
    readiness: state.latestReadiness ? {
      choice: state.latestReadiness.choice,
      energy: state.latestReadiness.energy,
      soreness: state.latestReadiness.soreness,
      illnessOrPain: state.latestReadiness.illnessOrPain,
    } : null,
    coachingPriorities: beliefs.map((belief) => belief.summary).slice(0, 3),
    cuePreferences: beliefs.filter((belief) => belief.kind === "preference").map((belief) => belief.summary),
    forbiddenBehavior: [
      "Do not diagnose pain or symptoms.",
      "Do not encourage the runner to exceed the prescribed workout.",
      "Do not reveal private memory or location details aloud.",
    ],
  };
}

