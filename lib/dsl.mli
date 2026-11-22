(* lib/dsl.mli - DSL to core compiler interface.

   Parses the `problem ... end_problem` DSL source, validates it
   semantically, and compiles it into a runnable problem bundle containing
   a `Problem.t`, grids, and initial state.  All errors are reported via
   the structured [error] type; no exceptions escape [compile]. *)

type error =
  | Lex_error of { line : int; col : int; message : string }
  | Parse_error of { line : int; col : int; message : string }
  | Semantic_error of string

val format_error : error -> string

type compiled_problem = {
  name : string;
  the_problem : Problem.t;
  state_grid : Solver.state_grid;
  control_grid : Grid.t1;
  initial_state : float array;
  dt : float;
}

val compile : string -> (compiled_problem, error) result
