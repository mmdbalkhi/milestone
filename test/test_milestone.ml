(* test/test_solver.ml - Structured unit and numerical tests for Control Lab core. *)

open Milestone
open Bridge
open Yojson.Safe

let eps = 1e-9

(* Small JSON navigation helpers *)
let jstring j =
  match j with `String s -> s | _ -> failwith (Printf.sprintf "expected string, got %s" (to_string j))
let jint j =
  match j with `Int n -> n | _ -> failwith (Printf.sprintf "expected int, got %s" (to_string j))
let jassoc key j =
  match j with `Assoc lst -> List.assoc key lst | _ -> failwith (Printf.sprintf "expected object, got %s" (to_string j))
let jlist j =
  match j with `List lst -> lst | _ -> failwith (Printf.sprintf "expected array, got %s" (to_string j))
let approx a b = abs_float (a -. b) < eps
let assert_true msg cond = if not cond then failwith ("FAIL [" ^ msg ^ "]")

let assert_approx msg expected actual =
  if not (approx expected actual) then
    failwith
      (Printf.sprintf "FAIL [%s]: expected %.10g, got %.10g" msg expected actual)

let assert_invalid_arg msg f =
  let raised =
    try
      ignore (f ());
      false
    with Invalid_argument _ -> true
  in
  assert_true msg raised

let test_grid_1d () =
  let g = Grid.make1 ~lo:0.0 ~hi:1.0 ~n:11 in
  for i = 0 to 10 do
    assert_approx "1D node spacing" (float_of_int i *. 0.1) (Grid.node1 g i)
  done;
  assert_true "1D clamp index low" (Grid.node1 g (-5) = Grid.node1 g 0);
  assert_true "1D clamp index high" (Grid.node1 g 100 = Grid.node1 g 10);

  let xs = Array.init 11 (fun i -> Grid.node1 g i) in
  for k = 0 to 100 do
    let x = float_of_int k *. 0.01 in
    assert_approx "1D linear interp exact on affine" x (Grid.interp1 g xs x)
  done;

  let cs = Array.make 11 4.2 in
  assert_approx "1D constant interp" 4.2 (Grid.interp1 g cs 0.37);
  assert_approx "1D interp out-of-range low" xs.(0) (Grid.interp1 g xs (-3.0));
  assert_approx "1D interp out-of-range high" xs.(10) (Grid.interp1 g xs 3.0);
  assert_true "1D nearest index" (Grid.nearest1 g 0.37 = 4);
  assert_true "1D nearest upper boundary" (Grid.nearest1 g 1.0 = 10);
  assert_invalid_arg "1D rejects n < 2" (fun () ->
      ignore (Grid.make1 ~lo:0.0 ~hi:1.0 ~n:1));
  assert_invalid_arg "1D rejects lo >= hi" (fun () ->
      ignore (Grid.make1 ~lo:1.0 ~hi:1.0 ~n:5))

let test_grid_2d () =
  let g2 = Grid.make2 ~lox:0.0 ~hix:1.0 ~nx:3 ~loy:0.0 ~hiy:1.0 ~ny:2 in
  assert_true "2D row-major (0,0)" (Grid.index2 g2 0 0 = 0);
  assert_true "2D row-major (1,0)" (Grid.index2 g2 1 0 = 2);
  assert_true "2D row-major (2,1)" (Grid.index2 g2 2 1 = 5);

  let x0, y0 = Grid.node2 g2 0 0 in
  let x1, y1 = Grid.node2 g2 2 1 in
  assert_approx "2D node origin x" 0.0 x0;
  assert_approx "2D node origin y" 0.0 y0;
  assert_approx "2D node far corner x" 1.0 x1;
  assert_approx "2D node far corner y" 1.0 y1;

  let xs2 = Array.init 6 (fun k -> float_of_int (k / 2) *. 0.5) in
  assert_approx "2D bilinear x-linear" 0.37 (Grid.interp2 g2 xs2 0.37 0.5);
  assert_approx "2D bilinear clamp low" 0.0 (Grid.interp2 g2 xs2 (-1.0) 0.5);
  assert_approx "2D bilinear clamp high" xs2.(5) (Grid.interp2 g2 xs2 2.0 2.0);
  assert_true "2D nearest cell" (Grid.nearest2 g2 0.37 0.5 = (1, 1))

