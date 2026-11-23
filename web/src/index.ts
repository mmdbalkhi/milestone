/// <reference types="vite/client" />

import { initBridge, type LintIssue } from "./bridge";
import { initUI, type ResultNames } from "./ui";

import { EditorState } from "@codemirror/state";
import {
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLineGutter,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
  highlightActiveLine,
} from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import {
  bracketMatching,
  foldGutter,
  foldKeymap,
  indentOnInput,
  syntaxHighlighting,
  HighlightStyle,
  StreamLanguage,
} from "@codemirror/language";
import { lintGutter, linter, type Diagnostic } from "@codemirror/lint";
import {
  autocompletion,
  closeBrackets,
  closeBracketsKeymap,
  completionKeymap,
} from "@codemirror/autocomplete";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { tags as t } from "@lezer/highlight";
import "@fontsource/ibm-plex-sans/400.css";
import "@fontsource/ibm-plex-sans/500.css";
import "@fontsource/ibm-plex-sans/600.css";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";

interface Example {
  id: string;
  label: string;
  source: string;
}

type TabName = "results" | "guide";

const DSL_KEYWORDS = [
  "problem",
  "end_problem",
  "state",
  "control",
  "parameter",
  "horizon",
  "dynamics",
  "end_dynamics",
  "initial",
  "end_initial",
  "target",
  "end_target",
  "bounds",
  "end_bounds",
  "cost",
  "end_cost",
  "solve",
  "end_solve",
  "method",
  "grid",
  "controls",
  "in",
  "running",
  "terminal",
] as const;

const DSL_METHODS = ["dynamic_programming"] as const;

const keywordSet = new Set<string>(DSL_KEYWORDS);
const methodSet = new Set<string>(DSL_METHODS);

