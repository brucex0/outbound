import Foundation

enum TrainingPlanLibrary {
    static let importedC25KSource = TrainingPlanSource(
        name: "c25k-web",
        license: "MIT",
        attribution: "Luke Murchison's c25k-web Couch-to-5K plan data",
        url: "https://github.com/lmorchard/c25k-web",
        importNotes: "Imported from the open-source `src/data/c25k.json` plan and translated into Outbound's workout model."
    )

    static let workoutTaxonomySource = TrainingPlanSource(
        name: "training-planner",
        license: "MIT",
        attribution: "Daniel Coats's training-planner sample workout taxonomy",
        url: "https://github.com/danielcoats/training-planner",
        importNotes: "Used as an open-source reference for realistic workout labels and session types like long runs, intervals, fartlek, cross-train, and time trials."
    )

    static let timeToRunSource = TrainingPlanSource(
        name: "time-to-run",
        license: "MIT",
        attribution: "Cody Hoover's time-to-run built-in plan library",
        url: "https://github.com/hoovercj/time-to-run",
        importNotes: "Imported from the open-source `src/workouts/plans` built-in plans and translated into Outbound's structured week and workout model."
    )

    static let templates: [TrainingPlanTemplate] = [
        base30Template,
        consistencyTemplate,
        comebackTemplate,
        fiveKTemplate,
        tenKTemplate,
        tenMileTemplate,
        halfTemplate,
        halfHansonsBeginnerTemplate,
        halfHansonsAdvancedTemplate
    ]

    static func fallbackWorkout(for focus: TrainingPlanFocus) -> TrainingPlanWorkout {
        switch focus {
        case .comeback:
            return walkRun(
                id: "fallback-comeback",
                day: "Today",
                title: "Reset walk-run",
                durationMinutes: 20,
                summary: "Short and low-pressure.",
                cue: "Keep the first restart small enough that you'd do it again tomorrow.",
                runSeconds: 60,
                walkSeconds: 90,
                repeats: 6
            )
        case .consistency:
            return easyRun(
                id: "fallback-consistency",
                day: "Today",
                title: "Consistency run",
                durationMinutes: 25,
                summary: "A simple aerobic run to keep the week moving.",
                cue: "The goal is to protect rhythm, not squeeze out a big performance day."
            )
        case .fiveK:
            return easyRun(
                id: "fallback-5k",
                day: "Today",
                title: "Easy 5K support run",
                durationMinutes: 30,
                summary: "A calm aerobic run that keeps the plan alive.",
                cue: "Stay easy and leave something in the tank."
            )
        case .tenK:
            return easyRun(
                id: "fallback-10k",
                day: "Today",
                title: "Aerobic 10K support run",
                durationMinutes: 35,
                summary: "Steady running without extra pressure.",
                cue: "Smooth beats fast today."
            )
        case .tenMile, .halfMarathon:
            return longRun(
                id: "fallback-endurance",
                day: "Today",
                durationMinutes: 60,
                summary: "An easy long aerobic day.",
                cue: "Let patience be the workout."
            )
        }
    }