let test_problem_and_solver () =
  let dt = 0.1 in
  let nsteps = 5 in
  assert_invalid_arg "Problem rejects non-positive horizon" (fun () ->
      ignore
        (Problem.make ~horizon:0
           ~dynamics:(Problem.double_integrator_dynamics ~dt)
           ~running_cost:(fun _ _ -> 0.0)
           ~terminal_cost:(fun _ -> 0.0)));

  (* 1D Bellman optimality check *)
  let dyn1 x u = [| x.(0) +. (dt *. u.(0)) |] in
  let run1 _ u = u.(0) *. u.(0) in
  let term1 x = x.(0) *. x.(0) in
  let p1 =
    Problem.make ~horizon:nsteps ~dynamics:dyn1 ~running_cost:run1
      ~terminal_cost:term1
  in
  let g1 = Grid.make1 ~lo:0.0 ~hi:1.0 ~n:11 in
  let cg = Grid.make1 ~lo:(-1.0) ~hi:1.0 ~n:9 in
  let sg1 = Solver.G1 g1 in
  let r1 = Solver.solve ~problem:p1 ~state_grid:sg1 ~control_grid:cg in

  for i = 0 to Grid.count1 g1 - 1 do
    let x = [| Grid.node1 g1 i |] in
    assert_approx "1D terminal value" (term1 x) r1.values.(nsteps).(i)
  done;

  for k = nsteps - 1 downto 0 do
    for i = 0 to Grid.count1 g1 - 1 do
      let x = [| Grid.node1 g1 i |] in
      let best = ref infinity in
      for cm = 0 to Grid.count1 cg - 1 do
        let u = [| Grid.node1 cg cm |] in
        let x_next = dyn1 x u in
        let v = run1 x u +. Grid.interp1 g1 r1.values.(k + 1) x_next.(0) in
        if v < !best then best := v
      done;
      assert_approx "1D Bellman invariant" !best r1.values.(k).(i)
    done
  done;

  let states, controls =
    Solver.rollout ~problem:p1 ~result:r1 ~state_grid:sg1
      ~initial_state:[| 0.3 |]
  in
  assert_true "1D states count" (Array.length states = nsteps + 1);
  assert_true "1D controls count" (Array.length controls = nsteps);
  assert_approx "1D initial state" 0.3 states.(0).(0);
  Array.iter
    (fun u ->
      assert_true "1D control lower bound" (u.(0) >= -1.0);
      assert_true "1D control upper bound" (u.(0) <= 1.0))
    controls

let test_double_integrator_target_trend () =
  (* Horizon 2.0s (20 steps of 0.1s) steering from (0, 0) toward x = 10, v = 0 *)
  let dt = 0.1 in
  let nsteps = 20 in
  let p =
    Problem.make ~horizon:nsteps
      ~dynamics:(Problem.double_integrator_dynamics ~dt)
      ~running_cost:(fun x u ->
        (x.(0) *. x.(0)) +. (x.(1) *. x.(1)) +. (0.1 *. u.(0) *. u.(0)))
      ~terminal_cost:(fun x ->
        let dx = x.(0) -. 10.0 in
        (10.0 *. dx *. dx) +. (10.0 *. x.(1) *. x.(1)))
  in
  let sg =
    Solver.G2
      (Grid.make2 ~lox:(-2.0) ~hix:12.0 ~nx:29 ~loy:(-5.0) ~hiy:10.0 ~ny:31)
  in
  let cg = Grid.make1 ~lo:(-2.0) ~hi:2.0 ~n:17 in
  let res = Solver.solve ~problem:p ~state_grid:sg ~control_grid:cg in
  let states, _ =
    Solver.rollout ~problem:p ~result:res ~state_grid:sg
      ~initial_state:[| 0.0; 0.0 |]
  in
  let final_x = states.(nsteps).(0) in
  assert_true "DI moves positively toward target x=10" (final_x > 2.0);
  assert_invalid_arg "Rollout rejects mismatched state dimension" (fun () ->
      ignore
        (Solver.rollout ~problem:p ~result:res ~state_grid:sg
           ~initial_state:[| 0.0 |]))

