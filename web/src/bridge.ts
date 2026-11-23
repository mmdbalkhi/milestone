/// <reference types="vite/client" />

export type SolveStage = "parse" | "semantic" | "runtime";

export interface TrajectoryResult {
  steps: number;
  dt: number;
  time: number[];
  states: number[][];
  controls: number[][];
}

export interface SolveResult {
  status: "ok" | "error";
  problem_name?: string;
  stage?: SolveStage;
  message?: string;
  result?: TrajectoryResult;
}

export type WorkerRequestType = "solve" | "lint";

export interface WorkerRequest {
  id: number;
  type: WorkerRequestType;
  dslSource: string;
}

export interface WorkerResponse {
  id: number;
  type: WorkerRequestType;
  result?: SolveResult;
  error?: { message: string };
}

export interface LintIssue {
  line: number;
  column: number;
  endColumn?: number;
  severity: "error" | "warning" | "info";
  message: string;
}

interface PendingRequest {
  resolve: (value: SolveResult) => void;
  reject: (reason: unknown) => void;
}

let worker: Worker | null = null;
let nextId = 0;
const pending = new Map<number, PendingRequest>();
function getWorker(): Worker {
  if (worker) return worker;

  // Plain static URL: Rolldown won't bundle or rewrite this.
  // BASE_URL keeps it correct if you deploy under a sub-path.
  worker = new Worker(`${import.meta.env.BASE_URL}solver-worker.js`, {
    type: "classic",
  });

  worker.addEventListener("message", (event: MessageEvent<WorkerResponse>) => {
    const response = event.data;
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id);

    if (response.error)
      return request.reject(new Error(response.error.message));
    if (!response.result)
      return request.reject(new Error("Worker returned empty response."));
    request.resolve(response.result);
  });

  worker.addEventListener("error", (event) => {
    // Never show a bare "Worker failed." again — surface the real cause.
    const detail = event.message
      ? `${event.message} (${event.filename}:${event.lineno})`
      : "Worker script failed to load — check the Network tab for the worker request.";
    const error = new Error(detail);
    for (const request of pending.values()) request.reject(error);
    pending.clear();
    worker?.terminate();
    worker = null;
  });

  return worker;
}

function request(
  type: WorkerRequestType,
  dslSource: string,
): Promise<SolveResult> {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });

    try {
      getWorker().postMessage({ id, type, dslSource } satisfies WorkerRequest);
    } catch (error) {
      pending.delete(id);
      reject(error);
    }
  });
}

function parseLintIssue(result: SolveResult): LintIssue[] {
  if (result.status !== "error") return [];

  const message = result.message ?? "Invalid DSL.";
  const match = message.match(/line\s+(\d+)\s+(?:col|column)\s+(\d+)/i);

  if (!match) {
    return [{ line: 1, column: 1, endColumn: 2, severity: "error", message }];
  }

  const line = Number.parseInt(match[1], 10);
  const column = Number.parseInt(match[2], 10);

  return [{ line, column, endColumn: column + 5, severity: "error", message }];
}

export function initBridge() {
  return {
    solve(dslSource: string): Promise<SolveResult> {
      return request("solve", dslSource);
    },
    async lint(dslSource: string): Promise<LintIssue[]> {
      if (!dslSource.trim()) return [];
      try {
        const result = await request("lint", dslSource);
        return parseLintIssue(result);
      } catch {
        return [];
      }
    },
  };
}
