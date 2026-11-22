(* lib/grid.mli - 1D and 2D uniform grids, clamping, interpolation.

   Internal record representations are abstract; grids are built with
   make1/make2 and queried through the operations below.  Out-of-bounds
   coordinates and indices are clamped to the grid domain: never silent
   nan, never unchecked array access. *)

type t1
type t2

val make1 : lo:float -> hi:float -> n:int -> t1

val make2 :
  lox:float -> hix:float -> nx:int -> loy:float -> hiy:float -> ny:int -> t2

val node1 : t1 -> int -> float
val node2 : t2 -> int -> int -> float * float
val index2 : t2 -> int -> int -> int
val clamp1 : t1 -> float -> float
val clamp2 : t2 -> float -> float -> float * float
val nearest1 : t1 -> float -> int
val nearest2 : t2 -> float -> float -> int * int

(* Number of nodes; for 2D returns (nx, ny). Needed to iterate state nodes. *)
val count1 : t1 -> int
val count2 : t2 -> int * int
val interp1 : t1 -> float array -> float -> float
val interp2 : t2 -> float array -> float -> float -> float
