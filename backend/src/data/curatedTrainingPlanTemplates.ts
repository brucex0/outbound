import { trainingPlanTemplates as rawTrainingPlanTemplates } from "./trainingPlanTemplates.js";

type RawTemplate = Record<string, any>;
type RawWorkout = Record<string, any>;

const outboundPlanStandardsSource = {
  name: "Outbound plan standards",
  license: "Original",
  attribution: "Outbound-authored plans benchmarked against established road-running coaching patterns",
  url: "https://www.halhigdon.com/",
  importNotes:
    "Uses original Outbound workout tables shaped by common coaching conventions: mostly easy running, one controlled quality day, progressive long runs, cutback weeks, and a taper for race plans.",
};

const coachBuiltTemplateIds = new Set([
  "run-consistency-v1",
  "run-comeback-v1",
  "run-base-30-v1",
  "run-10k-v1",
  "run-10mile-v1",
  "run-half-v1",
]);

export const trainingPlanTemplates = [
  ...rawTrainingPlanTemplates.map(curateTemplate),
  marathonTemplate(),
];

function curateTemplate(template: RawTemplate): RawTemplate {
  const curated = structuredClone(template);
  if (coachBuiltTemplateIds.has(curated.id)) {
    curated.source = outboundPlanStandardsSource;
  }
  if (curated.id === "run-5k-v1") {
    curated.subtitle = "A nine-week run/walk progression for building up to continuous running.";
  }
  if (curated.id === "run-base-30-v1") {
    curated.subtitle =
      "A 10-week base phase built around general aerobic work, strides, threshold touches, and endurance long runs.";
  }

  curated.weeks = curated.weeks.map((week: RawTemplate) => ({
    ...week,
    summary: week.summary.replace("Imported base week", "Base week"),
    workouts: week.workouts.map(curateWorkout),
  }));

  if (curated.id === "run-10k-v1") {
    const week = curated.weeks.find((candidate: RawTemplate) => candidate.index === 7);
    const workout = week?.workouts.find((candidate: RawWorkout) => candidate.id === "10k-w7-q");
    if (week) {
      week.summary =
        "A classic 10K sharpening week with controlled intervals, easy mileage, and a long aerobic finish.";
    }
    if (workout) {
      workout.summary = "Specific 10K rhythm practice with full control.";
    }
  }

  return curated;
}

function curateWorkout(workout: RawWorkout): RawWorkout {
  const summary = String(workout.summary ?? "").toLowerCase();
  if (!summary.includes("rest or cross-train") && summary !== "rest") return workout;

  return {
    ...workout,
    title: "Rest day",
    purpose: "Absorb the week and protect the next real session.",
    coachCue: "Take the rest day seriously. Recovery is part of the plan.",
    effortLabel: "Rest",
    durationSeconds: 0,
    steps: [
      {
        id: `${workout.id}-main`,
        kind: "crossTrain",
        label: "Rest or light mobility",
        durationSeconds: 0,
        detail: "Take the day off, or keep movement short and restorative.",
      },
    ],
    isOptional: true,
  };
}

