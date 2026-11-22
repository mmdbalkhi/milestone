// web/src/ui.ts
import type { SolveResult } from "./bridge";

interface DomRefs {
  editor: any;
  errorBox: HTMLElement;
  okBox: HTMLElement;
  summaryBox: HTMLElement;
  chartsContainer: HTMLElement;
  statusBox: HTMLElement;
  stateCanvas: HTMLCanvasElement;
  controlCanvas: HTMLCanvasElement;
}

let stateChart: any = null;
let controlChart: any = null;

function getChart() {
  const Chart = (window as any).Chart;
  if (!Chart) throw new Error("Chart.js not loaded. Check CDN connection.");
  return Chart;
}

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 400 },
  interaction: { mode: "index" as const, intersect: false },
  plugins: {
    legend: {
      position: "top" as const,
      labels: {
        usePointStyle: true,
        boxWidth: 8,
        font: { size: 12 },
        // Explicitly enable click-to-toggle (default, but good to be explicit)
        onClick: function (this: any, legendItem: any, legend: any) {
          const index = legendItem.datasetIndex;
          const ci = legend.chart;
          if (ci.isDatasetVisible(index)) {
            ci.hide(index);
            legendItem.hidden = true;
          } else {
            ci.show(index);
            legendItem.hidden = false;
          }
        },
      },
    },
    tooltip: {
      backgroundColor: "rgba(15, 23, 42, 0.9)",
      padding: 12,
      cornerRadius: 8,
      titleFont: { size: 13 },
      bodyFont: { size: 12 },
    },
  },
  scales: {
    x: {
      grid: { color: "#f1f5f9" },
      title: {
        display: true,
        text: "Time (s)",
        color: "#64748b",
        font: { size: 12, weight: "bold" },
      },
    },
    y: {
      grid: { color: "#f1f5f9" },
      title: {
        display: true,
        color: "#64748b",
        font: { size: 12, weight: "bold" },
      },
    },
  },
};

export function initUI(refs: DomRefs) {
  const {
    editor,
    errorBox,
    okBox,
    summaryBox,
    chartsContainer,
    statusBox,
    stateCanvas,
    controlCanvas,
  } = refs;

  const Chart = getChart();

  stateChart = new Chart(stateCanvas.getContext("2d"), {
    type: "line",
    data: { labels: [], datasets: [] },
    options: {
      ...chartOptions,
      scales: {
        ...chartOptions.scales,
        y: {
          ...chartOptions.scales.y,
          title: { display: true, text: "State" },
        },
      },
    },
  });

  controlChart = new Chart(controlCanvas.getContext("2d"), {
    type: "line",
    data: { labels: [], datasets: [] },
    options: {
      ...chartOptions,
      scales: {
        ...chartOptions.scales,
        y: {
          ...chartOptions.scales.y,
          title: { display: true, text: "Control" },
        },
      },
    },
  });

  function renderResults(result: SolveResult) {
    chartsContainer.style.display = "none";
    errorBox.style.display = "none";
    okBox.style.display = "none";
    summaryBox.style.display = "none";
    statusBox.style.display = "none";

    if (result.status === "error") {
      statusBox.className = "status-bar error";
      statusBox.textContent = `[${result.stage?.toUpperCase()}] ${result.message}`;
      statusBox.style.display = "block";
      return;
    }

    const r = result.result!;

    // Update Summary Strip
    const finalState = r.states[r.steps];
    const stateStr = finalState.map((v: number) => v.toFixed(3)).join(", ");
    summaryBox.innerHTML = `
      <span><strong>Steps:</strong> ${r.steps}</span>
      <span><strong>dt:</strong> ${r.dt}</span>
      <span><strong>Final State:</strong> [${stateStr}]</span>
    `;
    summaryBox.style.display = "flex";

    statusBox.className = "status-bar success";
    statusBox.textContent = `Solved "${result.problem_name}" successfully.`;
    statusBox.style.display = "block";
    chartsContainer.style.display = "block";

    const labels = r.time.map((t: number) => t.toFixed(2));
    const xs = r.states.map((s: number[]) => s[0]);
    const vs =
      r.states.length > 0 && r.states[0].length > 1
        ? r.states.map((s: number[]) => s[1])
        : [];
    const us = r.controls.map((c: number[]) => c[0]);

    // Update State Chart
    stateChart.data = {
      labels,
      datasets: [
        {
          label: "x (position)",
          data: xs,
          borderColor: "#2563eb",
          backgroundColor: "#2563eb22",
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
        },
        ...(vs.length > 0
          ? [
              {
                label: "v (velocity)",
                data: vs,
                borderColor: "#10b981",
                backgroundColor: "#10b98122",
                borderWidth: 2,
                pointRadius: 0,
                tension: 0.3,
              },
            ]
          : []),
      ],
    };
    stateChart.update();

    // Update Control Chart
    controlChart.data = {
      labels,
      datasets: [
        {
          label: "u (control)",
          data: us,
          borderColor: "#f59e0b",
          backgroundColor: "#f59e0b22",
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.1, // Step-like appearance for DP controls
        },
      ],
    };
    controlChart.update();
  }

  return {
    renderResults,
    getValue: () => editor.getValue(),
    setValue: (val: string) => editor.setValue(val),
  };
}
