// web/src/index.ts
import { initBridge, type SolveResult } from "./bridge";
import { initUI } from "./ui";

// 1. Define a lightweight custom syntax highlighter for our DSL
declare global {
  interface Window {
    CodeMirror: any;
  }
}

window.CodeMirror.defineSimpleMode("control-dsl", {
  start: [
    { regex: /#.*$/, token: "comment" },
    { regex: /\/\/.*$/, token: "comment" },
    {
      regex:
        /\b(problem|end_problem|state|control|parameter|horizon|dynamics|end_dynamics|initial|end_initial|target|end_target|bounds|end_bounds|cost|end_cost|solve|end_solve|method|grid|controls|in)\b/,
      token: "keyword",
    },
    { regex: /[a-zA-Z_][a-zA-Z0-9_]*'/, token: "variable-2" }, // e.g., x'
    { regex: /[a-zA-Z_][a-zA-Z0-9_]*/, token: "variable" },
    { regex: /-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, token: "number" },
    { regex: /[+\-*/^=,:\[\]()]/, token: "operator" },
    { regex: /".*?"/, token: "string" },
  ],
});

const presets = {
  doubleIntegrator: `problem DoubleIntegrator
  state: x, v
  control: u
  parameter: dt = 0.1
  dynamics:
    x' = x + dt * v
    v' = v + dt * u
  end_dynamics
  initial:
    x = 0
    v = 0
  end_initial
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
end_problem`,
  simpleIntegrator: `problem SimpleIntegrator
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
end_problem`,
  invalidDsl: `problem InvalidExample
  state: x
  control: u
  horizon: 5
  dynamics:
    x' = x + 0.1 * undefined_var
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
  end_cost
  solve:
    method = dynamic_programming
    grid = [21]
    controls = 11
  end_solve
end_problem`,
};

document.addEventListener("DOMContentLoaded", () => {
  const textarea = document.getElementById("dsl") as HTMLTextAreaElement;
  const editor = window.CodeMirror.fromTextArea(textarea, {
    mode: "control-dsl",
    theme: "one-dark",
    lineNumbers: true,
    indentUnit: 2,
    lineWrapping: true,
  });
  editor.setValue(presets.doubleIntegrator);

  const solveBtn = document.getElementById("solve") as HTMLButtonElement;
  const downloadBtn = document.getElementById(
    "download-csv",
  ) as HTMLButtonElement;
  const statusBox = document.getElementById("status") as HTMLElement;
  const errorBox = document.getElementById("error") as HTMLElement;
  const okBox = document.getElementById("ok") as HTMLElement;
  const summaryBox = document.getElementById("summary") as HTMLElement;
  const chartsContainer = document.getElementById("charts") as HTMLElement;
  const errorToast = document.getElementById("error-toast") as HTMLElement;

  let toastTimeout: number;
  function showToast(message: string, type: "error" | "success" = "error") {
    errorToast.textContent = message;
    errorToast.className = `toast ${type}-toast show`;

    clearTimeout(toastTimeout);
    toastTimeout = window.setTimeout(() => {
      errorToast.classList.remove("show");
    }, 6000); // Auto-hide after 6 seconds
  }

  const { solve } = initBridge();
  const ui = initUI({
    editor,
    errorBox,
    okBox,
    summaryBox,
    chartsContainer,
    statusBox,
    stateCanvas: document.getElementById("stateChart") as HTMLCanvasElement,
    controlCanvas: document.getElementById("controlChart") as HTMLCanvasElement,
  });

  // Preset buttons
  document.querySelectorAll(".preset-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const presetKey = (btn as HTMLElement).dataset
        .preset as keyof typeof presets;
      if (presetKey && presets[presetKey]) {
        editor.setValue(presets[presetKey]);
        showToast(`Loaded preset: ${presetKey}`, "success");
        errorBox.style.display = "none";
        okBox.style.display = "none";
        summaryBox.style.display = "none";
        chartsContainer.style.display = "none";
        downloadBtn.style.display = "none";
      }
    });
  });

  // Download CSV logic
  downloadBtn.addEventListener("click", () => {
    const raw = (window as any).__lastSolveResult as SolveResult | undefined;
    if (!raw || raw.status !== "ok" || !raw.result) return;

    const { time, states, controls } = raw.result;
    const stateCols = states[0].map((_, i) => `state_${i}`).join(",");
    const controlCols = controls[0].map((_, i) => `control_${i}`).join(",");

    let csv = `time,${stateCols},${controlCols}\n`;
    for (let k = 0; k < time.length; k++) {
      const stateStr = states[k] ? states[k].join(",") : "";
      const controlStr = controls[k] ? controls[k].join(",") : "";
      csv += `${time[k]},${stateStr},${controlStr}\n`;
    }

    const blob = new Blob([csv], { type: "text/csv" });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `trajectory_${raw.problem_name || "export"}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);
  });

  // Solve logic
  solveBtn.addEventListener("click", async () => {
    solveBtn.disabled = true;
    solveBtn.innerHTML = '<span class="spinner"></span> Solving…';
    statusBox.style.display = "none";
    errorBox.style.display = "none";
    okBox.style.display = "none";
    summaryBox.style.display = "none";
    chartsContainer.style.display = "none";
    downloadBtn.style.display = "none";
    errorToast.classList.remove("show"); // Hide any lingering toast

    try {
      const result = await solve(editor.getValue());
      (window as any).__lastSolveResult = result;

      ui.renderResults(result);

      if (result.status === "ok" && result.result) {
        downloadBtn.style.display = "inline-flex";
      } else if (result.status === "error") {
        showToast(`Solver Error: ${result.message}`, "error");
      }
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      showToast(`Fatal Error: ${errorMsg}`, "error");

      // Keep inline status for redundancy
      statusBox.className = "status-bar error";
      statusBox.textContent = "Fatal Error: " + errorMsg;
      statusBox.style.display = "block";
    } finally {
      solveBtn.disabled = false;
      solveBtn.textContent = "Solve";
    }
  });
});