// Auto-load all .mls files from ../../examples/
const exampleModules = import.meta.glob("../../examples/*.mls", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

const examples: Example[] = Object.entries(exampleModules).map(
  ([filePath, source]) => {
    const filename = filePath.split("/").pop() ?? filePath;
    const label = filename
      .replace(/\.mls$/, "")
      .replace(/[_-]+/g, " ")
      .replace(/\b\w/g, (char) => char.toUpperCase());

    return { id: filePath, label, source };
  },
);

const controlDslLanguage = StreamLanguage.define({
  name: "control-dsl",
  startState() {
    return {};
  },
  token(stream) {
    if (stream.eatSpace()) return null;
    if (stream.match(/^(?:#|\/\/).*/)) return "comment";
    if (stream.match(/^(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?/))
      return "number";
    if (stream.match(/^[A-Za-z_][A-Za-z0-9_]*'/)) return "variable-2";
    if (stream.match(/^[A-Za-z_][A-Za-z0-9_]*/)) {
      const word = stream.current();
      if (keywordSet.has(word)) return "keyword";
      if (methodSet.has(word)) return "atom";
      return "variable";
    }
    if (stream.match(/^[+\-*/^=<>!]+/)) return "operator";
    if (stream.match(/^[\[\](),:]/)) return "bracket";
    stream.next();
    return "invalid";
  },
});
const editorTheme = EditorView.theme({
  "&": { color: "#4c4f69", backgroundColor: "#ffffff" },
  ".cm-scroller": {
    fontFamily:
      '"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, monospace',
  },
  ".cm-content": { caretColor: "#04a5e5", padding: "12px 0" },
  ".cm-gutters": {
    backgroundColor: "#f6f7f9",
    color: "#9ca0b0",
    borderRight: "1px solid #e6e9ef",
  },
  ".cm-activeLine": { backgroundColor: "#f2f4f8" },
  ".cm-activeLineGutter": { backgroundColor: "#e6e9ef", color: "#4c4f69" },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor: "#cfe6f5",
  },
  ".cm-cursor": { borderLeftColor: "#04a5e5" },
});

const dslHighlightStyle = HighlightStyle.define([
  { tag: t.keyword, color: "#8839ef", fontWeight: "600" }, // mauve
  { tag: t.comment, color: "#8c8fa1", fontStyle: "italic" },
  { tag: t.number, color: "#fe640b" }, // peach
  { tag: t.operator, color: "#04a5e5" }, // sky
  { tag: t.bracket, color: "#df8e1d" }, // yellow (readable on white)
  { tag: t.variableName, color: "#4c4f69" },
  { tag: t.special(t.variableName), color: "#1e66f5", fontWeight: "600" }, // primed x'
  { tag: t.atom, color: "#179299", fontWeight: "600" }, // dynamic_programming
  { tag: t.invalid, color: "#d20f39", textDecoration: "underline wavy" },
]);
function mustGet<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing required element: #${id}`);
  return element as T;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      case "'":
        return "&#039;";
      default:
        return char;
    }
  });
}

function highlightDsl(source: string): string {
  let output = "";
  let index = 0;

  const appendToken = (className: string, value: string) => {
    output += `<span class="${className}">${escapeHtml(value)}</span>`;
  };

  while (index < source.length) {
    const rest = source.slice(index);

    const whitespace = rest.match(/^\s+/);
    if (whitespace) {
      output += escapeHtml(whitespace[0]);
      index += whitespace[0].length;
      continue;
    }

    const comment = rest.match(/^(?:#|\/\/).*/);
    if (comment) {
      appendToken("tok-comment", comment[0]);
      index += comment[0].length;
      continue;
    }

    const prime = rest.match(/^[A-Za-z_][A-Za-z0-9_]*'/);
    if (prime) {
      appendToken("tok-prime", prime[0]);
      index += prime[0].length;
      continue;
    }

    const number = rest.match(/^(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?/);
    if (number) {
      appendToken("tok-number", number[0]);
      index += number[0].length;
      continue;
    }

    const word = rest.match(/^[A-Za-z_][A-Za-z0-9_]*/);
    if (word) {
      const value = word[0];
      if (keywordSet.has(value)) appendToken("tok-keyword", value);
      else if (methodSet.has(value)) appendToken("tok-method", value);
      else appendToken("tok-variable", value);
      index += value.length;
      continue;
    }

    const char = source[index];
    if (/[+\-*/^=<>!]/.test(char)) appendToken("tok-operator", char);
    else if (/[\[\](),:]/.test(char)) appendToken("tok-bracket", char);
    else output += escapeHtml(char);

    index += 1;
  }

  return output;
}

function lintIssueToDiagnostic(view: EditorView, issue: LintIssue): Diagnostic {
  const lineNumber = Math.min(Math.max(issue.line, 1), view.state.doc.lines);
  const line = view.state.doc.line(lineNumber);
  const column = Math.max(issue.column - 1, 0);
  const endColumn = Math.max((issue.endColumn ?? issue.column + 1) - 1, column);

  return {
    from: Math.min(line.from + column, line.to),
    to: Math.min(line.from + endColumn, line.to),
    severity: issue.severity,
    message: issue.message,
  };
}

function createEditor(
  parent: HTMLElement,
  bridge: ReturnType<typeof initBridge>,
  initialDoc: string,
): EditorView {
  const dslLinter = linter(
    async (view) => {
      const source = view.state.doc.toString();
      if (!source.trim()) return [];
      const issues = await bridge.lint(source);
      return issues.map((issue) => lintIssueToDiagnostic(view, issue));
    },
    { delay: 450 },
  );

  return new EditorView({
    parent,
    state: EditorState.create({
      doc: initialDoc,
      extensions: [
        lineNumbers(),
        highlightActiveLineGutter(),
        highlightSpecialChars(),
        history(),
        foldGutter(),
        drawSelection(),
        dropCursor(),
        EditorState.allowMultipleSelections.of(true),
        indentOnInput(),
        bracketMatching(),
        closeBrackets(),
        autocompletion({
          override: [
            (context) => {
              const word = context.matchBefore(/[A-Za-z_][A-Za-z0-9_]*$/);
              if (!word && !context.explicit) return null;
              return {
                from: word?.from ?? context.pos,
                options: [...DSL_KEYWORDS, ...DSL_METHODS].map((label) => ({
                  label,
                  type: methodSet.has(label) ? "constant" : "keyword",
                })),
              };
            },
          ],
        }),
        rectangularSelection(),
        crosshairCursor(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        keymap.of([
          ...closeBracketsKeymap,
          ...defaultKeymap,
          ...searchKeymap,
          ...historyKeymap,
          ...foldKeymap,
          ...completionKeymap,
          indentWithTab,
        ]),
        controlDslLanguage,
        syntaxHighlighting(dslHighlightStyle),
        lintGutter(),
        dslLinter,
        EditorView.lineWrapping,
        editorTheme,
      ],
    }),
  });
}

function setEditorValue(editor: EditorView, value: string): void {
  editor.dispatch({
    changes: { from: 0, to: editor.state.doc.length, insert: value },
    selection: { anchor: 0 },
  });
}

function initTabs(onActivate: (tab: TabName) => void) {
  const buttons = Array.from(
    document.querySelectorAll<HTMLButtonElement>("[data-tab]"),
  );
  const panels: Record<TabName, HTMLElement> = {
    results: mustGet("panel-results"),
    guide: mustGet("panel-guide"),
  };

  function activate(tab: TabName, focus = false): void {
    for (const button of buttons) {
      const selected = button.dataset.tab === tab;
      button.setAttribute("aria-selected", String(selected));
      button.tabIndex = selected ? 0 : -1;
      if (selected && focus) button.focus();
    }
    panels.results.hidden = tab !== "results";
    panels.guide.hidden = tab !== "guide";
    onActivate(tab);
  }

  for (const button of buttons) {
    button.addEventListener("click", () =>
      activate(button.dataset.tab as TabName),
    );
  }

  activate("guide");
  return { activate };
}

function stripComment(line: string): string {
  return line.replace(/(?:#|\/\/).*$/, "").trim();
}

function extractVariableNames(source: string): ResultNames {
  const lines = source.split(/\r?\n/).map(stripComment);
  const sectionPattern =
    /^(?:state|control|parameter|dynamics|initial|target|horizon|bounds|cost|solve|end_problem|end_dynamics|end_initial|end_target|end_bounds|end_cost|end_solve)\b/;

  const result: Record<"state" | "control", string[]> = {
    state: [],
    control: [],
  };

  function pushNames(target: string[], text: string): void {
    for (const part of text.split(",")) {
      const name = part.trim();
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(name) && !target.includes(name)) {
        target.push(name);
      }
    }
  }

  for (let index = 0; index < lines.length; index++) {
    const match = lines[index].match(/^(state|control):\s*(.*)$/);
    if (!match) continue;

    const kind = match[1] as "state" | "control";
    const inlineValue = match[2].trim();

    if (inlineValue) {
      pushNames(result[kind], inlineValue);
      continue;
    }

    for (let next = index + 1; next < lines.length; next++) {
      const line = lines[next];
      if (!line) continue;
      if (sectionPattern.test(line)) break;
      pushNames(result[kind], line);
    }
  }

  return { stateNames: result.state, controlNames: result.control };
}

function makeNames(
  provided: string[] | undefined,
  count: number,
  prefix: string,
): string[] {
  return Array.from(
    { length: count },
    (_, index) => provided?.[index] || `${prefix}_${index}`,
  );
}

function csvCell(value: unknown): string {
  const text = String(value ?? "");
  if (/[",\n\r]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function downloadCsv(
  result: NonNullable<
    Awaited<ReturnType<ReturnType<typeof initBridge>["solve"]>>
  >,
  names: ResultNames,
): void {
  if (result.status !== "ok" || !result.result) return;

  const { time, states, controls } = result.result;
  const stateWidth = states[0]?.length ?? 0;
  const controlWidth = controls[0]?.length ?? 0;

  const stateNames = makeNames(names.stateNames, stateWidth, "state");
  const controlNames = makeNames(names.controlNames, controlWidth, "control");

  const rows = [
    ["time", ...stateNames, ...controlNames].map(csvCell).join(","),
  ];

  for (let index = 0; index < time.length; index++) {
    const row = [
      time[index],
      ...Array.from({ length: stateWidth }, (_, i) => states[index]?.[i] ?? ""),
      ...Array.from(
        { length: controlWidth },
        (_, i) => controls[index]?.[i] ?? "",
      ),
    ];
    rows.push(row.map(csvCell).join(","));
  }

  const blob = new Blob([rows.join("\n")], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  const safeName = (result.problem_name || "export").replace(/[^\w.-]+/g, "_");

  anchor.href = url;
  anchor.download = `trajectory_${safeName}.csv`;
  anchor.click();

  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function renderGuideExamples(container: HTMLElement): void {
  if (examples.length === 0) {
    container.innerHTML = "<p>No examples found in ../../examples/</p>";
    return;
  }

  container.innerHTML = examples
    .map(
      (example) => `
    <article class="example-card">
      <div class="example-card-header">
        <h4>${escapeHtml(example.label)}</h4>
        <button class="button" type="button" data-load-example="${escapeHtml(example.id)}">Load</button>
      </div>
      <pre><code>${highlightDsl(example.source)}</code></pre>
    </article>
  `,
    )
    .join("");
}

function main(): void {
  const editorHost = mustGet<HTMLElement>("editor");
  const exampleSelect = mustGet<HTMLSelectElement>("example-select");
  const blankBtn = mustGet<HTMLButtonElement>("blank-file");
  const solveBtn = mustGet<HTMLButtonElement>("solve");
  const downloadBtn = mustGet<HTMLButtonElement>("download-csv");
  const guideExamples = mustGet<HTMLElement>("guide-examples");

  const bridge = initBridge();
  const editor = createEditor(editorHost, bridge, "");

  const ui = initUI({
    errorBox: mustGet("error"),
    okBox: mustGet("ok"),
    summaryBox: mustGet("summary"),
    chartsContainer: mustGet("charts"),
    statusBox: mustGet("status"),
    emptyState: mustGet("results-empty"),
    stateCanvas: mustGet<HTMLCanvasElement>("stateChart"),
    controlCanvas: mustGet<HTMLCanvasElement>("controlChart"),
  });

  const tabs = initTabs((tab) => {
    if (tab === "results") ui.resizeCharts();
  });

  let lastResult: Awaited<ReturnType<typeof bridge.solve>> | null = null;
  let lastResultNames: ResultNames = {};

  function resetOutput(): void {
    lastResult = null;
    lastResultNames = {};
    downloadBtn.hidden = true;
    downloadBtn.disabled = true;
    ui.clearResults();
  }

  function loadSource(source: string, focus = true): void {
    setEditorValue(editor, source);
    resetOutput();
    if (focus) editor.focus();
  }

  function loadExample(id: string, focus = true): void {
    const example = examples.find((item) => item.id === id);
    if (!example) {
      loadSource("", focus);
      return;
    }
    exampleSelect.value = example.id;
    loadSource(example.source, focus);
  }

  function setSolving(isSolving: boolean): void {
    solveBtn.disabled = isSolving;
    solveBtn.textContent = isSolving ? "Solving…" : "Solve";
  }

  // Populate example dropdown
  exampleSelect.replaceChildren(new Option("Select example...", ""));
  for (const example of examples) {
    exampleSelect.append(new Option(example.label, example.id));
  }

  renderGuideExamples(guideExamples);

  exampleSelect.addEventListener("change", () => {
    const id = exampleSelect.value;
    if (!id) {
      loadSource("");
      return;
    }
    loadExample(id);
  });

  blankBtn.addEventListener("click", () => {
    exampleSelect.value = "";
    loadSource("");
  });

  guideExamples.addEventListener("click", (event) => {
    const target = event.target as HTMLElement;
    const button = target.closest<HTMLButtonElement>("[data-load-example]");
    if (!button) return;
    const id = button.dataset.loadExample;
    if (!id) return;
    loadExample(id);
  });

  solveBtn.addEventListener("click", async () => {
    const source = editor.state.doc.toString();
    const names = extractVariableNames(source);

    tabs.activate("results");
    setSolving(true);
    ui.beginSolve();

    downloadBtn.hidden = true;
    downloadBtn.disabled = true;

    try {
      const result = await bridge.solve(source);
      lastResult = result.status === "ok" ? result : null;
      lastResultNames = names;
      ui.renderResults(result, names);

      const canDownload = result.status === "ok" && Boolean(result.result);
      downloadBtn.hidden = !canDownload;
      downloadBtn.disabled = !canDownload;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      ui.showStatus("error", `Fatal Error: ${message}`);
    } finally {
      setSolving(false);
    }
  });

  downloadBtn.addEventListener("click", () => {
    if (!lastResult) return;
    downloadCsv(lastResult, lastResultNames);
  });

  window.addEventListener("resize", () => ui.resizeCharts());

  // Load first example if available
  if (examples.length > 0) {
    loadExample(examples[0].id, false);
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", main, { once: true });
} else {
  main();
}
