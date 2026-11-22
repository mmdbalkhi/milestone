(* lib/problem.mli - Finite-horizon deterministic optimal control problem.

       min  sum_{k=0}^{N-1} L(x_k, u_k) + g(x_N)
       s.t. x_{k+1} = f(x_k, u_k),  k = 0 .. N-1

   State and control are flat float arrays; state dimension <= 2 for v1.0.
   Internal record fields are the public interface. *)

type state = float array
type control = float array
type dynamics = state -> control -> state
type running_cost = state -> control -> float
type terminal_cost = state -> float

type t = {
  horizon : int; (* N >= 1 *)
  dynamics : dynamics; (* f: x_{k+1} = f(x_k, u_k) *)
  running_cost : running_cost; (* L(x_k, u_k) *)
  terminal_cost : terminal_cost; (* g(x_N) *)
}

val make :
  horizon:int ->
  dynamics:dynamics ->
  running_cost:running_cost ->
  terminal_cost:terminal_cost ->
  t

(* Double integrator dynamics:
     state  = [| x; v |]
     control = [| u |]
     x_{k+1} = x_k + dt * v_k
     v_{k+1} = v_k + dt * u_k *)
val double_integrator_dynamics : dt:float -> dynamics
