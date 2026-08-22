export type StandaloneWorkoutCatalogItem = {
  id: string;
  title: string;
  subtitle: string;
  durationLabel: string;
  systemImage: string;
  sport: "run" | "bike";
  detail: string;
  guideLine: string;
  startLabel: string;
  targetDistanceMeters?: number;
  targetDurationSeconds?: number;
  steps: Array<{ id: string; label: string; durationSeconds: number; detail?: string }>;
};

export const standaloneWorkoutCatalog: StandaloneWorkoutCatalogItem[] = [
  {
    id: "standalone-guided-5k", title: "Guided 5K",
    subtitle: "A steady 5K with distance cues and calm guidance.",
    durationLabel: "5 km · Steady", systemImage: "5.circle.fill", sport: "run",
    detail: "Run · 5 km · steady effort",
    guideLine: "Settle in early, stay smooth through the middle, and finish with control.",
    startLabel: "Start Guided 5K", targetDistanceMeters: 5_000, steps: [],
  },
  {
    id: "standalone-guided-10k", title: "Guided 10K",
    subtitle: "Patient pacing and progress cues across 10K.",
    durationLabel: "10 km · Endurance", systemImage: "10.circle.fill", sport: "run",
    detail: "Run · 10 km · aerobic effort",
    guideLine: "Keep the first half patient and let your rhythm carry you home.",
    startLabel: "Start Guided 10K", targetDistanceMeters: 10_000, steps: [],
  },
  {
    id: "standalone-speed-run", title: "Speed Run",
    subtitle: "Four controlled fast repeats with full guidance.",
    durationLabel: "30 min · Intervals", systemImage: "hare.fill", sport: "run",
    detail: "Run · 30 min · 4 fast repeats",
    guideLine: "Run each fast repeat with control and use every recovery.",
    startLabel: "Start Speed Run", targetDurationSeconds: 30 * 60,
    steps: [
      { id: "standalone-speed-warmup", label: "Easy warmup", durationSeconds: 8 * 60, detail: "Relaxed conversational running" },
      { id: "standalone-speed-fast-1", label: "Fast repeat 1", durationSeconds: 2 * 60, detail: "Quick and controlled" },
      { id: "standalone-speed-recover-1", label: "Easy recovery 1", durationSeconds: 2 * 60, detail: "Jog or walk until settled" },
      { id: "standalone-speed-fast-2", label: "Fast repeat 2", durationSeconds: 2 * 60, detail: "Match the first repeat" },
      { id: "standalone-speed-recover-2", label: "Easy recovery 2", durationSeconds: 2 * 60, detail: "Let your breathing come down" },
      { id: "standalone-speed-fast-3", label: "Fast repeat 3", durationSeconds: 2 * 60, detail: "Stay tall and relaxed" },
      { id: "standalone-speed-recover-3", label: "Easy recovery 3", durationSeconds: 2 * 60, detail: "Easy jog" },
      { id: "standalone-speed-fast-4", label: "Fast repeat 4", durationSeconds: 2 * 60, detail: "Finish fast, not strained" },
      { id: "standalone-speed-cooldown", label: "Cooldown", durationSeconds: 8 * 60, detail: "Easy running or walking" },
    ],
  },
];
