import { mobilityAdapter } from "./mobilityAdapter.js";
import { runAdapter } from "./runAdapter.js";
import { strengthAdapter } from "./strengthAdapter.js";
import { walkAdapter } from "./walkAdapter.js";
import type { Modality, ModalityAdapter, StimulusRequest } from "../types.js";

const adapters: ModalityAdapter[] = [
  runAdapter,
  walkAdapter,
  mobilityAdapter,
  strengthAdapter,
];

export function adapterFor(modality: Modality, stimulus?: StimulusRequest["stimulus"]): ModalityAdapter {
  const request = { modality, stimulus: stimulus ?? "easyAerobic" };
  return (
    adapters.find((adapter) => adapter.modality === modality && adapter.canSatisfy(request)) ??
    adapters.find((adapter) => adapter.canSatisfy(request)) ??
    mobilityAdapter
  );
}

export { adapters as modalityAdapters };
