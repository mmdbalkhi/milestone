(* lib/solver.ml - Backward dynamic programming solver (Rule 01). *)

open Problem

type state_grid = G1 of Grid.t1 | G2 of Grid.t2
type result = { values : float array array; policy : float array array }

let state_dim = function G1 _ -> 1 | G2 _ -> 2

let state_count = function
  | G1 g -> Grid.count1 g
  | G2 g ->
      let nx, ny = Grid.count2 g in
      nx * ny

let check_state_dim sg x msg =
  let expected = state_dim sg in
  if Array.length x <> expected then
    invalid_arg
      (msg ^ ": expected state vector of length " ^ string_of_int expected
     ^ ", got "
      ^ string_of_int (Array.length x))

let state_node sg i =
  match sg with
  | G1 g -> [| Grid.node1 g i |]
  | G2 g ->
      let _, ny = Grid.count2 g in
      let ii = i / ny and j = i mod ny in
      let x, y = Grid.node2 g ii j in
      [| x; y |]

let nearest_state_node sg x =
  match sg with
  | G1 g -> Grid.nearest1 g x.(0)
  | G2 g ->
      let _, ny = Grid.count2 g in
      let i, j = Grid.nearest2 g x.(0) x.(1) in
      (i * ny) + j

let interp_value sg v x =
  match sg with
  | G1 g -> Grid.interp1 g v x.(0)
  | G2 g -> Grid.interp2 g v x.(0) x.(1)

let solve ~problem ~state_grid ~control_grid =
  let nsteps = problem.horizon in
  let n = state_count state_grid in
  let m = Grid.count1 control_grid in
  let values = Array.init (nsteps + 1) (fun _ -> Array.make n 0.0) in
  let policy = Array.init nsteps (fun _ -> Array.make n 0.0) in

  (* Pre-allocate reusable buffers *)
  let state_dim = state_dim state_grid in
  let x_buf = Array.make state_dim 0.0 in
  let u_buf = [| 0.0 |] in

  (* Terminal: V_N(x_i) = g(x_i) *)
  for i = 0 to n - 1 do
    (* Fill x_buf with state node coordinates *)
    (match state_grid with
    | G1 g -> x_buf.(0) <- Grid.node1 g i
    | G2 g ->
        let _, ny = Grid.count2 g in
        let ii = i / ny and j = i mod ny in
        let x, y = Grid.node2 g ii j in
        x_buf.(0) <- x;
        x_buf.(1) <- y);
    values.(nsteps).(i) <- problem.terminal_cost x_buf
  done;

  let best_at x vtab =
    let best = ref infinity in
    let best_u = ref (Grid.node1 control_grid 0) in
    for cm = 0 to m - 1 do
      let u_val = Grid.node1 control_grid cm in
      u_buf.(0) <- u_val;
      let x_next = problem.dynamics x u_buf in
      let v =
        problem.running_cost x u_buf +. interp_value state_grid vtab x_next
      in
      if v < !best then begin
        best := v;
        best_u := u_val
      end
    done;
    (!best, !best_u)
  in

  (* Backward pass: k = N-1 downto 0 *)
  for k = nsteps - 1 downto 0 do
    for i = 0 to n - 1 do
      (* Fill x_buf with state node coordinates *)
      (match state_grid with
      | G1 g -> x_buf.(0) <- Grid.node1 g i
      | G2 g ->
          let _, ny = Grid.count2 g in
          let ii = i / ny and j = i mod ny in
          let x, y = Grid.node2 g ii j in
          x_buf.(0) <- x;
          x_buf.(1) <- y);
      let b, bu = best_at x_buf values.(k + 1) in
      values.(k).(i) <- b;
      policy.(k).(i) <- bu
    done
  done;
  { values; policy }

let rollout ~problem ~result ~state_grid ~initial_state =
  check_state_dim state_grid initial_state "Solver.rollout";
  let nsteps = problem.horizon in
  let policy = result.policy in
  let states = Array.make (nsteps + 1) initial_state in
  let controls = Array.make nsteps [| 0.0 |] in
  let x = ref initial_state in
  states.(0) <- !x;
  for k = 0 to nsteps - 1 do
    let i = nearest_state_node state_grid !x in
    let u_val = policy.(k).(i) in
    let u = [| u_val |] in
    controls.(k) <- u;
    x := problem.dynamics !x u;
    states.(k + 1) <- !x
  done;
  (states, controls)
