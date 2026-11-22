(* bin/main.ml - Quick check on DoubleIntegrator *)

open Milestone

let () =
  let dt = 0.1 in
  let horizon = 20 in
  let problem =
    Problem.make ~horizon
      ~dynamics:(Problem.double_integrator_dynamics ~dt)
      ~running_cost:(fun x u ->
        let xv = x.(0) and vv = x.(1) and uv = u.(0) in
        (xv *. xv) +. (vv *. vv) +. (0.1 *. uv *. uv))
      ~terminal_cost:(fun x ->
        let dx = x.(0) -. 10.0 in
        let vv = x.(1) in
        (10.0 *. dx *. dx) +. (10.0 *. vv *. vv))
  in
  let state_grid =
    Solver.G2
      (Grid.make2 ~lox:(-5.0) ~hix:15.0 ~nx:41 ~loy:(-10.0) ~hiy:10.0 ~ny:41)
  in
  let control_grid = Grid.make1 ~lo:(-2.0) ~hi:2.0 ~n:21 in
  let result = Solver.solve ~problem ~state_grid ~control_grid in
  let states, controls =
    Solver.rollout ~problem ~result ~state_grid ~initial_state:[| 0.0; 0.0 |]
  in
  for k = 0 to horizon - 1 do
    Printf.printf "k=%2d | x=%7.3f  v=%7.3f  u=%7.3f\n" k
      states.(k).(0)
      states.(k).(1)
      controls.(k).(0)
  done;
  Printf.printf "k=%2d | x=%7.3f  v=%7.3f  (terminal)\n" horizon
    states.(horizon).(0)
    states.(horizon).(1)
