importScripts("bridge_js.js");

self.addEventListener("message", (event) => {
  const { id, dslSource, type } = event.data;
  if (typeof id !== "number") return;

  try {
    if (typeof dslSource !== "string")
      throw new Error("DSL source must be a string.");
    if (!self.Milestone) throw new Error("OCaml bridge not loaded in worker.");

    const result = JSON.parse(self.Milestone.solve_from(dslSource));
    self.postMessage({ id, type, result });
  } catch (error) {
    self.postMessage({
      id,
      type,
      error: {
        message: error instanceof Error ? error.message : String(error),
      },
    });
  }
});
