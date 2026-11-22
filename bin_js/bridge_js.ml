(* bin_js/bridge_js.ml - JS entry point.
   Exposes [window.Milestone.solve_from_dsl(dsl: string): string]
   to the browser. Pure synchronous call; no Lwt, no promises. *)

open Js_of_ocaml

let () =
  (* Expose as window.Milestone *)
  Js.export "Milestone"
    object%js
      method solve_from_dsl (s : Js.js_string Js.t) : Js.js_string Js.t =
        let ocaml_src = Js.to_string s in
        (* Note the Milestone. prefix here *)
        let json_result = Milestone.Bridge.solve_from_dsl ocaml_src in
        Js.string json_result
    end
