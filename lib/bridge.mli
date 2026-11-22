(* lib/bridge.mli - Stateless string/JSON boundary between OCaml Core and Web/WASM.

   `solve_from_dsl` is the single integration boundary (AGENTS.md §2):
   Input:  DSL source text
   Output: JSON string (success result or structured error)

   Pure OCaml: no browser APIs, no js_of_ocaml, no wasm_of_ocaml.  It can be
   compiled natively or cross-compiled to WASM/JS. *)

val solve_from_dsl : string -> string
