(* lib/problem.ml - Finite-horizon deterministic optimal control problem. *)

type state = float array
type control = float array
type dynamics = state -> control -> state
type running_cost = state -> control -> float
type terminal_cost = state -> float

type t = {
  horizon : int;
  dynamics : dynamics;
  running_cost : running_cost;
  terminal_cost : terminal_cost;
}

let make ~horizon ~dynamics ~running_cost ~terminal_cost =
  if horizon < 1 then invalid_arg "Problem.make: horizon must be >= 1";
  { horizon; dynamics; running_cost; terminal_cost }

let double_integrator_dynamics ~dt =
  if (not (Float.is_finite dt)) || dt <= 0.0 then
    invalid_arg
      "Problem.double_integrator_dynamics: dt must be a positive finite float";
  fun x u ->
    if Array.length x < 2 then
      invalid_arg
        "double_integrator_dynamics: state vector must have length >= 2";
    if Array.length u < 1 then
      invalid_arg
        "double_integrator_dynamics: control vector must have length >= 1";
    let x_pos = x.(0) in
    let v_pos = x.(1) in
    let u_val = u.(0) in
    let x_next = x_pos +. (dt *. v_pos) in
    let v_next = v_pos +. (dt *. u_val) in
    [| x_next; v_next |]
