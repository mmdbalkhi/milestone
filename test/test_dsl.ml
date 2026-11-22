let sample_dsl =
  {|
problem DoubleIntegrator

    state:
        x, v

    control:
        u

    parameter:
        dt = 0.1

    dynamics:
        x' = x + dt * v
        v' = v + dt * u
    end_dynamics

    initial:
        x = 0
        v = 0
    end_initial

    target:
        x = 10
        v = 0
    end_target

    horizon: 20

    bounds:
        x in [-15, 15]
        v in [-10, 10]
        u in [-2, 2]
    end_bounds

    cost:
        running = x^2 + v^2 + 0.1 * u^2
        terminal = 10 * (x - 10)^2 + 10 * v^2
    end_cost

    solve:
        method = dynamic_programming
        grid = [41, 41]
        controls = 21
    end_solve

end_problem
|}

let test_dsl_compile_and_solve () =
  match Dsl.compile sample_dsl with
  | Error msg -> failwith ("DSL compile failed: " ^ msg)
  | Ok cp ->
      let res =
        Solver.solve ~problem:cp.the_problem ~state_grid:cp.state_grid
          ~control_grid:cp.control_grid
      in
      let states, controls =
        Solver.rollout ~problem:cp.the_problem ~result:res
          ~state_grid:cp.state_grid ~initial_state:cp.initial_state
      in
      assert (Array.length states = 21);
      assert (Array.length controls = 20);
      assert (abs_float (states.(20).(0) -. 3.330) < 1e-3);
      assert (abs_float (states.(20).(1) -. 1.900) < 1e-3)
