(* lib/grid.ml - 1D and 2D uniform grids with flat row-major storage. *)

type t1 = { n : int; lo : float; hi : float; dx : float; nodes : float array }

type t2 = {
  nx : int;
  ny : int;
  lox : float;
  hix : float;
  loy : float;
  hiy : float;
  dx : float;
  dy : float;
}

let make1 ~lo ~hi ~n =
  if n < 2 then invalid_arg "Grid.make1: n must be >= 2";
  if not (lo < hi) then invalid_arg "Grid.make1: lo must be < hi";
  let dx = (hi -. lo) /. float_of_int (n - 1) in
  let nodes = Array.init n (fun i -> lo +. (float_of_int i *. dx)) in
  { n; lo; hi; dx; nodes }

let make2 ~lox ~hix ~nx ~loy ~hiy ~ny =
  if nx < 2 then invalid_arg "Grid.make2: nx must be >= 2";
  if ny < 2 then invalid_arg "Grid.make2: ny must be >= 2";
  if not (lox < hix) then invalid_arg "Grid.make2: lox must be < hix";
  if not (loy < hiy) then invalid_arg "Grid.make2: loy must be < hiy";
  let dx = (hix -. lox) /. float_of_int (nx - 1) in
  let dy = (hiy -. loy) /. float_of_int (ny - 1) in
  { nx; ny; lox; hix; loy; hiy; dx; dy }

let clamp_int lo hi i = min (max i lo) hi
let clamp_float lo hi x = min (max x lo) hi

let node1 g i =
  let i = clamp_int 0 (g.n - 1) i in
  g.nodes.(i)

let node2 g i j =
  let i = clamp_int 0 (g.nx - 1) i in
  let j = clamp_int 0 (g.ny - 1) j in
  (g.lox +. (float_of_int i *. g.dx), g.loy +. (float_of_int j *. g.dy))

(* Row-major flat index: idx = i * ny + j, i = dim 0, j = dim 1. *)
let index2 g i j = (i * g.ny) + j
let clamp1 g x = clamp_float g.lo g.hi x
let clamp2 g x y = (clamp_float g.lox g.hix x, clamp_float g.loy g.hiy y)
let count1 g = g.n
let count2 g = (g.nx, g.ny)

let norm_pos ~lo ~dx ~n x =
  let max_idx = float_of_int (n - 1) in
  clamp_float 0.0 max_idx ((x -. lo) /. dx)

let nearest1 g x =
  let t = norm_pos ~lo:g.lo ~dx:g.dx ~n:g.n x in
  int_of_float (Float.round t)

let nearest2 g x y =
  let tx = norm_pos ~lo:g.lox ~dx:g.dx ~n:g.nx x in
  let ty = norm_pos ~lo:g.loy ~dx:g.dy ~n:g.ny y in
  (int_of_float (Float.round tx), int_of_float (Float.round ty))

let interp1 g xs x =
  if Array.length xs <> g.n then
    invalid_arg "Grid.interp1: value array length must match grid node count";
  let n = g.n in
  let t = norm_pos ~lo:g.lo ~dx:g.dx ~n x in
  let i0 = min (int_of_float (floor t)) (n - 2) in
  let i1 = i0 + 1 in
  let w = t -. float_of_int i0 in
  (xs.(i0) *. (1.0 -. w)) +. (xs.(i1) *. w)

let interp2 g xs x y =
  if Array.length xs <> g.nx * g.ny then
    invalid_arg "Grid.interp2: value array length must match nx * ny";
  let nx, ny = (g.nx, g.ny) in
  let tx = norm_pos ~lo:g.lox ~dx:g.dx ~n:nx x in
  let ty = norm_pos ~lo:g.loy ~dx:g.dy ~n:ny y in
  let i0 = min (int_of_float (floor tx)) (nx - 2) in
  let j0 = min (int_of_float (floor ty)) (ny - 2) in
  let i1 = i0 + 1 and j1 = j0 + 1 in
  let wx = tx -. float_of_int i0 in
  let wy = ty -. float_of_int j0 in
  let v00 = xs.((i0 * ny) + j0) in
  let v10 = xs.((i1 * ny) + j0) in
  let v01 = xs.((i0 * ny) + j1) in
  let v11 = xs.((i1 * ny) + j1) in
  ((1.0 -. wx) *. (1.0 -. wy) *. v00)
  +. (wx *. (1.0 -. wy) *. v10)
  +. ((1.0 -. wx) *. wy *. v01)
  +. (wx *. wy *. v11)
