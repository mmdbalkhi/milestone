import { Chart, registerables, type ChartOptions } from "chart.js";
import type { SolveResult } from "./bridge";

Chart.register(...registerables);

export interface ResultNames {
  stateNames?: string[];
  controlNames?: string[];
}

interface DomRefs {
  errorBox: HTMLElement;
  okBox: HTMLElement;
  summaryBox: HTMLElement;
  chartsContainer: HTMLElement;
  statusBox: HTMLElement;
  emptyState: HTMLElement;
  stateCanvas: HTMLCanvasElement;
  controlCanvas: HTMLCanvasElement;
}

type StatusKind = "success" | "error" | "info";

let stateChart: Chart<"line"> | null = null;
let controlChart: Chart<"line"> | null = null;

const colors = [
  "#2563eb",
  "#16a34a",
  "#f59e0b",
  "#dc2626",
  "#7c3aed",
  "#0891b2",
];

const baseChartOptions: ChartOptions<"line"> = {
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    duration: 250,
  },
  interaction: {
    mode: "index",
    intersect: false,
  },
  plugins: {
    legend: {
      position: "top",
      labels: {
        usePointStyle: true,
        boxWidth: 8,
        font: {
          size: 12,
        },
      },
    },
    tooltip: {
      backgroundColor: "rgba(15, 23, 42, 0.92)",
      padding: 12,
      cornerRadius: 8,
      titleFont: {
        size: 13,
      },
      bodyFont: {
        size: 12,
      },
    },
  },
};

function createLineChart(
  canvas: HTMLCanvasElement,
  yTitle: string,
): Chart<"line"> {
  const context = canvas.getContext("2d");

  if (!context) {
    throw new Error(`Could not get 2D canvas context for ${canvas.id}.`);
  }

  return new Chart(context, {
    type: "line",
    data: {
      labels: [],
      datasets: [],
    },
    options: {
      ...baseChartOptions,
      scales: {
        x: {
          grid: {
            color: "#e2e8f0",
          },
          title: {
            display: true,
            text: "Time",
            color: "#64748b",
            font: {
              size: 12,
              weight: "bold",
            },
          },
        },
        y: {
          grid: {
            color: "#e2e8f0",
          },
          title: {
            display: true,
            text: yTitle,
            color: "#64748b",
            font: {
              size: 12,
              weight: "bold",
            },
          },
        },
      },
    },
  });
}

function formatNumber(value: number): string {
  if (!Number.isFinite(value)) return String(value);
  if (Number.isInteger(value)) return String(value);

  return value.toFixed(4).replace(/\.?0+$/, "");
}

function makeNames(
  provided: string[] | undefined,
  count: number,
  prefix: string,
): string[] {
  return Array.from({ length: count }, (_, index) => {
    return provided?.[index] || `${prefix}_${index}`;
  });
}

function makeDataset(label: string, data: Array<number | null>, color: string) {
  return {
    label,
    data,
    borderColor: color,
    backgroundColor: `${color}22`,
    borderWidth: 2,
    pointRadius: 0,
    pointHoverRadius: 4,
    tension: 0.25,
  };
}

function metric(label: string, value: string): HTMLElement {
  const wrapper = document.createElement("div");
  wrapper.className = "metric";

  const labelElement = document.createElement("span");
  labelElement.className = "metric-label";
  labelElement.textContent = label;

  const valueElement = document.createElement("span");
  valueElement.className = "metric-value";
  valueElement.textContent = value;

  wrapper.append(labelElement, valueElement);

  return wrapper;
}

export function initUI(refs: DomRefs) {
  const {
    errorBox,
    okBox,
    summaryBox,
    chartsContainer,
    statusBox,
    emptyState,
    stateCanvas,
    controlCanvas,
  } = refs;

  stateChart = createLineChart(stateCanvas, "State");
  controlChart = createLineChart(controlCanvas, "Control");

  function showStatus(kind: StatusKind, message: string): void {
    statusBox.className = `status-bar ${kind}`;
    statusBox.textContent = message;
    statusBox.hidden = false;
  }

  function hideOutput(): void {
    errorBox.hidden = true;
    okBox.hidden = true;
    summaryBox.hidden = true;
    chartsContainer.hidden = true;
    statusBox.hidden = true;
  }

  function clearCharts(): void {
    if (stateChart) {
      stateChart.data.labels = [];
      stateChart.data.datasets = [];
      stateChart.update();
    }

    if (controlChart) {
      controlChart.data.labels = [];
      controlChart.data.datasets = [];
      controlChart.update();
    }
  }

  function clearResults(): void {
    hideOutput();
    clearCharts();
    emptyState.hidden = false;
  }

  function beginSolve(): void {
    hideOutput();
    emptyState.hidden = true;
    showStatus("info", "Solving…");
  }

  function resizeCharts(): void {
    requestAnimationFrame(() => {
      stateChart?.resize();
      controlChart?.resize();
    });
  }

  function renderResults(result: SolveResult, names: ResultNames = {}): void {
    hideOutput();
    emptyState.hidden = true;

    if (result.status === "error") {
      const stage = result.stage ? `[${result.stage.toUpperCase()}] ` : "";
      showStatus("error", `${stage}${result.message ?? "Unknown error."}`);
      return;
    }

    const trajectory = result.result;

    if (
      !trajectory ||
      !Array.isArray(trajectory.time) ||
      !Array.isArray(trajectory.states) ||
      !Array.isArray(trajectory.controls)
    ) {
      showStatus("error", "Solver returned no trajectory.");
      return;
    }

    const finalState = trajectory.states[trajectory.states.length - 1] ?? [];
    const stateNames = makeNames(
      names.stateNames,
      trajectory.states[0]?.length ?? 0,
      "state",
    );
    const controlNames = makeNames(
      names.controlNames,
      trajectory.controls[0]?.length ?? 0,
      "control",
    );

    const finalStateText = finalState
      .map((value, index) => `${stateNames[index]}=${formatNumber(value)}`)
      .join(", ");

    summaryBox.replaceChildren(
      metric("Problem", result.problem_name ?? "—"),
      metric("Steps", String(trajectory.steps)),
      metric("dt", formatNumber(trajectory.dt)),
      metric("Final State", `[${finalStateText}]`),
    );

    summaryBox.hidden = false;
    chartsContainer.hidden = false;

    showStatus(
      "success",
      `Solved "${result.problem_name ?? "problem"}" successfully.`,
    );

    const labels = trajectory.time.map((time) => formatNumber(time));

    const stateDatasets = stateNames.map((name, index) => {
      return makeDataset(
        name,
        trajectory.states.map((state) => state[index] ?? null),
        colors[index % colors.length],
      );
    });

    const controlDatasets = controlNames.map((name, index) => {
      return makeDataset(
        name,
        trajectory.controls.map((control) => control[index] ?? null),
        colors[(index + 2) % colors.length],
      );
    });

    if (stateChart) {
      stateChart.data.labels = labels;
      stateChart.data.datasets = stateDatasets;
      stateChart.update();
    }

    if (controlChart) {
      controlChart.data.labels = labels;
      controlChart.data.datasets = controlDatasets;
      controlChart.update();
    }

    resizeCharts();
  }

  return {
    renderResults,
    clearResults,
    beginSolve,
    showStatus,
    resizeCharts,
  };
}
