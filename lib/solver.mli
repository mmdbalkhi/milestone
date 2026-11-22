(* lib/solver.mli - Backward dynamic programming solver (Rule 01).

       min  sum_{k=0}^{N-1} L(x_k, u_k) + g(x_N)
       s.t. x_{k+1} = f(x_k, u_k)

   `solve` runs the backward pass and returns value tables and the
   argmin policy. `rollout` executes the policy forward from an exact
   initial state using nearest-grid-point policy queries. *)

type state_grid =
  | G1 of Grid.t1 (* 1D state *)
  | G2 of Grid.t2 (* 2D state, row-major *)

type result = {
  values : float array array; (* values.(k) over state nodes, k = 0..N *)
  policy : float array array; (* policy.(k) over state nodes, k = 0..N-1 *)
}

val solve :
  problem:Problem.t -> state_grid:state_grid -> control_grid:Grid.t1 -> result

val rollout :
  problem:Problem.t ->
  result:result ->
  state_grid:state_grid ->
  initial_state:Problem.state ->
  Problem.state array * Problem.control array
