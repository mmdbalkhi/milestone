# WASM Build Notes

The OCaml core (`lib/`) compiles natively via `dune build`. The bridge module
`lib/bridge.ml` provides `solve_from_dsl : string -> string` — pure OCaml, no
browser dependencies — so it can be cross-compiled to WASM/JS.

## Option A: js_of_ocaml (recommended)

```bash
opam install js_of_ocaml js_of_ocaml-compiler
```

Create a JS entry point `lib/bridge_js.ml`:

```ocaml
(* Expose solve_from_dsl to the global JS scope *)
let _ =
  Js_of_ocaml.Lwt_js.global_scope##.solve_from_dsl <-
    Js_of_ocaml.Lwt_js.wrap_meth (fun s -> Lwt.return (Bridge.solve_from_dsl s))
```

Add a Dune stanza `lib/dune_js`:

```lisp
(executable
 (name bridge_js)
 (libraries milestone js_of_ocaml)
 (flags (:standard -js)))
```

Build:

```bash
dune build lib/bridge_js.bc.js
```

Output: `_build/default/lib/bridge_js.bc.js`

## Option B: wasm_of_ocaml

```bash
opam install wasm_of_ocaml
```

Similar JS entry point, compiled with:

```bash
dune build lib/bridge_js.bc.wasm
```

## Current status

The `js_of_ocaml`/`wasm_of_ocaml` opam packages are not installable in this
environment (network restrictions), so the WASM build could not be verified.
The `lib/bridge.ml` module is pure OCaml and compiles natively; the web frontend
uses a deterministic mock until the real WASM module is available.
