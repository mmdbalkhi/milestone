# Rule 03: WASM / JS Bridge & Minimal Web Frontend

## Scope
Applies to the bridge module(s) exposing the OCaml Core to the browser and `web/`.
Do NOT modify `lib/grid.*`, `lib/problem.*`, or `lib/solver.*` unless strictly required to expose a pure function or JSON serializer.

## 1. Architectural Rule: Presentation Only
- All mathematical modeling, grid discretization, interpolation, backward DP, rollout, and DSL parsing/compilation MUST remain in OCaml.
- TypeScript/JavaScript in `web/` is strictly for:
  1. Editing/loading DSL text (with a default `DoubleIntegrator` preset).
  2. Calling the OCaml bridge function.
  3. Rendering trajectory/control charts and displaying clear error messages.
- Do NOT re-implement DP, interpolation, or expression parsing in JS/TS.

## 2. Bridge Contract (`solve_dsl`)
Expose a single deterministic function to the frontend:
- Input: `dsl_source : string`
- Output: JSON string matching one of two shapes:
  - Success:
    ```json
    {
      "status": "ok",
      "problem_name": "DoubleIntegrator",
      "result": {
        "steps": 20,
        "time": [0.0, 0.1, ...],
        "states": [[0.0, 0.0], ...],
        "controls": [[2.0], ...]
      }
    }
    ```
  - Error:
    ```json
    {
      "status": "error",
      "stage": "parse" | "semantic" | "runtime",
      "message": "human-readable error description"
    }
    ```

## 3. Build & Fallback Strategy
1. First attempt a minimal working prototype using `wasm_of_ocaml` (or `js_of_ocaml` if `wasm_of_ocaml` encounters toolchain/opam/Dune friction in the local environment).
2. If compiling OCaml to WASM/JS hits persistent environment or dependency issues, stop spending time on toolchain debugging and keep the working CLI/native Core as the primary deliverable.

## 4. Minimal UI Scope
- Use a lightweight setup (Vite + TypeScript + a plain text/code editor + a simple charting library like Chart.js or Plotly or lightweight SVG/Canvas).
- Keep it as a single clean page:
  - Left/Top: DSL editor + sample `DoubleIntegrator` button + `Solve` button.
  - Right/Bottom: State trajectory (`x`, `v` over time), control input (`u` over time), and a clean error box when `status === "error"`.
- Do NOT add multi-page routing, authentication, backend servers, themes/dashboards, or heavy animations.
