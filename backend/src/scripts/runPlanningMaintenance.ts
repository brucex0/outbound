import { runPlanningMaintenance } from "../services/planning/maintenance.js";

try {
  const result = await runPlanningMaintenance();
  console.log(JSON.stringify({ status: "ok", ...result }));
} catch (error) {
  console.error("Planning maintenance failed", error);
  process.exitCode = 1;
}
