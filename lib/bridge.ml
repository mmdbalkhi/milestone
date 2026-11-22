(* lib/bridge.ml - Stateless string/JSON boundary between OCaml Core and Web/WASM.

   Orchestrates: DSL compile -> Solver.solve -> Solver.rollout -> JSON serialize.
   All errors are caught and returned as structured JSON; no uncaught exceptions. *)

(* JSON helpers ---------------------------------------------------------- *)

let json_of_float_array arr =
  `List (List.init (Array.length arr) (fun i -> `Float arr.(i)))

let json_of_state_array arr =
  `List (List.init (Array.length arr) (fun i -> json_of_float_array arr.(i)))

(* Error classification -------------------------------------------------- *)

let stage_of_error = function
  | Dsl.Lex_error _ | Dsl.Parse_error _ -> "parse"
  | Dsl.Semantic_error _ -> "semantic"

let error_to_json stage message =
  `Assoc
    [
      ("status", `String "error");
      ("stage", `String stage);
      ("message", `String message);
    ]

let dsl_error_to_json err =
  error_to_json (stage_of_error err) (Dsl.format_error err)

(* Success result -------------------------------------------------------- *)

let result_to_json ~problem_name ~dt ~steps ~states ~controls =
  let time = Array.init (steps + 1) (fun k -> float_of_int k *. dt) in
  `Assoc
    [
      ("status", `String "ok");
      ("problem_name", `String problem_name);
      ( "result",
        `Assoc
          [
            ("steps", `Int steps);
            ("dt", `Float dt);
            ("time", json_of_float_array time);
            ("states", json_of_state_array states);
            ("controls", json_of_state_array controls);
          ] );
    ]

(* Entry point ----------------------------------------------------------- *)

let solve_from_dsl dsl_source =
  let json =
    try
      match Dsl.compile dsl_source with
      | Error err -> dsl_error_to_json err
      | Ok cp ->
          let result =
            Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
              ~control_grid:cp.control_grid
          in
          let states, controls =
            Solver.rollout ~problem:cp.the_problem ~result
              ~state_grid:cp.state_grid ~initial_state:cp.initial_state
          in
          result_to_json ~problem_name:cp.name ~dt:cp.dt
            ~steps:cp.the_problem.horizon ~states ~controls
    with exn -> error_to_json "runtime" (Printexc.to_string exn)
  in
  Yojson.Safe.to_string json
