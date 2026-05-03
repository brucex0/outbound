// @ts-nocheck
export const trainingPlanTemplates = [
  {
    "baseLongSessionMinutes" : 65,
    "baseWeeklyMinutes" : 150,
    "defaultWeeks" : 10,
    "focus" : "consistency",
    "highlights" : [
      "General aerobic days do most of the work.",
      "Threshold sessions arrive only after the base is established.",
      "Strides and endurance runs add range without constant hard workouts."
    ],
    "id" : "run-base-30-v1",
    "maxSessionsPerWeek" : 4,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Cody Hoover's time-to-run built-in plan library",
      "importNotes" : "Imported from the open-source `src/workouts/plans` built-in plans and translated into Outbound's structured week and workout model.",
      "license" : "MIT",
      "name" : "time-to-run",
      "url" : "https://github.com/hoovercj/time-to-run"
    },
    "sport" : "run",
    "subtitle" : "A 10-week imported base phase built around general aerobic work, strides, threshold touches, and endurance long runs.",
    "summary" : "A realistic base cycle for runners who want durable weekly rhythm before chasing a sharper race block.",
    "title" : "Base building 30 mpw",
    "weeks" : [
      {
        "focus" : "Build aerobic durability",
        "id" : "week-1-build-aerobic-durability",
        "index" : 1,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 1 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w1-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w1-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w1-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w1-d2-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w1-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w1-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "base30-w1-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "base30-w1-d4-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "base30-w1-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "base30-w1-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w1-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w1-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w1-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w1-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w1-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 2820,
                "id" : "base30-w1-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 6 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w1-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 6 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-2-build-aerobic-durability",
        "index" : 2,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 2 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w2-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w2-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w2-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w2-d2-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w2-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w2-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w2-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w2-d4-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "base30-w2-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "base30-w2-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w2-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w2-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w2-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w2-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w2-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 3450,
                "id" : "base30-w2-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 7 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w2-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 7 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-3-build-aerobic-durability",
        "index" : 3,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 3 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w3-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w3-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w3-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w3-d2-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w3-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w3-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w3-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w3-d4-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "base30-w3-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "base30-w3-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w3-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w3-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w3-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w3-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w3-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 3450,
                "id" : "base30-w3-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 7 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w3-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 7 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-4-build-aerobic-durability",
        "index" : 4,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 4 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w4-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w4-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w4-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w4-d2-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w4-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w4-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Stay easy on the run and keep the strides crisp, not exhausting.",
            "dayLabel" : "Thu",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Easy with pop",
            "id" : "base30-w4-d4",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Finish with a few quick relaxed strides.",
                "durationSeconds" : 2550,
                "id" : "base30-w4-d4-main",
                "kind" : "steady",
                "label" : "Easy run with strides 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 5 miles w/ 6x100m strides",
            "title" : "Easy run with strides"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w4-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w4-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w4-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w4-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w4-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w4-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w4-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 3450,
                "id" : "base30-w4-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 7 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w4-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 7 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-5-build-aerobic-durability",
        "index" : 5,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 5 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w5-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w5-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "base30-w5-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w5-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "base30-w5-d2-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w5-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w5-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w5-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "This should feel controlled, not desperate.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Comfortably hard",
            "id" : "base30-w5-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice sustained work just under red-line effort.",
            "steps" : [
              {
                "detail" : "Ease in gently.",
                "durationSeconds" : 600,
                "id" : "base30-w5-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay smooth through the middle.",
                "durationSeconds" : 2700,
                "id" : "base30-w5-d4-main",
                "kind" : "tempo",
                "label" : "Lactate threshold 6 miles w/ 16 min tempo"
              },
              {
                "detail" : "Bring your breathing back down.",
                "durationSeconds" : 480,
                "id" : "base30-w5-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Lactate threshold 6 miles w/ 16 min tempo",
            "title" : "Threshold run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w5-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w5-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w5-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w5-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w5-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w5-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w5-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w5-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4080,
                "id" : "base30-w5-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 8 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w5-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 8 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-6-build-aerobic-durability",
        "index" : 6,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 6 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w6-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w6-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "base30-w6-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "base30-w6-d2-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w6-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w6-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Stay easy on the run and keep the strides crisp, not exhausting.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Easy with pop",
            "id" : "base30-w6-d4",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Finish with a few quick relaxed strides.",
                "durationSeconds" : 3180,
                "id" : "base30-w6-d4-main",
                "kind" : "steady",
                "label" : "Easy run with strides 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles w/ 6x100m strides",
            "title" : "Easy run with strides"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "base30-w6-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "base30-w6-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w6-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w6-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w6-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w6-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w6-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4080,
                "id" : "base30-w6-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 8 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w6-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 8 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-7-build-aerobic-durability",
        "index" : 7,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 7 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w7-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w7-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w7-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w7-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w7-d2-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w7-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w7-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w7-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "This should feel controlled, not desperate.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Comfortably hard",
            "id" : "base30-w7-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice sustained work just under red-line effort.",
            "steps" : [
              {
                "detail" : "Ease in gently.",
                "durationSeconds" : 600,
                "id" : "base30-w7-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay smooth through the middle.",
                "durationSeconds" : 2700,
                "id" : "base30-w7-d4-main",
                "kind" : "tempo",
                "label" : "Lactate threshold 6 miles w/ 18 min tempo"
              },
              {
                "detail" : "Bring your breathing back down.",
                "durationSeconds" : 480,
                "id" : "base30-w7-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Lactate threshold 6 miles w/ 18 min tempo",
            "title" : "Threshold run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "base30-w7-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w7-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "base30-w7-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w7-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w7-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w7-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w7-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w7-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4080,
                "id" : "base30-w7-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 8 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w7-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 8 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-8-build-aerobic-durability",
        "index" : 8,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 8 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w8-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w8-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w8-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w8-d2-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w8-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w8-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Stay easy on the run and keep the strides crisp, not exhausting.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Easy with pop",
            "id" : "base30-w8-d4",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Finish with a few quick relaxed strides.",
                "durationSeconds" : 3810,
                "id" : "base30-w8-d4-main",
                "kind" : "steady",
                "label" : "Easy run with strides 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 7 miles w/ 6x100m strides",
            "title" : "Easy run with strides"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w8-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w8-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w8-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w8-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w8-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w8-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w8-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4710,
                "id" : "base30-w8-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 9 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w8-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 9 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-9-build-aerobic-durability",
        "index" : 9,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 9 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w9-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w9-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w9-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w9-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w9-d2-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w9-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w9-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w9-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "This should feel controlled, not desperate.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Comfortably hard",
            "id" : "base30-w9-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice sustained work just under red-line effort.",
            "steps" : [
              {
                "detail" : "Ease in gently.",
                "durationSeconds" : 600,
                "id" : "base30-w9-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay smooth through the middle.",
                "durationSeconds" : 3330,
                "id" : "base30-w9-d4-main",
                "kind" : "tempo",
                "label" : "Lactate threshold 7 miles w/ 20 min tempo"
              },
              {
                "detail" : "Bring your breathing back down.",
                "durationSeconds" : 480,
                "id" : "base30-w9-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Lactate threshold 7 miles w/ 20 min tempo",
            "title" : "Threshold run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w9-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w9-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w9-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w9-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w9-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w9-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w9-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w9-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4710,
                "id" : "base30-w9-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 9 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w9-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 9 miles",
            "title" : "Endurance run"
          }
        ]
      },
      {
        "focus" : "Build aerobic durability",
        "id" : "week-10-build-aerobic-durability",
        "index" : 10,
        "notes" : [
          "Treat cross-training days as optional support unless your body benefits from the extra movement."
        ],
        "summary" : "Imported base week 10 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w10-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w10-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "base30-w10-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "base30-w10-d2-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 7 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w10-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w10-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Stay easy on the run and keep the strides crisp, not exhausting.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Easy with pop",
            "id" : "base30-w10-d4",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Finish with a few quick relaxed strides.",
                "durationSeconds" : 4440,
                "id" : "base30-w10-d4-main",
                "kind" : "steady",
                "label" : "Easy run with strides 8 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 8 miles w/ 8x100m strides",
            "title" : "Easy run with strides"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "base30-w10-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "base30-w10-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "base30-w10-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "General aerobic 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "base30-w10-d6",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "base30-w10-d6-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or cross-training",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Easy-steady",
            "id" : "base30-w10-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "base30-w10-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4710,
                "id" : "base30-w10-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 9 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "base30-w10-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Endurance 9 miles",
            "title" : "Endurance run"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 35,
    "baseWeeklyMinutes" : 80,
    "defaultWeeks" : 4,
    "focus" : "consistency",
    "highlights" : [
      "Two easy aerobic runs anchor the week.",
      "A short quality touch keeps things interesting without dominating the schedule.",
      "One optional session gives flexibility instead of guilt."
    ],
    "id" : "run-consistency-v1",
    "maxSessionsPerWeek" : 4,
    "minSessionsPerWeek" : 2,
    "source" : {
      "attribution" : "Daniel Coats's training-planner sample workout taxonomy",
      "importNotes" : "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials.",
      "license" : "MIT",
      "name" : "training-planner",
      "url" : "https://github.com/danielcoats/training-planner"
    },
    "sport" : "run",
    "subtitle" : "A realistic rhythm for showing up without race pressure.",
    "summary" : "Three manageable sessions each week with one optional extra so consistency can survive normal life.",
    "title" : "Consistency builder",
    "weeks" : [
      {
        "focus" : "Find a repeatable rhythm",
        "id" : "week-1-find-a-repeatable-rhythm",
        "index" : 1,
        "notes" : [
          "Missing one run is not failure. Just return to the next planned session."
        ],
        "summary" : "Start with repeatable sessions that feel almost too manageable.",
        "workouts" : [
          {
            "coachCue" : "If this feels easy, that's a good sign.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1500,
            "effortLabel" : "Conversational",
            "id" : "consistency-w1-1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "consistency-w1-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 900,
                "id" : "consistency-w1-1-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "consistency-w1-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Simple conversational running.",
            "title" : "Easy start run"
          },
          {
            "coachCue" : "Float the quicker bits; don't turn them into sprints.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1680,
            "effortLabel" : "Playful steady",
            "id" : "consistency-w1-2",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "consistency-w1-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 60,
                "id" : "consistency-w1-2-surge-6",
                "kind" : "steady",
                "label" : "Surge 6"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "consistency-w1-2-float-6",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "consistency-w1-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Light variation to break up the week.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "Finish with the same calm pace you started with.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy-steady",
            "id" : "consistency-w1-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "consistency-w1-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 1140,
                "id" : "consistency-w1-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "consistency-w1-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Gentle endurance support.",
            "title" : "Long run"
          },
          {
            "coachCue" : "Choose something that opens you up, not something that buries you.",
            "dayLabel" : "Sun",
            "durationSeconds" : 1500,
            "effortLabel" : "Easy",
            "id" : "consistency-w1-4",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 1500,
                "id" : "consistency-w1-4-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional recovery movement.",
            "title" : "Cross-train"
          }
        ]
      },
      {
        "focus" : "Add one small stretch",
        "id" : "week-2-add-one-small-stretch",
        "index" : 2,
        "notes" : [
          "If life gets noisy this week, keep the easy run and the long run."
        ],
        "summary" : "Keep the structure familiar while nudging one session slightly longer.",
        "workouts" : [
          {
            "coachCue" : "This is habit work.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1680,
            "effortLabel" : "Conversational",
            "id" : "consistency-w2-1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "consistency-w2-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1080,
                "id" : "consistency-w2-1-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "consistency-w2-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady and unremarkable on purpose.",
            "title" : "Easy rhythm run"
          },
          {
            "coachCue" : "Run tall and keep the recoveries patient.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1800,
            "effortLabel" : "Strong but controlled",
            "id" : "consistency-w2-2",
            "isOptional" : false,
            "kind" : "hill",
            "purpose" : "Build strength and mechanics with lower top-end speed.",
            "steps" : [
              {
                "detail" : "Find a smooth hill.",
                "durationSeconds" : 600,
                "id" : "consistency-w2-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-1",
                "kind" : "interval",
                "label" : "Hill rep 1"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-1",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-2",
                "kind" : "interval",
                "label" : "Hill rep 2"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-2",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-3",
                "kind" : "interval",
                "label" : "Hill rep 3"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-3",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-4",
                "kind" : "interval",
                "label" : "Hill rep 4"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-4",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-5",
                "kind" : "interval",
                "label" : "Hill rep 5"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-5",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "consistency-w2-2-hill-6",
                "kind" : "interval",
                "label" : "Hill rep 6"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "consistency-w2-2-recover-6",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Shake the legs out.",
                "durationSeconds" : 480,
                "id" : "consistency-w2-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Short controlled hill efforts.",
            "title" : "Hill session"
          },
          {
            "coachCue" : "Let the run stay chatty from start to finish.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2400,
            "effortLabel" : "Easy-steady",
            "id" : "consistency-w2-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "consistency-w2-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 1440,
                "id" : "consistency-w2-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "consistency-w2-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Longer aerobic support.",
            "title" : "Long run"
          },
          {
            "coachCue" : "Optional really means optional.",
            "dayLabel" : "Sun",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy",
            "id" : "consistency-w2-4",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 1800,
                "id" : "consistency-w2-4-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional bike, walk, or mobility.",
            "title" : "Cross-train"
          }
        ]
      },
      {
        "focus" : "Protect momentum",
        "id" : "week-3-protect-momentum",
        "index" : 3,
        "notes" : [
          "Cut the optional day first if recovery feels off."
        ],
        "summary" : "The plan now feels familiar, so the priority is protecting the routine.",
        "workouts" : [
          {
            "coachCue" : "Keep the effort low enough to recover fast.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Conversational",
            "id" : "consistency-w3-1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "consistency-w3-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1200,
                "id" : "consistency-w3-1-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "consistency-w3-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Settle into a natural cadence.",
            "title" : "Easy support run"
          },
          {
            "coachCue" : "Comfortably hard beats dramatic.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1920,
            "effortLabel" : "Comfortably hard",
            "id" : "consistency-w3-2",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "consistency-w3-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 360,
                "id" : "consistency-w3-2-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "consistency-w3-2-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 360,
                "id" : "consistency-w3-2-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "consistency-w3-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Controlled steady work just under strain.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "This one should build calm confidence.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2520,
            "effortLabel" : "Easy-steady",
            "id" : "consistency-w3-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "consistency-w3-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 1560,
                "id" : "consistency-w3-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "consistency-w3-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A patient aerobic finish to the week.",
            "title" : "Long run"
          },
          {
            "coachCue" : "Only do this if your legs want it.",
            "dayLabel" : "Sun",
            "durationSeconds" : 1200,
            "effortLabel" : "Very easy",
            "id" : "consistency-w3-4",
            "isOptional" : true,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "consistency-w3-4-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 720,
                "id" : "consistency-w3-4-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "consistency-w3-4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Optional shuffle to stay loose.",
            "title" : "Recovery run"
          }
        ]
      },
      {
        "focus" : "Land the block feeling better",
        "id" : "week-4-land-the-block-feeling-better",
        "index" : 4,
        "notes" : [
          "A good cutback week should make you want the next block."
        ],
        "summary" : "A cutback week that still keeps the routine intact.",
        "workouts" : [
          {
            "coachCue" : "Less is more this week.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1440,
            "effortLabel" : "Conversational",
            "id" : "consistency-w4-1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "consistency-w4-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 840,
                "id" : "consistency-w4-1-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "consistency-w4-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Shorter on purpose.",
            "title" : "Easy cutback run"
          },
          {
            "coachCue" : "Stay loose; the goal is pop, not fatigue.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1440,
            "effortLabel" : "Playful steady",
            "id" : "consistency-w4-2",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "consistency-w4-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "consistency-w4-2-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 75,
                "id" : "consistency-w4-2-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "consistency-w4-2-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 75,
                "id" : "consistency-w4-2-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "consistency-w4-2-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 75,
                "id" : "consistency-w4-2-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "consistency-w4-2-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 75,
                "id" : "consistency-w4-2-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "consistency-w4-2-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 75,
                "id" : "consistency-w4-2-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "consistency-w4-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "A playful tune-up.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "End with plenty left.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1920,
            "effortLabel" : "Easy-steady",
            "id" : "consistency-w4-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "consistency-w4-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 960,
                "id" : "consistency-w4-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "consistency-w4-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A shorter long run to bank freshness.",
            "title" : "Long run"
          },
          {
            "coachCue" : "Use this to reset, not to chase numbers.",
            "dayLabel" : "Sun",
            "durationSeconds" : 1500,
            "effortLabel" : "Easy",
            "id" : "consistency-w4-4",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 1500,
                "id" : "consistency-w4-4-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional easy spin or walk.",
            "title" : "Cross-train"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 28,
    "baseWeeklyMinutes" : 55,
    "defaultWeeks" : 4,
    "focus" : "comeback",
    "highlights" : [
      "Walk-run ratios keep impact low while routine comes back.",
      "Rest days are part of the design, not evidence of weakness.",
      "The final week leaves enough headroom to continue instead of crash."
    ],
    "id" : "run-comeback-v1",
    "maxSessionsPerWeek" : 3,
    "minSessionsPerWeek" : 2,
    "source" : {
      "attribution" : "Daniel Coats's training-planner sample workout taxonomy",
      "importNotes" : "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials.",
      "license" : "MIT",
      "name" : "training-planner",
      "url" : "https://github.com/danielcoats/training-planner"
    },
    "sport" : "run",
    "subtitle" : "A soft return to structure after a gap or rough patch.",
    "summary" : "Walk-run sessions progress gently, with enough recovery built in that restarting feels doable instead of scary.",
    "title" : "Comeback runway",
    "weeks" : [
      {
        "focus" : "Reconnect with the routine",
        "id" : "week-1-reconnect-with-the-routine",
        "index" : 1,
        "notes" : [
          "If any run segment feels sticky, switch the whole session to brisk walking."
        ],
        "summary" : "Short sessions designed to feel safe and finish strong.",
        "workouts" : [
          {
            "coachCue" : "The win is simply getting moving again.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1500,
            "effortLabel" : "Gentle",
            "id" : "comeback-w1-1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Rebuild impact tolerance and confidence with controlled run segments.",
            "steps" : [
              {
                "detail" : "Get loose before the first run segment.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-1",
                "kind" : "run",
                "label" : "Run 1"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-1",
                "kind" : "walk",
                "label" : "Walk 1"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-2",
                "kind" : "run",
                "label" : "Run 2"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-2",
                "kind" : "walk",
                "label" : "Walk 2"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-3",
                "kind" : "run",
                "label" : "Run 3"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-3",
                "kind" : "walk",
                "label" : "Walk 3"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-4",
                "kind" : "run",
                "label" : "Run 4"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-4",
                "kind" : "walk",
                "label" : "Walk 4"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-5",
                "kind" : "run",
                "label" : "Run 5"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-5",
                "kind" : "walk",
                "label" : "Walk 5"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-1-run-6",
                "kind" : "run",
                "label" : "Run 6"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-1-walk-6",
                "kind" : "walk",
                "label" : "Walk 6"
              },
              {
                "detail" : "Let the session settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "One-minute run / 90-second walk rhythm.",
            "title" : "Restart session"
          },
          {
            "coachCue" : "Keep the runs gentle enough to finish calm.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1650,
            "effortLabel" : "Gentle",
            "id" : "comeback-w1-2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Rebuild impact tolerance and confidence with controlled run segments.",
            "steps" : [
              {
                "detail" : "Get loose before the first run segment.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-1",
                "kind" : "run",
                "label" : "Run 1"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-1",
                "kind" : "walk",
                "label" : "Walk 1"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-2",
                "kind" : "run",
                "label" : "Run 2"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-2",
                "kind" : "walk",
                "label" : "Walk 2"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-3",
                "kind" : "run",
                "label" : "Run 3"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-3",
                "kind" : "walk",
                "label" : "Walk 3"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-4",
                "kind" : "run",
                "label" : "Run 4"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-4",
                "kind" : "walk",
                "label" : "Walk 4"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-5",
                "kind" : "run",
                "label" : "Run 5"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-5",
                "kind" : "walk",
                "label" : "Walk 5"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-6",
                "kind" : "run",
                "label" : "Run 6"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-6",
                "kind" : "walk",
                "label" : "Walk 6"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 60,
                "id" : "comeback-w1-2-run-7",
                "kind" : "run",
                "label" : "Run 7"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w1-2-walk-7",
                "kind" : "walk",
                "label" : "Walk 7"
              },
              {
                "detail" : "Let the session settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Same rhythm with a touch more time.",
            "title" : "Repeatable return"
          },
          {
            "coachCue" : "No catching up. Just collect time on feet.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1500,
            "effortLabel" : "Conversational",
            "id" : "comeback-w1-3",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 900,
                "id" : "comeback-w1-3-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w1-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Choose the easiest version that feels inviting.",
            "title" : "Long easy walk or jog"
          }
        ]
      },
      {
        "focus" : "Lengthen carefully",
        "id" : "week-2-lengthen-carefully",
        "index" : 2,
        "notes" : [
          "This is still a restart block. Err on the side of too easy."
        ],
        "summary" : "The run segments get a little longer, but recovery still leads.",
        "workouts" : [
          {
            "coachCue" : "Keep every run segment at easy effort.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1860,
            "effortLabel" : "Gentle",
            "id" : "comeback-w2-1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Rebuild impact tolerance and confidence with controlled run segments.",
            "steps" : [
              {
                "detail" : "Get loose before the first run segment.",
                "durationSeconds" : 300,
                "id" : "comeback-w2-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-1",
                "kind" : "run",
                "label" : "Run 1"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-1",
                "kind" : "walk",
                "label" : "Walk 1"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-2",
                "kind" : "run",
                "label" : "Run 2"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-2",
                "kind" : "walk",
                "label" : "Walk 2"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-3",
                "kind" : "run",
                "label" : "Run 3"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-3",
                "kind" : "walk",
                "label" : "Walk 3"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-4",
                "kind" : "run",
                "label" : "Run 4"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-4",
                "kind" : "walk",
                "label" : "Walk 4"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-5",
                "kind" : "run",
                "label" : "Run 5"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-5",
                "kind" : "walk",
                "label" : "Walk 5"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-6",
                "kind" : "run",
                "label" : "Run 6"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-6",
                "kind" : "walk",
                "label" : "Walk 6"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-run-7",
                "kind" : "run",
                "label" : "Run 7"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-1-walk-7",
                "kind" : "walk",
                "label" : "Walk 7"
              },
              {
                "detail" : "Let the session settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w2-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "90-second run / 90-second walk.",
            "title" : "Run-walk build"
          },
          {
            "coachCue" : "Take the easiest line that keeps momentum.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1080,
            "effortLabel" : "Very easy",
            "id" : "comeback-w2-2",
            "isOptional" : false,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "comeback-w2-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 600,
                "id" : "comeback-w2-2-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "comeback-w2-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A soft shuffle or brisk walk.",
            "title" : "Recovery run"
          },
          {
            "coachCue" : "Don't rush the first half.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2070,
            "effortLabel" : "Gentle",
            "id" : "comeback-w2-3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Rebuild impact tolerance and confidence with controlled run segments.",
            "steps" : [
              {
                "detail" : "Get loose before the first run segment.",
                "durationSeconds" : 300,
                "id" : "comeback-w2-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-1",
                "kind" : "run",
                "label" : "Run 1"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-1",
                "kind" : "walk",
                "label" : "Walk 1"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-2",
                "kind" : "run",
                "label" : "Run 2"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-2",
                "kind" : "walk",
                "label" : "Walk 2"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-3",
                "kind" : "run",
                "label" : "Run 3"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-3",
                "kind" : "walk",
                "label" : "Walk 3"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-4",
                "kind" : "run",
                "label" : "Run 4"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-4",
                "kind" : "walk",
                "label" : "Walk 4"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-5",
                "kind" : "run",
                "label" : "Run 5"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-5",
                "kind" : "walk",
                "label" : "Walk 5"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-6",
                "kind" : "run",
                "label" : "Run 6"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-6",
                "kind" : "walk",
                "label" : "Walk 6"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 120,
                "id" : "comeback-w2-3-run-7",
                "kind" : "run",
                "label" : "Run 7"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w2-3-walk-7",
                "kind" : "walk",
                "label" : "Walk 7"
              },
              {
                "detail" : "Let the session settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w2-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Two-minute run / 90-second walk.",
            "title" : "Confidence session"
          }
        ]
      },
      {
        "focus" : "Blend into steady running",
        "id" : "week-3-blend-into-steady-running",
        "index" : 3,
        "notes" : [
          "If Thursday feels forced, convert it back into a walk-run."
        ],
        "summary" : "The walks shrink and the running begins to connect.",
        "workouts" : [
          {
            "coachCue" : "Run smooth rather than ambitious.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1950,
            "effortLabel" : "Gentle",
            "id" : "comeback-w3-1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Rebuild impact tolerance and confidence with controlled run segments.",
            "steps" : [
              {
                "detail" : "Get loose before the first run segment.",
                "durationSeconds" : 300,
                "id" : "comeback-w3-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 180,
                "id" : "comeback-w3-1-run-1",
                "kind" : "run",
                "label" : "Run 1"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w3-1-walk-1",
                "kind" : "walk",
                "label" : "Walk 1"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 180,
                "id" : "comeback-w3-1-run-2",
                "kind" : "run",
                "label" : "Run 2"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w3-1-walk-2",
                "kind" : "walk",
                "label" : "Walk 2"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 180,
                "id" : "comeback-w3-1-run-3",
                "kind" : "run",
                "label" : "Run 3"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w3-1-walk-3",
                "kind" : "walk",
                "label" : "Walk 3"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 180,
                "id" : "comeback-w3-1-run-4",
                "kind" : "run",
                "label" : "Run 4"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w3-1-walk-4",
                "kind" : "walk",
                "label" : "Walk 4"
              },
              {
                "detail" : "Relax the pace.",
                "durationSeconds" : 180,
                "id" : "comeback-w3-1-run-5",
                "kind" : "run",
                "label" : "Run 5"
              },
              {
                "detail" : "Recover fully.",
                "durationSeconds" : 90,
                "id" : "comeback-w3-1-walk-5",
                "kind" : "walk",
                "label" : "Walk 5"
              },
              {
                "detail" : "Let the session settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w3-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three-minute run / 90-second walk.",
            "title" : "Connected effort"
          },
          {
            "coachCue" : "A tiny continuous run is enough.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1200,
            "effortLabel" : "Conversational",
            "id" : "comeback-w3-2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "comeback-w3-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 600,
                "id" : "comeback-w3-2-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w3-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Run easy the whole way if you can, or insert walks as needed.",
            "title" : "Easy continuous run"
          },
          {
            "coachCue" : "Keep the final ten minutes especially controlled.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy-steady",
            "id" : "comeback-w3-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "comeback-w3-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 840,
                "id" : "comeback-w3-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "comeback-w3-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy endurance on forgiving effort.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Finish wanting more",
        "id" : "week-4-finish-wanting-more",
        "index" : 4,
        "notes" : [
          "This block is successful if it makes the next month feel possible."
        ],
        "summary" : "A calm finish that sets up the next block rather than exhausting you.",
        "workouts" : [
          {
            "coachCue" : "Stay within yourself.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1320,
            "effortLabel" : "Conversational",
            "id" : "comeback-w4-1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "comeback-w4-1-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 720,
                "id" : "comeback-w4-1-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "comeback-w4-1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Simple continuous running.",
            "title" : "Easy confidence run"
          },
          {
            "coachCue" : "The quicker segments should feel playful.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1440,
            "effortLabel" : "Playful steady",
            "id" : "comeback-w4-2",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "comeback-w4-2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "comeback-w4-2-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "comeback-w4-2-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "comeback-w4-2-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "comeback-w4-2-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "comeback-w4-2-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "comeback-w4-2-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "comeback-w4-2-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "comeback-w4-2-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 45,
                "id" : "comeback-w4-2-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 90,
                "id" : "comeback-w4-2-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "comeback-w4-2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Short surges to wake the legs up.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "Land this run feeling like you could have kept going.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1920,
            "effortLabel" : "Easy-steady",
            "id" : "comeback-w4-3",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "comeback-w4-3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 960,
                "id" : "comeback-w4-3-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "comeback-w4-3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A patient aerobic close to the block.",
            "title" : "Long run"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 35,
    "baseWeeklyMinutes" : 90,
    "defaultWeeks" : 9,
    "focus" : "fiveK",
    "highlights" : [
      "Every week has a clear progression target instead of vague mileage.",
      "Warmups and cooldowns are built into every workout.",
      "The later weeks reduce complexity and build continuous-running confidence."
    ],
    "id" : "run-5k-v1",
    "maxSessionsPerWeek" : 3,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Luke Murchison's c25k-web Couch-to-5K plan data",
      "importNotes" : "Imported from the open-source `src/data/c25k.json` plan and translated into Outbound's workout model.",
      "license" : "MIT",
      "name" : "c25k-web",
      "url" : "https://github.com/lmorchard/c25k-web"
    },
    "sport" : "run",
    "subtitle" : "A full nine-week run/walk progression imported from open-source plan data.",
    "summary" : "Three sessions each week move from short run-walk intervals to a continuous 30-minute run.",
    "title" : "Couch to 5K",
    "weeks" : [
      {
        "focus" : "Build continuous running",
        "id" : "week-1-build-continuous-running",
        "index" : 1,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Build comfort with short one-minute run segments.",
        "workouts" : [
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1710,
            "effortLabel" : "Easy",
            "id" : "w1d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w1d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-13",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d1-14",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d1-15",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w1d1-16",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Build comfort with short one-minute run segments.",
            "title" : "Week 1, Workout 1"
          },
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1710,
            "effortLabel" : "Easy",
            "id" : "w1d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w1d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-13",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d2-14",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d2-15",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w1d2-16",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Build comfort with short one-minute run segments.",
            "title" : "Week 1, Workout 2"
          },
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1710,
            "effortLabel" : "Easy",
            "id" : "w1d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w1d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-13",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w1d3-14",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 60,
                "id" : "w1d3-15",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w1d3-16",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Build comfort with short one-minute run segments.",
            "title" : "Week 1, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-2-build-continuous-running",
        "index" : 2,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Lengthen the running while keeping plenty of walk recovery.",
        "workouts" : [
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy",
            "id" : "w2d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w2d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d1-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d1-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d1-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d1-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 60,
                "id" : "w2d1-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w2d1-13",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Lengthen the running while keeping plenty of walk recovery.",
            "title" : "Week 2, Workout 1"
          },
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy",
            "id" : "w2d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w2d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d2-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d2-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d2-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d2-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d2-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 60,
                "id" : "w2d2-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w2d2-13",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Lengthen the running while keeping plenty of walk recovery.",
            "title" : "Week 2, Workout 2"
          },
          {
            "coachCue" : "Keep every run interval comfortably easy.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy",
            "id" : "w2d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w2d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d3-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d3-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d3-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d3-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-9",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 120,
                "id" : "w2d3-10",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w2d3-11",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 60,
                "id" : "w2d3-12",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w2d3-13",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Lengthen the running while keeping plenty of walk recovery.",
            "title" : "Week 2, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-3-build-continuous-running",
        "index" : 3,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Mix short and medium run segments so continuous running starts to feel less foreign.",
        "workouts" : [
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1680,
            "effortLabel" : "Easy",
            "id" : "w3d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w3d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d1-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d1-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d1-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w3d1-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Mix short and medium run segments so continuous running starts to feel less foreign.",
            "title" : "Week 3, Workout 1"
          },
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1680,
            "effortLabel" : "Easy",
            "id" : "w3d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w3d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d2-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d2-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d2-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d2-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d2-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w3d2-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Mix short and medium run segments so continuous running starts to feel less foreign.",
            "title" : "Week 3, Workout 2"
          },
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1680,
            "effortLabel" : "Easy",
            "id" : "w3d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w3d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d3-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d3-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d3-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 90,
                "id" : "w3d3-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w3d3-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w3d3-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w3d3-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w3d3-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Mix short and medium run segments so continuous running starts to feel less foreign.",
            "title" : "Week 3, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-4-build-continuous-running",
        "index" : 4,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Step into longer blocks with two three-minute segments and two five-minute segments.",
        "workouts" : [
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1890,
            "effortLabel" : "Easy",
            "id" : "w4d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w4d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 150,
                "id" : "w4d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d1-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d1-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 0,
                "id" : "w4d1-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w4d1-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Step into longer blocks with two three-minute segments and two five-minute segments.",
            "title" : "Week 4, Workout 1"
          },
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1890,
            "effortLabel" : "Easy",
            "id" : "w4d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w4d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 150,
                "id" : "w4d2-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d2-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d2-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d2-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 0,
                "id" : "w4d2-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w4d2-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Step into longer blocks with two three-minute segments and two five-minute segments.",
            "title" : "Week 4, Workout 2"
          },
          {
            "coachCue" : "Stay patient through the early blocks so the later ones still feel possible.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1890,
            "effortLabel" : "Easy",
            "id" : "w4d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w4d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d3-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d3-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 150,
                "id" : "w4d3-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 180,
                "id" : "w4d3-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 90,
                "id" : "w4d3-6",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w4d3-7",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 0,
                "id" : "w4d3-8",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w4d3-9",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Step into longer blocks with two three-minute segments and two five-minute segments.",
            "title" : "Week 4, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-5-build-continuous-running",
        "index" : 5,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "This is the first real leap week, ending with a twenty-minute continuous run.",
        "workouts" : [
          {
            "coachCue" : "Let the middle eight-minute run stay under control.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2040,
            "effortLabel" : "Easy",
            "id" : "w5d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w5d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w5d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w5d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 480,
                "id" : "w5d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w5d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w5d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w5d1-6",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Five minutes run, three minutes walk, eight minutes run, three minutes walk, five minutes run.",
            "title" : "Week 5, Workout 1"
          },
          {
            "coachCue" : "Focus on smoothness in the second block.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1860,
            "effortLabel" : "Easy",
            "id" : "w5d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w5d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 480,
                "id" : "w5d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 300,
                "id" : "w5d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 480,
                "id" : "w5d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w5d2-4",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Two eight-minute run blocks with a five-minute walk between them.",
            "title" : "Week 5, Workout 2"
          },
          {
            "coachCue" : "Start slower than you think you need to.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1800,
            "effortLabel" : "Easy",
            "id" : "w5d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w5d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1200,
                "id" : "w5d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w5d3-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Your first continuous twenty-minute run.",
            "title" : "Week 5, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-6-build-continuous-running",
        "index" : 6,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Alternate interval days with another jump in continuous running.",
        "workouts" : [
          {
            "coachCue" : "This week is about confidence, not proving toughness.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2040,
            "effortLabel" : "Easy",
            "id" : "w6d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w6d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w6d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w6d1-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 480,
                "id" : "w6d1-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w6d1-4",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 300,
                "id" : "w6d1-5",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w6d1-6",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A return to five- and eight-minute run segments.",
            "title" : "Week 6, Workout 1"
          },
          {
            "coachCue" : "Treat the second ten-minute block like a calm reset.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1980,
            "effortLabel" : "Easy",
            "id" : "w6d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w6d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 600,
                "id" : "w6d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Recover fully before the next run.",
                "durationSeconds" : 180,
                "id" : "w6d2-2",
                "kind" : "walk",
                "label" : "Walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 600,
                "id" : "w6d2-3",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w6d2-4",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Two ten-minute runs with a short walk between them.",
            "title" : "Week 6, Workout 2"
          },
          {
            "coachCue" : "Relax the shoulders and let the time unfold.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1920,
            "effortLabel" : "Easy",
            "id" : "w6d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w6d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1320,
                "id" : "w6d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w6d3-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Continuous twenty-two-minute running.",
            "title" : "Week 6, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-7-build-continuous-running",
        "index" : 7,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Three identical continuous 25-minute runs build familiarity over novelty.",
        "workouts" : [
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "w7d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w7d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1500,
                "id" : "w7d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w7d1-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three identical continuous 25-minute runs build familiarity over novelty.",
            "title" : "Week 7, Workout 1"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "w7d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w7d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1500,
                "id" : "w7d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w7d2-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three identical continuous 25-minute runs build familiarity over novelty.",
            "title" : "Week 7, Workout 2"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "w7d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w7d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1500,
                "id" : "w7d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w7d3-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three identical continuous 25-minute runs build familiarity over novelty.",
            "title" : "Week 7, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-8-build-continuous-running",
        "index" : 8,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Push continuous running to 28 minutes while keeping the effort patient.",
        "workouts" : [
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2280,
            "effortLabel" : "Easy",
            "id" : "w8d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w8d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1680,
                "id" : "w8d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w8d1-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Push continuous running to 28 minutes while keeping the effort patient.",
            "title" : "Week 8, Workout 1"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2280,
            "effortLabel" : "Easy",
            "id" : "w8d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w8d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1680,
                "id" : "w8d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w8d2-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Push continuous running to 28 minutes while keeping the effort patient.",
            "title" : "Week 8, Workout 2"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2280,
            "effortLabel" : "Easy",
            "id" : "w8d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w8d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1680,
                "id" : "w8d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w8d3-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Push continuous running to 28 minutes while keeping the effort patient.",
            "title" : "Week 8, Workout 3"
          }
        ]
      },
      {
        "focus" : "Build continuous running",
        "id" : "week-9-build-continuous-running",
        "index" : 9,
        "notes" : [
          "Take at least one full rest day between C25K sessions."
        ],
        "summary" : "Three continuous 30-minute runs complete the progression.",
        "workouts" : [
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2400,
            "effortLabel" : "Easy",
            "id" : "w9d1",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w9d1-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1800,
                "id" : "w9d1-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w9d1-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three continuous 30-minute runs complete the progression.",
            "title" : "Week 9, Workout 1"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2400,
            "effortLabel" : "Easy",
            "id" : "w9d2",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w9d2-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1800,
                "id" : "w9d2-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w9d2-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three continuous 30-minute runs complete the progression.",
            "title" : "Week 9, Workout 2"
          },
          {
            "coachCue" : "Go out slower than you want for the first five minutes.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2400,
            "effortLabel" : "Easy",
            "id" : "w9d3",
            "isOptional" : false,
            "kind" : "walkRun",
            "purpose" : "Progress from run-walk intervals toward continuous running.",
            "steps" : [
              {
                "detail" : "Ease into the workout.",
                "durationSeconds" : 300,
                "id" : "w9d3-0",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Keep the pace light.",
                "durationSeconds" : 1800,
                "id" : "w9d3-1",
                "kind" : "run",
                "label" : "Run"
              },
              {
                "detail" : "Let the effort settle.",
                "durationSeconds" : 300,
                "id" : "w9d3-2",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Three continuous 30-minute runs complete the progression.",
            "title" : "Week 9, Workout 3"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 55,
    "baseWeeklyMinutes" : 135,
    "defaultWeeks" : 8,
    "focus" : "tenK",
    "highlights" : [
      "Intervals, tempo, and fartlek each appear with a clear purpose.",
      "Long runs build gradually instead of spiking.",
      "Week 4 and week 8 back off so the block stays usable."
    ],
    "id" : "run-10k-v1",
    "maxSessionsPerWeek" : 4,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Daniel Coats's training-planner sample workout taxonomy",
      "importNotes" : "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials.",
      "license" : "MIT",
      "name" : "training-planner",
      "url" : "https://github.com/danielcoats/training-planner"
    },
    "sport" : "run",
    "subtitle" : "A balanced 10K block with aerobic support, controlled quality, and progression you can actually recover from.",
    "summary" : "Four-week structure repeated with progressive long runs, one quality session, and one optional cross-training day.",
    "title" : "10K builder",
    "weeks" : [
      {
        "focus" : "Set the aerobic floor",
        "id" : "week-1-set-the-aerobic-floor",
        "index" : 1,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Start with familiar paces and a light workout touch.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2100,
            "effortLabel" : "Conversational",
            "id" : "10k-w1-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w1-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1500,
                "id" : "10k-w1-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w1-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Work the reps, but keep the first one restrained.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1920,
            "effortLabel" : "10K effort",
            "id" : "10k-w1-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "10k-w1-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-easy-3",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 120,
                "id" : "10k-w1-q-hard-4",
                "kind" : "interval",
                "label" : "Hard rep 4"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "10k-w1-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Controlled faster running with easy recoveries.",
            "title" : "4 x 2 min intervals"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w1-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w1-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3000,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w1-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w1-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2040,
                "id" : "10k-w1-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w1-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Add steady pressure",
        "id" : "week-2-add-steady-pressure",
        "index" : 2,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The quality day shifts toward threshold work while the long run grows slightly.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2160,
            "effortLabel" : "Conversational",
            "id" : "10k-w2-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w2-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1560,
                "id" : "10k-w2-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w2-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Smooth breathing matters more than pace numbers.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2280,
            "effortLabel" : "Comfortably hard",
            "id" : "10k-w2-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "10k-w2-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "10k-w2-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "10k-w2-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "10k-w2-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "10k-w2-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Two controlled tempo blocks.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w2-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w2-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3300,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w2-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w2-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2340,
                "id" : "10k-w2-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w2-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Stretch range",
        "id" : "week-3-stretch-range",
        "index" : 3,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "A fartlek session lets you move a little quicker without locking into a pace target.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2280,
            "effortLabel" : "Conversational",
            "id" : "10k-w3-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w3-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1680,
                "id" : "10k-w3-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w3-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Think flow, not fight.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2400,
            "effortLabel" : "Playful steady",
            "id" : "10k-w3-q",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "10k-w3-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10k-w3-q-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10k-w3-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10k-w3-q-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10k-w3-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10k-w3-q-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10k-w3-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10k-w3-q-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10k-w3-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10k-w3-q-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10k-w3-q-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "10k-w3-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Three-minute surges with patient recoveries.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w3-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w3-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3600,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w3-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w3-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2640,
                "id" : "10k-w3-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w3-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Cut back and absorb",
        "id" : "week-4-cut-back-and-absorb",
        "index" : 4,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "A lighter week keeps the block sustainable.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Conversational",
            "id" : "10k-w4-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w4-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1200,
                "id" : "10k-w4-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w4-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Keep the climbs springy and the recoveries complete.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1680,
            "effortLabel" : "Strong but controlled",
            "id" : "10k-w4-q",
            "isOptional" : false,
            "kind" : "hill",
            "purpose" : "Build strength and mechanics with lower top-end speed.",
            "steps" : [
              {
                "detail" : "Find a smooth hill.",
                "durationSeconds" : 600,
                "id" : "10k-w4-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-1",
                "kind" : "interval",
                "label" : "Hill rep 1"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-1",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-2",
                "kind" : "interval",
                "label" : "Hill rep 2"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-2",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-3",
                "kind" : "interval",
                "label" : "Hill rep 3"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-3",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-4",
                "kind" : "interval",
                "label" : "Hill rep 4"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-4",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-5",
                "kind" : "interval",
                "label" : "Hill rep 5"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-5",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 45,
                "id" : "10k-w4-q-hill-6",
                "kind" : "interval",
                "label" : "Hill rep 6"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 75,
                "id" : "10k-w4-q-recover-6",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Shake the legs out.",
                "durationSeconds" : 480,
                "id" : "10k-w4-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Short hill form session.",
            "title" : "Hill session"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w4-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w4-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 2700,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w4-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w4-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 1740,
                "id" : "10k-w4-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w4-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Rebuild after the cutback",
        "id" : "week-5-rebuild-after-the-cutback",
        "index" : 5,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The second half of the block starts a little stronger than the first.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2400,
            "effortLabel" : "Conversational",
            "id" : "10k-w5-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w5-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1800,
                "id" : "10k-w5-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w5-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Keep the final rep looking like the first.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2460,
            "effortLabel" : "10K effort",
            "id" : "10k-w5-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "10k-w5-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 180,
                "id" : "10k-w5-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w5-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 180,
                "id" : "10k-w5-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w5-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 180,
                "id" : "10k-w5-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w5-q-easy-3",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 180,
                "id" : "10k-w5-q-hard-4",
                "kind" : "interval",
                "label" : "Hard rep 4"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w5-q-easy-4",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 180,
                "id" : "10k-w5-q-hard-5",
                "kind" : "interval",
                "label" : "Hard rep 5"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "10k-w5-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Slightly longer reps at controlled 10K effort.",
            "title" : "5 x 3 min intervals"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w5-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w5-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3720,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w5-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w5-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2760,
                "id" : "10k-w5-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w5-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Sharpen threshold",
        "id" : "week-6-sharpen-threshold",
        "index" : 6,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Longer steady blocks make race effort feel calmer.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2400,
            "effortLabel" : "Conversational",
            "id" : "10k-w6-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w6-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1800,
                "id" : "10k-w6-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w6-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Stay patient for the first two blocks.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2520,
            "effortLabel" : "Comfortably hard",
            "id" : "10k-w6-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "10k-w6-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "10k-w6-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "10k-w6-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "10k-w6-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "10k-w6-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 360,
                "id" : "10k-w6-q-tempo-2",
                "kind" : "tempo",
                "label" : "Tempo block 3"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "10k-w6-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Three tempo segments with short floats.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w6-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w6-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3900,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w6-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w6-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2940,
                "id" : "10k-w6-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w6-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Peak specific work",
        "id" : "week-7-peak-specific-work",
        "index" : 7,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "A classic open-source-style workout mix of intervals, easy mileage, and a long aerobic finish.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2100,
            "effortLabel" : "Conversational",
            "id" : "10k-w7-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w7-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1500,
                "id" : "10k-w7-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w7-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Run these at rhythm, not rage.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2400,
            "effortLabel" : "10K effort",
            "id" : "10k-w7-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "10k-w7-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10k-w7-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w7-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10k-w7-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w7-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10k-w7-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10k-w7-q-easy-3",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10k-w7-q-hard-4",
                "kind" : "interval",
                "label" : "Hard rep 4"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "10k-w7-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Inspired by open-source interval workout seeds.",
            "title" : "4 x 800m effort"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10k-w7-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10k-w7-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4200,
            "effortLabel" : "Easy-steady",
            "id" : "10k-w7-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10k-w7-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3240,
                "id" : "10k-w7-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10k-w7-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Freshen up and check fitness",
        "id" : "week-8-freshen-up-and-check-fitness",
        "index" : 8,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Back off volume, then finish with a controlled 10K effort or local race.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1680,
            "effortLabel" : "Conversational",
            "id" : "10k-w8-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10k-w8-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1080,
                "id" : "10k-w8-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10k-w8-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Keep this snappy, not draining.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1440,
            "effortLabel" : "Light and snappy",
            "id" : "10k-w8-q",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Stay sharp while protecting freshness.",
            "steps" : [
              {
                "detail" : "Stay relaxed.",
                "durationSeconds" : 480,
                "id" : "10k-w8-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 60,
                "id" : "10k-w8-q-pickup-1",
                "kind" : "interval",
                "label" : "Pickup 1"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10k-w8-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 60,
                "id" : "10k-w8-q-pickup-2",
                "kind" : "interval",
                "label" : "Pickup 2"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10k-w8-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 60,
                "id" : "10k-w8-q-pickup-3",
                "kind" : "interval",
                "label" : "Pickup 3"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10k-w8-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 60,
                "id" : "10k-w8-q-pickup-4",
                "kind" : "interval",
                "label" : "Pickup 4"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10k-w8-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 60,
                "id" : "10k-w8-q-pickup-5",
                "kind" : "interval",
                "label" : "Pickup 5"
              },
              {
                "detail" : "Keep this short and easy.",
                "durationSeconds" : 360,
                "id" : "10k-w8-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Short pickups to feel sharp without fatigue.",
            "title" : "Race-prep run"
          },
          {
            "coachCue" : "Keep this tiny and relaxed.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1080,
            "effortLabel" : "Very easy",
            "id" : "10k-w8-recovery",
            "isOptional" : true,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "10k-w8-recovery-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 600,
                "id" : "10k-w8-recovery-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "10k-w8-recovery-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Short recovery jog before the event.",
            "title" : "Recovery run"
          },
          {
            "coachCue" : "Settle in early and finish the last third with intent.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3300,
            "effortLabel" : "Race effort",
            "id" : "10k-w8-race",
            "isOptional" : false,
            "kind" : "race",
            "purpose" : "Express the work with patience early and intent late.",
            "steps" : [
              {
                "detail" : "Stay loose and calm.",
                "durationSeconds" : 600,
                "id" : "10k-w8-race-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Start controlled, then build into the second half.",
                "durationSeconds" : 2100,
                "id" : "10k-w8-race-race",
                "kind" : "race",
                "label" : "Main effort"
              },
              {
                "detail" : "Let the effort taper fully.",
                "durationSeconds" : 600,
                "id" : "10k-w8-race-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "A local 10K, time trial, or controlled progression run.",
            "title" : "10K effort day"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 70,
    "baseWeeklyMinutes" : 170,
    "defaultWeeks" : 8,
    "focus" : "tenMile",
    "highlights" : [
      "Long runs progress from 70 to 95 minutes.",
      "Midweek tempo and hill sessions build durable strength.",
      "Cross-training stays optional so the plan remains livable."
    ],
    "id" : "run-10mile-v1",
    "maxSessionsPerWeek" : 4,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Daniel Coats's training-planner sample workout taxonomy",
      "importNotes" : "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials.",
      "license" : "MIT",
      "name" : "training-planner",
      "url" : "https://github.com/danielcoats/training-planner"
    },
    "sport" : "run",
    "subtitle" : "An endurance-focused block for runners ready for longer weekends without turning every weekday into a grind.",
    "summary" : "Steady midweek work plus gradually longer weekend runs build enough range for a confident 10-mile day.",
    "title" : "10 mile plan",
    "weeks" : [
      {
        "focus" : "Build steady range",
        "id" : "week-1-build-steady-range",
        "index" : 1,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Start with aerobic volume that feels durable.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2400,
            "effortLabel" : "Conversational",
            "id" : "10m-w1-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w1-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1800,
                "id" : "10m-w1-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w1-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Run tall and keep the downhill recoveries easy.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2160,
            "effortLabel" : "Strong but controlled",
            "id" : "10m-w1-q",
            "isOptional" : false,
            "kind" : "hill",
            "purpose" : "Build strength and mechanics with lower top-end speed.",
            "steps" : [
              {
                "detail" : "Find a smooth hill.",
                "durationSeconds" : 600,
                "id" : "10m-w1-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-1",
                "kind" : "interval",
                "label" : "Hill rep 1"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-1",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-2",
                "kind" : "interval",
                "label" : "Hill rep 2"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-2",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-3",
                "kind" : "interval",
                "label" : "Hill rep 3"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-3",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-4",
                "kind" : "interval",
                "label" : "Hill rep 4"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-4",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-5",
                "kind" : "interval",
                "label" : "Hill rep 5"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-5",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "10m-w1-q-hill-6",
                "kind" : "interval",
                "label" : "Hill rep 6"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "10m-w1-q-recover-6",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Shake the legs out.",
                "durationSeconds" : 480,
                "id" : "10m-w1-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Form-focused hill repetitions.",
            "title" : "Hill session"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w1-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w1-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4200,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w1-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w1-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3240,
                "id" : "10m-w1-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w1-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Add tempo control",
        "id" : "week-2-add-tempo-control",
        "index" : 2,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The week gets slightly longer while the quality stays measured.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "10m-w2-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w2-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1920,
                "id" : "10m-w2-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w2-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Stay smooth and avoid a red-line feel.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2520,
            "effortLabel" : "Comfortably hard",
            "id" : "10m-w2-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "10m-w2-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "10m-w2-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "10m-w2-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "10m-w2-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "10m-w2-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Two ten-minute tempo blocks.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w2-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w2-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4500,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w2-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w2-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3540,
                "id" : "10m-w2-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w2-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry strength",
        "id" : "week-3-carry-strength",
        "index" : 3,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The quality day asks for steadier work while the long run extends.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2640,
            "effortLabel" : "Conversational",
            "id" : "10m-w3-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w3-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2040,
                "id" : "10m-w3-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w3-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Let the fast bits feel controlled, not all-out.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2640,
            "effortLabel" : "Playful steady",
            "id" : "10m-w3-q",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "10m-w3-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10m-w3-q-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10m-w3-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10m-w3-q-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10m-w3-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10m-w3-q-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10m-w3-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10m-w3-q-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10m-w3-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "10m-w3-q-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "10m-w3-q-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "10m-w3-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Alternating surges that build strength without a strict pace target.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w3-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w3-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4800,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w3-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w3-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3840,
                "id" : "10m-w3-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w3-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Absorb the work",
        "id" : "week-4-absorb-the-work",
        "index" : 4,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "A lighter week before the second build.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2040,
            "effortLabel" : "Conversational",
            "id" : "10m-w4-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w4-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1440,
                "id" : "10m-w4-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w4-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Nothing heroic today.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1920,
            "effortLabel" : "Conversational",
            "id" : "10m-w4-q",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w4-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1320,
                "id" : "10m-w4-q-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w4-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Just enough structure to keep flow.",
            "title" : "Steady cutback run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w4-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w4-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 3600,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w4-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w4-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 2640,
                "id" : "10m-w4-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w4-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Return sharper",
        "id" : "week-5-return-sharper",
        "index" : 5,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Rebuild with a stronger aerobic set and more range on the weekend.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2700,
            "effortLabel" : "Conversational",
            "id" : "10m-w5-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w5-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2100,
                "id" : "10m-w5-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w5-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "These should feel strong but repeatable.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2760,
            "effortLabel" : "10K effort",
            "id" : "10m-w5-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "10m-w5-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10m-w5-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10m-w5-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10m-w5-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10m-w5-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10m-w5-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10m-w5-q-easy-3",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10m-w5-q-hard-4",
                "kind" : "interval",
                "label" : "Hard rep 4"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "10m-w5-q-easy-4",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 240,
                "id" : "10m-w5-q-hard-5",
                "kind" : "interval",
                "label" : "Hard rep 5"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "10m-w5-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Threshold-adjacent reps to support sustained pace.",
            "title" : "5 x 4 min intervals"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w5-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w5-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5100,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w5-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w5-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4140,
                "id" : "10m-w5-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w5-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Practice sustained work",
        "id" : "week-6-practice-sustained-work",
        "index" : 6,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Tempo work gets longer while the long run climbs again.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2700,
            "effortLabel" : "Conversational",
            "id" : "10m-w6-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w6-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2100,
                "id" : "10m-w6-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w6-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "The middle block should feel the smoothest.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2880,
            "effortLabel" : "Comfortably hard",
            "id" : "10m-w6-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "10m-w6-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "10m-w6-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "10m-w6-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "10m-w6-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "10m-w6-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "10m-w6-q-tempo-2",
                "kind" : "tempo",
                "label" : "Tempo block 3"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "10m-w6-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Three tempo segments with short floats.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w6-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w6-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5400,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w6-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w6-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4440,
                "id" : "10m-w6-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w6-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Peak endurance",
        "id" : "week-7-peak-endurance",
        "index" : 7,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The final big week asks for patience more than speed.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "10m-w7-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w7-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1920,
                "id" : "10m-w7-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w7-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Quick but never strained.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2040,
            "effortLabel" : "Light and snappy",
            "id" : "10m-w7-q",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Stay sharp while protecting freshness.",
            "steps" : [
              {
                "detail" : "Stay relaxed.",
                "durationSeconds" : 480,
                "id" : "10m-w7-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 75,
                "id" : "10m-w7-q-pickup-1",
                "kind" : "interval",
                "label" : "Pickup 1"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10m-w7-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 75,
                "id" : "10m-w7-q-pickup-2",
                "kind" : "interval",
                "label" : "Pickup 2"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10m-w7-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 75,
                "id" : "10m-w7-q-pickup-3",
                "kind" : "interval",
                "label" : "Pickup 3"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10m-w7-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 75,
                "id" : "10m-w7-q-pickup-4",
                "kind" : "interval",
                "label" : "Pickup 4"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "10m-w7-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 75,
                "id" : "10m-w7-q-pickup-5",
                "kind" : "interval",
                "label" : "Pickup 5"
              },
              {
                "detail" : "Keep this short and easy.",
                "durationSeconds" : 360,
                "id" : "10m-w7-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Pickups to keep the legs lively.",
            "title" : "Race-prep run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "10m-w7-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "10m-w7-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5700,
            "effortLabel" : "Easy-steady",
            "id" : "10m-w7-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "10m-w7-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4740,
                "id" : "10m-w7-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "10m-w7-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Freshen up",
        "id" : "week-8-freshen-up",
        "index" : 8,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Pull volume down and carry freshness into a 10-mile effort or supported long run.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Conversational",
            "id" : "10m-w8-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w8-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1200,
                "id" : "10m-w8-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w8-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Leave the run feeling sharper than when you started.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1440,
            "effortLabel" : "Conversational",
            "id" : "10m-w8-q",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "10m-w8-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 840,
                "id" : "10m-w8-q-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "10m-w8-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Short and calming.",
            "title" : "Easy pre-race run"
          },
          {
            "coachCue" : "Keep this tiny and relaxed.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1080,
            "effortLabel" : "Very easy",
            "id" : "10m-w8-recovery",
            "isOptional" : true,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "10m-w8-recovery-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 600,
                "id" : "10m-w8-recovery-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "10m-w8-recovery-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Short recovery jog before the event.",
            "title" : "Recovery run"
          },
          {
            "coachCue" : "Be patient in the first half so you can run strong late.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5100,
            "effortLabel" : "Race effort",
            "id" : "10m-w8-race",
            "isOptional" : false,
            "kind" : "race",
            "purpose" : "Express the work with patience early and intent late.",
            "steps" : [
              {
                "detail" : "Stay loose and calm.",
                "durationSeconds" : 600,
                "id" : "10m-w8-race-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Start controlled, then build into the second half.",
                "durationSeconds" : 3900,
                "id" : "10m-w8-race-race",
                "kind" : "race",
                "label" : "Main effort"
              },
              {
                "detail" : "Let the effort taper fully.",
                "durationSeconds" : 600,
                "id" : "10m-w8-race-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Race, long progression run, or supported solo effort.",
            "title" : "10 mile effort day"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 80,
    "baseWeeklyMinutes" : 200,
    "defaultWeeks" : 10,
    "focus" : "halfMarathon",
    "highlights" : [
      "Long runs grow to 120 minutes, then taper back.",
      "Quality work emphasizes sustained control rather than repeated all-out efforts.",
      "Cutback weeks prevent the plan from becoming brittle."
    ],
    "id" : "run-half-v1",
    "maxSessionsPerWeek" : 4,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Daniel Coats's training-planner sample workout taxonomy",
      "importNotes" : "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials.",
      "license" : "MIT",
      "name" : "training-planner",
      "url" : "https://github.com/danielcoats/training-planner"
    },
    "sport" : "run",
    "subtitle" : "A practical half build with one real long run, one purposeful quality day, and enough recovery to stay honest.",
    "summary" : "A ten-week half block that progresses long runs steadily while using tempo, intervals, and race-prep sessions sparingly.",
    "title" : "Half marathon plan",
    "weeks" : [
      {
        "focus" : "Settle into half structure",
        "id" : "week-1-settle-into-half-structure",
        "index" : 1,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The first week establishes the four-day rhythm without forcing pace.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-w1-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w1-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1920,
                "id" : "half-w1-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w1-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Think calm strength.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2640,
            "effortLabel" : "Comfortably hard",
            "id" : "half-w1-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "half-w1-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "half-w1-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "half-w1-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "half-w1-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "half-w1-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Two ten-minute tempo blocks.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w1-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w1-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4500,
            "effortLabel" : "Easy-steady",
            "id" : "half-w1-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w1-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3540,
                "id" : "half-w1-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w1-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Strength through range",
        "id" : "week-2-strength-through-range",
        "index" : 2,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The long run grows, while the quality day stays controlled.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2700,
            "effortLabel" : "Conversational",
            "id" : "half-w2-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w2-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2100,
                "id" : "half-w2-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w2-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Settle into rhythm before the pace settles into you.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2640,
            "effortLabel" : "10K effort",
            "id" : "half-w2-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "half-w2-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w2-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "half-w2-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w2-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "half-w2-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w2-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "half-w2-q-easy-3",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w2-q-hard-4",
                "kind" : "interval",
                "label" : "Hard rep 4"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "half-w2-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Longer threshold reps with complete recoveries.",
            "title" : "4 x 5 min intervals"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w2-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w2-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5100,
            "effortLabel" : "Easy-steady",
            "id" : "half-w2-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w2-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4140,
                "id" : "half-w2-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w2-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Hold steady effort",
        "id" : "week-3-hold-steady-effort",
        "index" : 3,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Sustained tempo and a longer long run raise the floor.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2700,
            "effortLabel" : "Conversational",
            "id" : "half-w3-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w3-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2100,
                "id" : "half-w3-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w3-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Stay tall when the work accumulates.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2880,
            "effortLabel" : "Comfortably hard",
            "id" : "half-w3-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "half-w3-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "half-w3-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "half-w3-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 600,
                "id" : "half-w3-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 120,
                "id" : "half-w3-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "half-w3-q-tempo-2",
                "kind" : "tempo",
                "label" : "Tempo block 3"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "half-w3-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Three steady tempo segments.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w3-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w3-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5700,
            "effortLabel" : "Easy-steady",
            "id" : "half-w3-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w3-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4740,
                "id" : "half-w3-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w3-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Cut back before the next build",
        "id" : "week-4-cut-back-before-the-next-build",
        "index" : 4,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Volume comes down enough for the next push to land well.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2100,
            "effortLabel" : "Conversational",
            "id" : "half-w4-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w4-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1500,
                "id" : "half-w4-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w4-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Short and springy beats sloggy.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2040,
            "effortLabel" : "Strong but controlled",
            "id" : "half-w4-q",
            "isOptional" : false,
            "kind" : "hill",
            "purpose" : "Build strength and mechanics with lower top-end speed.",
            "steps" : [
              {
                "detail" : "Find a smooth hill.",
                "durationSeconds" : 600,
                "id" : "half-w4-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-1",
                "kind" : "interval",
                "label" : "Hill rep 1"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-1",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-2",
                "kind" : "interval",
                "label" : "Hill rep 2"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-2",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-3",
                "kind" : "interval",
                "label" : "Hill rep 3"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-3",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-4",
                "kind" : "interval",
                "label" : "Hill rep 4"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-4",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-5",
                "kind" : "interval",
                "label" : "Hill rep 5"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-5",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Short, tall, and powerful.",
                "durationSeconds" : 60,
                "id" : "half-w4-q-hill-6",
                "kind" : "interval",
                "label" : "Hill rep 6"
              },
              {
                "detail" : "Reset fully before the next climb.",
                "durationSeconds" : 90,
                "id" : "half-w4-q-recover-6",
                "kind" : "recovery",
                "label" : "Walk back recovery"
              },
              {
                "detail" : "Shake the legs out.",
                "durationSeconds" : 480,
                "id" : "half-w4-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Light hill session for strength and mechanics.",
            "title" : "Hill session"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w4-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w4-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4200,
            "effortLabel" : "Easy-steady",
            "id" : "half-w4-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w4-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3240,
                "id" : "half-w4-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w4-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Rebuild stronger",
        "id" : "week-5-rebuild-stronger",
        "index" : 5,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Back to a higher long-run range with a quality session that stays measured.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2880,
            "effortLabel" : "Conversational",
            "id" : "half-w5-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w5-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2280,
                "id" : "half-w5-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w5-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Keep the fast bits strong but relaxed.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2760,
            "effortLabel" : "Playful steady",
            "id" : "half-w5-q",
            "isOptional" : false,
            "kind" : "fartlek",
            "purpose" : "Practice changing gears without the rigidity of track intervals.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 480,
                "id" : "half-w5-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-1",
                "kind" : "steady",
                "label" : "Surge 1"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-2",
                "kind" : "steady",
                "label" : "Surge 2"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-3",
                "kind" : "steady",
                "label" : "Surge 3"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-4",
                "kind" : "steady",
                "label" : "Surge 4"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-5",
                "kind" : "steady",
                "label" : "Surge 5"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-5",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Run by feel, not by force.",
                "durationSeconds" : 180,
                "id" : "half-w5-q-surge-6",
                "kind" : "steady",
                "label" : "Surge 6"
              },
              {
                "detail" : "Recover while still moving.",
                "durationSeconds" : 120,
                "id" : "half-w5-q-float-6",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 360,
                "id" : "half-w5-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Three-minute surges sprinkled into a steady run.",
            "title" : "Fartlek run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w5-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w5-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 6000,
            "effortLabel" : "Easy-steady",
            "id" : "half-w5-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w5-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 5040,
                "id" : "half-w5-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w5-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Peak sustained work",
        "id" : "week-6-peak-sustained-work",
        "index" : 6,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "This week leans into long aerobic control.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2880,
            "effortLabel" : "Conversational",
            "id" : "half-w6-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w6-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2280,
                "id" : "half-w6-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w6-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Stay just below strain.",
            "dayLabel" : "Thu",
            "durationSeconds" : 3120,
            "effortLabel" : "Comfortably hard",
            "id" : "half-w6-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "half-w6-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 720,
                "id" : "half-w6-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "half-w6-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 720,
                "id" : "half-w6-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "half-w6-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Two longer tempo blocks.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w6-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w6-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 6600,
            "effortLabel" : "Easy-steady",
            "id" : "half-w6-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w6-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 5640,
                "id" : "half-w6-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w6-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Peak long run",
        "id" : "week-7-peak-long-run",
        "index" : 7,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The weekend reaches its high point while the quality day stays compact.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2700,
            "effortLabel" : "Conversational",
            "id" : "half-w7-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w7-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 2100,
                "id" : "half-w7-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w7-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "You should finish feeling eager, not empty.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2160,
            "effortLabel" : "Light and snappy",
            "id" : "half-w7-q",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Stay sharp while protecting freshness.",
            "steps" : [
              {
                "detail" : "Stay relaxed.",
                "durationSeconds" : 480,
                "id" : "half-w7-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-pickup-1",
                "kind" : "interval",
                "label" : "Pickup 1"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-pickup-2",
                "kind" : "interval",
                "label" : "Pickup 2"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-pickup-3",
                "kind" : "interval",
                "label" : "Pickup 3"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-pickup-4",
                "kind" : "interval",
                "label" : "Pickup 4"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-float-4",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 90,
                "id" : "half-w7-q-pickup-5",
                "kind" : "interval",
                "label" : "Pickup 5"
              },
              {
                "detail" : "Keep this short and easy.",
                "durationSeconds" : 360,
                "id" : "half-w7-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Controlled pickups to keep the legs awake.",
            "title" : "Race-prep run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w7-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w7-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 7200,
            "effortLabel" : "Easy-steady",
            "id" : "half-w7-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w7-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 6240,
                "id" : "half-w7-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w7-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Step down slightly",
        "id" : "week-8-step-down-slightly",
        "index" : 8,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "The long run comes back while tempo rhythm stays alive.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-w8-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w8-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1920,
                "id" : "half-w8-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w8-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Practice restraint.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2520,
            "effortLabel" : "Comfortably hard",
            "id" : "half-w8-q",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Raise your comfort with sustained work just under strain.",
            "steps" : [
              {
                "detail" : "Keep this relaxed.",
                "durationSeconds" : 600,
                "id" : "half-w8-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "half-w8-q-tempo-0",
                "kind" : "tempo",
                "label" : "Tempo block 1"
              },
              {
                "detail" : "Bring your breathing down before the next block.",
                "durationSeconds" : 180,
                "id" : "half-w8-q-float-0",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Controlled discomfort.",
                "durationSeconds" : 480,
                "id" : "half-w8-q-tempo-1",
                "kind" : "tempo",
                "label" : "Tempo block 2"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 480,
                "id" : "half-w8-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Shorter threshold blocks with plenty in reserve.",
            "title" : "Tempo run"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w8-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w8-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 5700,
            "effortLabel" : "Easy-steady",
            "id" : "half-w8-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w8-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 4740,
                "id" : "half-w8-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w8-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Sharpen, don't chase",
        "id" : "week-9-sharpen,-don't-chase",
        "index" : 9,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "A lighter week with a final specific session.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 2100,
            "effortLabel" : "Conversational",
            "id" : "half-w9-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w9-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 1500,
                "id" : "half-w9-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w9-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "Let the pace come to you.",
            "dayLabel" : "Thu",
            "durationSeconds" : 2220,
            "effortLabel" : "10K effort",
            "id" : "half-w9-q",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support without losing control of the week.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 600,
                "id" : "half-w9-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w9-q-hard-1",
                "kind" : "interval",
                "label" : "Hard rep 1"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "half-w9-q-easy-1",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w9-q-hard-2",
                "kind" : "interval",
                "label" : "Hard rep 2"
              },
              {
                "detail" : "Walk or jog until you feel ready again.",
                "durationSeconds" : 120,
                "id" : "half-w9-q-easy-2",
                "kind" : "recovery",
                "label" : "Easy recovery"
              },
              {
                "detail" : "Quick but controlled.",
                "durationSeconds" : 300,
                "id" : "half-w9-q-hard-3",
                "kind" : "interval",
                "label" : "Hard rep 3"
              },
              {
                "detail" : "Bring things back down slowly.",
                "durationSeconds" : 480,
                "id" : "half-w9-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Controlled half-marathon effort with easy recoveries.",
            "title" : "3 x 5 min race-pace effort"
          },
          {
            "coachCue" : "Skip this if your legs are asking for recovery.",
            "dayLabel" : "Sat",
            "durationSeconds" : 2100,
            "effortLabel" : "Easy",
            "id" : "half-w9-ct",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Add aerobic support without extra run impact.",
            "steps" : [
              {
                "detail" : "Stay mostly aerobic.",
                "durationSeconds" : 2100,
                "id" : "half-w9-ct-main",
                "kind" : "crossTrain",
                "label" : "Bike, walk, row, or mobility circuit"
              }
            ],
            "summary" : "Optional low-impact aerobic support.",
            "title" : "Cross-train"
          },
          {
            "coachCue" : "The right pace is the one that keeps the back half steady.",
            "dayLabel" : "Sun",
            "durationSeconds" : 4200,
            "effortLabel" : "Easy-steady",
            "id" : "half-w9-long",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build durable endurance with low drama and steady effort.",
            "steps" : [
              {
                "detail" : "Start more gently than you think you need to.",
                "durationSeconds" : 480,
                "id" : "half-w9-long-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Stay under control for the whole middle.",
                "durationSeconds" : 3240,
                "id" : "half-w9-long-main",
                "kind" : "steady",
                "label" : "Long aerobic running"
              },
              {
                "detail" : "Walk a bit before you stop completely.",
                "durationSeconds" : 480,
                "id" : "half-w9-long-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Long aerobic support run.",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Race week",
        "id" : "week-10-race-week",
        "index" : 10,
        "notes" : [
          "If you miss a weekday, do not stack it onto the long-run day."
        ],
        "summary" : "Carry freshness into your half marathon or supported long effort.",
        "workouts" : [
          {
            "coachCue" : "Let this feel boring in the best possible way.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1440,
            "effortLabel" : "Conversational",
            "id" : "half-w10-easy",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Build aerobic support while keeping recovery intact.",
            "steps" : [
              {
                "detail" : "Ease into the session.",
                "durationSeconds" : 300,
                "id" : "half-w10-easy-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk or jog"
              },
              {
                "detail" : "You should be able to speak in short sentences.",
                "durationSeconds" : 840,
                "id" : "half-w10-easy-main",
                "kind" : "steady",
                "label" : "Easy run"
              },
              {
                "detail" : "Let your breathing settle.",
                "durationSeconds" : 300,
                "id" : "half-w10-easy-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Steady conversational running.",
            "title" : "Easy aerobic run"
          },
          {
            "coachCue" : "This should feel crisp and brief.",
            "dayLabel" : "Thu",
            "durationSeconds" : 1320,
            "effortLabel" : "Light and snappy",
            "id" : "half-w10-q",
            "isOptional" : false,
            "kind" : "racePrep",
            "purpose" : "Stay sharp while protecting freshness.",
            "steps" : [
              {
                "detail" : "Stay relaxed.",
                "durationSeconds" : 480,
                "id" : "half-w10-q-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 45,
                "id" : "half-w10-q-pickup-1",
                "kind" : "interval",
                "label" : "Pickup 1"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 75,
                "id" : "half-w10-q-float-1",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 45,
                "id" : "half-w10-q-pickup-2",
                "kind" : "interval",
                "label" : "Pickup 2"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 75,
                "id" : "half-w10-q-float-2",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 45,
                "id" : "half-w10-q-pickup-3",
                "kind" : "interval",
                "label" : "Pickup 3"
              },
              {
                "detail" : "Reset before the next pickup.",
                "durationSeconds" : 75,
                "id" : "half-w10-q-float-3",
                "kind" : "recovery",
                "label" : "Easy float"
              },
              {
                "detail" : "Quick, light, and under control.",
                "durationSeconds" : 45,
                "id" : "half-w10-q-pickup-4",
                "kind" : "interval",
                "label" : "Pickup 4"
              },
              {
                "detail" : "Keep this short and easy.",
                "durationSeconds" : 360,
                "id" : "half-w10-q-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown jog"
              }
            ],
            "summary" : "Short tune-up with quick strides.",
            "title" : "Race-prep run"
          },
          {
            "coachCue" : "Keep this tiny and relaxed.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1080,
            "effortLabel" : "Very easy",
            "id" : "half-w10-recovery",
            "isOptional" : true,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "half-w10-recovery-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 600,
                "id" : "half-w10-recovery-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "half-w10-recovery-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Short recovery jog before the event.",
            "title" : "Recovery run"
          },
          {
            "coachCue" : "Start patient, settle into rhythm, and trust the work.",
            "dayLabel" : "Sun",
            "durationSeconds" : 7200,
            "effortLabel" : "Race effort",
            "id" : "half-w10-race",
            "isOptional" : false,
            "kind" : "race",
            "purpose" : "Express the work with patience early and intent late.",
            "steps" : [
              {
                "detail" : "Stay loose and calm.",
                "durationSeconds" : 600,
                "id" : "half-w10-race-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Start controlled, then build into the second half.",
                "durationSeconds" : 6000,
                "id" : "half-w10-race-race",
                "kind" : "race",
                "label" : "Main effort"
              },
              {
                "detail" : "Let the effort taper fully.",
                "durationSeconds" : 600,
                "id" : "half-w10-race-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Race day or a calm supported long progression.",
            "title" : "Half marathon effort day"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 80,
    "baseWeeklyMinutes" : 180,
    "defaultWeeks" : 19,
    "focus" : "halfMarathon",
    "highlights" : [
      "Uses easy runs, half-marathon pace work, intervals, and long runs in a repeatable weekly rhythm.",
      "Volume rises gradually before tapering into race day.",
      "Cross-training and rest still appear, but this is more demanding than the lighter local half block."
    ],
    "id" : "run-half-hansons-beginner-v1",
    "maxSessionsPerWeek" : 6,
    "minSessionsPerWeek" : 3,
    "source" : {
      "attribution" : "Cody Hoover's time-to-run built-in plan library",
      "importNotes" : "Imported from the open-source `src/workouts/plans` built-in plans and translated into Outbound's structured week and workout model.",
      "license" : "MIT",
      "name" : "time-to-run",
      "url" : "https://github.com/hoovercj/time-to-run"
    },
    "sport" : "run",
    "subtitle" : "An imported week-by-week half plan with easy mileage, HMP sessions, interval workouts, and progressive long runs.",
    "summary" : "A larger-volume imported half block for runners who want a complete calendar with explicit workouts nearly every day.",
    "title" : "Half marathon beginner import",
    "weeks" : [
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-1-progress-into-structured-half-marathon-work",
        "index" : 1,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 1 with 3 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w1-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w1-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w1-d2",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w1-d2-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w1-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w1-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w1-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w1-d4-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Fri",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w1-d5",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w1-d5-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w1-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w1-d6-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w1-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w1-d7-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w1-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-2-progress-into-structured-half-marathon-work",
        "index" : 2,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 2 with 5 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w2-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w2-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "2 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w2-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w2-d2-main",
                "kind" : "steady",
                "label" : "Easy run 2 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 2 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w2-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w2-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w2-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w2-d4-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w2-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w2-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w2-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w2-d6-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w2-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w2-d7-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w2-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-3-progress-into-structured-half-marathon-work",
        "index" : 3,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 3 with 5 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w3-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w3-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w3-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w3-d2-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w3-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w3-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w3-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w3-d4-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w3-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w3-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w3-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w3-d6-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w3-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w3-d7-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w3-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-4-progress-into-structured-half-marathon-work",
        "index" : 4,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 4 with 5 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w4-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w4-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w4-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w4-d2-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w4-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w4-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w4-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w4-d4-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w4-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w4-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w4-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w4-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w4-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w4-d7-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w4-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-5-progress-into-structured-half-marathon-work",
        "index" : 5,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 5 with 5 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w5-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w5-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w5-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w5-d2-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w5-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w5-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w5-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w5-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-beginner-w5-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w5-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w5-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w5-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w5-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w5-d6-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w5-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w5-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w5-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4080,
                "id" : "half-hansons-beginner-w5-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 8 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w5-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "8 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-6-progress-into-structured-half-marathon-work",
        "index" : 6,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 6 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w6-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w6-d1-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w6-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w6-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 2160,
                "id" : "half-hansons-beginner-w6-d2-line-1",
                "kind" : "interval",
                "label" : "12x400m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w6-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w6-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w6-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w6-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w6-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-beginner-w6-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w6-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w6-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w6-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w6-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w6-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w6-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w6-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w6-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 4710,
                "id" : "half-hansons-beginner-w6-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 9 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w6-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "9 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-7-progress-into-structured-half-marathon-work",
        "index" : 7,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 7 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w7-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w7-d1-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w7-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w7-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1440,
                "id" : "half-hansons-beginner-w7-d2-line-1",
                "kind" : "interval",
                "label" : "8x600m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w7-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n8x600m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w7-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w7-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w7-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w7-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-beginner-w7-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w7-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w7-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-beginner-w7-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 4 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w7-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w7-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w7-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w7-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w7-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w7-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w7-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-8-progress-into-structured-half-marathon-work",
        "index" : 8,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 8 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w8-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w8-d1-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w8-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w8-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1080,
                "id" : "half-hansons-beginner-w8-d2-line-1",
                "kind" : "interval",
                "label" : "6x800m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w8-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w8-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w8-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w8-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w8-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-beginner-w8-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w8-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w8-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w8-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w8-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w8-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w8-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w8-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w8-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w8-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w8-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-9-progress-into-structured-half-marathon-work",
        "index" : 9,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 9 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w9-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w9-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w9-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w9-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1200,
                "id" : "half-hansons-beginner-w9-d2-line-1",
                "kind" : "interval",
                "label" : "5x1k @ 5k-10k pace w. 600m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w9-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w9-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w9-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w9-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w9-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-beginner-w9-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w9-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w9-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w9-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w9-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w9-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w9-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w9-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w9-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w9-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w9-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-10-progress-into-structured-half-marathon-work",
        "index" : 10,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 10 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w10-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w10-d1-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w10-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w10-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 960,
                "id" : "half-hansons-beginner-w10-d2-line-1",
                "kind" : "interval",
                "label" : "4x1,200m @ 5k-10k pace w. 600m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w10-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1,200m @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w10-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w10-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w10-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w10-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-beginner-w10-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w10-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w10-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w10-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w10-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w10-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w10-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w10-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w10-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-beginner-w10-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w10-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-11-progress-into-structured-half-marathon-work",
        "index" : 11,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 11 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w11-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w11-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w11-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w11-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1080,
                "id" : "half-hansons-beginner-w11-d2-line-1",
                "kind" : "interval",
                "label" : "6x1 miles @ HMP -10s w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w11-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x1 miles @ HMP -10s w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w11-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w11-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w11-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w11-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-beginner-w11-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w11-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w11-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w11-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w11-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w11-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w11-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w11-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w11-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w11-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w11-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-12-progress-into-structured-half-marathon-work",
        "index" : 12,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 12 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w12-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w12-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w12-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w12-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1200,
                "id" : "half-hansons-beginner-w12-d2-line-1",
                "kind" : "interval",
                "label" : "4x1.5 miles @ HMP -10s w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w12-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1.5 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w12-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w12-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w12-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w12-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-beginner-w12-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w12-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w12-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w12-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w12-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w12-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w12-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w12-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w12-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-beginner-w12-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w12-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-13-progress-into-structured-half-marathon-work",
        "index" : 13,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 13 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w13-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w13-d1-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w13-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w13-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 900,
                "id" : "half-hansons-beginner-w13-d2-line-1",
                "kind" : "interval",
                "label" : "3x2 miles @ HMP -10s w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w13-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3x2 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w13-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w13-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w13-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w13-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-beginner-w13-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w13-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w13-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w13-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w13-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w13-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w13-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w13-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w13-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w13-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w13-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-14-progress-into-structured-half-marathon-work",
        "index" : 14,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 14 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w14-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w14-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w14-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w14-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 960,
                "id" : "half-hansons-beginner-w14-d2-line-1",
                "kind" : "interval",
                "label" : "2x3 miles @ HMP -10s w. 1 miles jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w14-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n2x3 miles @ HMP -10s w. 1 miles jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w14-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w14-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w14-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w14-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-beginner-w14-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w14-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w14-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w14-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w14-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w14-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w14-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w14-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w14-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-beginner-w14-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w14-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-15-progress-into-structured-half-marathon-work",
        "index" : 15,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 15 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w15-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-beginner-w15-d1-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 7 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w15-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w15-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 900,
                "id" : "half-hansons-beginner-w15-d2-line-1",
                "kind" : "interval",
                "label" : "3x2 miles @ HMP -10s w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w15-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3x2 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w15-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w15-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w15-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w15-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-beginner-w15-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w15-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w15-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w15-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w15-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w15-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w15-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w15-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w15-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-beginner-w15-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w15-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-16-progress-into-structured-half-marathon-work",
        "index" : 16,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 16 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w16-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w16-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w16-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w16-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1200,
                "id" : "half-hansons-beginner-w16-d2-line-1",
                "kind" : "interval",
                "label" : "4x1.5 miles @ HMP -10s w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w16-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1.5 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w16-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w16-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w16-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w16-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-beginner-w16-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w16-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w16-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w16-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w16-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w16-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w16-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-beginner-w16-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w16-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-beginner-w16-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-beginner-w16-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-17-progress-into-structured-half-marathon-work",
        "index" : 17,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 17 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w17-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w17-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-beginner-w17-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w17-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1080,
                "id" : "half-hansons-beginner-w17-d2-line-1",
                "kind" : "interval",
                "label" : "6x1 miles @ HMP -10s w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w17-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x1 miles @ HMP -10s w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w17-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w17-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-beginner-w17-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w17-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-beginner-w17-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles@ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-beginner-w17-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w17-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w17-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w17-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w17-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w17-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 4440,
                "id" : "half-hansons-beginner-w17-d7-main",
                "kind" : "steady",
                "label" : "Easy run 8 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w17-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 8 miles",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Progress into structured half-marathon work",
        "id" : "week-18-progress-into-structured-half-marathon-work",
        "index" : 18,
        "notes" : [
          "This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."
        ],
        "summary" : "Imported beginner half week 18 with 5 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w18-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w18-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-beginner-w18-d2",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-beginner-w18-d2-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Wed",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w18-d3",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d3-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-beginner-w18-d3-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d3-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 6 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w18-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-beginner-w18-d4-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 5 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-beginner-w18-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-beginner-w18-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-beginner-w18-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Easy 3 miles",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Stay calmer than feels natural in the opening stretch.",
            "dayLabel" : "Sat",
            "distanceLabel" : "13.1 mi",
            "durationSeconds" : 8253,
            "effortLabel" : "Race effort",
            "id" : "half-hansons-beginner-w18-d6",
            "isOptional" : false,
            "kind" : "race",
            "purpose" : "Express the training with patient pacing and a strong finish.",
            "steps" : [
              {
                "detail" : "Stay loose.",
                "durationSeconds" : 600,
                "id" : "half-hansons-beginner-w18-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Start controlled and build late.",
                "durationSeconds" : 7053,
                "id" : "half-hansons-beginner-w18-d6-race",
                "kind" : "race",
                "label" : "Race effort 13.1 mi"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 600,
                "id" : "half-hansons-beginner-w18-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Race Day!",
            "title" : "Race day"
          }
        ]
      }
    ]
  },
  {
    "baseLongSessionMinutes" : 95,
    "baseWeeklyMinutes" : 260,
    "defaultWeeks" : 18,
    "focus" : "halfMarathon",
    "highlights" : [
      "Multiple easy-run days support quality instead of replacing it.",
      "Regular HMP and interval workouts make the structure highly specific.",
      "Peak long runs and weekly load are significantly higher than the beginner and local half plans."
    ],
    "id" : "run-half-hansons-advanced-v1",
    "maxSessionsPerWeek" : 6,
    "minSessionsPerWeek" : 5,
    "source" : {
      "attribution" : "Cody Hoover's time-to-run built-in plan library",
      "importNotes" : "Imported from the open-source `src/workouts/plans` built-in plans and translated into Outbound's structured week and workout model.",
      "license" : "MIT",
      "name" : "time-to-run",
      "url" : "https://github.com/hoovercj/time-to-run"
    },
    "sport" : "run",
    "subtitle" : "A higher-volume imported half plan with frequent easy mileage, race-pace work, interval sessions, and longer long runs.",
    "summary" : "An advanced imported option for runners who already tolerate consistent weekly mileage and want a denser plan.",
    "title" : "Half marathon advanced import",
    "weeks" : [
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-1-carry-higher-half-marathon-volume",
        "index" : 1,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 1 with 4 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Mon",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w1-d1",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w1-d1-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Tue",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w1-d2",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w1-d2-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w1-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w1-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w1-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w1-d4-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "3 mi",
            "durationSeconds" : 1890,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w1-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1290,
                "id" : "half-hansons-advanced-w1-d5-main",
                "kind" : "steady",
                "label" : "Easy run 3 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "3 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w1-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w1-d6-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w1-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w1-d7-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w1-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-2-carry-higher-half-marathon-volume",
        "index" : 2,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 2 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w2-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w2-d1-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w2-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w2-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 2160,
                "id" : "half-hansons-advanced-w2-d2-line-1",
                "kind" : "interval",
                "label" : "12x400m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w2-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w2-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w2-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w2-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w2-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-advanced-w2-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w2-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w2-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w2-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w2-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w2-d6-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w2-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w2-d7-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w2-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-3-carry-higher-half-marathon-volume",
        "index" : 3,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 3 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w3-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w3-d1-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w3-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w3-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1440,
                "id" : "half-hansons-advanced-w3-d2-line-1",
                "kind" : "interval",
                "label" : "8x600m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w3-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n8x600m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w3-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w3-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w3-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w3-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-advanced-w3-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w3-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w3-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w3-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w3-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w3-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w3-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-advanced-w3-d7-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w3-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "7 miles Easy",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-4-carry-higher-half-marathon-volume",
        "index" : 4,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 4 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w4-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w4-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w4-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w4-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1080,
                "id" : "half-hansons-advanced-w4-d2-line-1",
                "kind" : "interval",
                "label" : "6x800m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w4-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w4-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w4-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3870,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w4-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w4-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 1890,
                "id" : "half-hansons-advanced-w4-d4-line-1",
                "kind" : "tempo",
                "label" : "3 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w4-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w4-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w4-d5-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w4-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w4-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w4-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 4440,
                "id" : "half-hansons-advanced-w4-d7-main",
                "kind" : "steady",
                "label" : "Easy run 8 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w4-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "8 miles Easy",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-5-carry-higher-half-marathon-volume",
        "index" : 5,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 5 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "4 mi",
            "durationSeconds" : 2520,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w5-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 1920,
                "id" : "half-hansons-advanced-w5-d1-main",
                "kind" : "steady",
                "label" : "Easy run 4 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "4 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w5-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w5-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1200,
                "id" : "half-hansons-advanced-w5-d2-line-1",
                "kind" : "interval",
                "label" : "5x1k @ 5k-10k pace w. 600m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w5-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w5-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w5-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w5-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w5-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-advanced-w5-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w5-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w5-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w5-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w5-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w5-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w5-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w5-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w5-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w5-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w5-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-6-carry-higher-half-marathon-volume",
        "index" : 6,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 6 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w6-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w6-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w6-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w6-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 960,
                "id" : "half-hansons-advanced-w6-d2-line-1",
                "kind" : "interval",
                "label" : "4x1,200m @ 5k-10k pace w. 600m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w6-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1,200m @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w6-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w6-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w6-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w6-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-advanced-w6-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w6-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w6-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w6-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w6-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w6-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w6-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w6-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w6-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-advanced-w6-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w6-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-7-carry-higher-half-marathon-volume",
        "index" : 7,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 7 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w7-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w7-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w7-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w7-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 900,
                "id" : "half-hansons-advanced-w7-d2-line-1",
                "kind" : "interval",
                "label" : "3x1 miles @ 5k-10k pace w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w7-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3x1 miles @ 5k-10k pace w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w7-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w7-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4500,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w7-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w7-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 2520,
                "id" : "half-hansons-advanced-w7-d4-line-1",
                "kind" : "tempo",
                "label" : "4 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w7-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w7-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w7-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w7-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w7-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w7-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w7-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w7-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w7-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w7-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-8-carry-higher-half-marathon-volume",
        "index" : 8,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 8 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w8-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w8-d1-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w8-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w8-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1200,
                "id" : "half-hansons-advanced-w8-d2-line-1",
                "kind" : "interval",
                "label" : "5x1k @ 5k-10k pace w. 600m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w8-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w8-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w8-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w8-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w8-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-advanced-w8-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w8-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w8-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w8-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w8-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w8-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w8-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w8-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w8-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-advanced-w8-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w8-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-9-carry-higher-half-marathon-volume",
        "index" : 9,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 9 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w9-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w9-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w9-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w9-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1080,
                "id" : "half-hansons-advanced-w9-d2-line-1",
                "kind" : "interval",
                "label" : "6x800m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w9-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w9-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w9-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w9-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w9-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-advanced-w9-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w9-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w9-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w9-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w9-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w9-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w9-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w9-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w9-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w9-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w9-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-10-carry-higher-half-marathon-volume",
        "index" : 10,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 10 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w10-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-advanced-w10-d1-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "7 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5670,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w10-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w10-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 2160,
                "id" : "half-hansons-advanced-w10-d2-line-1",
                "kind" : "interval",
                "label" : "12x400m @ 5k-10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w10-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w10-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w10-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w10-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w10-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-advanced-w10-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w10-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w10-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w10-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w10-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w10-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w10-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "12 mi",
            "durationSeconds" : 7560,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w10-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w10-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 6600,
                "id" : "half-hansons-advanced-w10-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 12 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w10-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "12 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-11-carry-higher-half-marathon-volume",
        "index" : 11,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 11 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w11-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w11-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w11-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w11-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1080,
                "id" : "half-hansons-advanced-w11-d2-line-1",
                "kind" : "interval",
                "label" : "6x1 miles @ 10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w11-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x1 miles @ 10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w11-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w11-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w11-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w11-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-advanced-w11-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w11-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w11-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w11-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w11-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w11-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w11-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w11-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w11-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w11-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w11-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-12-carry-higher-half-marathon-volume",
        "index" : 12,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 12 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w12-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w12-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w12-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w12-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1200,
                "id" : "half-hansons-advanced-w12-d2-line-1",
                "kind" : "interval",
                "label" : "4x1.5 miles @ 10k pace w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w12-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1.5 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w12-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w12-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w12-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w12-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-advanced-w12-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w12-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w12-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w12-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w12-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w12-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w12-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "14 mi",
            "durationSeconds" : 8820,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w12-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w12-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 7860,
                "id" : "half-hansons-advanced-w12-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 14 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w12-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "14 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-13-carry-higher-half-marathon-volume",
        "index" : 13,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 13 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w13-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-advanced-w13-d1-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "7 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w13-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w13-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 900,
                "id" : "half-hansons-advanced-w13-d2-line-1",
                "kind" : "interval",
                "label" : "3x2 miles @ 10k pace w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w13-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3x2 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w13-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w13-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "9 mi",
            "durationSeconds" : 5760,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w13-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w13-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3780,
                "id" : "half-hansons-advanced-w13-d4-line-1",
                "kind" : "tempo",
                "label" : "6 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w13-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w13-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w13-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w13-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w13-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w13-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w13-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w13-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w13-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w13-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-14-carry-higher-half-marathon-volume",
        "index" : 14,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 14 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w14-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w14-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w14-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w14-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 960,
                "id" : "half-hansons-advanced-w14-d2-line-1",
                "kind" : "interval",
                "label" : "2x3 miles @ 10k pace w. 1 miles jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w14-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n2x3 miles @ 10k pace w. 1 miles jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w14-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w14-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6390,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w14-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w14-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 4410,
                "id" : "half-hansons-advanced-w14-d4-line-1",
                "kind" : "tempo",
                "label" : "7 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w14-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w14-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w14-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w14-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w14-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w14-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "14 mi",
            "durationSeconds" : 8820,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w14-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w14-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 7860,
                "id" : "half-hansons-advanced-w14-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 14 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w14-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "14 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-15-carry-higher-half-marathon-volume",
        "index" : 15,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 15 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w15-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-advanced-w15-d1-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "7 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w15-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w15-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 900,
                "id" : "half-hansons-advanced-w15-d2-line-1",
                "kind" : "interval",
                "label" : "3x2 miles @ 10k pace w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w15-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n3x2 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w15-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w15-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6390,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w15-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w15-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 4410,
                "id" : "half-hansons-advanced-w15-d4-line-1",
                "kind" : "tempo",
                "label" : "7 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w15-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w15-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w15-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w15-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w15-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w15-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w15-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w15-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 5340,
                "id" : "half-hansons-advanced-w15-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 10 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w15-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "10 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-16-carry-higher-half-marathon-volume",
        "index" : 16,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 16 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w16-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w16-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w16-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w16-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1200,
                "id" : "half-hansons-advanced-w16-d2-line-1",
                "kind" : "interval",
                "label" : "4x1.5 miles @ 10k pace w. 800m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w16-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n4x1.5 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w16-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w16-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6390,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w16-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w16-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 4410,
                "id" : "half-hansons-advanced-w16-d4-line-1",
                "kind" : "tempo",
                "label" : "7 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w16-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w16-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w16-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w16-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w16-d6-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w16-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run this patiently enough that the last third still looks relaxed.",
            "dayLabel" : "Sun",
            "distanceLabel" : "14 mi",
            "durationSeconds" : 8820,
            "effortLabel" : "Easy-steady",
            "id" : "half-hansons-advanced-w16-d7",
            "isOptional" : false,
            "kind" : "longRun",
            "purpose" : "Build range and aerobic durability.",
            "steps" : [
              {
                "detail" : "Settle in gradually.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w16-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the effort below strain.",
                "durationSeconds" : 7860,
                "id" : "half-hansons-advanced-w16-d7-main",
                "kind" : "steady",
                "label" : "Endurance run 14 mi"
              },
              {
                "detail" : "Walk a bit before stopping.",
                "durationSeconds" : 480,
                "id" : "half-hansons-advanced-w16-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "14 miles Long Run",
            "title" : "Long run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-17-carry-higher-half-marathon-volume",
        "index" : 17,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 17 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "7 mi",
            "durationSeconds" : 4410,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w17-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3810,
                "id" : "half-hansons-advanced-w17-d1-main",
                "kind" : "steady",
                "label" : "Easy run 7 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "7 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Run the reps with control so the final one still looks clean.",
            "dayLabel" : "Tue",
            "distanceLabel" : "10 mi",
            "durationSeconds" : 6300,
            "effortLabel" : "Controlled fast",
            "id" : "half-hansons-advanced-w17-d2",
            "isOptional" : false,
            "kind" : "interval",
            "purpose" : "Build speed support and rhythm changes without turning the whole week hard.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w17-d2-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "durationSeconds" : 1080,
                "id" : "half-hansons-advanced-w17-d2-line-1",
                "kind" : "interval",
                "label" : "6x1 miles @ 10k pace w. 400m jog rest"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w17-d2-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n6x1 miles @ 10k pace w. 400m jog rest\n1.5 miles Cool Down",
            "title" : "Interval session"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w17-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w17-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Lock into rhythm instead of chasing pace.",
            "dayLabel" : "Thu",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5130,
            "effortLabel" : "Steady threshold",
            "id" : "half-hansons-advanced-w17-d4",
            "isOptional" : false,
            "kind" : "tempo",
            "purpose" : "Practice goal-rhythm work inside a supported session.",
            "steps" : [
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w17-d4-line-0",
                "kind" : "warmup",
                "label" : "1.5 miles Warm Up"
              },
              {
                "detail" : "Run this at controlled half-marathon effort.",
                "durationSeconds" : 3150,
                "id" : "half-hansons-advanced-w17-d4-line-1",
                "kind" : "tempo",
                "label" : "5 miles @ HMP"
              },
              {
                "durationSeconds" : 990,
                "id" : "half-hansons-advanced-w17-d4-line-2",
                "kind" : "cooldown",
                "label" : "1.5 miles Cool Down"
              }
            ],
            "summary" : "1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down",
            "title" : "Half-marathon pace run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w17-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w17-d5-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sat",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w17-d6",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w17-d6-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Sun",
            "distanceLabel" : "8 mi",
            "durationSeconds" : 5040,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w17-d7",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 4440,
                "id" : "half-hansons-advanced-w17-d7-main",
                "kind" : "steady",
                "label" : "Easy run 8 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w17-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "8 miles Easy",
            "title" : "Easy run"
          }
        ]
      },
      {
        "focus" : "Carry higher half-marathon volume",
        "id" : "week-18-carry-higher-half-marathon-volume",
        "index" : 18,
        "notes" : [
          "This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."
        ],
        "summary" : "Imported advanced half week 18 with 6 scheduled items.",
        "workouts" : [
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Mon",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w18-d1",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d1-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w18-d1-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d1-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Tue",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w18-d2",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d2-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w18-d2-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d2-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Take the easiest option that helps you absorb the week.",
            "dayLabel" : "Wed",
            "durationSeconds" : 1800,
            "effortLabel" : "Optional easy",
            "id" : "half-hansons-advanced-w18-d3",
            "isOptional" : true,
            "kind" : "crossTrain",
            "purpose" : "Use this day for recovery or light aerobic support.",
            "steps" : [
              {
                "detail" : "Walk, bike, mobility, or take the day off entirely.",
                "durationSeconds" : 1800,
                "id" : "half-hansons-advanced-w18-d3-main",
                "kind" : "crossTrain",
                "label" : "Optional cross-train or full rest"
              }
            ],
            "summary" : "Rest or Cross-Train",
            "title" : "Rest or cross-train"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Thu",
            "distanceLabel" : "6 mi",
            "durationSeconds" : 3780,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w18-d4",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d4-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 3180,
                "id" : "half-hansons-advanced-w18-d4-main",
                "kind" : "steady",
                "label" : "Easy run 6 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d4-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "6 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Let this support the week rather than steal from it.",
            "dayLabel" : "Fri",
            "distanceLabel" : "5 mi",
            "durationSeconds" : 3150,
            "effortLabel" : "Conversational",
            "id" : "half-hansons-advanced-w18-d5",
            "isOptional" : false,
            "kind" : "easy",
            "purpose" : "Add aerobic support while preserving recovery.",
            "steps" : [
              {
                "detail" : "Start relaxed.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d5-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Keep the whole run conversational.",
                "durationSeconds" : 2550,
                "id" : "half-hansons-advanced-w18-d5-main",
                "kind" : "steady",
                "label" : "Easy run 5 mi"
              },
              {
                "detail" : "Bring the session down calmly.",
                "durationSeconds" : 300,
                "id" : "half-hansons-advanced-w18-d5-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "5 miles Easy",
            "title" : "Easy run"
          },
          {
            "coachCue" : "Keep it tiny. Fresh beats fit right now.",
            "dayLabel" : "Sat",
            "durationSeconds" : 1920,
            "effortLabel" : "Very easy",
            "id" : "half-hansons-advanced-w18-d6",
            "isOptional" : false,
            "kind" : "recovery",
            "purpose" : "Promote recovery while keeping the habit alive.",
            "steps" : [
              {
                "detail" : "No rush.",
                "durationSeconds" : 240,
                "id" : "half-hansons-advanced-w18-d6-warmup",
                "kind" : "warmup",
                "label" : "Warm up walk"
              },
              {
                "detail" : "Stay well below strain.",
                "durationSeconds" : 1440,
                "id" : "half-hansons-advanced-w18-d6-main",
                "kind" : "recovery",
                "label" : "Recovery jog"
              },
              {
                "detail" : "Finish feeling refreshed.",
                "durationSeconds" : 240,
                "id" : "half-hansons-advanced-w18-d6-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "3 miles Shakeout Run",
            "title" : "Recovery run"
          },
          {
            "coachCue" : "Stay calmer than feels natural in the opening stretch.",
            "dayLabel" : "Sun",
            "distanceLabel" : "13.1 mi",
            "durationSeconds" : 8253,
            "effortLabel" : "Race effort",
            "id" : "half-hansons-advanced-w18-d7",
            "isOptional" : false,
            "kind" : "race",
            "purpose" : "Express the training with patient pacing and a strong finish.",
            "steps" : [
              {
                "detail" : "Stay loose.",
                "durationSeconds" : 600,
                "id" : "half-hansons-advanced-w18-d7-warmup",
                "kind" : "warmup",
                "label" : "Warm up jog"
              },
              {
                "detail" : "Start controlled and build late.",
                "durationSeconds" : 7053,
                "id" : "half-hansons-advanced-w18-d7-race",
                "kind" : "race",
                "label" : "Race effort 13.1 mi"
              },
              {
                "detail" : "Let the effort taper off.",
                "durationSeconds" : 600,
                "id" : "half-hansons-advanced-w18-d7-cooldown",
                "kind" : "cooldown",
                "label" : "Cooldown walk"
              }
            ],
            "summary" : "Race Day!",
            "title" : "Race day"
          }
        ]
      }
    ]
  }
];