function marathonTemplate(): RawTemplate {
  const weeks = [
    marathonWeek(1, "marathon-w1", "Set the marathon rhythm", "Establish four steady run days without forcing pace.", 45, hillRun("marathon-w1-q", "Thu", 42, "Short hill repetitions to build durable mechanics.", "Run tall and keep every climb controlled.", 60, 90, 6), 50, 90),
    marathonWeek(2, "marathon-w2", "Build aerobic range", "A little more time on feet while the quality stays restrained.", 48, tempoRun("marathon-w2-q", "Thu", 48, "Two controlled tempo blocks inside a steady run.", "Stay below strain; marathon fitness is patient.", [600, 600], 180), 55, 100),
    marathonWeek(3, "marathon-w3", "Extend the long day", "Let the long run grow while weekday work remains manageable.", 50, fartlekRun("marathon-w3-q", "Thu", 50, "Relaxed surges that add range without track pressure.", "Keep the fast parts smooth enough to recover from.", 180, 150, 5), 60, 110),
    marathonWeek(4, "marathon-w4", "Cut back and absorb", "Reduce load so the next build has somewhere to go.", 40, racePrepRun("marathon-w4-q", "Thu", 34, "Light strides to keep the legs awake.", "Quick, relaxed, and done before it bites.", 45, 75, 5), 45, 85),
    marathonWeek(5, "marathon-w5", "Return to steady pressure", "Rebuild volume with a controlled threshold touch.", 52, tempoRun("marathon-w5-q", "Thu", 54, "Three tempo pieces with easy floats.", "You are practicing control, not proving speed.", [600, 600, 480], 120), 65, 120),
    marathonWeek(6, "marathon-w6", "Practice marathon effort", "Introduce marathon-effort rhythm while the long run grows.", 55, tempoRun("marathon-w6-q", "Thu", 58, "Sustained marathon-effort running with plenty of control.", "This should feel honest but repeatable.", [840, 720], 180), 68, 130),
    marathonWeek(7, "marathon-w7", "Build strength late", "A bigger endurance week with hills for strength instead of raw speed.", 55, hillRun("marathon-w7-q", "Thu", 48, "Moderate hill repetitions for strength under control.", "Powerful, not frantic.", 75, 105, 7), 70, 140),
    marathonWeek(8, "marathon-w8", "Second cutback", "Step down before the most specific part of the plan.", 44, easyRun("marathon-w8-q", "Thu", "Steady cutback run", 40, "A relaxed run with no hidden agenda.", "Let this week give something back."), 52, 100),
    marathonWeek(9, "marathon-w9", "Marathon-specific endurance", "The long run gets serious while midweek work stays measured.", 58, tempoRun("marathon-w9-q", "Thu", 60, "Long steady blocks near marathon effort.", "Settle into rhythm and leave ego out of it.", [960, 840], 180), 72, 150),
    marathonWeek(10, "marathon-w10", "Peak support week", "Use controlled quality to support the biggest long-run stretch.", 58, intervalRun("marathon-w10-q", "Thu", "5 x 5 min controlled reps", "Long controlled reps with easy recoveries.", "Smooth form matters more than pace.", 12, 10, 300, 150, 5), 75, 160),
    marathonWeek(11, "marathon-w11", "Absorb before peak", "A lighter long run keeps the block from getting brittle.", 48, racePrepRun("marathon-w11-q", "Thu", 38, "Short pickups to stay coordinated.", "Keep this light and clean.", 60, 90, 5), 60, 120),
    marathonWeek(12, "marathon-w12", "Peak long run", "The longest week asks for patience, fueling practice, and restraint.", 60, tempoRun("marathon-w12-q", "Thu", 56, "A final controlled marathon-effort touch.", "Stay economical; save the big swing for race day.", [1080, 600], 180), 75, 180),
    marathonWeek(13, "marathon-w13", "Begin the taper", "Keep rhythm while volume starts to come down.", 50, fartlekRun("marathon-w13-q", "Thu", 44, "Short relaxed surges for leg turnover.", "Freshness is the priority.", 90, 120, 6), 60, 135),
    marathonWeek(14, "marathon-w14", "Sharpen lightly", "Shorter sessions keep confidence high without adding fatigue.", 42, racePrepRun("marathon-w14-q", "Thu", 34, "Brief pickups with long easy floats.", "Light, quick, and under control.", 45, 90, 5), 48, 100),
    marathonWeek(15, "marathon-w15", "Protect freshness", "Race rhythm stays alive while the total load drops.", 34, racePrepRun("marathon-w15-q", "Thu", 28, "A short tune-up to keep the legs awake.", "Finish wanting more.", 30, 75, 4), 35, 65),
    marathonWeek(16, "marathon-w16", "Race week", "A calm final week that protects energy for the marathon.", 25, racePrepRun("marathon-w16-q", "Thu", 22, "Tiny tune-up with relaxed strides.", "Sharp, not tired.", 25, 75, 4), 18, 30, raceRun("marathon-w16-race", "Sun", "Marathon effort day", 260, "Race day or a supported marathon-distance effort.", "Start with restraint, fuel early, and let the back half come to you.")),
  ];

  return {
    id: "run-marathon-v1",
    focus: "marathon",
    sport: "run",
    title: "Marathon plan",
    subtitle: "A 16-week marathon build with patient mileage, cutback weeks, race-specific endurance, and a real taper.",
    defaultWeeks: 16,
    minSessionsPerWeek: 4,
    maxSessionsPerWeek: 5,
    baseWeeklyMinutes: 260,
    baseLongSessionMinutes: 100,
    summary:
      "A steady marathon block for runners who already have a running base and need long-run progression without turning every day hard.",
    highlights: [
      "Long runs progress in waves so adaptation has room to land.",
      "Midweek quality alternates hills, tempo, marathon-effort work, and light sharpening.",
      "Cutback weeks and a three-week taper protect freshness before race day.",
    ],
    source: outboundPlanStandardsSource,
    weeks,
  };
}

