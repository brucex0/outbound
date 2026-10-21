// Deterministic completion work must finish before the request releases Cloud Run
// CPU, and must not depend on optional model analysis succeeding.
export async function completeActivity(tasks: {
  rebuildProfile: () => Promise<unknown>;
  enqueuePlanning: () => Promise<unknown>;
  analyze: () => Promise<unknown>;
}): Promise<void> {
  const operations = ["guide_profile_rebuild", "planning_enqueue"] as const;
  const results = await Promise.allSettled([
    Promise.resolve().then(tasks.rebuildProfile),
    Promise.resolve().then(tasks.enqueuePlanning),
  ]);
  results.forEach((result, index) => recordCompletion(operations[index], result));
  // Analysis is optional and remains best effort; its failure cannot skip the
  // profile or planning work and must not change the saved activity response.
  void Promise.resolve().then(tasks.analyze).then(
    () => recordCompletion("activity_analysis", { status: "fulfilled", value: undefined }),
    (reason: unknown) => recordCompletion("activity_analysis", { status: "rejected", reason })
  );
}

function recordCompletion(operation: string, result: PromiseSettledResult<unknown>): void {
  if (result.status === "fulfilled") {
    console.info("activity_completion_task", { operation, outcome: "success" });
    return;
  }
  const error: unknown = result.reason;
  const status = error instanceof Error && "status" in error && typeof error.status === "number" ? error.status : undefined;
  // Provider messages and Prisma error objects can contain private input.
  console.error("activity_completion_task", { operation, outcome: "failure", status,
    errorType: error instanceof Error ? error.name : "unknown" });
}
