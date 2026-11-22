// Type declarations for the OCaml-compiled JS module.
// Loaded via <script src="bridge_js.js"> which defines window.Milestone.

declare global {
  interface Window {
    Milestone: {
      solve_from(dsl_source: string): string;
    };
  }
}

export {};
