import type { SolveResult, WorkerRequest, WorkerResponse } from "./bridge";

interface MilestoneApi {
  solve_from(dslSource: string): string;
}

interface WorkerScope {
  importScripts?: (...urls: string[]) => void;
  postMessage(message: WorkerResponse): void;
  addEventListener(
    type: "message",
    listener: (event: MessageEvent<WorkerRequest>) => void,
  ): void;
  Milestone?: MilestoneApi;
}

const scope = self as unknown as WorkerScope;

if (typeof scope.importScripts !== "function") {
  throw new Error("This worker must be loaded as a classic worker.");
}

scope.importScripts("/bridge_js.js");

scope.addEventListener("message", (event) => {
  const { id, dslSource, type } = event.data;

  if (typeof id !== "number") return;

  try {
    if (typeof dslSource !== "string") {
      throw new Error("DSL source must be a string.");
    }

    if (!scope.Milestone) {
      throw new Error("OCaml bridge not loaded in worker.");
    }

    const rawJson = scope.Milestone.solve_from(dslSource);
    const result = JSON.parse(rawJson) as SolveResult;

    scope.postMessage({ id, type, result });
  } catch (error) {
    scope.postMessage({
      id,
      type,
      error: {
        message: error instanceof Error ? error.message : String(error),
      },
    });
  }
});
