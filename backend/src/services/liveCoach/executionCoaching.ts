import type { LiveCoachCompiledContext, SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachGuidancePlan } from "./liveCoachTypes.js";

type Phase = "warmup" | "easy" | "work" | "recovery" | "walk" | "cooldown" | "open";
const pacerIntroductions: Record<SupportedAILocale, string> = {
  en: "These beats match your current rhythm. Try one step per beat, keeping the effort comfortable.",
  es: "Estos golpes siguen tu ritmo actual. Prueba a dar un paso con cada golpe, sin dejar de correr a gusto.",
  "zh-Hans": "接下来的鼓点会跟随你现在的步频。试着每个鼓点迈一步，保持轻松舒适就好。",
};

/** Opportunistic device playback only: deliberately has no scheduled trigger. */
export function cadencePacerIntroductionCues(context: LiveCoachCompiledContext): LiveCoachGuidancePlan["cues"] {
  if (context.activityType !== "running" || context.race || context.safetyRequiresFixedOnly) return [];
  return [{
    id: "cadence_pacer.intro", moment: "workout_instruction", instructionId: "cadence_pacer.intro",
    phases: ["any"], priority: "steady", cooldownSeconds: 300,
    phrases: [{ id: "cadence_pacer.intro.0", text: pacerIntroductions[context.locale] }],
  }];
}

const scripts: Record<SupportedAILocale, Record<Phase | "breathing" | "form" | "pacing", string>> = {
  en: {
    warmup: "Start gently and build effort gradually; these opening minutes prepare you for the work ahead.",
    easy: "Keep this section conversational; slowing down is fine if speaking a full sentence becomes difficult.",
    work: "Build toward the prescribed effort smoothly; avoid spending the whole interval recovering from a fast start.",
    recovery: "Let the pace come down and your breathing settle; recovery prepares you for the next effort.",
    walk: "Keep your walking steps comfortable and shoulders relaxed; follow the effort planned for this section.",
    cooldown: "Ease the effort down gradually; use this final section to finish calmly rather than chase speed.",
    open: "Keep the effort manageable; leave room to adjust smoothly if the session starts feeling harder than planned.",
    breathing: "Check whether your breathing fits the planned effort; ease off if it feels harder than intended.",
    form: "Try softening your hands and relaxing your shoulders; notice whether you are holding unnecessary tension.",
    pacing: "Make any pace adjustment gradually; a controlled effort matters more than chasing each changing pace reading.",
  },
  es: {
    warmup: "Empieza suave y aumenta el esfuerzo poco a poco; estos primeros minutos te preparan para lo que viene.",
    easy: "Mantén un esfuerzo que te permita conversar; afloja si te cuesta decir una frase completa.",
    work: "Alcanza el esfuerzo indicado progresivamente; evita pasar todo el intervalo recuperándote de una salida demasiado rápida.",
    recovery: "Baja el ritmo y deja que la respiración se calme; esta recuperación prepara el siguiente esfuerzo.",
    walk: "Camina con pasos cómodos y los hombros relajados; respeta el esfuerzo previsto para este tramo.",
    cooldown: "Reduce el esfuerzo poco a poco; aprovecha este tramo final para terminar con calma, sin buscar más velocidad.",
    open: "Mantén un esfuerzo sostenible; deja margen para ajustar con suavidad si la sesión cuesta más de lo previsto.",
    breathing: "Comprueba si tu respiración corresponde al esfuerzo previsto; afloja si te está costando más de lo indicado.",
    form: "Prueba a aflojar las manos y relajar los hombros; comprueba si estás acumulando tensión innecesaria.",
    pacing: "Ajusta la velocidad poco a poco; controlar el esfuerzo importa más que perseguir cada cambio del ritmo mostrado.",
  },
  "zh-Hans": {
    warmup: "先轻松起步，再逐步增加强度，让身体为接下来的训练做好准备。",
    easy: "这一段保持能轻松交谈的强度；如果说完整句子有些吃力，就放慢一点。",
    work: "逐步达到规定强度，别在起步时猛冲，以免后面一直忙着缓过劲来。",
    recovery: "放慢配速，让呼吸平稳下来；这一段恢复是为了准备好下一次发力。",
    walk: "步伐保持舒适，肩膀放松，按这一段规定的强度走就好。",
    cooldown: "逐步降低强度，用最后这一段从容结束，不必再追求速度。",
    open: "保持能够持续的强度；如果训练比预期更吃力，就给自己留些余地，平稳调整。",
    breathing: "留意呼吸是否符合计划强度；如果比预期更吃力，就降低一点强度。",
    form: "试着放松双手和肩膀，留意自己是不是一直在不自觉地用力绷紧。",
    pacing: "需要调整配速时慢慢来；控制好强度，比追着屏幕上每次配速变化更重要。",
  },
};

/** Scheduled instruction opportunities fill quiet steady runs; they assert no sensor observations. */
export function executionCoachingCues(context: LiveCoachCompiledContext): LiveCoachGuidancePlan["cues"] {
  if (context.activityType !== "running" || context.race || context.safetyRequiresFixedOnly
      || context.workoutExecution) return [];
  const steps = (context.clientWorkout?.steps ?? []).map((value) => {
    const step = value as { phase?: string; durationSeconds?: number };
    return { phase: phase(step.phase), duration: Math.max(0, step.durationSeconds ?? 0) };
  });
  const structuredDuration = steps.reduce((total, step) => total + step.duration, 0);
  const duration = Math.min(7_200, structuredDuration || context.clientWorkout?.targetDurationSeconds
    || context.workout?.durationSeconds || 3_600);
  const cues: LiveCoachGuidancePlan["cues"] = [];
  let previousPhase: Phase | undefined;
  let variation = 0;
  for (let elapsed = 30; elapsed < duration - 30; elapsed += 120) {
    let start = 0;
    let current: Phase = "open";
    let remaining = duration - elapsed;
    for (const step of steps) {
      if (elapsed < start + step.duration) {
        current = step.phase;
        remaining = start + step.duration - elapsed;
        break;
      }
      start += step.duration;
    }
    // Transitions and interval execution retain priority. No adjacent cue at a boundary.
    if (steps.length && (elapsed - start < 25 || remaining < 35)) continue;
    const key = previousPhase !== current ? current
      : (["breathing", "form", "pacing", current] as const)[variation++ % 4];
    previousPhase = current;
    const id = `execution_coaching.${elapsed}`;
    cues.push({
      id, moment: "workout_instruction", instructionId: id,
      trigger: { type: "elapsed_time", startSeconds: elapsed, endSeconds: elapsed + 20 },
      phases: ["any"], priority: "steady", cooldownSeconds: 90,
      phrases: [{ id: `${id}.0`, text: scripts[context.locale][key] }],
    });
  }
  return cues;
}

function phase(value: string | undefined): Phase {
  return value && ["warmup", "easy", "work", "recovery", "walk", "cooldown"].includes(value)
    ? value as Phase : "open";
}
