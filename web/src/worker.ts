// web/src/worker.ts
// Runs the OCaml solver off the main thread.

// Load the OCaml bridge into the worker context.
// Note: importScripts only works in classic workers (no { type: "module" }).
importScripts("/bridge_js.js");

self.addEventListener("message", (event: MessageEvent) => {
  const { id, dslSource } = event.data;
  try {
    // globalThis refers to the worker's global scope
    const workerGlobal = globalThis as unknown as {
      Milestone?: { solve_from: (s: string) => string };
    };

    if (!workerGlobal.Milestone) {
      throw new Error(
        "OCaml bridge not loaded. Ensure bridge_js.js is in web/public/ and accessible at /bridge_js.js",
      );
    }

    const rawJson = workerGlobal.Milestone.solve_from(dslSource);
    const result = JSON.parse(rawJson);
    self.postMessage({ id, result });
  } catch (err) {
    self.postMessage({
      id,
      error: { message: err instanceof Error ? err.message : String(err) },
    });
  }
});
