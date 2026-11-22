(* bin/run_dsl.ml - Run a .dsl file through the DP solver from CLI. *)

open Milestone

let read_file path =
  let ic = open_in_bin path in
  let len = in_channel_length ic in
  let buf = really_input_string ic len in
  close_in ic;
  buf

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "Usage: dune exec run_dsl -- <path/to/problem.mls>";
    exit 1
  end;
  let path = Sys.argv.(1) in
  let source = read_file path in
  match Dsl.compile source with
  | Error err ->
      prerr_endline ("DSL error: " ^ Dsl.format_error err);
      exit 1
  | Ok cp ->
      let res =
        Solver.solve
          ~problem:cp.the_problem
          ~state_grid:cp.state_grid
          ~control_grid:cp.control_grid
      in
      let (states, controls) =
        Solver.rollout
          ~problem:cp.the_problem
          ~result:res
          ~state_grid:cp.state_grid
          ~initial_state:cp.initial_state
      in
      Printf.printf "Problem: %s\n" cp.name;
      for k = 0 to cp.the_problem.horizon - 1 do
        let st_str =
          states.(k)
          |> Array.to_list
          |> List.map (Printf.sprintf "%.3f")
          |> String.concat ", "
        in
        Printf.printf "k=%2d | state=[%s]  u=%.3f\n" k st_str controls.(k).(0)
      done;
      let final_str =
        states.(cp.the_problem.horizon)
        |> Array.to_list
        |> List.map (Printf.sprintf "%.3f")
        |> String.concat ", "
      in
      Printf.printf "k=%2d | state=[%s]  (terminal)\n"
        cp.the_problem.horizon final_str