let test_dsl_double_integrator_match () =
  let di_dsl =
    "problem DoubleIntegrator\n\n\
     state:\n\
     x, v\n\n\
     control:\n\
     u\n\n\
     parameter:\n\
     dt = 0.1\n\n\
     dynamics:\n\
     x' = x + dt * v\n\
     v' = v + dt * u\n\
     end_dynamics\n\n\
     initial:\n\
     x = 0\n\
     v = 0\n\
     end_initial\n\n\
     target:\n\
     x = 10\n\
     v = 0\n\
     end_target\n\n\
     horizon: 20\n\n\
     bounds:\n\
     x in [-15, 15]\n\
     v in [-10, 10]\n\
     u in [-2, 2]\n\
     end_bounds\n\n\
     cost:\n\
     running = x^2 + v^2 + 0.1 * u^2\n\
     terminal = 10 * (x - 10)^2 + 10 * v^2\n\
     end_cost\n\n\
     solve:\n\
     method = dynamic_programming\n\
     grid = [100, 100]\n\
     controls = 41\n\
     end_solve\n\n\
     end_problem\n"
  in

  (* Compile the DSL *)
  let cp =
    match Dsl.compile di_dsl with
    | Ok cp -> cp
    | Error err -> failwith ("DSL compile failed: " ^ Dsl.format_error err)
  in
  (* initial state matches [0, 0] *)
  assert_approx "DSL initial x" 0.0 cp.initial_state.(0);
  assert_approx "DSL initial v" 0.0 cp.initial_state.(1);

  (* Build equivalent hardcoded problem (same grid/costs/horizon as DSL) *)
  let dt = 0.1 in
  let nsteps = 20 in
  let p_hard =
    Problem.make ~horizon:nsteps
      ~dynamics:(Problem.double_integrator_dynamics ~dt)
      ~running_cost:(fun x u ->
        (x.(0) *. x.(0)) +. (x.(1) *. x.(1)) +. (0.1 *. u.(0) *. u.(0)))
      ~terminal_cost:(fun x ->
        let dx = x.(0) -. 10.0 in
        (10.0 *. dx *. dx) +. (10.0 *. x.(1) *. x.(1)))
  in
  let sg_hard =
    Solver.G2
      (Grid.make2 ~lox:(-15.0) ~hix:15.0 ~nx:100 ~loy:(-10.0) ~hiy:10.0 ~ny:100)
  in
  let cg_hard = Grid.make1 ~lo:(-2.0) ~hi:2.0 ~n:41 in

  (* Solve both *)
  let r_dsl =
    Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
      ~control_grid:cp.control_grid
  in
  let r_hard =
    Solver.solve ~problem:p_hard ~state_grid:sg_hard ~control_grid:cg_hard
  in

  (* Compare terminal values at all grid nodes *)
  let nn = 100 * 100 in
  let max_diff =
    let rec loop i acc =
      if i >= nn then acc
      else
        let d =
          abs_float (r_hard.values.(nsteps).(i) -. r_dsl.values.(nsteps).(i))
        in
        loop (i + 1) (max acc d)
    in
    loop 0 0.0
  in
  ignore max_diff;
  let () = assert_true "DSL terminal values close" (max_diff < 1e-6) in

  (* Compare values at k=0 *)
  let max_diff0 =
    let rec loop i acc =
      if i >= nn then acc
      else
        let d = abs_float (r_hard.values.(0).(i) -. r_dsl.values.(0).(i)) in
        loop (i + 1) (max acc d)
    in
    loop 0 0.0
  in
  ignore max_diff0;
  let () = assert_true "DSL k=0 values close" (max_diff0 < 1e-6) in

  (* Compare policies *)
  let max_diff_policy =
    let rec loop_k k acc =
      if k >= nsteps then acc
      else
        let rec loop_i i acc2 =
          if i >= nn then acc2
          else
            let d = abs_float (r_hard.policy.(k).(i) -. r_dsl.policy.(k).(i)) in
            loop_i (i + 1) (max acc2 d)
        in
        loop_k (k + 1) (max acc (loop_i 0 0.0))
    in
    loop_k 0 0.0
  in
  let () = assert_true "DSL policies close" (max_diff_policy < 1e-6) in

  (* Rollout from (0,0) *)
  let st_dsl, ct_dsl =
    Solver.rollout ~problem:cp.the_problem ~result:r_dsl
      ~state_grid:cp.state_grid ~initial_state:cp.initial_state
  in
  let st_hard, ct_hard =
    Solver.rollout ~problem:p_hard ~result:r_hard ~state_grid:sg_hard
      ~initial_state:cp.initial_state
  in
  (* Rollout comparison *)
  let max_diff_rollout =
    let rec loop k acc =
      if k > nsteps then acc
      else
        let d1 = abs_float (st_hard.(k).(0) -. st_dsl.(k).(0)) in
        let d2 = abs_float (st_hard.(k).(1) -. st_dsl.(k).(1)) in
        loop (k + 1) (max acc (max d1 d2))
    in
    loop 0 0.0
  in
  let () = assert_true "DSL rollout states close" (max_diff_rollout < 1e-6) in
  let max_diff_ctrl =
    let rec loop k acc =
      if k >= nsteps then acc
      else
        let d = abs_float (ct_hard.(k).(0) -. ct_dsl.(k).(0)) in
        loop (k + 1) (max acc d)
    in
    loop 0 0.0
  in
  ignore max_diff_ctrl;
  assert_true "DSL rollout controls close" (max_diff_ctrl < 1e-6)

