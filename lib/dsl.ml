(* lib/dsl.ml - Hand-written lexer, recursive-descent parser, and compiler
   for the control-lab DSL.  No external dependencies (no ocamllex/menhir).

   All errors are reported via the structured [error] type; no uncaught
   exceptions escape [compile].  The lexer and parser are reentrant: all
   mutable state is threaded through explicit state records. *)

(***********************************************************************)
(* Errors                                                              *)
(***********************************************************************)

type error =
  | Lex_error of { line : int; col : int; message : string }
  | Parse_error of { line : int; col : int; message : string }
  | Semantic_error of string

exception Lex_fail of int * int * string
exception Parse_fail of int * int * string
exception Semantic_fail of string

let lex_fail line col msg = raise (Lex_fail (line, col, msg))
let parse_fail line col msg = raise (Parse_fail (line, col, msg))
let semantic_fail msg = raise (Semantic_fail msg)

type compiled_problem = {
  name : string;
  the_problem : Problem.t;
  state_grid : Solver.state_grid;
  control_grid : Grid.t1;
  initial_state : float array;
  dt : float;
}

type compiled_expr = float array -> float

let format_error = function
  | Lex_error { line; col; message } ->
      Printf.sprintf "lex error at line %d col %d: %s" line col message
  | Parse_error { line; col; message } ->
      Printf.sprintf "parse error at line %d col %d: %s" line col message
  | Semantic_error message -> Printf.sprintf "semantic error: %s" message

(***********************************************************************)
(* Tokens                                                              *)
(***********************************************************************)

type token_kind =
  | KW of string
  | COLON
  | COMMA
  | LBRACKET
  | RBRACKET
  | LPAREN
  | RPAREN
  | PLUS
  | MINUS
  | STAR
  | SLASH
  | CARET
  | EQ
  | PRIME
  | IDENT of string
  | FLOAT of float
  | INT of int
  | EOF

type token = { kind : token_kind; line : int; col : int }

let pp_kind = function
  | KW s -> s
  | COLON -> ":"
  | COMMA -> ","
  | LBRACKET -> "["
  | RBRACKET -> "]"
  | LPAREN -> "("
  | RPAREN -> ")"
  | PLUS -> "+"
  | MINUS -> "-"
  | STAR -> "*"
  | SLASH -> "/"
  | CARET -> "^"
  | EQ -> "="
  | PRIME -> "'"
  | IDENT s -> Printf.sprintf "\"%s\"" s
  | FLOAT f -> Printf.sprintf "%g" f
  | INT i -> Printf.sprintf "%d" i
  | EOF -> "end of input"

(***********************************************************************)
(* Lexer                                                               *)
(***********************************************************************)

type lexer_state = {
  mutable str : string;
  mutable pos : int;
  mutable line : int;
  mutable col : int;
}

let make_lexer_state s = { str = s; pos = 0; line = 1; col = 1 }

let peek st =
  let p = st.pos in
  if p < String.length st.str then st.str.[p] else '\000'

let peek2 st =
  let p = st.pos in
  if p + 1 < String.length st.str then st.str.[p + 1] else '\000'

let next st =
  let c = peek st in
  st.pos <- st.pos + 1;
  (match c with
  | '\n' ->
      st.line <- st.line + 1;
      st.col <- 1
  | _ -> st.col <- st.col + 1);
  c

let cur_pos st = (st.line, st.col)

let skip_ws_comments st =
  let rec loop () =
    match peek st with
    | '\000' -> ()
    | ' ' | '\t' | '\n' | '\r' ->
        ignore (next st);
        loop ()
    | '#' ->
        ignore (next st);
        let rec skip_to_eol () =
          match peek st with
          | '\000' | '\n' -> ()
          | '\r' -> ignore (next st)
          | _ ->
              ignore (next st);
              skip_to_eol ()
        in
        skip_to_eol ();
        loop ()
    | '/' when peek2 st = '/' ->
        ignore (next st);
        ignore (next st);
        let rec skip_line_comment () =
          match peek st with
          | '\000' | '\n' -> ()
          | '\r' -> ignore (next st)
          | _ ->
              ignore (next st);
              skip_line_comment ()
        in
        skip_line_comment ();
        loop ()
    | _ -> ()
  in
  loop ()