function marathonWeek(index: number, prefix: string, focus: string, summary: string, easyMinutes: number, quality: RawWorkout, mediumMinutes: number, longMinutes: number, raceDay?: RawWorkout): RawTemplate {
  const workouts = [
    easyRun(`${prefix}-easy`, "Tue", "Easy aerobic run", easyMinutes, "Steady conversational running.", "Keep this comfortably aerobic."),
    quality,
    longRun(`${prefix}-medium`, "Sat", mediumMinutes, "Medium-long support run.", "Treat this as endurance support, not a second race."),
    longRun(`${prefix}-long`, "Sun", longMinutes, "Key long run for marathon durability.", "Practice patience and fueling before you practice toughness."),
  ];
  if (raceDay) {
    workouts[2] = recoveryRun(`${prefix}-shakeout`, "Sat", Math.max(15, mediumMinutes), "Short shakeout before the event.", "Keep this tiny and confidence-building.", true);
    workouts[3] = raceDay;
  }
  return week(index, focus, summary, workouts, [
    "Do not stack missed weekday work onto the long run.",
    "Practice fueling on long runs once they pass 90 minutes.",
  ]);
}

function week(index: number, focus: string, summary: string, workouts: RawWorkout[], notes: string[]): RawTemplate {
  return {
    id: `week-${index}-${focus.toLowerCase().replaceAll(" ", "-")}`,
    index,
    focus,
    summary,
    workouts,
    notes,
  };
}

function easyRun(id: string, day: string, title: string, durationMinutes: number, summary: string, cue: string, optional = false): RawWorkout {
  return workout(id, title, "easy", day, summary, "Build aerobic support while keeping recovery intact.", cue, "Conversational", durationMinutes, [
    step(`${id}-warmup`, "warmup", "Warm up walk or jog", 300, "Ease into the session."),
    step(`${id}-main`, "steady", "Easy run", Math.max(1, durationMinutes - 10) * 60, "You should be able to speak in short sentences."),
    step(`${id}-cooldown`, "cooldown", "Cooldown walk", 300, "Let your breathing settle."),
  ], optional);
}

function recoveryRun(id: string, day: string, durationMinutes: number, summary: string, cue: string, optional = false): RawWorkout {
  return workout(id, "Recovery run", "recovery", day, summary, "Promote recovery while keeping the habit alive.", cue, "Very easy", durationMinutes, [
    step(`${id}-warmup`, "warmup", "Warm up walk", 240, "No rush."),
    step(`${id}-main`, "recovery", "Recovery jog", Math.max(1, durationMinutes - 8) * 60, "Stay well below strain."),
    step(`${id}-cooldown`, "cooldown", "Cooldown walk", 240, "Finish feeling refreshed."),
  ], optional);
}

function longRun(id: string, day: string, durationMinutes: number, summary: string, cue: string): RawWorkout {
  return workout(id, "Long run", "longRun", day, summary, "Build durable endurance with low drama and steady effort.", cue, "Easy-steady", durationMinutes, [
    step(`${id}-warmup`, "warmup", "Warm up jog", 480, "Start more gently than you think you need to."),
    step(`${id}-main`, "steady", "Long aerobic running", Math.max(1, durationMinutes - 16) * 60, "Stay under control for the whole middle."),
    step(`${id}-cooldown`, "cooldown", "Cooldown walk", 480, "Walk a bit before you stop completely."),
  ]);
}

function tempoRun(id: string, day: string, durationMinutes: number, summary: string, cue: string, blocks: number[], floatSeconds: number): RawWorkout {
  const steps = [step(`${id}-warmup`, "warmup", "Warm up jog", 600, "Keep this relaxed.")];
  blocks.forEach((block, index) => {
    steps.push(step(`${id}-tempo-${index}`, "tempo", `Tempo block ${index + 1}`, block, "Controlled discomfort."));
    if (index < blocks.length - 1) {
      steps.push(step(`${id}-float-${index}`, "recovery", "Easy float", floatSeconds, "Bring your breathing down before the next block."));
    }
  });
  steps.push(step(`${id}-cooldown`, "cooldown", "Cooldown jog", 480, "Let the effort taper off."));
  return workout(id, "Tempo run", "tempo", day, summary, "Raise your comfort with sustained work just under strain.", cue, "Comfortably hard", durationMinutes, steps);
}