let test_dsl_invalid_inputs () =
  (* Syntax error: 'problem' without a name *)
  let bad_syntax = "problem\n end_problem\n" in
  (match Dsl.compile bad_syntax with
  | Ok _ -> failwith "expected syntax error for nameless problem"
  | Error _ -> ());

  (* Semantic: missing bounds for state variable *)
  let bad_bounds =
    "problem Bad\n\
    \ state:\n\
    \  x\n\
    \ control:\n\
    \  u\n\
    \ horizon: 1\n\
    \ dynamics:\n\
    \  x' = x\n\
    \ end_dynamics\n\
    \ initial:\n\
    \  x = 0\n\
    \ end_initial\n\
    \ cost:\n\
    \  running = x\n\
    \ terminal = x\n\
    \ end_cost\n\
    \ solve:\n\
    \  method = dynamic_programming\n\
    \  grid = [10]\n\
    \  controls = 10\n\
    \ end_solve\n\
    \ end_problem\n"
  in
  (match Dsl.compile bad_bounds with
  | Ok _ -> failwith "expected missing-bounds error"
  | Error _ -> ());

  (* Semantic: undefined variable referenced in dynamics *)
  let bad_undef =
    "problem Bad\n\
    \ state:\n\
    \  x\n\
    \ control:\n\
    \  u\n\
    \ bounds:\n\
    \  x in [0, 1]\n\
    \  u in [0, 1]\n\
    \ end_bounds\n\
    \ horizon: 1\n\
    \ dynamics:\n\
    \  x' = y\n\
    \ end_dynamics\n\
    \ initial:\n\
    \  x = 0\n\
    \ end_initial\n\
    \ cost:\n\
    \  running = x\n\
    \ terminal = x\n\
    \ end_cost\n\
    \ solve:\n\
    \  method = dynamic_programming\n\
    \  grid = [10]\n\
    \  controls = 10\n\
    \ end_solve\n\
    \ end_problem\n"
  in
  (match Dsl.compile bad_undef with
  | Ok _ -> failwith "expected undefined-variable error"
  | Error _ -> ());

  (* Semantic: horizon < 1 *)
  let bad_horizon =
    "problem Bad\n\
    \ state:\n\
    \  x\n\
    \ control:\n\
    \  u\n\
    \ bounds:\n\
    \  x in [0, 1]\n\
    \  u in [0, 1]\n\
    \ end_bounds\n\
    \ horizon: 0\n\
    \ dynamics:\n\
    \  x' = x\n\
    \ end_dynamics\n\
    \ initial:\n\
    \  x = 0\n\
    \ end_initial\n\
    \ cost:\n\
    \  running = x\n\
    \ terminal = x\n\
    \ end_cost\n\
    \ solve:\n\
    \  method = dynamic_programming\n\
    \  grid = [10]\n\
    \  controls = 10\n\
    \ end_solve\n\
    \ end_problem\n"
  in
  (match Dsl.compile bad_horizon with
  | Ok _ -> failwith "expected horizon error"
  | Error _ -> ());

  (* Semantic: 3 state variables (> 2) rejected *)
  let bad_state_count =
    "problem Bad\n\
    \ state:\n\
    \  x, y, z\n\
    \ control:\n\
    \  u\n\
    \ bounds:\n\
    \  x in [0, 1]\n\
    \  y in [0, 1]\n\
    \  z in [0, 1]\n\
    \  u in [0, 1]\n\
    \ end_bounds\n\
    \ horizon: 1\n\
    \ dynamics:\n\
    \  x' = x\n\
    \  y' = y\n\
    \  z' = z\n\
    \ end_dynamics\n\
    \ initial:\n\
    \  x = 0\n\
    \  y = 0\n\
    \  z = 0\n\
    \ end_initial\n\
    \ cost:\n\
    \  running = x\n\
    \ terminal = x\n\
    \ end_cost\n\
    \ solve:\n\
    \  method = dynamic_programming\n\
    \  grid = [10, 10, 10]\n\
    \  controls = 10\n\
    \ end_solve\n\
    \ end_problem\n"
  in
  match Dsl.compile bad_state_count with
  | Ok _ -> failwith "expected state-count error"
  | Error _ -> ()