    static func completionWorkout(for focus: TrainingPlanFocus) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: "completion-\(focus.rawValue)",
            title: "Optional recovery shakeout",
            kind: .recovery,
            dayLabel: "Optional",
            summary: "You already covered the core week.",
            purpose: "Keep moving lightly if you want a little extra freshness.",
            coachCue: "The plan is already intact. Anything here should feel restorative.",
            effortLabel: "Very easy",
            durationSeconds: 20 * 60,
            distanceLabel: nil,
            steps: [
                step("completion-warmup", .warmup, "Warm up walk", 4 * 60, "Relax your shoulders."),
                step("completion-run", .recovery, "Easy jog or brisk walk", 12 * 60, "Stay well below strain."),
                step("completion-cooldown", .cooldown, "Cooldown walk", 4 * 60, "Finish feeling fresh.")
            ],
            isOptional: true
        )
    }

    private static let consistencyTemplate = TrainingPlanTemplate(
        id: "run-consistency-v1",
        focus: .consistency,
        sport: .run,
        title: "Consistency builder",
        subtitle: "A realistic rhythm for showing up without race pressure.",
        defaultWeeks: 4,
        minSessionsPerWeek: 2,
        maxSessionsPerWeek: 4,
        baseWeeklyMinutes: 80,
        baseLongSessionMinutes: 35,
        summary: "Three manageable sessions each week with one optional extra so consistency can survive normal life.",
        highlights: [
            "Two easy aerobic runs anchor the week.",
            "A short quality touch keeps things interesting without dominating the schedule.",
            "One optional session gives flexibility instead of guilt."
        ],
        source: workoutTaxonomySource,
        weeks: [
            week(
                1,
                focus: "Find a repeatable rhythm",
                summary: "Start with repeatable sessions that feel almost too manageable.",
                workouts: [
                    easyRun(id: "consistency-w1-1", day: "Tue", title: "Easy start run", durationMinutes: 25, summary: "Simple conversational running.", cue: "If this feels easy, that's a good sign."),
                    fartlekRun(id: "consistency-w1-2", day: "Thu", durationMinutes: 28, summary: "Light variation to break up the week.", cue: "Float the quicker bits; don't turn them into sprints.", hardSeconds: 60, easySeconds: 90, repeats: 6),
                    longRun(id: "consistency-w1-3", day: "Sat", durationMinutes: 35, summary: "Gentle endurance support.", cue: "Finish with the same calm pace you started with."),
                    crossTrain(id: "consistency-w1-4", day: "Sun", durationMinutes: 25, summary: "Optional recovery movement.", cue: "Choose something that opens you up, not something that buries you.", optional: true)
                ],
                notes: ["Missing one run is not failure. Just return to the next planned session."]
            ),
            week(
                2,
                focus: "Add one small stretch",
                summary: "Keep the structure familiar while nudging one session slightly longer.",
                workouts: [
                    easyRun(id: "consistency-w2-1", day: "Tue", title: "Easy rhythm run", durationMinutes: 28, summary: "Steady and unremarkable on purpose.", cue: "This is habit work."),
                    hillRun(id: "consistency-w2-2", day: "Thu", durationMinutes: 30, summary: "Short controlled hill efforts.", cue: "Run tall and keep the recoveries patient.", hardSeconds: 45, easySeconds: 75, repeats: 6),
                    longRun(id: "consistency-w2-3", day: "Sat", durationMinutes: 40, summary: "Longer aerobic support.", cue: "Let the run stay chatty from start to finish."),
                    crossTrain(id: "consistency-w2-4", day: "Sun", durationMinutes: 30, summary: "Optional bike, walk, or mobility.", cue: "Optional really means optional.", optional: true)
                ],
                notes: ["If life gets noisy this week, keep the easy run and the long run."]
            ),
            week(
                3,
                focus: "Protect momentum",
                summary: "The plan now feels familiar, so the priority is protecting the routine.",
                workouts: [
                    easyRun(id: "consistency-w3-1", day: "Tue", title: "Easy support run", durationMinutes: 30, summary: "Settle into a natural cadence.", cue: "Keep the effort low enough to recover fast."),
                    tempoRun(id: "consistency-w3-2", day: "Thu", durationMinutes: 32, summary: "Controlled steady work just under strain.", cue: "Comfortably hard beats dramatic.", blocks: [6 * 60, 6 * 60], floatSeconds: 3 * 60),
                    longRun(id: "consistency-w3-3", day: "Sat", durationMinutes: 42, summary: "A patient aerobic finish to the week.", cue: "This one should build calm confidence."),
                    recoveryRun(id: "consistency-w3-4", day: "Sun", durationMinutes: 20, summary: "Optional shuffle to stay loose.", cue: "Only do this if your legs want it.", optional: true)
                ],
                notes: ["Cut the optional day first if recovery feels off."]
            ),
            week(
                4,
                focus: "Land the block feeling better",
                summary: "A cutback week that still keeps the routine intact.",
                workouts: [
                    easyRun(id: "consistency-w4-1", day: "Tue", title: "Easy cutback run", durationMinutes: 24, summary: "Shorter on purpose.", cue: "Less is more this week."),
                    fartlekRun(id: "consistency-w4-2", day: "Thu", durationMinutes: 24, summary: "A playful tune-up.", cue: "Stay loose; the goal is pop, not fatigue.", hardSeconds: 45, easySeconds: 75, repeats: 5),
                    longRun(id: "consistency-w4-3", day: "Sat", durationMinutes: 32, summary: "A shorter long run to bank freshness.", cue: "End with plenty left."),
                    crossTrain(id: "consistency-w4-4", day: "Sun", durationMinutes: 25, summary: "Optional easy spin or walk.", cue: "Use this to reset, not to chase numbers.", optional: true)
                ],
                notes: ["A good cutback week should make you want the next block."]
            )
        ]
    )

    private static let comebackTemplate = TrainingPlanTemplate(
        id: "run-comeback-v1",
        focus: .comeback,
        sport: .run,
        title: "Comeback runway",
        subtitle: "A soft return to structure after a gap or rough patch.",
        defaultWeeks: 4,
        minSessionsPerWeek: 2,
        maxSessionsPerWeek: 3,
        baseWeeklyMinutes: 55,
        baseLongSessionMinutes: 28,
        summary: "Walk-run sessions progress gently, with enough recovery built in that restarting feels doable instead of scary.",
        highlights: [
            "Walk-run ratios keep impact low while routine comes back.",
            "Rest days are part of the design, not evidence of weakness.",
            "The final week leaves enough headroom to continue instead of crash."
        ],
        source: workoutTaxonomySource,
        weeks: [
            week(
                1,
                focus: "Reconnect with the routine",
                summary: "Short sessions designed to feel safe and finish strong.",
                workouts: [
                    walkRun(id: "comeback-w1-1", day: "Tue", title: "Restart session", durationMinutes: 20, summary: "One-minute run / 90-second walk rhythm.", cue: "The win is simply getting moving again.", runSeconds: 60, walkSeconds: 90, repeats: 6),
                    walkRun(id: "comeback-w1-2", day: "Thu", title: "Repeatable return", durationMinutes: 22, summary: "Same rhythm with a touch more time.", cue: "Keep the runs gentle enough to finish calm.", runSeconds: 60, walkSeconds: 90, repeats: 7),
                    easyRun(id: "comeback-w1-3", day: "Sat", title: "Long easy walk or jog", durationMinutes: 25, summary: "Choose the easiest version that feels inviting.", cue: "No catching up. Just collect time on feet.")
                ],
                notes: ["If any run segment feels sticky, switch the whole session to brisk walking."]
            ),
            week(
                2,
                focus: "Lengthen carefully",
                summary: "The run segments get a little longer, but recovery still leads.",
                workouts: [
                    walkRun(id: "comeback-w2-1", day: "Tue", title: "Run-walk build", durationMinutes: 24, summary: "90-second run / 90-second walk.", cue: "Keep every run segment at easy effort.", runSeconds: 90, walkSeconds: 90, repeats: 7),
                    recoveryRun(id: "comeback-w2-2", day: "Thu", durationMinutes: 18, summary: "A soft shuffle or brisk walk.", cue: "Take the easiest line that keeps momentum."),
                    walkRun(id: "comeback-w2-3", day: "Sat", title: "Confidence session", durationMinutes: 28, summary: "Two-minute run / 90-second walk.", cue: "Don't rush the first half.", runSeconds: 120, walkSeconds: 90, repeats: 7)
                ],
                notes: ["This is still a restart block. Err on the side of too easy."]
            ),
            week(
                3,
                focus: "Blend into steady running",
                summary: "The walks shrink and the running begins to connect.",
                workouts: [
                    walkRun(id: "comeback-w3-1", day: "Tue", title: "Connected effort", durationMinutes: 26, summary: "Three-minute run / 90-second walk.", cue: "Run smooth rather than ambitious.", runSeconds: 180, walkSeconds: 90, repeats: 5),
                    easyRun(id: "comeback-w3-2", day: "Thu", title: "Easy continuous run", durationMinutes: 20, summary: "Run easy the whole way if you can, or insert walks as needed.", cue: "A tiny continuous run is enough."),
                    longRun(id: "comeback-w3-3", day: "Sat", durationMinutes: 30, summary: "Easy endurance on forgiving effort.", cue: "Keep the final ten minutes especially controlled.")
                ],
                notes: ["If Thursday feels forced, convert it back into a walk-run."]
            ),
            week(
                4,
                focus: "Finish wanting more",
                summary: "A calm finish that sets up the next block rather than exhausting you.",
                workouts: [
                    easyRun(id: "comeback-w4-1", day: "Tue", title: "Easy confidence run", durationMinutes: 22, summary: "Simple continuous running.", cue: "Stay within yourself."),
                    fartlekRun(id: "comeback-w4-2", day: "Thu", durationMinutes: 24, summary: "Short surges to wake the legs up.", cue: "The quicker segments should feel playful.", hardSeconds: 45, easySeconds: 90, repeats: 5),
                    longRun(id: "comeback-w4-3", day: "Sat", durationMinutes: 32, summary: "A patient aerobic close to the block.", cue: "Land this run feeling like you could have kept going.")
                ],
                notes: ["This block is successful if it makes the next month feel possible."]
            )
        ]
    )

    private static let fiveKTemplate = TrainingPlanTemplate(
        id: "run-5k-v1",
        focus: .fiveK,
        sport: .run,
        title: "Couch to 5K",
        subtitle: "A full nine-week run/walk progression imported from open-source plan data.",
        defaultWeeks: 9,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 3,
        baseWeeklyMinutes: 90,
        baseLongSessionMinutes: 35,
        summary: "Three sessions each week move from short run-walk intervals to a continuous 30-minute run.",
        highlights: [
            "Every week has a clear progression target instead of vague mileage.",
            "Warmups and cooldowns are built into every workout.",
            "The later weeks reduce complexity and build continuous-running confidence."
        ],
        source: importedC25KSource,
        weeks: importedC25KWeeks()
    )

    private static let base30Template = TrainingPlanTemplate(
        id: "run-base-30-v1",
        focus: .consistency,
        sport: .run,
        title: "Base building 30 mpw",
        subtitle: "A 10-week imported base phase built around general aerobic work, strides, threshold touches, and endurance long runs.",
        defaultWeeks: 10,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 4,
        baseWeeklyMinutes: 150,
        baseLongSessionMinutes: 65,
        summary: "A realistic base cycle for runners who want durable weekly rhythm before chasing a sharper race block.",
        highlights: [
            "General aerobic days do most of the work.",
            "Threshold sessions arrive only after the base is established.",
            "Strides and endurance runs add range without constant hard workouts."
        ],
        source: timeToRunSource,
        weeks: importedWeeks(
            prefix: "base30",
            focus: "Build aerobic durability",
            summaryPrefix: "Imported base week",
            notes: ["Treat cross-training days as optional support unless your body benefits from the extra movement."],
            weeks: [
                [("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("General aerobic 3 miles", 3), ("General aerobic 3 miles", 3), ("Rest or cross-training", 0), ("Endurance 6 miles", 6)],
                [("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("General aerobic 3 miles", 3), ("Rest or cross-training", 0), ("Endurance 7 miles", 7)],
                [("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("General aerobic 3 miles", 3), ("Rest or cross-training", 0), ("Endurance 7 miles", 7)],
                [("Rest or cross-training", 0), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("General aerobic 5 miles w/ 6x100m strides", 5), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("Endurance 7 miles", 7)],
                [("Rest or cross-training", 0), ("General aerobic 5 miles", 5), ("Rest or cross-training", 0), ("Lactate threshold 6 miles w/ 16 min tempo", 6), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("Endurance 8 miles", 8)],
                [("Rest or cross-training", 0), ("General aerobic 5 miles", 5), ("Rest or cross-training", 0), ("General aerobic 6 miles w/ 6x100m strides", 6), ("General aerobic 4 miles", 4), ("Rest or cross-training", 0), ("Endurance 8 miles", 8)],
                [("Rest or cross-training", 0), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("Lactate threshold 6 miles w/ 18 min tempo", 6), ("General aerobic 5 miles", 5), ("Rest or cross-training", 0), ("Endurance 8 miles", 8)],
                [("Rest or cross-training", 0), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("General aerobic 7 miles w/ 6x100m strides", 7), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("Endurance 9 miles", 9)],
                [("Rest or cross-training", 0), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("Lactate threshold 7 miles w/ 20 min tempo", 7), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("Endurance 9 miles", 9)],
                [("Rest or cross-training", 0), ("General aerobic 7 miles", 7), ("Rest or cross-training", 0), ("General aerobic 8 miles w/ 8x100m strides", 8), ("General aerobic 6 miles", 6), ("Rest or cross-training", 0), ("Endurance 9 miles", 9)]
            ]
        )
    )

    private static let tenKTemplate = TrainingPlanTemplate(
        id: "run-10k-v1",
        focus: .tenK,
        sport: .run,
        title: "10K builder",
        subtitle: "A balanced 10K block with aerobic support, controlled quality, and progression you can actually recover from.",
        defaultWeeks: 8,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 4,
        baseWeeklyMinutes: 135,
        baseLongSessionMinutes: 55,
        summary: "Four-week structure repeated with progressive long runs, one quality session, and one optional cross-training day.",
        highlights: [
            "Intervals, tempo, and fartlek each appear with a clear purpose.",
            "Long runs build gradually instead of spiking.",
            "Week 4 and week 8 back off so the block stays usable."
        ],
        source: workoutTaxonomySource,
        weeks: [
            buildWeek(index: 1, prefix: "10k-w1", focus: "Set the aerobic floor", summary: "Start with familiar paces and a light workout touch.", easyMinutes: 35, quality: intervalRun(id: "10k-w1-q", day: "Thu", title: "4 x 2 min intervals", summary: "Controlled faster running with easy recoveries.", cue: "Work the reps, but keep the first one restrained.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 120, easySeconds: 120, repeats: 4), longMinutes: 50),
            buildWeek(index: 2, prefix: "10k-w2", focus: "Add steady pressure", summary: "The quality day shifts toward threshold work while the long run grows slightly.", easyMinutes: 36, quality: tempoRun(id: "10k-w2-q", day: "Thu", durationMinutes: 38, summary: "Two controlled tempo blocks.", cue: "Smooth breathing matters more than pace numbers.", blocks: [8 * 60, 8 * 60], floatSeconds: 3 * 60), longMinutes: 55),
            buildWeek(index: 3, prefix: "10k-w3", focus: "Stretch range", summary: "A fartlek session lets you move a little quicker without locking into a pace target.", easyMinutes: 38, quality: fartlekRun(id: "10k-w3-q", day: "Thu", durationMinutes: 40, summary: "Three-minute surges with patient recoveries.", cue: "Think flow, not fight.", hardSeconds: 180, easySeconds: 120, repeats: 5), longMinutes: 60),
            buildWeek(index: 4, prefix: "10k-w4", focus: "Cut back and absorb", summary: "A lighter week keeps the block sustainable.", easyMinutes: 30, quality: hillRun(id: "10k-w4-q", day: "Thu", durationMinutes: 28, summary: "Short hill form session.", cue: "Keep the climbs springy and the recoveries complete.", hardSeconds: 45, easySeconds: 75, repeats: 6), longMinutes: 45),
            buildWeek(index: 5, prefix: "10k-w5", focus: "Rebuild after the cutback", summary: "The second half of the block starts a little stronger than the first.", easyMinutes: 40, quality: intervalRun(id: "10k-w5-q", day: "Thu", title: "5 x 3 min intervals", summary: "Slightly longer reps at controlled 10K effort.", cue: "Keep the final rep looking like the first.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 180, easySeconds: 120, repeats: 5), longMinutes: 62),
            buildWeek(index: 6, prefix: "10k-w6", focus: "Sharpen threshold", summary: "Longer steady blocks make race effort feel calmer.", easyMinutes: 40, quality: tempoRun(id: "10k-w6-q", day: "Thu", durationMinutes: 42, summary: "Three tempo segments with short floats.", cue: "Stay patient for the first two blocks.", blocks: [8 * 60, 8 * 60, 6 * 60], floatSeconds: 2 * 60), longMinutes: 65),
            buildWeek(index: 7, prefix: "10k-w7", focus: "Peak specific work", summary: "A classic open-source-style workout mix of intervals, easy mileage, and a long aerobic finish.", easyMinutes: 35, quality: intervalRun(id: "10k-w7-q", day: "Thu", title: "4 x 800m effort", summary: "Inspired by open-source interval workout seeds.", cue: "Run these at rhythm, not rage.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 240, easySeconds: 120, repeats: 4), longMinutes: 70),
            buildWeek(index: 8, prefix: "10k-w8", focus: "Freshen up and check fitness", summary: "Back off volume, then finish with a controlled 10K effort or local race.", easyMinutes: 28, quality: racePrepRun(id: "10k-w8-q", day: "Thu", durationMinutes: 24, summary: "Short pickups to feel sharp without fatigue.", cue: "Keep this snappy, not draining.", pickupSeconds: 60, floatSeconds: 90, repeats: 5), longMinutes: 40, raceDay: raceRun(id: "10k-w8-race", day: "Sun", title: "10K effort day", durationMinutes: 55, summary: "A local 10K, time trial, or controlled progression run.", cue: "Settle in early and finish the last third with intent."))
        ]
    )

    private static let tenMileTemplate = TrainingPlanTemplate(
        id: "run-10mile-v1",
        focus: .tenMile,
        sport: .run,
        title: "10 mile plan",
        subtitle: "An endurance-focused block for runners ready for longer weekends without turning every weekday into a grind.",
        defaultWeeks: 8,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 4,
        baseWeeklyMinutes: 170,
        baseLongSessionMinutes: 70,
        summary: "Steady midweek work plus gradually longer weekend runs build enough range for a confident 10-mile day.",
        highlights: [
            "Long runs progress from 70 to 95 minutes.",
            "Midweek tempo and hill sessions build durable strength.",
            "Cross-training stays optional so the plan remains livable."
        ],
        source: workoutTaxonomySource,
        weeks: [
            buildWeek(index: 1, prefix: "10m-w1", focus: "Build steady range", summary: "Start with aerobic volume that feels durable.", easyMinutes: 40, quality: hillRun(id: "10m-w1-q", day: "Thu", durationMinutes: 36, summary: "Form-focused hill repetitions.", cue: "Run tall and keep the downhill recoveries easy.", hardSeconds: 60, easySeconds: 90, repeats: 6), longMinutes: 70),
            buildWeek(index: 2, prefix: "10m-w2", focus: "Add tempo control", summary: "The week gets slightly longer while the quality stays measured.", easyMinutes: 42, quality: tempoRun(id: "10m-w2-q", day: "Thu", durationMinutes: 42, summary: "Two ten-minute tempo blocks.", cue: "Stay smooth and avoid a red-line feel.", blocks: [10 * 60, 10 * 60], floatSeconds: 3 * 60), longMinutes: 75),
            buildWeek(index: 3, prefix: "10m-w3", focus: "Carry strength", summary: "The quality day asks for steadier work while the long run extends.", easyMinutes: 44, quality: fartlekRun(id: "10m-w3-q", day: "Thu", durationMinutes: 44, summary: "Alternating surges that build strength without a strict pace target.", cue: "Let the fast bits feel controlled, not all-out.", hardSeconds: 180, easySeconds: 120, repeats: 5), longMinutes: 80),
            buildWeek(index: 4, prefix: "10m-w4", focus: "Absorb the work", summary: "A lighter week before the second build.", easyMinutes: 34, quality: easyRun(id: "10m-w4-q", day: "Thu", title: "Steady cutback run", durationMinutes: 32, summary: "Just enough structure to keep flow.", cue: "Nothing heroic today."), longMinutes: 60),
            buildWeek(index: 5, prefix: "10m-w5", focus: "Return sharper", summary: "Rebuild with a stronger aerobic set and more range on the weekend.", easyMinutes: 45, quality: intervalRun(id: "10m-w5-q", day: "Thu", title: "5 x 4 min intervals", summary: "Threshold-adjacent reps to support sustained pace.", cue: "These should feel strong but repeatable.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 240, easySeconds: 120, repeats: 5), longMinutes: 85),
            buildWeek(index: 6, prefix: "10m-w6", focus: "Practice sustained work", summary: "Tempo work gets longer while the long run climbs again.", easyMinutes: 45, quality: tempoRun(id: "10m-w6-q", day: "Thu", durationMinutes: 48, summary: "Three tempo segments with short floats.", cue: "The middle block should feel the smoothest.", blocks: [10 * 60, 10 * 60, 8 * 60], floatSeconds: 2 * 60), longMinutes: 90),
            buildWeek(index: 7, prefix: "10m-w7", focus: "Peak endurance", summary: "The final big week asks for patience more than speed.", easyMinutes: 42, quality: racePrepRun(id: "10m-w7-q", day: "Thu", durationMinutes: 34, summary: "Pickups to keep the legs lively.", cue: "Quick but never strained.", pickupSeconds: 75, floatSeconds: 90, repeats: 5), longMinutes: 95),
            buildWeek(index: 8, prefix: "10m-w8", focus: "Freshen up", summary: "Pull volume down and carry freshness into a 10-mile effort or supported long run.", easyMinutes: 30, quality: easyRun(id: "10m-w8-q", day: "Thu", title: "Easy pre-race run", durationMinutes: 24, summary: "Short and calming.", cue: "Leave the run feeling sharper than when you started."), longMinutes: 55, raceDay: raceRun(id: "10m-w8-race", day: "Sun", title: "10 mile effort day", durationMinutes: 85, summary: "Race, long progression run, or supported solo effort.", cue: "Be patient in the first half so you can run strong late."))
        ]
    )

    private static let halfTemplate = TrainingPlanTemplate(
        id: "run-half-v1",
        focus: .halfMarathon,
        sport: .run,
        title: "Half marathon plan",
        subtitle: "A practical half build with one real long run, one purposeful quality day, and enough recovery to stay honest.",
        defaultWeeks: 10,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 4,
        baseWeeklyMinutes: 200,
        baseLongSessionMinutes: 80,
        summary: "A ten-week half block that progresses long runs steadily while using tempo, intervals, and race-prep sessions sparingly.",
        highlights: [
            "Long runs grow to 120 minutes, then taper back.",
            "Quality work emphasizes sustained control rather than repeated all-out efforts.",
            "Cutback weeks prevent the plan from becoming brittle."
        ],
        source: workoutTaxonomySource,
        weeks: [
            buildWeek(index: 1, prefix: "half-w1", focus: "Settle into half structure", summary: "The first week establishes the four-day rhythm without forcing pace.", easyMinutes: 42, quality: tempoRun(id: "half-w1-q", day: "Thu", durationMinutes: 44, summary: "Two ten-minute tempo blocks.", cue: "Think calm strength.", blocks: [10 * 60, 10 * 60], floatSeconds: 3 * 60), longMinutes: 75),
            buildWeek(index: 2, prefix: "half-w2", focus: "Strength through range", summary: "The long run grows, while the quality day stays controlled.", easyMinutes: 45, quality: intervalRun(id: "half-w2-q", day: "Thu", title: "4 x 5 min intervals", summary: "Longer threshold reps with complete recoveries.", cue: "Settle into rhythm before the pace settles into you.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 300, easySeconds: 120, repeats: 4), longMinutes: 85),
            buildWeek(index: 3, prefix: "half-w3", focus: "Hold steady effort", summary: "Sustained tempo and a longer long run raise the floor.", easyMinutes: 45, quality: tempoRun(id: "half-w3-q", day: "Thu", durationMinutes: 48, summary: "Three steady tempo segments.", cue: "Stay tall when the work accumulates.", blocks: [10 * 60, 10 * 60, 8 * 60], floatSeconds: 2 * 60), longMinutes: 95),
            buildWeek(index: 4, prefix: "half-w4", focus: "Cut back before the next build", summary: "Volume comes down enough for the next push to land well.", easyMinutes: 35, quality: hillRun(id: "half-w4-q", day: "Thu", durationMinutes: 34, summary: "Light hill session for strength and mechanics.", cue: "Short and springy beats sloggy.", hardSeconds: 60, easySeconds: 90, repeats: 6), longMinutes: 70),
            buildWeek(index: 5, prefix: "half-w5", focus: "Rebuild stronger", summary: "Back to a higher long-run range with a quality session that stays measured.", easyMinutes: 48, quality: fartlekRun(id: "half-w5-q", day: "Thu", durationMinutes: 46, summary: "Three-minute surges sprinkled into a steady run.", cue: "Keep the fast bits strong but relaxed.", hardSeconds: 180, easySeconds: 120, repeats: 6), longMinutes: 100),
            buildWeek(index: 6, prefix: "half-w6", focus: "Peak sustained work", summary: "This week leans into long aerobic control.", easyMinutes: 48, quality: tempoRun(id: "half-w6-q", day: "Thu", durationMinutes: 52, summary: "Two longer tempo blocks.", cue: "Stay just below strain.", blocks: [12 * 60, 12 * 60], floatSeconds: 3 * 60), longMinutes: 110),
            buildWeek(index: 7, prefix: "half-w7", focus: "Peak long run", summary: "The weekend reaches its high point while the quality day stays compact.", easyMinutes: 45, quality: racePrepRun(id: "half-w7-q", day: "Thu", durationMinutes: 36, summary: "Controlled pickups to keep the legs awake.", cue: "You should finish feeling eager, not empty.", pickupSeconds: 90, floatSeconds: 90, repeats: 5), longMinutes: 120),
            buildWeek(index: 8, prefix: "half-w8", focus: "Step down slightly", summary: "The long run comes back while tempo rhythm stays alive.", easyMinutes: 42, quality: tempoRun(id: "half-w8-q", day: "Thu", durationMinutes: 42, summary: "Shorter threshold blocks with plenty in reserve.", cue: "Practice restraint.", blocks: [8 * 60, 8 * 60], floatSeconds: 3 * 60), longMinutes: 95),
            buildWeek(index: 9, prefix: "half-w9", focus: "Sharpen, don't chase", summary: "A lighter week with a final specific session.", easyMinutes: 35, quality: intervalRun(id: "half-w9-q", day: "Thu", title: "3 x 5 min race-pace effort", summary: "Controlled half-marathon effort with easy recoveries.", cue: "Let the pace come to you.", warmupMinutes: 10, cooldownMinutes: 8, hardSeconds: 300, easySeconds: 120, repeats: 3), longMinutes: 70),
            buildWeek(index: 10, prefix: "half-w10", focus: "Race week", summary: "Carry freshness into your half marathon or supported long effort.", easyMinutes: 24, quality: racePrepRun(id: "half-w10-q", day: "Thu", durationMinutes: 22, summary: "Short tune-up with quick strides.", cue: "This should feel crisp and brief.", pickupSeconds: 45, floatSeconds: 75, repeats: 4), longMinutes: 40, raceDay: raceRun(id: "half-w10-race", day: "Sun", title: "Half marathon effort day", durationMinutes: 120, summary: "Race day or a calm supported long progression.", cue: "Start patient, settle into rhythm, and trust the work."))
        ]
    )

    private static let halfHansonsBeginnerTemplate = TrainingPlanTemplate(
        id: "run-half-hansons-beginner-v1",
        focus: .halfMarathon,
        sport: .run,
        title: "Half marathon beginner import",
        subtitle: "An imported week-by-week half plan with easy mileage, HMP sessions, interval workouts, and progressive long runs.",
        defaultWeeks: 19,
        minSessionsPerWeek: 3,
        maxSessionsPerWeek: 6,
        baseWeeklyMinutes: 180,
        baseLongSessionMinutes: 80,
        summary: "A larger-volume imported half block for runners who want a complete calendar with explicit workouts nearly every day.",
        highlights: [
            "Uses easy runs, half-marathon pace work, intervals, and long runs in a repeatable weekly rhythm.",
            "Volume rises gradually before tapering into race day.",
            "Cross-training and rest still appear, but this is more demanding than the lighter local half block."
        ],
        source: timeToRunSource,
        weeks: importedWeeks(
            prefix: "half-hansons-beginner",
            focus: "Progress into structured half-marathon work",
            summaryPrefix: "Imported beginner half week",
            notes: ["This imported plan is higher commitment than the local half build. Use it only when recent consistency is already solid."],
            weeks: [
                [("Rest or Cross-Train", 0), ("Rest or Cross-Train", 0), ("Rest or Cross-Train", 0), ("Easy 3 miles", 3), ("Rest or Cross-Train", 0), ("Easy 3 miles", 3), ("Easy 4 miles", 4)],
                [("Rest or Cross-Train", 0), ("Easy 2 miles", 2), ("Rest or Cross-Train", 0), ("Easy 3 miles", 3), ("Easy 3 miles", 3), ("Easy 3 miles", 3), ("Easy 4 miles", 4)],
                [("Rest or Cross-Train", 0), ("Easy 4 miles", 4), ("Rest or Cross-Train", 0), ("Easy 4 miles", 4), ("Easy 4 miles", 4), ("Easy 4 miles", 4), ("Easy 5 miles", 5)],
                [("Rest or Cross-Train", 0), ("Easy 5 miles", 5), ("Rest or Cross-Train", 0), ("Easy 3 miles", 3), ("Easy 3 miles", 3), ("Easy 5 miles", 5), ("Easy 6 miles", 6)],
                [("Rest or Cross-Train", 0), ("Easy 5 miles", 5), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down", 6), ("Easy 5 miles", 5), ("Easy 4 miles", 4), ("8 miles Long Run", 8)],
                [("Easy 4 miles", 4), ("1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 9), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles@ HMP\n1.5 miles Cool Down", 6), ("Easy 4 miles", 4), ("Easy 5 miles", 5), ("9 miles Long Run", 9)],
                [("Easy 4 miles", 4), ("1.5 miles Warm Up\n8x600m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 7), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles@ HMP\n1.5 miles Cool Down", 6), ("Easy 4 miles", 4), ("Easy 6 miles", 6), ("10 miles Long Run", 10)],
                [("Easy 6 miles", 6), ("1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 7), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down", 7), ("Easy 5 miles", 5), ("Easy 6 miles", 6), ("10 miles Long Run", 10)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down", 7), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("10 miles Long Run", 10)],
                [("Easy 6 miles", 6), ("1.5 miles Warm Up\n4x1,200m @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles@ HMP\n1.5 miles Cool Down", 7), ("Easy 5 miles", 5), ("Easy 5 miles", 5), ("12 miles Long Run", 12)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n6x1 miles @ HMP -10s w. 400m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down", 8), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("10 miles Long Run", 10)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n4x1.5 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down", 8), ("Easy 5 miles", 5), ("Easy 6 miles", 6), ("12 miles Long Run", 12)],
                [("Easy 6 miles", 6), ("1.5 miles Warm Up\n3x2 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down", 8), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("10 miles Long Run", 10)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n2x3 miles @ HMP -10s w. 1 miles jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down", 9), ("Easy 5 miles", 5), ("Easy 6 miles", 6), ("12 miles Long Run", 12)],
                [("Easy 7 miles", 7), ("1.5 miles Warm Up\n3x2 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down", 9), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("10 miles Long Run", 10)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n4x1.5 miles @ HMP -10s w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles@ HMP\n1.5 miles Cool Down", 9), ("Easy 5 miles", 5), ("Easy 6 miles", 6), ("12 miles Long Run", 12)],
                [("Easy 5 miles", 5), ("1.5 miles Warm Up\n6x1 miles @ HMP -10s w. 400m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles@ HMP\n1.5 miles Cool Down", 8), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("Easy 8 miles", 8)],
                [("Easy 5 miles", 5), ("Rest or Cross-Train", 0), ("Easy 6 miles", 6), ("Easy 5 miles", 5), ("Easy 3 miles", 3), ("Race Day!", 13.1)]
            ]
        )
    )

    private static let halfHansonsAdvancedTemplate = TrainingPlanTemplate(
        id: "run-half-hansons-advanced-v1",
        focus: .halfMarathon,
        sport: .run,
        title: "Half marathon advanced import",
        subtitle: "A higher-volume imported half plan with frequent easy mileage, race-pace work, interval sessions, and longer long runs.",
        defaultWeeks: 18,
        minSessionsPerWeek: 5,
        maxSessionsPerWeek: 6,
        baseWeeklyMinutes: 260,
        baseLongSessionMinutes: 95,
        summary: "An advanced imported option for runners who already tolerate consistent weekly mileage and want a denser plan.",
        highlights: [
            "Multiple easy-run days support quality instead of replacing it.",
            "Regular HMP and interval workouts make the structure highly specific.",
            "Peak long runs and weekly load are significantly higher than the beginner and local half plans."
        ],
        source: timeToRunSource,
        weeks: importedWeeks(
            prefix: "half-hansons-advanced",
            focus: "Carry higher half-marathon volume",
            summaryPrefix: "Imported advanced half week",
            notes: ["This is the heaviest plan currently in the app. It should only surface for users with a clear existing base."],
            weeks: [
                [("Rest or Cross-Train", 0), ("Rest or Cross-Train", 0), ("Rest or Cross-Train", 0), ("4 miles Easy", 4), ("3 miles Easy", 3), ("4 miles Easy", 4), ("6 miles Easy", 6)],
                [("4 miles Easy", 4), ("1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 9), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down", 6), ("4 miles Easy", 4), ("4 miles Easy", 4), ("6 miles Easy", 6)],
                [("4 miles Easy", 4), ("1.5 miles Warm Up\n8x600m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 7), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down", 6), ("5 miles Easy", 5), ("5 miles Easy", 5), ("7 miles Easy", 7)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 7), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n3 miles @ HMP\n1.5 miles Cool Down", 6), ("4 miles Easy", 4), ("6 miles Easy", 6), ("8 miles Easy", 8)],
                [("4 miles Easy", 4), ("1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down", 7), ("5 miles Easy", 5), ("6 miles Easy", 6), ("10 miles Long Run", 10)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n4x1,200m @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down", 7), ("6 miles Easy", 6), ("6 miles Easy", 6), ("12 miles Long Run", 12)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n3x1 miles @ 5k-10k pace w. 800m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n4 miles @ HMP\n1.5 miles Cool Down", 7), ("6 miles Easy", 6), ("5 miles Easy", 5), ("10 miles Long Run", 10)],
                [("6 miles Easy", 6), ("1.5 miles Warm Up\n5x1k @ 5k-10k pace w. 600m jog rest\n1.5 miles Cool Down", 8), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down", 8), ("6 miles Easy", 6), ("6 miles Easy", 6), ("12 miles Long Run", 12)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n6x800m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 7), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down", 8), ("6 miles Easy", 6), ("5 miles Easy", 5), ("10 miles Long Run", 10)],
                [("7 miles Easy", 7), ("1.5 miles Warm Up\n12x400m @ 5k-10k pace w. 400m jog rest\n1.5 miles Cool Down", 9), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down", 8), ("5 miles Easy", 5), ("6 miles Easy", 6), ("12 miles Long Run", 12)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n6x1 miles @ 10k pace w. 400m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down", 9), ("6 miles Easy", 6), ("5 miles Easy", 5), ("10 miles Long Run", 10)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n4x1.5 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down", 9), ("5 miles Easy", 5), ("6 miles Easy", 6), ("14 miles Long Run", 14)],
                [("7 miles Easy", 7), ("1.5 miles Warm Up\n3x2 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n6 miles @ HMP\n1.5 miles Cool Down", 9), ("6 miles Easy", 6), ("5 miles Easy", 5), ("10 miles Long Run", 10)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n2x3 miles @ 10k pace w. 1 miles jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down", 10), ("5 miles Easy", 5), ("6 miles Easy", 6), ("14 miles Long Run", 14)],
                [("7 miles Easy", 7), ("1.5 miles Warm Up\n3x2 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down", 10), ("6 miles Easy", 6), ("5 miles Easy", 5), ("10 miles Long Run", 10)],
                [("5 miles Easy", 5), ("1.5 miles Warm Up\n4x1.5 miles @ 10k pace w. 800m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n7 miles @ HMP\n1.5 miles Cool Down", 10), ("5 miles Easy", 5), ("6 miles Easy", 6), ("14 miles Long Run", 14)],
                [("7 miles Easy", 7), ("1.5 miles Warm Up\n6x1 miles @ 10k pace w. 400m jog rest\n1.5 miles Cool Down", 10), ("Rest or Cross-Train", 0), ("1.5 miles Warm Up\n5 miles @ HMP\n1.5 miles Cool Down", 8), ("6 miles Easy", 6), ("5 miles Easy", 5), ("8 miles Easy", 8)],
                [("5 miles Easy", 5), ("5 miles Easy", 5), ("Rest or Cross-Train", 0), ("6 miles Easy", 6), ("5 miles Easy", 5), ("3 miles Shakeout Run", 3), ("Race Day!", 13.1)]
            ]
        )
    )
}

private extension TrainingPlanLibrary {
    static let weekDayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func importedC25KWeeks() -> [TrainingPlanWeek] {
        [
            repeatedC25KWeek(index: 1, runSeconds: 60, walkSeconds: 90, repeats: 8, summary: "Build comfort with short one-minute run segments."),
            repeatedC25KWeek(index: 2, runSeconds: 90, walkSeconds: 120, repeats: 6, summary: "Lengthen the running while keeping plenty of walk recovery.", trailingWalkSeconds: 60),
            repeatedMixedC25KWeek(index: 3, summary: "Mix short and medium run segments so continuous running starts to feel less foreign.", blocks: [(90, 90), (180, 180), (90, 90), (180, 180)]),
            repeatedMixedC25KWeek(index: 4, summary: "Step into longer blocks with two three-minute segments and two five-minute segments.", blocks: [(180, 90), (300, 150), (180, 90), (300, 0)]),
            customC25KWeek(
                index: 5,
                summary: "This is the first real leap week, ending with a twenty-minute continuous run.",
                workouts: [
                    c25kWorkout(id: "w5d1", day: "Tue", title: "Week 5, Workout 1", summary: "Five minutes run, three minutes walk, eight minutes run, three minutes walk, five minutes run.", cue: "Let the middle eight-minute run stay under control.", events: [.warmup(300), .run(300), .walk(180), .run(480), .walk(180), .run(300), .cooldown(300)]),
                    c25kWorkout(id: "w5d2", day: "Thu", title: "Week 5, Workout 2", summary: "Two eight-minute run blocks with a five-minute walk between them.", cue: "Focus on smoothness in the second block.", events: [.warmup(300), .run(480), .walk(300), .run(480), .cooldown(300)]),
                    c25kWorkout(id: "w5d3", day: "Sat", title: "Week 5, Workout 3", summary: "Your first continuous twenty-minute run.", cue: "Start slower than you think you need to.", events: [.warmup(300), .run(1200), .cooldown(300)])
                ]
            ),
            customC25KWeek(
                index: 6,
                summary: "Alternate interval days with another jump in continuous running.",
                workouts: [
                    c25kWorkout(id: "w6d1", day: "Tue", title: "Week 6, Workout 1", summary: "A return to five- and eight-minute run segments.", cue: "This week is about confidence, not proving toughness.", events: [.warmup(300), .run(300), .walk(180), .run(480), .walk(180), .run(300), .cooldown(300)]),
                    c25kWorkout(id: "w6d2", day: "Thu", title: "Week 6, Workout 2", summary: "Two ten-minute runs with a short walk between them.", cue: "Treat the second ten-minute block like a calm reset.", events: [.warmup(300), .run(600), .walk(180), .run(600), .cooldown(300)]),
                    c25kWorkout(id: "w6d3", day: "Sat", title: "Week 6, Workout 3", summary: "Continuous twenty-two-minute running.", cue: "Relax the shoulders and let the time unfold.", events: [.warmup(300), .run(1320), .cooldown(300)])
                ]
            ),
            repeatedContinuousC25KWeek(index: 7, continuousRunSeconds: 1500, summary: "Three identical continuous 25-minute runs build familiarity over novelty."),
            repeatedContinuousC25KWeek(index: 8, continuousRunSeconds: 1680, summary: "Push continuous running to 28 minutes while keeping the effort patient."),
            repeatedContinuousC25KWeek(index: 9, continuousRunSeconds: 1800, summary: "Three continuous 30-minute runs complete the progression.")
        ]
    }

    static func importedWeeks(
        prefix: String,
        focus: String,
        summaryPrefix: String,
        notes: [String],
        weeks: [[(String, Double)]]
    ) -> [TrainingPlanWeek] {
        weeks.enumerated().map { index, entries in
            let weekIndex = index + 1
            let workouts = entries.enumerated().map { dayIndex, entry in
                importedWorkout(
                    id: "\(prefix)-w\(weekIndex)-d\(dayIndex + 1)",
                    day: dayIndex < weekDayLabels.count ? weekDayLabels[dayIndex] : "Day \(dayIndex + 1)",
                    description: entry.0,
                    totalDistance: entry.1
                )
            }
            return week(
                weekIndex,
                focus: focus,
                summary: "\(summaryPrefix) \(weekIndex) with \(workouts.filter { !$0.isOptional || $0.kind != .crossTrain }.count) scheduled items.",
                workouts: workouts,
                notes: notes
            )
        }
    }

    static func week(
        _ index: Int,
        focus: String,
        summary: String,
        workouts: [TrainingPlanWorkout],
        notes: [String]
    ) -> TrainingPlanWeek {
        TrainingPlanWeek(
            id: "week-\(index)-\(focus.lowercased().replacingOccurrences(of: " ", with: "-"))",
            index: index,
            focus: focus,
            summary: summary,
            workouts: workouts,
            notes: notes
        )
    }

    static func buildWeek(
        index: Int,
        prefix: String,
        focus: String,
        summary: String,
        easyMinutes: Int,
        quality: TrainingPlanWorkout,
        longMinutes: Int,
        raceDay: TrainingPlanWorkout? = nil
    ) -> TrainingPlanWeek {
        var workouts = [
            easyRun(id: "\(prefix)-easy", day: "Tue", title: "Easy aerobic run", durationMinutes: easyMinutes, summary: "Steady conversational running.", cue: "Let this feel boring in the best possible way."),
            quality,
            crossTrain(id: "\(prefix)-ct", day: "Sat", durationMinutes: 35, summary: "Optional low-impact aerobic support.", cue: "Skip this if your legs are asking for recovery.", optional: true),
            longRun(id: "\(prefix)-long", day: "Sun", durationMinutes: longMinutes, summary: "Long aerobic support run.", cue: "The right pace is the one that keeps the back half steady.")
        ]
        if let raceDay {
            workouts[2] = recoveryRun(id: "\(prefix)-recovery", day: "Sat", durationMinutes: 18, summary: "Short recovery jog before the event.", cue: "Keep this tiny and relaxed.", optional: true)
            workouts[3] = raceDay
        }
        return week(index, focus: focus, summary: summary, workouts: workouts, notes: ["If you miss a weekday, do not stack it onto the long-run day."])
    }

    static func repeatedC25KWeek(
        index: Int,
        runSeconds: Int,
        walkSeconds: Int,
        repeats: Int,
        summary: String,
        trailingWalkSeconds: Int = 0
    ) -> TrainingPlanWeek {
        let workouts = (1...3).map { session in
            c25kRepeatingWorkout(
                id: "w\(index)d\(session)",
                day: sessionDay(session),
                title: "Week \(index), Workout \(session)",
                summary: summary,
                cue: "Keep every run interval comfortably easy.",
                runSeconds: runSeconds,
                walkSeconds: walkSeconds,
                repeats: repeats,
                trailingWalkSeconds: trailingWalkSeconds
            )
        }
        return customC25KWeek(index: index, summary: summary, workouts: workouts)
    }

    static func repeatedMixedC25KWeek(
        index: Int,
        summary: String,
        blocks: [(Int, Int)]
    ) -> TrainingPlanWeek {
        let workouts = (1...3).map { session in
            let events: [C25KEvent] = [.warmup(300)] + blocks.flatMap { [.run($0.0), .walk($0.1)] } + [.cooldown(300)]
            return c25kWorkout(
                id: "w\(index)d\(session)",
                day: sessionDay(session),
                title: "Week \(index), Workout \(session)",
                summary: summary,
                cue: "Stay patient through the early blocks so the later ones still feel possible.",
                events: events
            )
        }
        return customC25KWeek(index: index, summary: summary, workouts: workouts)
    }

    static func repeatedContinuousC25KWeek(
        index: Int,
        continuousRunSeconds: Int,
        summary: String
    ) -> TrainingPlanWeek {
        let workouts = (1...3).map { session in
            c25kWorkout(
                id: "w\(index)d\(session)",
                day: sessionDay(session),
                title: "Week \(index), Workout \(session)",
                summary: summary,
                cue: "Go out slower than you want for the first five minutes.",
                events: [.warmup(300), .run(continuousRunSeconds), .cooldown(300)]
            )
        }
        return customC25KWeek(index: index, summary: summary, workouts: workouts)
    }

    static func customC25KWeek(
        index: Int,
        summary: String,
        workouts: [TrainingPlanWorkout]
    ) -> TrainingPlanWeek {
        week(index, focus: "Build continuous running", summary: summary, workouts: workouts, notes: ["Take at least one full rest day between C25K sessions."])
    }

    static func sessionDay(_ number: Int) -> String {
        switch number {
        case 1: return "Tue"
        case 2: return "Thu"
        default: return "Sat"
        }
    }

    static func easyRun(
        id: String,
        day: String,
        title: String = "Easy run",
        durationMinutes: Int,
        summary: String,
        cue: String,
        optional: Bool = false
    ) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: id,
            title: title,
            kind: .easy,
            dayLabel: day,
            summary: summary,
            purpose: "Build aerobic support while keeping recovery intact.",
            coachCue: cue,
            effortLabel: "Conversational",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: [
                step("\(id)-warmup", .warmup, "Warm up walk or jog", 5 * 60, "Ease into the session."),
                step("\(id)-main", .steady, "Easy run", max(1, durationMinutes - 10) * 60, "You should be able to speak in short sentences."),
                step("\(id)-cooldown", .cooldown, "Cooldown walk", 5 * 60, "Let your breathing settle.")
            ],
            isOptional: optional
        )
    }

    static func recoveryRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        optional: Bool = false
    ) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: id,
            title: "Recovery run",
            kind: .recovery,
            dayLabel: day,
            summary: summary,
            purpose: "Promote recovery while keeping the habit alive.",
            coachCue: cue,
            effortLabel: "Very easy",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: [
                step("\(id)-warmup", .warmup, "Warm up walk", 4 * 60, "No rush."),
                step("\(id)-main", .recovery, "Recovery jog", max(1, durationMinutes - 8) * 60, "Stay well below strain."),
                step("\(id)-cooldown", .cooldown, "Cooldown walk", 4 * 60, "Finish feeling refreshed.")
            ],
            isOptional: optional
        )
    }

    static func walkRun(
        id: String,
        day: String,
        title: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        runSeconds: Int,
        walkSeconds: Int,
        repeats: Int
    ) -> TrainingPlanWorkout {
        let mainSteps = (1...repeats).flatMap { rep in
            [
                step("\(id)-run-\(rep)", .run, "Run \(rep)", runSeconds, "Relax the pace."),
                step("\(id)-walk-\(rep)", .walk, "Walk \(rep)", walkSeconds, "Recover fully.")
            ]
        }
        let totalSeconds = 5 * 60 + mainSteps.reduce(0) { $0 + $1.durationSeconds } + 5 * 60
        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: .walkRun,
            dayLabel: day,
            summary: summary,
            purpose: "Rebuild impact tolerance and confidence with controlled run segments.",
            coachCue: cue,
            effortLabel: "Gentle",
            durationSeconds: max(durationMinutes * 60, totalSeconds),
            distanceLabel: nil,
            steps: [step("\(id)-warmup", .warmup, "Warm up walk", 5 * 60, "Get loose before the first run segment.")] + mainSteps + [step("\(id)-cooldown", .cooldown, "Cooldown walk", 5 * 60, "Let the session settle.")],
            isOptional: false
        )
    }

    static func tempoRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        blocks: [Int],
        floatSeconds: Int
    ) -> TrainingPlanWorkout {
        var steps = [step("\(id)-warmup", .warmup, "Warm up jog", 10 * 60, "Keep this relaxed.")]
        for (index, block) in blocks.enumerated() {
            steps.append(step("\(id)-tempo-\(index)", .tempo, "Tempo block \(index + 1)", block, "Controlled discomfort."))
            if index < blocks.count - 1 {
                steps.append(step("\(id)-float-\(index)", .recovery, "Easy float", floatSeconds, "Bring your breathing down before the next block."))
            }
        }
        steps.append(step("\(id)-cooldown", .cooldown, "Cooldown jog", 8 * 60, "Let the effort taper off."))
        return TrainingPlanWorkout(
            id: id,
            title: "Tempo run",
            kind: .tempo,
            dayLabel: day,
            summary: summary,
            purpose: "Raise your comfort with sustained work just under strain.",
            coachCue: cue,
            effortLabel: "Comfortably hard",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func intervalRun(
        id: String,
        day: String,
        title: String,
        summary: String,
        cue: String,
        warmupMinutes: Int,
        cooldownMinutes: Int,
        hardSeconds: Int,
        easySeconds: Int,
        repeats: Int
    ) -> TrainingPlanWorkout {
        var steps = [step("\(id)-warmup", .warmup, "Warm up jog", warmupMinutes * 60, "Ease into the session.")]
        for rep in 1...repeats {
            steps.append(step("\(id)-hard-\(rep)", .interval, "Hard rep \(rep)", hardSeconds, "Quick but controlled."))
            if rep < repeats {
                steps.append(step("\(id)-easy-\(rep)", .recovery, "Easy recovery", easySeconds, "Walk or jog until you feel ready again."))
            }
        }
        steps.append(step("\(id)-cooldown", .cooldown, "Cooldown jog", cooldownMinutes * 60, "Bring things back down slowly."))
        let total = steps.reduce(0) { $0 + $1.durationSeconds }
        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: .interval,
            dayLabel: day,
            summary: summary,
            purpose: "Build speed support without losing control of the week.",
            coachCue: cue,
            effortLabel: "10K effort",
            durationSeconds: total,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func fartlekRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        hardSeconds: Int,
        easySeconds: Int,
        repeats: Int
    ) -> TrainingPlanWorkout {
        var steps = [step("\(id)-warmup", .warmup, "Warm up jog", 8 * 60, "Start relaxed.")]
        for rep in 1...repeats {
            steps.append(step("\(id)-surge-\(rep)", .steady, "Surge \(rep)", hardSeconds, "Run by feel, not by force."))
            steps.append(step("\(id)-float-\(rep)", .recovery, "Easy float", easySeconds, "Recover while still moving."))
        }
        steps.append(step("\(id)-cooldown", .cooldown, "Cooldown jog", 6 * 60, "Let your breathing settle."))
        return TrainingPlanWorkout(
            id: id,
            title: "Fartlek run",
            kind: .fartlek,
            dayLabel: day,
            summary: summary,
            purpose: "Practice changing gears without the rigidity of track intervals.",
            coachCue: cue,
            effortLabel: "Playful steady",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func hillRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        hardSeconds: Int,
        easySeconds: Int,
        repeats: Int
    ) -> TrainingPlanWorkout {
        var steps = [step("\(id)-warmup", .warmup, "Warm up jog", 10 * 60, "Find a smooth hill.")]
        for rep in 1...repeats {
            steps.append(step("\(id)-hill-\(rep)", .interval, "Hill rep \(rep)", hardSeconds, "Short, tall, and powerful."))
            steps.append(step("\(id)-recover-\(rep)", .recovery, "Walk back recovery", easySeconds, "Reset fully before the next climb."))
        }
        steps.append(step("\(id)-cooldown", .cooldown, "Cooldown jog", 8 * 60, "Shake the legs out."))
        return TrainingPlanWorkout(
            id: id,
            title: "Hill session",
            kind: .hill,
            dayLabel: day,
            summary: summary,
            purpose: "Build strength and mechanics with lower top-end speed.",
            coachCue: cue,
            effortLabel: "Strong but controlled",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func longRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String
    ) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: id,
            title: "Long run",
            kind: .longRun,
            dayLabel: day,
            summary: summary,
            purpose: "Build durable endurance with low drama and steady effort.",
            coachCue: cue,
            effortLabel: "Easy-steady",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: [
                step("\(id)-warmup", .warmup, "Warm up jog", 8 * 60, "Start more gently than you think you need to."),
                step("\(id)-main", .steady, "Long aerobic running", max(1, durationMinutes - 16) * 60, "Stay under control for the whole middle."),
                step("\(id)-cooldown", .cooldown, "Cooldown walk", 8 * 60, "Walk a bit before you stop completely.")
            ],
            isOptional: false
        )
    }

    static func crossTrain(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        optional: Bool
    ) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: id,
            title: "Cross-train",
            kind: .crossTrain,
            dayLabel: day,
            summary: summary,
            purpose: "Add aerobic support without extra run impact.",
            coachCue: cue,
            effortLabel: "Easy",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: [
                step("\(id)-main", .crossTrain, "Bike, walk, row, or mobility circuit", durationMinutes * 60, "Stay mostly aerobic.")
            ],
            isOptional: optional
        )
    }

    static func racePrepRun(
        id: String,
        day: String,
        durationMinutes: Int,
        summary: String,
        cue: String,
        pickupSeconds: Int,
        floatSeconds: Int,
        repeats: Int
    ) -> TrainingPlanWorkout {
        var steps = [step("\(id)-warmup", .warmup, "Warm up jog", 8 * 60, "Stay relaxed.")]
        for rep in 1...repeats {
            steps.append(step("\(id)-pickup-\(rep)", .interval, "Pickup \(rep)", pickupSeconds, "Quick, light, and under control."))
            if rep < repeats {
                steps.append(step("\(id)-float-\(rep)", .recovery, "Easy float", floatSeconds, "Reset before the next pickup."))
            }
        }
        steps.append(step("\(id)-cooldown", .cooldown, "Cooldown jog", 6 * 60, "Keep this short and easy."))
        return TrainingPlanWorkout(
            id: id,
            title: "Race-prep run",
            kind: .racePrep,
            dayLabel: day,
            summary: summary,
            purpose: "Stay sharp while protecting freshness.",
            coachCue: cue,
            effortLabel: "Light and snappy",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func raceRun(
        id: String,
        day: String,
        title: String,
        durationMinutes: Int,
        summary: String,
        cue: String
    ) -> TrainingPlanWorkout {
        TrainingPlanWorkout(
            id: id,
            title: title,
            kind: .race,
            dayLabel: day,
            summary: summary,
            purpose: "Express the work with patience early and intent late.",
            coachCue: cue,
            effortLabel: "Race effort",
            durationSeconds: durationMinutes * 60,
            distanceLabel: nil,
            steps: [
                step("\(id)-warmup", .warmup, "Warm up jog", 10 * 60, "Stay loose and calm."),
                step("\(id)-race", .race, "Main effort", max(1, durationMinutes - 20) * 60, "Start controlled, then build into the second half."),
                step("\(id)-cooldown", .cooldown, "Cooldown walk", 10 * 60, "Let the effort taper fully.")
            ],
            isOptional: false
        )
    }

    static func c25kRepeatingWorkout(
        id: String,
        day: String,
        title: String,
        summary: String,
        cue: String,
        runSeconds: Int,
        walkSeconds: Int,
        repeats: Int,
        trailingWalkSeconds: Int
    ) -> TrainingPlanWorkout {
        var events: [C25KEvent] = [.warmup(300)]
        for rep in 1...repeats {
            events.append(.run(runSeconds))
            if rep < repeats || trailingWalkSeconds > 0 {
                events.append(.walk(rep == repeats ? trailingWalkSeconds : walkSeconds))
            }
        }
        events.append(.cooldown(300))
        return c25kWorkout(id: id, day: day, title: title, summary: summary, cue: cue, events: events)
    }

    static func c25kWorkout(
        id: String,
        day: String,
        title: String,
        summary: String,
        cue: String,
        events: [C25KEvent]
    ) -> TrainingPlanWorkout {
        let steps = events.enumerated().map { index, event in
            switch event {
            case .warmup(let seconds):
                return step("\(id)-\(index)", .warmup, "Warm up walk", seconds, "Ease into the workout.")
            case .run(let seconds):
                return step("\(id)-\(index)", .run, "Run", seconds, "Keep the pace light.")
            case .walk(let seconds):
                return step("\(id)-\(index)", .walk, "Walk", seconds, "Recover fully before the next run.")
            case .cooldown(let seconds):
                return step("\(id)-\(index)", .cooldown, "Cooldown walk", seconds, "Let the effort settle.")
            }
        }
        let total = steps.reduce(0) { $0 + $1.durationSeconds }
        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: .walkRun,
            dayLabel: day,
            summary: summary,
            purpose: "Progress from run-walk intervals toward continuous running.",
            coachCue: cue,
            effortLabel: "Easy",
            durationSeconds: total,
            distanceLabel: nil,
            steps: steps,
            isOptional: false
        )
    }

    static func step(
        _ id: String,
        _ kind: TrainingPlanWorkoutStepKind,
        _ label: String,
        _ durationSeconds: Int,
        _ detail: String? = nil
    ) -> TrainingPlanWorkoutStep {
        TrainingPlanWorkoutStep(
            id: id,
            kind: kind,
            label: label,
            durationSeconds: durationSeconds,
            detail: detail
        )
    }

    static func importedWorkout(
        id: String,
        day: String,
        description: String,
        totalDistance: Double
    ) -> TrainingPlanWorkout {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = normalized.lowercased()

        if lowercase.contains("rest or cross-train") || lowercase == "rest" {
            return TrainingPlanWorkout(
                id: id,
                title: "Rest or cross-train",
                kind: .crossTrain,
                dayLabel: day,
                summary: normalized,
                purpose: "Use this day for recovery or light aerobic support.",
                coachCue: "Take the easiest option that helps you absorb the week.",
                effortLabel: "Optional easy",
                durationSeconds: 30 * 60,
                distanceLabel: nil,
                steps: [
                    step("\(id)-main", .crossTrain, "Optional cross-train or full rest", 30 * 60, "Walk, bike, mobility, or take the day off entirely.")
                ],
                isOptional: true
            )
        }

        if lowercase.contains("race day") {
            let distanceLabel = totalDistance > 0 ? formattedDistanceLabel(totalDistance) : nil
            return TrainingPlanWorkout(
                id: id,
                title: "Race day",
                kind: .race,
                dayLabel: day,
                summary: normalized,
                purpose: "Express the training with patient pacing and a strong finish.",
                coachCue: "Stay calmer than feels natural in the opening stretch.",
                effortLabel: "Race effort",
                durationSeconds: estimatedDurationSeconds(distanceMiles: max(totalDistance, 6)),
                distanceLabel: distanceLabel,
                steps: [
                    step("\(id)-warmup", .warmup, "Warm up jog", 10 * 60, "Stay loose."),
                    step("\(id)-race", .race, distanceLabel.map { "Race effort \($0)" } ?? "Main effort", max(estimatedDurationSeconds(distanceMiles: max(totalDistance, 6)) - 20 * 60, 20 * 60), "Start controlled and build late."),
                    step("\(id)-cooldown", .cooldown, "Cooldown walk", 10 * 60, "Let the effort taper off.")
                ],
                isOptional: false
            )
        }

        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return importedStructuredWorkout(
                id: id,
                day: day,
                lines: lines,
                summary: normalized,
                totalDistance: totalDistance
            )
        }

        if lowercase.contains("long run") || lowercase.contains("endurance") {
            return TrainingPlanWorkout(
                id: id,
                title: lowercase.contains("long run") ? "Long run" : "Endurance run",
                kind: .longRun,
                dayLabel: day,
                summary: normalized,
                purpose: "Build range and aerobic durability.",
                coachCue: "Run this patiently enough that the last third still looks relaxed.",
                effortLabel: "Easy-steady",
                durationSeconds: estimatedDurationSeconds(distanceMiles: max(totalDistance, 5)),
                distanceLabel: totalDistance > 0 ? formattedDistanceLabel(totalDistance) : nil,
                steps: [
                    step("\(id)-warmup", .warmup, "Warm up jog", 8 * 60, "Settle in gradually."),
                    step("\(id)-main", .steady, totalDistance > 0 ? "Endurance run \(formattedDistanceLabel(totalDistance))" : "Endurance run", max(estimatedDurationSeconds(distanceMiles: max(totalDistance, 5)) - 16 * 60, 20 * 60), "Keep the effort below strain."),
                    step("\(id)-cooldown", .cooldown, "Cooldown walk", 8 * 60, "Walk a bit before stopping.")
                ],
                isOptional: false
            )
        }

        if lowercase.contains("threshold") || lowercase.contains("tempo") {
            let duration = estimatedDurationSeconds(distanceMiles: max(totalDistance, 4))
            return TrainingPlanWorkout(
                id: id,
                title: "Threshold run",
                kind: .tempo,
                dayLabel: day,
                summary: normalized,
                purpose: "Practice sustained work just under red-line effort.",
                coachCue: "This should feel controlled, not desperate.",
                effortLabel: "Comfortably hard",
                durationSeconds: duration,
                distanceLabel: totalDistance > 0 ? formattedDistanceLabel(totalDistance) : nil,
                steps: [
                    step("\(id)-warmup", .warmup, "Warm up jog", 10 * 60, "Ease in gently."),
                    step("\(id)-main", .tempo, normalized, max(duration - 18 * 60, 18 * 60), "Stay smooth through the middle."),
                    step("\(id)-cooldown", .cooldown, "Cooldown jog", 8 * 60, "Bring your breathing back down.")
                ],
                isOptional: false
            )
        }

        if lowercase.contains("shakeout") {
            return recoveryRun(
                id: id,
                day: day,
                durationMinutes: Int(ceil(Double(estimatedDurationSeconds(distanceMiles: max(totalDistance, 3))) / 60.0)),
                summary: normalized,
                cue: "Keep it tiny. Fresh beats fit right now."
            )
        }

        let title: String
        let kind: TrainingPlanWorkoutKind
        let cue: String
        if lowercase.contains("strides") {
            title = "Easy run with strides"
            kind = .racePrep
            cue = "Stay easy on the run and keep the strides crisp, not exhausting."
        } else if lowercase.contains("easy") || lowercase.contains("general aerobic") {
            title = "Easy run"
            kind = .easy
            cue = "Let this support the week rather than steal from it."
        } else {
            title = "Run"
            kind = .easy
            cue = "Keep this smooth and under control."
        }

        let duration = estimatedDurationSeconds(distanceMiles: max(totalDistance, 3))
        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: kind,
            dayLabel: day,
            summary: normalized,
            purpose: "Add aerobic support while preserving recovery.",
            coachCue: cue,
            effortLabel: kind == .racePrep ? "Easy with pop" : "Conversational",
            durationSeconds: duration,
            distanceLabel: totalDistance > 0 ? formattedDistanceLabel(totalDistance) : nil,
            steps: [
                step("\(id)-warmup", .warmup, "Warm up jog", 5 * 60, "Start relaxed."),
                step("\(id)-main", .steady, totalDistance > 0 ? "\(title) \(formattedDistanceLabel(totalDistance))" : title, max(duration - 10 * 60, 15 * 60), kind == .racePrep ? "Finish with a few quick relaxed strides." : "Keep the whole run conversational."),
                step("\(id)-cooldown", .cooldown, "Cooldown walk", 5 * 60, "Bring the session down calmly.")
            ],
            isOptional: false
        )
    }

    static func importedStructuredWorkout(
        id: String,
        day: String,
        lines: [String],
        summary: String,
        totalDistance: Double
    ) -> TrainingPlanWorkout {
        let mainLine = lines.dropFirst().first(where: { !$0.lowercased().contains("cool down") }) ?? lines[0]
        let lowerMain = mainLine.lowercased()
        let kind: TrainingPlanWorkoutKind
        let title: String
        let effort: String
        let purpose: String
        let cue: String

        if lowerMain.contains("pace") || lowerMain.contains("x") {
            kind = .interval
            title = "Interval session"
            effort = "Controlled fast"
            purpose = "Build speed support and rhythm changes without turning the whole week hard."
            cue = "Run the reps with control so the final one still looks clean."
        } else if lowerMain.contains("@ hmp") {
            kind = .tempo
            title = "Half-marathon pace run"
            effort = "Steady threshold"
            purpose = "Practice goal-rhythm work inside a supported session."
            cue = "Lock into rhythm instead of chasing pace."
        } else {
            kind = .tempo
            title = "Structured workout"
            effort = "Moderate-hard"
            purpose = "Build race-specific strength with a defined main set."
            cue = "Keep the main set honest but repeatable."
        }

        let stepKinds = lines.enumerated().map { index, line -> TrainingPlanWorkoutStep in
            let lower = line.lowercased()
            let stepKind: TrainingPlanWorkoutStepKind
            if lower.contains("warm up") {
                stepKind = .warmup
            } else if lower.contains("cool down") {
                stepKind = .cooldown
            } else if kind == .interval {
                stepKind = .interval
            } else {
                stepKind = .tempo
            }
            return step(
                "\(id)-line-\(index)",
                stepKind,
                line,
                estimatedStepDurationSeconds(for: line, fallbackDistanceMiles: totalDistance / Double(max(lines.count, 1))),
                lower.contains("@ hmp") ? "Run this at controlled half-marathon effort." : nil
            )
        }

        let total = max(stepKinds.reduce(0) { $0 + $1.durationSeconds }, estimatedDurationSeconds(distanceMiles: max(totalDistance, 5)))
        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: kind,
            dayLabel: day,
            summary: summary,
            purpose: purpose,
            coachCue: cue,
            effortLabel: effort,
            durationSeconds: total,
            distanceLabel: totalDistance > 0 ? formattedDistanceLabel(totalDistance) : nil,
            steps: stepKinds,
            isOptional: false
        )
    }

    static func estimatedDurationSeconds(distanceMiles: Double) -> Int {
        Int((distanceMiles * 10.5 * 60).rounded())
    }

    static func estimatedStepDurationSeconds(for line: String, fallbackDistanceMiles: Double) -> Int {
        let lower = line.lowercased()
        if lower.contains("warm up") || lower.contains("cool down") {
            return Int((extractLeadingDistance(from: line) ?? 1.5) * 11 * 60)
        }
        if let minuteValue = extractMinutes(from: line) {
            return minuteValue * 60
        }
        if lower.contains("400m"), let reps = extractRepeatCount(from: line) {
            return reps * 3 * 60
        }
        if lower.contains("600m"), let reps = extractRepeatCount(from: line) {
            return reps * 4 * 60
        }
        if lower.contains("800m"), let reps = extractRepeatCount(from: line) {
            return reps * 5 * 60
        }
        if lower.contains("1k"), let reps = extractRepeatCount(from: line) {
            return reps * 5 * 60
        }
        if lower.contains("1 miles") || lower.contains("1 mile"), let reps = extractRepeatCount(from: line) {
            return reps * 8 * 60
        }
        if lower.contains("1.5 miles"), let reps = extractRepeatCount(from: line) {
            return reps * 12 * 60
        }
        if lower.contains("2 miles"), let reps = extractRepeatCount(from: line) {
            return reps * 16 * 60
        }
        if lower.contains("3 miles"), let reps = extractRepeatCount(from: line) {
            return reps * 24 * 60
        }
        if let distance = extractLeadingDistance(from: line) {
            return estimatedDurationSeconds(distanceMiles: distance)
        }
        return estimatedDurationSeconds(distanceMiles: max(fallbackDistanceMiles, 1))
    }

    static func extractLeadingDistance(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = trimmed.prefix { "0123456789.,".contains($0) }
        let normalized = prefix.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    static func extractMinutes(from line: String) -> Int? {
        let tokens = line.replacingOccurrences(of: ",", with: "").split(separator: " ")
        for index in tokens.indices.dropLast() {
            if let value = Int(tokens[index]), tokens[tokens.index(after: index)].lowercased().hasPrefix("min") {
                return value
            }
        }
        return nil
    }

    static func extractRepeatCount(from line: String) -> Int? {
        let tokens = line.replacingOccurrences(of: ",", with: "").split(separator: " ")
        for token in tokens {
            if let xIndex = token.firstIndex(of: "x"), let value = Int(token[..<xIndex]) {
                return value
            }
        }
        return nil
    }

    static func formattedDistanceLabel(_ miles: Double) -> String {
        if miles == 13.1 { return "13.1 mi" }
        if miles == 26.2 { return "26.2 mi" }
        if miles.rounded() == miles {
            return "\(Int(miles)) mi"
        }
        return "\(miles.formatted(.number.precision(.fractionLength(1)))) mi"
    }
}

private enum C25KEvent {
    case warmup(Int)
    case run(Int)
    case walk(Int)
    case cooldown(Int)
}
