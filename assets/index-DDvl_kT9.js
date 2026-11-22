import'data:text/javascript,"assets/index-DDvl_kT9.js";if(!import.meta.resolve)throw Error("import.meta.resolve not supported")';export function __vite_legacy_guard(){import.meta.url,import(`_`).catch(()=>1),(async function*(){})().next()}(function(){let e=document.createElement(`link`).relList;if(e&&e.supports&&e.supports(`modulepreload`))return;for(let e of document.querySelectorAll(`link[rel="modulepreload"]`))n(e);new MutationObserver(e=>{for(let t of e)if(t.type===`childList`)for(let e of t.addedNodes)e.tagName===`LINK`&&e.rel===`modulepreload`&&n(e)}).observe(document,{childList:!0,subtree:!0});function t(e){let t={};return e.integrity&&(t.integrity=e.integrity),e.referrerPolicy&&(t.referrerPolicy=e.referrerPolicy),t.credentials=e.crossOrigin===`use-credentials`?`include`:e.crossOrigin===`anonymous`?`omit`:`same-origin`,t}function n(e){if(e.ep)return;e.ep=!0;let n=t(e);fetch(e.href,n)}})();var e=null,t=0,n=new Map;function r(){return e||(e=new Worker(new URL(`/assets/worker-CIJRdaPR.js`,``+import.meta.url)),e.addEventListener(`message`,e=>{let{id:t,result:r,error:i}=e.data,a=n.get(t);a&&(n.delete(t),i?a.reject(Error(i.message)):a.resolve(r))})),e}function i(){function e(e){return new Promise((i,a)=>{let o=t++;n.set(o,{resolve:i,reject:a}),r().postMessage({id:o,dslSource:e})})}return{solve:e}}var a=null,o=null;function s(){let e=window.Chart;if(!e)throw Error(`Chart.js not loaded. Check CDN connection.`);return e}var c={responsive:!0,maintainAspectRatio:!1,animation:{duration:400},interaction:{mode:`index`,intersect:!1},plugins:{legend:{position:`top`,labels:{usePointStyle:!0,boxWidth:8,font:{size:12},onClick:function(e,t){let n=e.datasetIndex,r=t.chart;r.isDatasetVisible(n)?(r.hide(n),e.hidden=!0):(r.show(n),e.hidden=!1)}}},tooltip:{backgroundColor:`rgba(15, 23, 42, 0.9)`,padding:12,cornerRadius:8,titleFont:{size:13},bodyFont:{size:12}}},scales:{x:{grid:{color:`#f1f5f9`},title:{display:!0,text:`Time (s)`,color:`#64748b`,font:{size:12,weight:`bold`}}},y:{grid:{color:`#f1f5f9`},title:{display:!0,color:`#64748b`,font:{size:12,weight:`bold`}}}}};function l(e){let{editor:t,errorBox:n,okBox:r,summaryBox:i,chartsContainer:l,statusBox:u,stateCanvas:d,controlCanvas:f}=e,p=s();a=new p(d.getContext(`2d`),{type:`line`,data:{labels:[],datasets:[]},options:{...c,scales:{...c.scales,y:{...c.scales.y,title:{display:!0,text:`State`}}}}}),o=new p(f.getContext(`2d`),{type:`line`,data:{labels:[],datasets:[]},options:{...c,scales:{...c.scales,y:{...c.scales.y,title:{display:!0,text:`Control`}}}}});function m(e){if(l.style.display=`none`,n.style.display=`none`,r.style.display=`none`,i.style.display=`none`,u.style.display=`none`,e.status===`error`){u.className=`status-bar error`,u.textContent=`[${e.stage?.toUpperCase()}] ${e.message}`,u.style.display=`block`;return}let t=e.result,s=t.states[t.steps].map(e=>e.toFixed(3)).join(`, `);i.innerHTML=`
      <span><strong>Steps:</strong> ${t.steps}</span>
      <span><strong>dt:</strong> ${t.dt}</span>
      <span><strong>Final State:</strong> [${s}]</span>
    `,i.style.display=`flex`,u.className=`status-bar success`,u.textContent=`Solved "${e.problem_name}" successfully.`,u.style.display=`block`,l.style.display=`block`;let c=t.time.map(e=>e.toFixed(2)),d=t.states.map(e=>e[0]),f=t.states.length>0&&t.states[0].length>1?t.states.map(e=>e[1]):[],p=t.controls.map(e=>e[0]);a.data={labels:c,datasets:[{label:`x (position)`,data:d,borderColor:`#2563eb`,backgroundColor:`#2563eb22`,borderWidth:2,pointRadius:0,tension:.3},...f.length>0?[{label:`v (velocity)`,data:f,borderColor:`#10b981`,backgroundColor:`#10b98122`,borderWidth:2,pointRadius:0,tension:.3}]:[]]},a.update(),o.data={labels:c,datasets:[{label:`u (control)`,data:p,borderColor:`#f59e0b`,backgroundColor:`#f59e0b22`,borderWidth:2,pointRadius:0,tension:.1}]},o.update()}return{renderResults:m,getValue:()=>t.getValue(),setValue:e=>t.setValue(e)}}window.CodeMirror.defineSimpleMode(`control-dsl`,{start:[{regex:/#.*$/,token:`comment`},{regex:/\/\/.*$/,token:`comment`},{regex:/\b(problem|end_problem|state|control|parameter|horizon|dynamics|end_dynamics|initial|end_initial|target|end_target|bounds|end_bounds|cost|end_cost|solve|end_solve|method|grid|controls|in)\b/,token:`keyword`},{regex:/[a-zA-Z_][a-zA-Z0-9_]*'/,token:`variable-2`},{regex:/[a-zA-Z_][a-zA-Z0-9_]*/,token:`variable`},{regex:/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/,token:`number`},{regex:/[+\-*/^=,:\[\]()]/,token:`operator`},{regex:/".*?"/,token:`string`}]});var u={doubleIntegrator:`problem DoubleIntegrator
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
end_problem`,simpleIntegrator:`problem SimpleIntegrator
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
end_problem`,invalidDsl:`problem InvalidExample
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
end_problem`};document.addEventListener(`DOMContentLoaded`,()=>{let e=document.getElementById(`dsl`),t=window.CodeMirror.fromTextArea(e,{mode:`control-dsl`,theme:`one-dark`,lineNumbers:!0,indentUnit:2,lineWrapping:!0});t.setValue(u.doubleIntegrator);let n=document.getElementById(`solve`),r=document.getElementById(`download-csv`),a=document.getElementById(`status`),o=document.getElementById(`error`),s=document.getElementById(`ok`),c=document.getElementById(`summary`),d=document.getElementById(`charts`),f=document.getElementById(`error-toast`),p;function m(e,t=`error`){f.textContent=e,f.className=`toast ${t}-toast show`,clearTimeout(p),p=window.setTimeout(()=>{f.classList.remove(`show`)},6e3)}let{solve:h}=i(),g=l({editor:t,errorBox:o,okBox:s,summaryBox:c,chartsContainer:d,statusBox:a,stateCanvas:document.getElementById(`stateChart`),controlCanvas:document.getElementById(`controlChart`)});document.querySelectorAll(`.preset-btn`).forEach(e=>{e.addEventListener(`click`,()=>{let n=e.dataset.preset;n&&u[n]&&(t.setValue(u[n]),m(`Loaded preset: ${n}`,`success`),o.style.display=`none`,s.style.display=`none`,c.style.display=`none`,d.style.display=`none`,r.style.display=`none`)})}),r.addEventListener(`click`,()=>{let e=window.__lastSolveResult;if(!e||e.status!==`ok`||!e.result)return;let{time:t,states:n,controls:r}=e.result,i=`time,${n[0].map((e,t)=>`state_${t}`).join(`,`)},${r[0].map((e,t)=>`control_${t}`).join(`,`)}\n`;for(let e=0;e<t.length;e++){let a=n[e]?n[e].join(`,`):``,o=r[e]?r[e].join(`,`):``;i+=`${t[e]},${a},${o}\n`}let a=new Blob([i],{type:`text/csv`}),o=window.URL.createObjectURL(a),s=document.createElement(`a`);s.href=o,s.download=`trajectory_${e.problem_name||`export`}.csv`,s.click(),window.URL.revokeObjectURL(o)}),n.addEventListener(`click`,async()=>{n.disabled=!0,n.innerHTML=`<span class="spinner"></span> Solving…`,a.style.display=`none`,o.style.display=`none`,s.style.display=`none`,c.style.display=`none`,d.style.display=`none`,r.style.display=`none`,f.classList.remove(`show`);try{let e=await h(t.getValue());window.__lastSolveResult=e,g.renderResults(e),e.status===`ok`&&e.result?r.style.display=`inline-flex`:e.status===`error`&&m(`Solver Error: ${e.message}`,`error`)}catch(e){let t=e instanceof Error?e.message:String(e);m(`Fatal Error: ${t}`,`error`),a.className=`status-bar error`,a.textContent=`Fatal Error: `+t,a.style.display=`block`}finally{n.disabled=!1,n.textContent=`Solve`}})});
//# sourceMappingURL=index-DDvl_kT9.js.map