let test_bridge_success () =
  let bridge_dsl =
    "problem DoubleIntegrator\n\n\
   state:\n\
   x, v\n\n\
   control:\n\
   u\n\n\
   parameter:\n\
   dt = 0.1\n\n\
   dynamics:\n\
   x' = x + dt * v\n\
   v' = v + dt * u\n\
   end_dynamics\n\n\
   initial:\n\
   x = 0\n\
   v = 0\n\
   end_initial\n\n\
   horizon: 20\n\n\
   bounds:\n\
   x in [-15, 15]\n\
   v in [-10, 10]\n\
   u in [-2, 2]\n\
   end_bounds\n\n\
   cost:\n\
   running = x^2 + v^2 + 0.1 * u^2\n\
   terminal = 10 * (x - 10)^2 + 10 * v^2\n\
   end_cost\n\n\
   solve:\n\
   method = dynamic_programming\n\
   grid = [100, 100]\n\
   controls = 41\n\
   end_solve\n\n\
   end_problem\n"
  in
  let json = Bridge.solve_from_dsl bridge_dsl in
  (* Parse the JSON back to verify structure *)
  let yj = from_string json in
  let status = jstring (jassoc "status" yj) in
  if status <> "ok" then failwith ("Bridge status: " ^ status);
  let pname = jstring (jassoc "problem_name" yj) in
  if pname <> "DoubleIntegrator" then
    failwith ("Bridge problem_name: " ^ pname);
  let result = jassoc "result" yj in
  let steps = jint (jassoc "steps" result) in
  if steps <> 20 then failwith (Printf.sprintf "steps=%d" steps);
  let time = jlist (jassoc "time" result) in
  if List.length time <> steps + 1 then
    failwith
      (Printf.sprintf "time length=%d expected=%d" (List.length time) (steps + 1));
  let states = jlist (jassoc "states" result) in
  if List.length states <> steps + 1 then
    failwith
      (Printf.sprintf "states length=%d expected=%d" (List.length states) (steps + 1));
  let controls = jlist (jassoc "controls" result) in
  if List.length controls <> steps then
    failwith
      (Printf.sprintf "controls length=%d expected=%d" (List.length controls) steps)

