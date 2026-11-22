# Web Frontend — Control Lab

This directory contains a minimal Vite + TypeScript frontend for the Control Lab
OCaml DP solver. It communicates with the OCaml core through the
`solve_from_dsl : string -> string` bridge (JSON over string).

## Files

- `index.html` — Single page: DSL editor + Solve button + charts + error box
- `src/bridge.ts` — Bridge to OCaml (currently a deterministic mock)
- `src/ui.ts` — Chart.js rendering of state/control trajectories
- `vite.config.ts` — Vite configuration
- `package.json` — Dependencies (vite, typescript, chart.js)

## Getting the real OCaml bridge

The frontend currently uses a **mock bridge** (`web/src/bridge.ts`) because the
OCaml-to-WASM compiler (`js_of_ocaml` / `wasm_of_ocaml`) could not be installed
in this environment (network restrictions). To replace the mock with the real
OCaml bridge:

### 1. Install js_of_ocaml

```bash
opam install js_of_ocaml js_of_ocaml-compiler
```

### 2. Add a JS entry point

Create `lib/bridge_js.ml` that exposes `solve_from_dsl` to JavaScript:

```ocaml
(* lib/bridge_js.ml *)
let _ =
  Js_of_ocaml.Lwt_js global_scope
```

and a `lib/dune_js` stanza:

```lisp
(executable
 (name bridge_js)
 (libraries milestone js_of_ocaml)
 (flags (:standard -js)))
```

Then compile:

```bash
dune build lib/bridge_js.bc.js
```

This produces `_build/default/lib/bridge_js.bc.js` which exposes `solve_from_dsl`
on the global scope.

### 3. Wire into the frontend

Replace the mock in `web/src/bridge.ts` with a call to the compiled JS:

```ts
export async function solve(dslSource: string): Promise<SolveResult> {
  const resp = await fetch('/bridge.js'); // or inline the compiled output
  const result = await window.solve_from_dsl(dslSource);
  return JSON.parse(result);
}
```

### 4. Run the frontend

```bash
cd web
npm install
npm run dev
```

Then open `http://localhost:5173`.

## Without network (this environment)

Since `npm install` and `opam install` cannot reach the registry here, the
frontend is designed to work with Chart.js loaded from CDN in `index.html`.
Open `web/index.html` directly in a browser to use the mock bridge.

## JSON contract

The bridge returns one of:

**Success:**
```json
{"status":"ok","problem_name":"DoubleIntegrator","result":
 {"steps":20,"time":[0.0,0.1,...],"states":[[0.0,0.0],...],"controls":[[2.0],...]}}
```

**Error:**
```json
{"status":"error","stage":"parse"|"semantic"|"runtime","message":"..."}
```
