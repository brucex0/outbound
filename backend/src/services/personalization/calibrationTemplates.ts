import type { CalibrationSessionKind } from "./contracts.js";

export type CalibrationWorkout = {
  id: string;
  kind: CalibrationSessionKind;
  title: string;
  purpose: string;
  durationSeconds: number;
  steps: Array<{ id: string; label: string; durationSeconds: number; detail: string }>;
};

export function calibrationWorkouts(comfortableMinutes = 30): CalibrationWorkout[] {
  const comfortable = clamp(comfortableMinutes, 20, 60);
  const longer = clamp(Math.round(comfortable * 1.25 / 5) * 5, comfortable + 5, 75);
  return [
    {
      id: "calibration-comfortable-run",
      kind: "comfortableRun",
      title: "Comfortable run",
      purpose: "Learn your natural easy effort without testing your speed.",
      durationSeconds: comfortable * 60,
      steps: threePartSteps(comfortable, "Run naturally", "Conversational effort"),
    },
    {
      id: "calibration-easy-pickups",
      kind: "easyPickups",
      title: "Easy + short pickups",
      purpose: "Observe controlled faster running without an all-out effort.",
      durationSeconds: comfortable * 60,
      steps: [
        { id: "warmup", label: "Easy warm-up", durationSeconds: 10 * 60, detail: "Conversational" },
        { id: "pickups", label: "4 relaxed pickups", durationSeconds: 8 * 60, detail: "20 seconds quicker, full easy recovery" },
        { id: "easy-finish", label: "Easy finish", durationSeconds: Math.max(5, comfortable - 18) * 60, detail: "Relaxed" },
      ],
    },
    {
      id: "calibration-longer-relaxed-run",
      kind: "longerRelaxedRun",
      title: "Longer relaxed run",
      purpose: "Learn sustainable endurance and recovery response.",
      durationSeconds: longer * 60,
      steps: threePartSteps(longer, "Relaxed running", "Keep enough reserve to continue"),
    },
  ];
}

function threePartSteps(totalMinutes: number, middleLabel: string, middleDetail: string) {
  return [
    { id: "settle", label: "Settle in", durationSeconds: 5 * 60, detail: "Very easy" },
    { id: "main", label: middleLabel, durationSeconds: Math.max(10, totalMinutes - 10) * 60, detail: middleDetail },
    { id: "finish", label: "Easy finish", durationSeconds: 5 * 60, detail: "Ease down" },
  ];
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}