let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_alphanum c = is_alpha c || (c >= '0' && c <= '9')
let is_digit c = c >= '0' && c <= '9'

let keyword_of_string = function
  | "problem" -> Some (KW "problem")
  | "end_problem" -> Some (KW "end_problem")
  | "state" -> Some (KW "state")
  | "control" -> Some (KW "control")
  | "parameter" -> Some (KW "parameter")
  | "horizon" -> Some (KW "horizon")
  | "dynamics" -> Some (KW "dynamics")
  | "end_dynamics" -> Some (KW "end_dynamics")
  | "initial" -> Some (KW "initial")
  | "end_initial" -> Some (KW "end_initial")
  | "target" -> Some (KW "target")
  | "end_target" -> Some (KW "end_target")
  | "bounds" -> Some (KW "bounds")
  | "end_bounds" -> Some (KW "end_bounds")
  | "cost" -> Some (KW "cost")
  | "end_cost" -> Some (KW "end_cost")
  | "solve" -> Some (KW "solve")
  | "end_solve" -> Some (KW "end_solve")
  | "method" -> Some (KW "method")
  | "grid" -> Some (KW "grid")
  | "controls" -> Some (KW "controls")
  | "in" -> Some (KW "in")
  | _ -> None

let read_ident_or_keyword st =
  let line, col = cur_pos st in
  let buf = Buffer.create 16 in
  let rec loop () =
    match peek st with
    | c when is_alphanum c ->
        ignore (next st);
        Buffer.add_char buf c;
        loop ()
    | _ -> ()
  in
  loop ();
  let name = Buffer.contents buf in
  match keyword_of_string name with
  | Some kind -> { kind; line; col }
  | None -> { kind = IDENT name; line; col }

let read_number st =
  let line, col = cur_pos st in
  let buf = Buffer.create 16 in
  let rec loop_digits () =
    match peek st with
    | c when is_digit c ->
        ignore (next st);
        Buffer.add_char buf c;
        loop_digits ()
    | _ -> ()
  in
  loop_digits ();
  let int_part = Buffer.contents buf in
  if peek st = '.' && is_digit (peek2 st) then begin
    ignore (next st);
    Buffer.add_char buf '.';
    loop_digits ();
    let s = Buffer.contents buf in
    match float_of_string_opt s with
    | Some f -> { kind = FLOAT f; line; col }
    | None -> lex_fail line col (Printf.sprintf "invalid float literal: %s" s)
  end
  else
    match int_of_string_opt int_part with
    | Some i -> { kind = INT i; line; col }
    | None ->
        lex_fail line col
          (Printf.sprintf "invalid integer literal: %s" int_part)

let rec lex_one st =
  skip_ws_comments st;
  let line, col = cur_pos st in
  match peek st with
  | '\000' -> { kind = EOF; line; col }
  | ':' ->
      ignore (next st);
      { kind = COLON; line; col }
  | ',' ->
      ignore (next st);
      { kind = COMMA; line; col }
  | '[' ->
      ignore (next st);
      { kind = LBRACKET; line; col }
  | ']' ->
      ignore (next st);
      { kind = RBRACKET; line; col }
  | '(' ->
      ignore (next st);
      { kind = LPAREN; line; col }
  | ')' ->
      ignore (next st);
      { kind = RPAREN; line; col }
  | '+' ->
      ignore (next st);
      { kind = PLUS; line; col }
  | '-' ->
      ignore (next st);
      { kind = MINUS; line; col }
  | '*' ->
      ignore (next st);
      { kind = STAR; line; col }
  | '/' ->
      ignore (next st);
      { kind = SLASH; line; col }
  | '^' ->
      ignore (next st);
      { kind = CARET; line; col }
  | '=' ->
      ignore (next st);
      { kind = EQ; line; col }
  | '\'' ->
      ignore (next st);
      { kind = PRIME; line; col }
  | c when is_alpha c -> read_ident_or_keyword st
  | c when is_digit c -> read_number st
  | c -> lex_fail line col (Printf.sprintf "unexpected character %c" c)

let lex_all s =
  let st = make_lexer_state s in
  let rec loop acc =
    match lex_one st with
    | { kind = EOF } as t -> List.rev (t :: acc)
    | t -> loop (t :: acc)
  in
  loop []