let test_bridge_parse_error () =
  (* Missing comma after state variable - syntax error *)
  let bad =
    "problem Bad\n state:\n  x v\n control:\n  u\n bounds:\n  x in [0, 1]\n  u in [0, 1]\n end_bounds\n horizon: 1\n dynamics:\n  x' = x\n end_dynamics\n initial:\n  x = 0\n end_initial\n cost:\n  running = x\n terminal = x\n end_cost\n solve:\n  method = dynamic_programming\n  grid = [10]\n  controls = 10\n end_solve\n end_problem\n"
  in
  let json = Bridge.solve_from_dsl bad in
  let yj = from_string json in
  let status = jstring (jassoc "status" yj) in
  if status <> "error" then failwith ("expected error status, got: " ^ status);
  let stage = jstring (jassoc "stage" yj) in
  if stage <> "parse" then
    failwith (Printf.sprintf "expected parse stage, got: %s" stage)

let test_bridge_semantic_error () =
  (* Missing bounds for state variable *)
  let bad =
    "problem Bad\n state:\n  x\n control:\n  u\n horizon: 1\n dynamics:\n  x' = x\n end_dynamics\n initial:\n  x = 0\n end_initial\n cost:\n  running = x\n terminal = x\n end_cost\n solve:\n  method = dynamic_programming\n  grid = [10]\n  controls = 10\n end_solve\n end_problem\n"
  in
  let json = Bridge.solve_from_dsl bad in
  let yj = from_string json in
  let status = jstring (jassoc "status" yj) in
  if status <> "error" then failwith ("expected error status, got: " ^ status);
  let stage = jstring (jassoc "stage" yj) in
  if stage <> "semantic" then
    failwith (Printf.sprintf "expected semantic stage, got: %s" stage)

(***********************************************************************)
(* Additional DSL tests                                                *)
(***********************************************************************)

let test_dsl_1d_problem () =
  (* 1D DSL problem end-to-end *)
  let dsl =
    {|
problem OneDim
  state: x
  control: u
  parameter: dt = 0.1
  dynamics:
    x' = x + dt * u
  end_dynamics
  initial:
    x = 0
  end_initial
  horizon: 30
  bounds:
    x in [-5, 10]
    u in [-3, 3]
  end_bounds
  cost:
    running = 0.1 * u^2
    terminal = (x - 3)^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [61]
    controls = 21
  end_solve
end_problem
|}
  in
  let cp =
    match Dsl.compile dsl with
    | Ok cp -> cp
    | Error err -> failwith ("1D DSL compile failed: " ^ Dsl.format_error err)
  in
  assert_approx "1D DSL initial state" 0.0 cp.initial_state.(0);
  let res =
    Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
      ~control_grid:cp.control_grid
  in
  let states, controls =
    Solver.rollout ~problem:cp.the_problem ~result:res
      ~state_grid:cp.state_grid ~initial_state:cp.initial_state
  in
  assert_true "1D DSL states count" (Array.length states = 31);
  assert_true "1D DSL controls count" (Array.length controls = 30);
  (* Should move toward target x = 3 *)
  assert_true "1D DSL moves toward target" (states.(30).(0) > 1.5);
  Array.iter
    (fun u ->
      assert_true "1D DSL control lower bound" (u.(0) >= -3.0);
      assert_true "1D DSL control upper bound" (u.(0) <= 3.0))
    controls

