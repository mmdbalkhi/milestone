// web/src/bridge.ts

export interface SolveResult {
  status: "ok" | "error";
  problem_name?: string;
  stage?: "parse" | "semantic" | "runtime";
  message?: string;
  result?: {
    steps: number;
    dt: number;
    time: number[];
    states: number[][];
    controls: number[][];
  };
}

let worker: Worker | null = null;
let nextId = 0;
const pending = new Map<
  number,
  {
    resolve: (value: SolveResult) => void;
    reject: (reason: unknown) => void;
  }
>();

function getWorker(): Worker {
  if (!worker) {
    // REMOVED { type: "module" } so importScripts works in the classic worker
    worker = new Worker(new URL("./worker.ts", import.meta.url));

    worker.addEventListener("message", (event: MessageEvent) => {
      const { id, result, error } = event.data;
      const p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (error) p.reject(new Error(error.message));
      else p.resolve(result as SolveResult);
    });
  }
  return worker;
}

export function initBridge() {
  function solve(dslSource: string): Promise<SolveResult> {
    return new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      getWorker().postMessage({ id, dslSource });
    });
  }

  return { solve };
}