(***********************************************************************)
(* AST                                                                 *)
(***********************************************************************)

type binop = Add | Sub | Mul | Div

type expr =
  | EFloat of float
  | EInt of int
  | EIdent of string
  | ENeg of expr
  | EBin of expr * binop * expr
  | EPow of expr * expr

type dynamics_eq = { var : string; expr : expr }
type initial_eq = dynamics_eq
type bound = { var : string; lo : float; hi : float }

type ast = {
  name : string;
  state : string list;
  control : string list;
  parameters : (string * expr) list;
  dynamics : dynamics_eq list;
  initial : initial_eq list;
  target : initial_eq list option;
  horizon : int option;
  bounds : bound list;
  running_cost : expr option;
  terminal_cost : expr option;
  solve_method : string option;
  solve_grid : int list option;
  solve_controls : int option;
}

(***********************************************************************)
(* Parser                                                              *)
(***********************************************************************)
let assoc_opt key lst = try Some (List.assoc key lst) with Not_found -> None

type parser_state = { toks : token array; mutable pos : int }

let make_parser_state toks = { toks = Array.of_list toks; pos = 0 }
let curr st = st.toks.(st.pos)
let advance st = st.pos <- st.pos + 1

let require_kind st k =
  match curr st with
  | { kind = k' } when k' = k -> advance st
  | { kind = k'; line; col } ->
      parse_fail line col
        (Printf.sprintf "expected %s, got %s" (pp_kind k) (pp_kind k'))

let require_ident st =
  match curr st with
  | { kind = IDENT name } ->
      advance st;
      name
  | { kind = KW k; line; col } ->
      parse_fail line col
        (Printf.sprintf "expected identifier, got keyword %s" k)
  | { kind = k; line; col } ->
      parse_fail line col
        (Printf.sprintf "expected identifier, got %s" (pp_kind k))

let require_number st =
  match curr st with
  | { kind = FLOAT f } ->
      advance st;
      f
  | { kind = INT i } ->
      advance st;
      float_of_int i
  | { kind = k; line; col } ->
      parse_fail line col (Printf.sprintf "expected number, got %s" (pp_kind k))

(* Expression parsing with precedence (lowest to highest):
     add_sub := mul_div (('+' | '-') mul_div)*        left-assoc
     mul_div := unary (('*' | '/') unary)*             left-assoc
     unary   := '-' unary | power
     power   := primary ('^' power)?                   right-assoc
     primary := FLOAT | INT | IDENT | '(' expr ')' *)

let rec parse_expr st = parse_add_sub st

and parse_add_sub st =
  let left = parse_mul_div st in
  let rec loop acc =
    match curr st with
    | { kind = PLUS } ->
        advance st;
        loop (EBin (acc, Add, parse_mul_div st))
    | { kind = MINUS } ->
        advance st;
        loop (EBin (acc, Sub, parse_mul_div st))
    | _ -> acc
  in
  loop left

and parse_mul_div st =
  let left = parse_unary st in
  let rec loop acc =
    match curr st with
    | { kind = STAR } ->
        advance st;
        loop (EBin (acc, Mul, parse_unary st))
    | { kind = SLASH } ->
        advance st;
        loop (EBin (acc, Div, parse_unary st))
    | _ -> acc
  in
  loop left

and parse_unary st =
  match curr st with
  | { kind = MINUS } ->
      advance st;
      ENeg (parse_unary st)
  | _ -> parse_power st

and parse_power st =
  let base = parse_primary st in
  match curr st with
  | { kind = CARET } ->
      advance st;
      EPow (base, parse_power st)
  | _ -> base

and parse_primary st =
  match curr st with
  | { kind = FLOAT f } ->
      advance st;
      EFloat f
  | { kind = INT i } ->
      advance st;
      EInt i
  | { kind = IDENT name } ->
      advance st;
      EIdent name
  | { kind = LPAREN } ->
      advance st;
      let e = parse_expr st in
      require_kind st RPAREN;
      e
  | { kind = k; line; col } ->
      parse_fail line col
        (Printf.sprintf "expected expression, got %s" (pp_kind k))

let is_section_keyword = function
  | "state" | "control" | "parameter" | "horizon" | "dynamics" | "initial"
  | "target" | "bounds" | "cost" | "solve" | "end_problem" ->
      true
  | _ -> false

let parse_ident_list_until_section_start st =
  let rec loop acc =
    match curr st with
    | { kind = IDENT name } when not (is_section_keyword name) -> (
        advance st;
        match curr st with
        | { kind = COMMA } ->
            advance st;
            loop (name :: acc)
        | _ -> List.rev (name :: acc))
    | _ -> List.rev acc
  in
  loop []

let parse_state_section st =
  require_kind st (KW "state");
  require_kind st COLON;
  parse_ident_list_until_section_start st

let parse_control_section st =
  require_kind st (KW "control");
  require_kind st COLON;
  parse_ident_list_until_section_start st

let parse_parameter_section st =
  require_kind st (KW "parameter");
  require_kind st COLON;
  let rec loop acc =
    match curr st with
    | { kind = IDENT name } when not (is_section_keyword name) ->
        advance st;
        require_kind st EQ;
        let e = parse_expr st in
        loop ((name, e) :: acc)
    | _ -> List.rev acc
  in
  loop []

let parse_horizon_section st =
  require_kind st (KW "horizon");
  require_kind st COLON;
  match curr st with
  | { kind = INT i } ->
      advance st;
      i
  | { kind = k; line; col } ->
      parse_fail line col
        (Printf.sprintf "expected integer horizon, got %s" (pp_kind k))

(* Shared parser for `initial`, `target`, and `dynamics` sections.
   When [require_prime] is true, each left-hand side must be followed
   by a PRIME token (used for dynamics equations like `x' = ...`). *)
let parse_assignment_section st ~keyword ~end_keyword ~label ~require_prime =
  require_kind st (KW keyword);
  require_kind st COLON;
  let rec loop acc =
    match curr st with
    | { kind = KW k } when k = end_keyword ->
        advance st;
        List.rev acc
    | { kind = IDENT _ } ->
        let name = require_ident st in
        if require_prime then
          begin match curr st with
          | { kind = PRIME } -> advance st
          | { kind = k; line; col } ->
              parse_fail line col
                (Printf.sprintf "expected '' after state variable '%s', got %s"
                   name (pp_kind k))
          end;
        require_kind st EQ;
        let e = parse_expr st in
        loop ({ var = name; expr = e } :: acc)
    | { kind = k; line; col } ->
        parse_fail line col
          (Printf.sprintf "expected %s assignment or %s, got %s" label
             end_keyword (pp_kind k))
  in
  loop []

let parse_dynamics_section st =
  parse_assignment_section st ~keyword:"dynamics" ~end_keyword:"end_dynamics"
    ~label:"dynamics equation" ~require_prime:true

let parse_initial_section st =
  parse_assignment_section st ~keyword:"initial" ~end_keyword:"end_initial"
    ~label:"initial" ~require_prime:false

let parse_target_section st =
  parse_assignment_section st ~keyword:"target" ~end_keyword:"end_target"
    ~label:"target" ~require_prime:false

let read_bound_number st =
  match curr st with
  | { kind = MINUS } ->
      advance st;
      -.require_number st
  | _ -> require_number st

let parse_bounds_section st =
  require_kind st (KW "bounds");
  require_kind st COLON;
  let rec loop acc =
    match curr st with
    | { kind = KW "end_bounds" } ->
        advance st;
        List.rev acc
    | { kind = IDENT _ } ->
        let name = require_ident st in
        require_kind st (KW "in");
        require_kind st LBRACKET;
        let lo = read_bound_number st in
        require_kind st COMMA;
        let hi = read_bound_number st in
        require_kind st RBRACKET;
        loop ({ var = name; lo; hi } :: acc)
    | { kind = k; line; col } ->
        parse_fail line col
          (Printf.sprintf "expected bound declaration or end_bounds, got %s"
             (pp_kind k))
  in
  loop []

let parse_cost_section st =
  require_kind st (KW "cost");
  require_kind st COLON;
  let running = ref None in
  let terminal = ref None in
  let rec loop () =
    match curr st with
    | { kind = KW "end_cost" } -> advance st
    | { kind = IDENT "running" } ->
        advance st;
        require_kind st EQ;
        running := Some (parse_expr st);
        loop ()
    | { kind = IDENT "terminal" } ->
        advance st;
        require_kind st EQ;
        terminal := Some (parse_expr st);
        loop ()
    | { kind = k; line; col } ->
        parse_fail line col
          (Printf.sprintf "expected cost assignment or end_cost, got %s"
             (pp_kind k))
  in
  loop ();
  (!running, !terminal)

let parse_solve_section st =
  require_kind st (KW "solve");
  require_kind st COLON;
  let solv_method = ref None in
  let grid = ref None in
  let controls = ref None in
  let rec loop () =
    match curr st with
    | { kind = KW "end_solve" } -> advance st
    | { kind = KW "method" } -> (
        advance st;
        require_kind st EQ;
        match curr st with
        | { kind = IDENT m } ->
            advance st;
            solv_method := Some m;
            loop ()
        | { kind = k; line; col } ->
            parse_fail line col
              (Printf.sprintf "expected method identifier, got %s" (pp_kind k)))
    | { kind = KW "grid" } ->
        advance st;
        require_kind st EQ;
        require_kind st LBRACKET;
        let rec parse_grid_list acc =
          match curr st with
          | { kind = INT i } -> (
              advance st;
              match curr st with
              | { kind = COMMA } ->
                  advance st;
                  parse_grid_list (i :: acc)
              | { kind = RBRACKET } ->
                  advance st;
                  List.rev (i :: acc)
              | { kind = k; line; col } ->
                  parse_fail line col
                    (Printf.sprintf "expected ',' or ']' in grid, got %s"
                       (pp_kind k)))
          | { kind = RBRACKET } ->
              advance st;
              List.rev acc
          | { kind = k; line; col } ->
              parse_fail line col
                (Printf.sprintf "expected integer in grid, got %s" (pp_kind k))
        in
        let g = parse_grid_list [] in
        grid := Some g;
        loop ()
    | { kind = KW "controls" } -> (
        advance st;
        require_kind st EQ;
        match curr st with
        | { kind = INT i } ->
            advance st;
            controls := Some i;
            loop ()
        | { kind = k; line; col } ->
            parse_fail line col
              (Printf.sprintf "expected integer controls, got %s" (pp_kind k)))
    | { kind = k; line; col } ->
        parse_fail line col
          (Printf.sprintf "expected solve setting or end_solve, got %s"
             (pp_kind k))
  in
  loop ();
  (!solv_method, !grid, !controls)

let parse_program st =
  require_kind st (KW "problem");
  let name = require_ident st in
  let state_r = ref [] in
  let control_r = ref [] in
  let params_r = ref [] in
  let dynamics_r = ref [] in
  let initial_r = ref [] in
  let target_r = ref None in
  let horizon_r = ref None in
  let bounds_r = ref [] in
  let running_r = ref None in
  let terminal_r = ref None in
  let method_r = ref None in
  let grid_r = ref None in
  let controls_r = ref None in
  let rec loop () =
    match curr st with
    | { kind = KW "end_problem" } -> advance st
    | { kind = KW "state" } ->
        state_r := parse_state_section st;
        loop ()
    | { kind = KW "control" } ->
        control_r := parse_control_section st;
        loop ()
    | { kind = KW "parameter" } ->
        params_r := parse_parameter_section st;
        loop ()
    | { kind = KW "horizon" } ->
        horizon_r := Some (parse_horizon_section st);
        loop ()
    | { kind = KW "dynamics" } ->
        dynamics_r := parse_dynamics_section st;
        loop ()
    | { kind = KW "initial" } ->
        initial_r := parse_initial_section st;
        loop ()
    | { kind = KW "target" } ->
        target_r := Some (parse_target_section st);
        loop ()
    | { kind = KW "bounds" } ->
        bounds_r := parse_bounds_section st;
        loop ()
    | { kind = KW "cost" } ->
        let run, term = parse_cost_section st in
        running_r := run;
        terminal_r := term;
        loop ()
    | { kind = KW "solve" } ->
        let m, g, c = parse_solve_section st in
        method_r := m;
        grid_r := g;
        controls_r := c;
        loop ()
    | { kind = k; line; col } ->
        parse_fail line col (Printf.sprintf "unexpected section %s" (pp_kind k))
  in
  loop ();
  {
    name;
    state = !state_r;
    control = !control_r;
    parameters = !params_r;
    dynamics = !dynamics_r;
    initial = !initial_r;
    target = !target_r;
    horizon = !horizon_r;
    bounds = !bounds_r;
    running_cost = !running_r;
    terminal_cost = !terminal_r;
    solve_method = !method_r;
    solve_grid = !grid_r;
    solve_controls = !controls_r;
  }

(***********************************************************************)
(* Expression evaluator                                                *)
(***********************************************************************)

(* Collect identifiers referenced by an expression, using an accumulator
   to avoid the quadratic cost of list concatenation. *)
let expr_idents e =
  let rec aux acc = function
    | EFloat _ | EInt _ -> acc
    | EIdent name -> name :: acc
    | ENeg e -> aux acc e
    | EBin (e1, _, e2) -> aux (aux acc e1) e2
    | EPow (e1, e2) -> aux (aux acc e1) e2
  in
  aux [] e

let rec eval_expr env = function
  | EFloat f -> f
  | EInt i -> float_of_int i
  | EIdent name -> (
      match List.assoc_opt name env with
      | Some v -> v
      | None -> semantic_fail (Printf.sprintf "unbound variable: %s" name))
  | ENeg e -> -.eval_expr env e
  | EBin (e1, op, e2) -> (
      let a = eval_expr env e1 in
      let b = eval_expr env e2 in
      match op with
      | Add -> a +. b
      | Sub -> a -. b
      | Mul -> a *. b
      | Div -> a /. b)
  | EPow (e1, e2) -> Float.pow (eval_expr env e1) (eval_expr env e2)

(***********************************************************************)
(* Expression compiler: AST -> native OCaml function                   *)
(***********************************************************************)

(* Compile an AST expression into a native OCaml function.
   The environment is a flat float array with layout:
     [| param1; param2; ...; state1; state2; ...; control1; ... |]
   We pre-compute the index of each variable. *)
let compile_expr (env_names : string list) (e : expr) : compiled_expr =
  (* Build a lookup table: name -> index *)
  let index_table = Hashtbl.create 16 in
  List.iteri (fun i name -> Hashtbl.add index_table name i) env_names;
  let get_idx name =
    match Hashtbl.find_opt index_table name with
    | Some i -> i
    | None -> semantic_fail (Printf.sprintf "unbound variable: %s" name)
  in
  (* Recursively compile the expression *)
  let rec gen = function
    | EFloat f -> fun _env -> f
    | EInt i -> fun _env -> float_of_int i
    | EIdent name ->
        let idx = get_idx name in
        fun env -> env.(idx)
    | ENeg e ->
        let f = gen e in
        fun env -> -.f env
    | EBin (e1, op, e2) -> (
        let f1 = gen e1 and f2 = gen e2 in
        match op with
        | Add -> fun env -> f1 env +. f2 env
        | Sub -> fun env -> f1 env -. f2 env
        | Mul -> fun env -> f1 env *. f2 env
        | Div -> fun env -> f1 env /. f2 env)
    | EPow (e1, e2) ->
        let f1 = gen e1 and f2 = gen e2 in
        fun env -> Float.pow (f1 env) (f2 env)
  in
  gen e
(***********************************************************************)
(* Compiler: validation + code generation                              *)
(***********************************************************************)

let zip_names_values names values =
  if List.length names <> List.length values then
    semantic_fail "internal: name/value length mismatch";
  List.combine names values

let compile_exn dsl_source =
  let toks_list = lex_all dsl_source in
  let pst = make_parser_state toks_list in
  let ast = parse_program pst in

  (* ---------------- Semantic validation ---------------- *)
  let state_names = ast.state in
  let control_names = ast.control in
  let n_state = List.length state_names in
  let n_control = List.length control_names in

  if n_state <> 1 && n_state <> 2 then
    semantic_fail (Printf.sprintf "state count must be 1 or 2, got %d" n_state);
  if n_control <> 1 then
    semantic_fail (Printf.sprintf "control count must be 1, got %d" n_control);

  let all_vars = state_names @ control_names @ List.map fst ast.parameters in

  (* Dynamics: exactly one equation per state variable *)
  let dynamics_map = Hashtbl.create 16 in
  List.iter
    (fun (eq : dynamics_eq) ->
      if Hashtbl.mem dynamics_map eq.var then
        semantic_fail
          (Printf.sprintf "duplicate dynamics for state '%s'" eq.var);
      Hashtbl.add dynamics_map eq.var eq.expr)
    ast.dynamics;
  List.iter
    (fun s ->
      if not (Hashtbl.mem dynamics_map s) then
        semantic_fail (Printf.sprintf "missing dynamics for state '%s'" s))
    state_names;

  (* Initial: exactly one value per state variable *)
  let initial_map = Hashtbl.create 16 in
  List.iter
    (fun (eq : initial_eq) ->
      if Hashtbl.mem initial_map eq.var then
        semantic_fail (Printf.sprintf "duplicate initial value for '%s'" eq.var);
      Hashtbl.add initial_map eq.var eq.expr)
    ast.initial;
  List.iter
    (fun s ->
      if not (Hashtbl.mem initial_map s) then
        semantic_fail (Printf.sprintf "missing initial value for state '%s'" s))
    state_names;

  (* Bounds: each state and control variable has [lo, hi] with lo < hi *)
  let bounds_map = Hashtbl.create 16 in
  List.iter (fun b -> Hashtbl.add bounds_map b.var b) ast.bounds;
  List.iter
    (fun s ->
      match Hashtbl.find_opt bounds_map s with
      | None -> semantic_fail (Printf.sprintf "missing bounds for state '%s'" s)
      | Some b ->
          if b.lo >= b.hi then
            semantic_fail
              (Printf.sprintf "bounds for '%s' must satisfy lo < hi" s))
    state_names;
  List.iter
    (fun c ->
      match Hashtbl.find_opt bounds_map c with
      | None ->
          semantic_fail (Printf.sprintf "missing bounds for control '%s'" c)
      | Some b ->
          if b.lo >= b.hi then
            semantic_fail
              (Printf.sprintf "bounds for '%s' must satisfy lo < hi" c))
    control_names;

  (* Horizon *)
  let horizon =
    match ast.horizon with
    | Some h when h >= 1 -> h
    | _ -> semantic_fail "horizon must be an integer >= 1"
  in

  (* Solve section *)
  let solv_method =
    match ast.solve_method with
    | Some m -> m
    | None -> semantic_fail "solve.method is required"
  in
  if solv_method <> "dynamic_programming" then
    semantic_fail (Printf.sprintf "unsupported solve method '%s'" solv_method);
  let grid_counts =
    match ast.solve_grid with
    | Some g -> g
    | None -> semantic_fail "solve.grid is required"
  in
  if List.length grid_counts <> n_state then
    semantic_fail
      (Printf.sprintf "solve.grid length (%d) must match state count (%d)"
         (List.length grid_counts) n_state);
  List.iter
    (fun n -> if n < 2 then semantic_fail "solve.grid counts must each be >= 2")
    grid_counts;
  let controls_n =
    match ast.solve_controls with
    | Some c when c >= 2 -> c
    | _ -> semantic_fail "solve.controls must be an integer >= 2"
  in

  (* All identifiers in dynamics and cost must be declared *)
  let declared = all_vars in
  let check_expr e =
    List.iter
      (fun v ->
        if not (List.mem v declared) then
          semantic_fail
            (Printf.sprintf "undefined variable '%s' referenced in expression" v))
      (expr_idents e)
  in
  List.iter (fun eq -> check_expr eq.expr) ast.dynamics;
  (match ast.running_cost with Some e -> check_expr e | None -> ());
  (match ast.terminal_cost with Some e -> check_expr e | None -> ());

  (* ---------------- Build compiled problem ---------------- *)

  (* Parameters are evaluated once at compile time.  [param_env] is used for
     one-shot evaluation (initial state, dt); [param_values] seeds the flat
     environment buffer used by the compiled expressions. *)
  let param_env = List.map (fun (n, e) -> (n, eval_expr [] e)) ast.parameters in
  let param_names = List.map fst param_env in
  let param_values = Array.of_list (List.map snd param_env) in
  let n_params = List.length param_names in
  let control_offset = n_params + n_state in

  (* Flat environment layout: [| params...; states...; controls... |].
     Reused across calls; the solver is single-threaded and never holds a
     reference to it, so sharing one buffer is safe. *)
  let env_names = param_names @ state_names @ control_names in
  let env_buf = Array.make (List.length env_names) 0.0 in
  Array.blit param_values 0 env_buf 0 n_params;

  (* Dynamics must be ordered by [state_names], not by source order:
     the solver reads x_next.(i) as the i-th declared state variable. *)
  let compiled_dynamics =
    Array.of_list
      (List.map
         (fun s -> compile_expr env_names (Hashtbl.find dynamics_map s))
         state_names)
  in
  let compiled_running_cost =
    match ast.running_cost with
    | Some e -> compile_expr env_names e
    | None -> fun _ -> 0.0
  in
  let compiled_terminal_cost =
    match ast.terminal_cost with
    | Some e -> compile_expr (param_names @ state_names) e
    | None -> fun _ -> 0.0
  in

  let dynamics_fun x u =
    Array.blit x 0 env_buf n_params n_state;
    Array.blit u 0 env_buf control_offset n_control;
    Array.init n_state (fun i -> compiled_dynamics.(i) env_buf)
  in

  let running_cost_fun x u =
    Array.blit x 0 env_buf n_params n_state;
    Array.blit u 0 env_buf control_offset n_control;
    compiled_running_cost env_buf
  in

  let terminal_cost_fun x =
    Array.blit x 0 env_buf n_params n_state;
    compiled_terminal_cost env_buf
  in

  let problem =
    Problem.make ~horizon ~dynamics:dynamics_fun ~running_cost:running_cost_fun
      ~terminal_cost:terminal_cost_fun
  in
  (* State grid *)
  let get_bounds v =
    match Hashtbl.find_opt bounds_map v with
    | Some b -> (b.lo, b.hi)
    | None ->
        semantic_fail (Printf.sprintf "internal: missing bounds for '%s'" v)
  in

  let state_grid =
    match state_names with
    | [ s ] ->
        let lo, hi = get_bounds s in
        let n = List.hd grid_counts in
        Solver.G1 (Grid.make1 ~lo ~hi ~n)
    | [ s1; s2 ] ->
        let lo1, hi1 = get_bounds s1 in
        let lo2, hi2 = get_bounds s2 in
        let n1 = List.hd grid_counts in
        let n2 = List.hd (List.tl grid_counts) in
        Solver.G2 (Grid.make2 ~lox:lo1 ~hix:hi1 ~nx:n1 ~loy:lo2 ~hiy:hi2 ~ny:n2)
    | _ -> semantic_fail "internal: invalid state count"
  in

  (* Control grid (1D, single control variable) *)
  let control_grid =
    let c = List.hd control_names in
    let lo, hi = get_bounds c in
    Grid.make1 ~lo ~hi ~n:controls_n
  in

  (* Initial state *)
  let initial_state =
    Array.of_list
      (List.map
         (fun s ->
           match Hashtbl.find_opt initial_map s with
           | Some e -> eval_expr param_env e
           | None ->
               semantic_fail
                 (Printf.sprintf "internal: missing initial for '%s'" s))
         state_names)
  in
  (* Extract dt from parameters (default 1.0 if not declared). *)
  let dt =
    match assoc_opt "dt" param_env with
    | Some v when v > 0.0 -> v
    | Some _ -> semantic_fail "parameter 'dt' must be positive"
    | None -> 1.0
  in
  {
    name = ast.name;
    the_problem = problem;
    state_grid;
    control_grid;
    initial_state;
    dt;
  }

let compile dsl_source =
  try Ok (compile_exn dsl_source) with
  | Lex_fail (line, col, msg) -> Error (Lex_error { line; col; message = msg })
  | Parse_fail (line, col, msg) ->
      Error (Parse_error { line; col; message = msg })
  | Semantic_fail msg -> Error (Semantic_error msg)
  | Invalid_argument msg -> Error (Semantic_error msg)
  | exn ->
      Error
        (Semantic_error
           (Printf.sprintf "internal error: %s" (Printexc.to_string exn)))