function intervalRun(id: string, day: string, title: string, summary: string, cue: string, warmupMinutes: number, cooldownMinutes: number, hardSeconds: number, easySeconds: number, repeats: number): RawWorkout {
  const steps = [step(`${id}-warmup`, "warmup", "Warm up jog", warmupMinutes * 60, "Ease into the session.")];
  for (let rep = 1; rep <= repeats; rep += 1) {
    steps.push(step(`${id}-hard-${rep}`, "interval", `Hard rep ${rep}`, hardSeconds, "Quick but controlled."));
    if (rep < repeats) steps.push(step(`${id}-easy-${rep}`, "recovery", "Easy recovery", easySeconds, "Walk or jog until you feel ready again."));
  }
  steps.push(step(`${id}-cooldown`, "cooldown", "Cooldown jog", cooldownMinutes * 60, "Bring things back down slowly."));
  const durationMinutes = Math.ceil(steps.reduce((sum, item) => sum + item.durationSeconds, 0) / 60);
  return workout(id, title, "interval", day, summary, "Build speed support without losing control of the week.", cue, "10K effort", durationMinutes, steps);
}

function fartlekRun(id: string, day: string, durationMinutes: number, summary: string, cue: string, hardSeconds: number, easySeconds: number, repeats: number): RawWorkout {
  const steps = [step(`${id}-warmup`, "warmup", "Warm up jog", 480, "Start relaxed.")];
  for (let rep = 1; rep <= repeats; rep += 1) {
    steps.push(step(`${id}-surge-${rep}`, "steady", `Surge ${rep}`, hardSeconds, "Run by feel, not by force."));
    steps.push(step(`${id}-float-${rep}`, "recovery", "Easy float", easySeconds, "Recover while still moving."));
  }
  steps.push(step(`${id}-cooldown`, "cooldown", "Cooldown jog", 360, "Let your breathing settle."));
  return workout(id, "Fartlek run", "fartlek", day, summary, "Practice changing gears without the rigidity of track intervals.", cue, "Playful steady", durationMinutes, steps);
}

function hillRun(id: string, day: string, durationMinutes: number, summary: string, cue: string, hardSeconds: number, easySeconds: number, repeats: number): RawWorkout {
  const steps = [step(`${id}-warmup`, "warmup", "Warm up jog", 600, "Find a smooth hill.")];
  for (let rep = 1; rep <= repeats; rep += 1) {
    steps.push(step(`${id}-hill-${rep}`, "interval", `Hill rep ${rep}`, hardSeconds, "Short, tall, and powerful."));
    steps.push(step(`${id}-recover-${rep}`, "recovery", "Walk back recovery", easySeconds, "Reset fully before the next climb."));
  }
  steps.push(step(`${id}-cooldown`, "cooldown", "Cooldown jog", 480, "Shake the legs out."));
  return workout(id, "Hill session", "hill", day, summary, "Build strength and mechanics with lower top-end speed.", cue, "Strong but controlled", durationMinutes, steps);
}

function racePrepRun(id: string, day: string, durationMinutes: number, summary: string, cue: string, pickupSeconds: number, floatSeconds: number, repeats: number): RawWorkout {
  const steps = [step(`${id}-warmup`, "warmup", "Warm up jog", 480, "Stay relaxed.")];
  for (let rep = 1; rep <= repeats; rep += 1) {
    steps.push(step(`${id}-pickup-${rep}`, "interval", `Pickup ${rep}`, pickupSeconds, "Quick, light, and under control."));
    if (rep < repeats) steps.push(step(`${id}-float-${rep}`, "recovery", "Easy float", floatSeconds, "Reset before the next pickup."));
  }
  steps.push(step(`${id}-cooldown`, "cooldown", "Cooldown jog", 360, "Keep this short and easy."));
  return workout(id, "Race-prep run", "racePrep", day, summary, "Stay sharp while protecting freshness.", cue, "Light and snappy", durationMinutes, steps);
}

function raceRun(id: string, day: string, title: string, durationMinutes: number, summary: string, cue: string): RawWorkout {
  return workout(id, title, "race", day, summary, "Express the work with patience early and intent late.", cue, "Race effort", durationMinutes, [
    step(`${id}-warmup`, "warmup", "Warm up jog", 600, "Stay loose and calm."),
    step(`${id}-race`, "race", "Main effort", Math.max(1, durationMinutes - 20) * 60, "Start controlled, then build into the second half."),
    step(`${id}-cooldown`, "cooldown", "Cooldown walk", 600, "Let the effort taper fully."),
  ]);
}

function workout(id: string, title: string, kind: string, dayLabel: string, summary: string, purpose: string, coachCue: string, effortLabel: string, durationMinutes: number, steps: RawTemplate[], isOptional = false): RawWorkout {
  return {
    id,
    title,
    kind,
    dayLabel,
    summary,
    purpose,
    coachCue,
    effortLabel,
    durationSeconds: durationMinutes * 60,
    distanceLabel: null,
    steps,
    isOptional,
  };
}

function step(id: string, kind: string, label: string, durationSeconds: number, detail: string): RawTemplate {
  return { id, kind, label, durationSeconds, detail };
}
