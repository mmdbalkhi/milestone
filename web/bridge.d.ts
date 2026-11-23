declare global {
  interface Window {
    Milestone?: {
      solve_from(dslSource: string): string;
    };
  }

  interface DedicatedWorkerGlobalScope {
    Milestone?: {
      solve_from(dslSource: string): string;
    };
  }
}

export {};