let test_dsl_comments () =
  (* DSL with # and // comments, including inline *)
  let dsl =
    {|
# Top-level hash comment
problem WithComments
  state: x  // inline comment on state
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * u  # inline hash comment
  end_dynamics
  initial:
    x = 0
  end_initial
  bounds:
    x in [-5, 5]
    u in [-1, 1]
  end_bounds
  cost:
    running = u^2
    terminal = x^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
// trailing slash comment
|}
  in
  match Dsl.compile dsl with
  | Ok _ -> ()
  | Error err -> failwith ("Comments test failed: " ^ Dsl.format_error err)

let test_dsl_missing_optional_sections () =
  (* DSL without target section *)
  let dsl_no_target =
    {|
problem NoTarget
  state: x
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * u
  end_dynamics
  initial:
    x = 1
  end_initial
  bounds:
    x in [-5, 5]
    u in [-1, 1]
  end_bounds
  cost:
    running = u^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp =
    match Dsl.compile dsl_no_target with
    | Ok cp -> cp
    | Error err -> failwith ("No-target DSL failed: " ^ Dsl.format_error err)
  in
  let res =
    Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
      ~control_grid:cp.control_grid
  in
  let states, _ =
    Solver.rollout ~problem:cp.the_problem ~result:res
      ~state_grid:cp.state_grid ~initial_state:cp.initial_state
  in
  assert_true "No-target runs" (Array.length states = 6);
  (* DSL without running_cost (defaults to 0) *)
  let dsl_no_running =
    {|
problem NoRunning
  state: x
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * u
  end_dynamics
  initial:
    x = 1
  end_initial
  bounds:
    x in [-5, 5]
    u in [-1, 1]
  end_bounds
  cost:
    terminal = x^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp2 =
    match Dsl.compile dsl_no_running with
    | Ok cp -> cp
    | Error err ->
        failwith ("No-running DSL failed: " ^ Dsl.format_error err)
  in
  let res2 =
    Solver.solve ~problem:cp2.the_problem ~state_grid:cp2.state_grid
      ~control_grid:cp2.control_grid
  in
  (* Running cost should be 0 everywhere *)
  assert_approx "No-running cost is 0" 0.0
    (cp2.the_problem.running_cost [| 1.0 |] [| 0.5 |]);
  ignore res2;
  (* DSL without terminal_cost (defaults to 0) *)
  let dsl_no_terminal =
    {|
problem NoTerminal
  state: x
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * u
  end_dynamics
  initial:
    x = 1
  end_initial
  bounds:
    x in [-5, 5]
    u in [-1, 1]
  end_bounds
  cost:
    running = u^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp3 =
    match Dsl.compile dsl_no_terminal with
    | Ok cp -> cp
    | Error err ->
        failwith ("No-terminal DSL failed: " ^ Dsl.format_error err)
  in
  assert_approx "No-terminal cost is 0" 0.0
    (cp3.the_problem.terminal_cost [| 42.0 |])

let test_dsl_negative_bounds () =
  (* DSL with fully negative bounds *)
  let dsl =
    {|
problem NegBounds
  state: x
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * u
  end_dynamics
  initial:
    x = -2
  end_initial
  bounds:
    x in [-10, -1]
    u in [-3, -1]
  end_bounds
  cost:
    running = u^2
    terminal = (x + 5)^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp =
    match Dsl.compile dsl with
    | Ok cp -> cp
    | Error err -> failwith ("Neg bounds DSL failed: " ^ Dsl.format_error err)
  in
  assert_approx "Neg bounds initial" (-2.0) cp.initial_state.(0);
  let res =
    Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
      ~control_grid:cp.control_grid
  in
  let _, controls =
    Solver.rollout ~problem:cp.the_problem ~result:res
      ~state_grid:cp.state_grid ~initial_state:cp.initial_state
  in
  (* All controls should be in [-3, -1] *)
  Array.iter
    (fun u ->
      assert_true "Neg bounds control lower" (u.(0) >= -3.0);
      assert_true "Neg bounds control upper" (u.(0) <= -1.0))
    controls

let test_dsl_parameter_expressions () =
  (* Parameters used in dynamics, initial, and cost expressions *)
  let dsl =
    {|
problem ParamExpr
  state: x
  control: u
  parameter:
    a = 2.0
    b = 0.5
    c = 3.0
  horizon: 5
  dynamics:
    x' = a * x + b * u
  end_dynamics
  initial:
    x = c
  end_initial
  bounds:
    x in [-10, 10]
    u in [-5, 5]
  end_bounds
  cost:
    running = a * u^2
    terminal = b * x^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp =
    match Dsl.compile dsl with
    | Ok cp -> cp
    | Error err ->
        failwith ("Param expr DSL failed: " ^ Dsl.format_error err)
  in
  assert_approx "Param initial" 3.0 cp.initial_state.(0);
  (* Verify dynamics uses parameters: x' = 2*x + 0.5*u *)
  let x_next = cp.the_problem.dynamics [| 1.0 |] [| 2.0 |] in
  assert_approx "Param dynamics" (2.0 *. 1.0 +. 0.5 *. 2.0) x_next.(0);
  (* Verify running cost uses parameter: a * u^2 = 2 * 4 = 8 *)
  assert_approx "Param running cost" 8.0
    (cp.the_problem.running_cost [| 0.0 |] [| 2.0 |]);
  (* Verify terminal cost uses parameter: b * x^2 = 0.5 * 9 = 4.5 *)
  assert_approx "Param terminal cost" 4.5
    (cp.the_problem.terminal_cost [| 3.0 |])

let string_contains sub s =
  let n = String.length sub and m = String.length s in
  if n > m then false
  else
    let rec loop i =
      if i > m - n then false
      else if String.sub s i n = sub then true
      else loop (i + 1)
    in
    loop 0

let test_error_formatting () =
  (* Parse error: 'problem' without a name *)
  let dsl_bad = "problem\n end_problem\n" in
  (match Dsl.compile dsl_bad with
  | Ok _ -> failwith "expected parse error"
  | Error err ->
      let msg = Dsl.format_error err in
      assert_true "parse error non-empty" (String.length msg > 0);
      assert_true "parse error mentions line" (string_contains "line" msg));
  (* Semantic error: undefined variable *)
  let dsl_undef =
    {|
problem Bad
  state: x
  control: u
  horizon: 1
  dynamics:
    x' = y
  end_dynamics
  initial:
    x = 0
  end_initial
  bounds:
    x in [0, 1]
    u in [0, 1]
  end_bounds
  cost:
    running = x
    terminal = x
  end_cost
  solve:
    method = dynamic_programming
    grid = [10]
    controls = 10
  end_solve
end_problem
|}
  in
  match Dsl.compile dsl_undef with
  | Ok _ -> failwith "expected semantic error"
  | Error err ->
      let msg = Dsl.format_error err in
      assert_true "undef error mentions variable 'y'" (string_contains "y" msg);
      assert_true "undef error mentions 'undefined'"
        (string_contains "undefined" msg)

let test_dsl_power_operator () =
  (* Explicit test for the ^ operator with various exponents *)
  let dsl =
    {|
problem PowerTest
  state: x
  control: u
  horizon: 3
  dynamics:
    x' = x + 0.1 * u^3
  end_dynamics
  initial:
    x = 1
  end_initial
  bounds:
    x in [-5, 5]
    u in [-2, 2]
  end_bounds
  cost:
    running = u^4
    terminal = (x - 2)^2
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem
|}
  in
  let cp =
    match Dsl.compile dsl with
    | Ok cp -> cp
    | Error err -> failwith ("Power DSL failed: " ^ Dsl.format_error err)
  in
  (* u^3 with u = 2 should be 8 *)
  let x_next = cp.the_problem.dynamics [| 0.0 |] [| 2.0 |] in
  assert_approx "Power u^3" (0.0 +. 0.1 *. 8.0) x_next.(0);
  (* u^4 with u = 2 should be 16 *)
  assert_approx "Power u^4" 16.0 (cp.the_problem.running_cost [| 0.0 |] [| 2.0 |]);
  ignore (Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
            ~control_grid:cp.control_grid)

let () =
  test_grid_1d ();
  test_grid_2d ();
  test_problem_and_solver ();
  test_double_integrator_target_trend ();
  test_dsl_double_integrator_match ();
  test_dsl_invalid_inputs ();
  test_dsl_1d_problem ();
  test_dsl_comments ();
  test_dsl_missing_optional_sections ();
  test_dsl_negative_bounds ();
  test_dsl_parameter_expressions ();
  test_error_formatting ();
  test_dsl_power_operator ();
  print_endline "all tests passed"
