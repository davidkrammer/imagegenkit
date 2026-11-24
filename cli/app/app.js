"use strict";
/* ImageGenKit app (Windows): talks to imagegenkit_app.py on 127.0.0.1. */

const T = window.IGK_TOKEN;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const S = { state: null, log: [], view: "overview", tab: "providers", metric: "images", gen: null, local: null, openProv: null };
const COLORS = ["#4a7bdc", "#e0703f", "#4caf7a", "#d9689a", "#8a6cdc", "#d4a72c", "#3fa7b5", "#9a8f84", "#c95353", "#6a8f3a"];
const FIXED = { openai: "#4a7bdc", grok: "#e0703f", gemini: "#4caf7a", openrouter: "#d9689a", codex: "#3fa7b5", local: "#8a6cdc", xai: "#c95353" };

// ---------- api ----------
async function api(path, body, opts = {}) {
  const init = { method: body === undefined ? "GET" : "POST", headers: { "X-IGK-Token": T } };
  if (body !== undefined) {
    if (body instanceof Blob) { init.body = body; init.headers["X-Filename"] = encodeURIComponent(opts.filename || "image.png"); }
    else { init.body = JSON.stringify(body); init.headers["Content-Type"] = "application/json"; }
  }
  const r = await fetch(path, init);
  let data = null;
  try { data = await r.json(); } catch (e) { /* empty */ }
  if (!r.ok || (data && data.error)) throw new Error((data && data.error) || `HTTP ${r.status}`);
  return data;
}
const fileUrl = (p) => `/file?t=${encodeURIComponent(T)}&path=${encodeURIComponent(p)}`;

function toast(msg, err = false) {
  const t = $("#toast");
  t.textContent = msg; t.className = "toast" + (err ? " err" : "");
  clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.add("hidden"), err ? 6000 : 2800);
}
function esc(s) { return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function h(html) { const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content.firstElementChild; }
const money = (v) => "$" + (v || 0).toFixed(v && v < 1 ? (v < 0.1 ? 3 : 2) : 2);
const icon = {
  spark: '<svg viewBox="0 0 24 24"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/></svg>',
  dollar: '<svg viewBox="0 0 24 24"><path d="M12 3v18M16.5 7.5c0-1.7-2-3-4.5-3s-4.5 1.3-4.5 3 2 2.6 4.5 3 4.5 1.3 4.5 3.2-2 3-4.5 3-4.5-1.3-4.5-3"/></svg>',
  image: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="M4 18l5-5 4 4 3-3 4 4"/></svg>',
  bolt: '<svg viewBox="0 0 24 24"><path d="M13 3L5 13h6l-1 8 8-10h-6z"/></svg>',
  clock: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  open: '<svg viewBox="0 0 24 24"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>',
  folder: '<svg viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
  copy: '<svg viewBox="0 0 24 24"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg>',
  ref: '<svg viewBox="0 0 24 24"><path d="M9 14l-5-5 5-5"/><path d="M4 9h10a6 6 0 0 1 0 12h-2"/></svg>',
  x: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  layers: '<svg viewBox="0 0 24 24"><path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/></svg>',
  chart: '<svg viewBox="0 0 24 24"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
  box: '<svg viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
  up: '<svg viewBox="0 0 24 24"><path d="M6 15l6-6 6 6"/></svg>',
  down: '<svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
  chev: '<svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>',
};

// ---------- data ----------
async function loadAll() {
  const [state, log] = await Promise.all([api("/api/state"), api("/api/log")]);
  S.state = state; S.log = log;
  renderChrome();
  render();
}
async function reloadState() { S.state = await api("/api/state"); renderChrome(); }

function provLabel(name) { const p = (S.state?.providers || []).find((x) => x.name === name); return p ? p.label : name; }
function provColor(name) {
  if (FIXED[name]) return FIXED[name];
  const names = [...new Set(S.log.map((e) => e.provider))].sort();
  return COLORS[(names.indexOf(name) + 3) % COLORS.length];
}
function filtered() {
  const prov = $("#f-provider").value, days = +$("#f-range").value, q = $("#f-search").value.trim().toLowerCase();
  const since = days ? Date.now() - days * 864e5 : 0;
  return S.log.filter((e) => (!prov || e.provider === prov) && (!since || new Date(e.ts).getTime() >= since) &&
    (!q || (e.prompt || "").toLowerCase().includes(q) || (e.model || "").toLowerCase().includes(q)));
}
function isFree(e) { return ["grok-build", "codex-cli", "local"].includes(e.type) || e.provider === "grok"; }
function thumbFor(e, i = 0) {
  const t = (e.thumbs || [])[i], o = (e.outputs || [])[i];
  if (e.exists && e.exists[i] === false) return t || null;
  return t || o || null;
}
function project(e) { const c = (e.cwd || "").replace(/[\\/]+$/, ""); return c ? c.split(/[\\/]/).pop() : "—"; }
function dayKey(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
function dayLabel(key) {
  const d = new Date(key + "T12:00:00"), today = dayKey(new Date()), y = new Date(); y.setDate(y.getDate() - 1);
  if (key === today) return "Today";
  if (key === dayKey(y)) return "Yesterday";
  const diff = (Date.now() - d) / 864e5;
  return d.toLocaleDateString(undefined, diff < 7 ? { weekday: "long" } : { weekday: "short", month: "short", day: "numeric", year: d.getFullYear() !== new Date().getFullYear() ? "numeric" : undefined });
}

// ---------- chrome ----------
function renderChrome() {
  const st = S.state;
  const ready = st.providers.filter((p) => p.ready).length;
  $("#ready-line").innerHTML = `<span class="dot ${ready ? "ok" : "bad"}"></span><span>${ready ? `${ready} provider${ready > 1 ? "s" : ""} ready` : "No provider ready"}</span>`;
  const sel = $("#f-provider"), cur = sel.value;
  const names = [...new Set(S.log.map((e) => e.provider))];
  sel.innerHTML = '<option value="">All Providers</option>' + names.map((n) => `<option value="${esc(n)}">${esc(provLabel(n))}</option>`).join("");
  sel.value = names.includes(cur) ? cur : "";
  $('[data-tab="local"]').textContent = "On " + st.device;
}

function setView(v) {
  S.view = v;
  $$(".nav").forEach((b) => b.classList.toggle("active", b.dataset.view === v));
  $$(".view").forEach((s) => s.classList.toggle("active", s.id === "view-" + v));
  $("#view-title").textContent = { overview: "Overview", gallery: "Gallery", history: "History", settings: "Settings" }[v];
  $("#filters").classList.toggle("hidden", v === "settings");
  $("#f-search").classList.toggle("hidden", v === "overview");
  render();
}

function render() {
  if (!S.state) return;
  ({ overview: renderOverview, gallery: renderGallery, history: renderHistory, settings: renderSettings })[S.view]();
}

// ---------- overview ----------
function renderOverview() {
  const el = $("#view-overview"), list = filtered(), days = +$("#f-range").value;
  $("#view-sub").textContent = "";
  if (!S.log.length) { el.innerHTML = emptyState(); bindEmpty(el); return; }
  const imgs = list.reduce((a, e) => a + (e.outputs || []).length, 0);
  const paid = list.filter((e) => !isFree(e)).reduce((a, e) => a + (e.outputs || []).length, 0);
  const spend = list.reduce((a, e) => a + (e.cost || 0), 0);
  const secs = list.filter((e) => e.seconds).map((e) => e.seconds);
  const avg = secs.length ? secs.reduce((a, b) => a + b, 0) / secs.length : 0;
  const byProv = {}, byProj = {};
  for (const e of list) {
    const p = (byProv[e.provider] ||= { images: 0, spend: 0, free: isFree(e) });
    p.images += (e.outputs || []).length; p.spend += e.cost || 0;
    const j = (byProj[project(e)] ||= { images: 0, spend: 0 });
    j.images += (e.outputs || []).length; j.spend += e.cost || 0;
  }
  const top = Object.entries(byProv).sort((a, b) => b[1].images - a[1].images);
  const projects = Object.entries(byProj).sort((a, b) => b[1].images - a[1].images).slice(0, 8);
  const recent = list.filter((e) => thumbFor(e)).slice(0, 4);
  const rangeTxt = days ? (days === 365 ? "Last 12 months" : `Last ${days} days`) : "All time";
  el.innerHTML = `
  <div class="grid">
    <div class="card hero">
      <div><h2>${rangeTxt}</h2><div class="sub">${top.length ? "Mostly " + esc(provLabel(top[0][0])) : "Nothing yet"} · ${projects.length} project${projects.length === 1 ? "" : "s"}</div></div>
      <div class="hero-stack">${recent.map((e, i) => `<img src="${fileUrl(thumbFor(e))}" style="--r:${[-6, 3, -2, 5][i]}deg" alt="">`).join("")}</div>
    </div>
    <div class="grid cols-4">
      ${stat(icon.dollar, "Spend", money(spend), "")}
      ${stat(icon.image, "Images", imgs, paid ? `${paid} paid` : "")}
      ${stat(icon.bolt, "Runs", list.length, "")}
      ${stat(icon.clock, "Avg. time", avg ? `${Math.round(avg)} s` : "—", "")}
    </div>
    <div class="card">
      <div class="row" style="margin-bottom:8px"><h2 style="margin:0">${icon.chart} Activity</h2><div class="grow"></div>
        <div class="legend">${top.map(([n]) => `<span><i class="dot" style="background:${provColor(n)}"></i>${esc(provLabel(n))}</span>`).join("")}</div>
        <div class="seg" id="metric"><button data-m="images" class="${S.metric === "images" ? "on" : ""}">Images</button><button data-m="spend" class="${S.metric === "spend" ? "on" : ""}">Spend</button></div>
      </div>
      <div class="chart" id="chart"></div>
    </div>
    <div class="grid cols-2">
      <div class="card"><table class="bars-table"><tr><th><h2 style="margin:0">${icon.layers} Providers</h2></th><th>Images</th><th>Spend</th></tr>
        ${top.map(([n, v]) => barRow(provLabel(n), v.images, v.free && !v.spend ? "Plan" : money(v.spend), v.images / (top[0][1].images || 1), provColor(n))).join("")}
      </table></div>
      <div class="card"><table class="bars-table"><tr><th><h2 style="margin:0">${icon.box} Projects</h2></th><th>Images</th><th>Spend</th></tr>
        ${projects.map(([n, v]) => barRow(n, v.images, money(v.spend), v.images / (projects[0][1].images || 1), "var(--text)")).join("")}
      </table></div>
    </div>
    ${limitCard()}
  </div>`;
  $$("#metric button", el).forEach((b) => b.onclick = () => { S.metric = b.dataset.m; renderOverview(); });
  drawChart($("#chart", el), list, days || 90);
}
function stat(ic, label, value, small) {
  return `<div class="card stat"><div class="label"><span class="ico">${ic}</span>${label}</div><div class="value">${esc(value)}${small ? `<small>${esc(small)}</small>` : ""}</div></div>`;
}
function barRow(name, images, spend, frac, color) {
  return `<tr><td>${esc(name)}</td><td class="num">${images}</td><td class="num muted">${esc(spend)}</td></tr>
  <tr><td colspan="3"><div class="bar"><i style="width:${Math.max(2, frac * 100)}%;background:${color}"></i></div></td></tr>`;
}
function limitCard() {
  const L = S.state.limits, U = S.state.usage;
  if (!L.monthly_cost && !L.monthly_images) return "";
  const parts = [];
  if (L.monthly_cost) parts.push(limitBar("Spend this month", U.cost / L.monthly_cost, `${money(U.cost)} of ${money(L.monthly_cost)}`));
  if (L.monthly_images) parts.push(limitBar("Images this month", U.images / L.monthly_images, `${U.images} of ${L.monthly_images}`));
  return `<div class="card"><h2>Monthly limits</h2><div class="grid cols-2">${parts.join("")}</div>
    <div class="small muted" style="margin-top:8px">${L.stop_paid ? "When a limit is reached, paid images pause until next month. Subscriptions keep working." : "Limits only warn."}</div></div>`;
}
function limitBar(label, frac, txt) {
  const color = frac >= 1 ? "var(--bad)" : frac >= 0.8 ? "var(--warn)" : "var(--ok)";
  return `<div><div class="row"><span>${label}</span><span class="grow"></span><span class="muted">${txt}</span></div>
    <div class="bar" style="height:6px;margin-top:6px"><i style="width:${Math.min(100, frac * 100)}%;background:${color}"></i></div></div>`;
}
function drawChart(box, list, days) {
  const n = Math.min(days, 120), start = new Date(); start.setHours(0, 0, 0, 0); start.setDate(start.getDate() - n + 1);
  const keys = [...Array(n)].map((_, i) => { const d = new Date(start); d.setDate(d.getDate() + i); return dayKey(d); });
  const data = Object.fromEntries(keys.map((k) => [k, {}]));
  for (const e of list) {
    const k = dayKey(new Date(e.ts));
    if (!data[k]) continue;
    data[k][e.provider] = (data[k][e.provider] || 0) + (S.metric === "spend" ? e.cost || 0 : (e.outputs || []).length);
  }
  const totals = keys.map((k) => Object.values(data[k]).reduce((a, b) => a + b, 0));
  const max = Math.max(...totals, S.metric === "spend" ? 0.01 : 1);
  const W = 1000, H = 240, pl = 34, pb = 24, bw = (W - pl) / n;
  const nice = niceMax(max), ticks = [0, nice / 3, (2 * nice) / 3, nice];
  let s = `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">`;
  for (const t of ticks) {
    const y = H - pb - (t / nice) * (H - pb - 10);
    s += `<line x1="${pl}" x2="${W}" y1="${y}" y2="${y}" stroke="var(--line)" stroke-dasharray="3 4" stroke-width="1"/>`;
    s += `<text x="0" y="${y + 4}" font-size="11" fill="var(--faint)">${S.metric === "spend" ? "$" + t.toFixed(t < 1 ? 2 : 0) : Math.round(t)}</text>`;
  }
  keys.forEach((k, i) => {
    let y = H - pb;
    const x = pl + i * bw + bw * 0.18, w = Math.max(1, bw * 0.64);
    for (const [p, v] of Object.entries(data[k]).sort()) {
      const hgt = (v / nice) * (H - pb - 10);
      y -= hgt;
      s += `<rect x="${x}" y="${y}" width="${w}" height="${hgt}" rx="2" fill="${provColor(p)}" opacity=".75"/>`;
    }
    s += `<rect class="hit" data-i="${i}" x="${pl + i * bw}" y="0" width="${bw}" height="${H - pb}" fill="transparent"/>`;
    if (i % Math.ceil(n / 6) === 0) s += `<text x="${x}" y="${H - 6}" font-size="11" fill="var(--faint)">${new Date(k + "T12:00").toLocaleDateString(undefined, { month: "short", day: "numeric" })}</text>`;
  });
  box.innerHTML = s + "</svg>";
  const tip = h('<div class="tip hidden"></div>'); box.appendChild(tip);
  box.querySelectorAll(".hit").forEach((r) => {
    r.addEventListener("mouseenter", () => {
      const k = keys[+r.dataset.i], entries = Object.entries(data[k]);
      if (!entries.length) { tip.classList.add("hidden"); return; }
      tip.innerHTML = `<b>${new Date(k + "T12:00").toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}</b>` +
        entries.map(([p, v]) => `<div class="row" style="gap:6px"><i class="dot" style="background:${provColor(p)}"></i>${esc(provLabel(p))}<span class="grow"></span>${S.metric === "spend" ? money(v) : v}</div>`).join("");
      tip.classList.remove("hidden");
      const bx = box.getBoundingClientRect(), rx = r.getBoundingClientRect();
      tip.style.left = Math.min(bx.width - 160, Math.max(0, rx.left - bx.left - 40)) + "px"; tip.style.top = "0px";
    });
    r.addEventListener("mouseleave", () => tip.classList.add("hidden"));
  });
}
function niceMax(v) { const p = Math.pow(10, Math.floor(Math.log10(v))); for (const m of [1, 1.5, 2, 3, 5, 10]) if (m * p >= v) return m * p; return 10 * p; }

function emptyState() {
  const ready = S.state.providers.some((p) => p.ready);
  return `<div class="empty"><img src="/static/icon.svg" width="72" alt=""><h2>Welcome to ImageGenKit</h2>
  <p>${ready ? "You're set up. Make your first image." : "Connect a provider first: a ChatGPT or Grok subscription, an API key, or a free model that runs on " + esc(S.state.device) + "."}</p>
  <div class="row" style="justify-content:center">${ready ? '<button class="btn primary" data-go="generate">' + icon.spark + "Generate</button>" : '<button class="btn primary" data-go="providers">Connect a provider</button>'}</div></div>`;
}
function bindEmpty(el) {
  $$("[data-go]", el).forEach((b) => b.onclick = () => b.dataset.go === "generate" ? openGenerate() : (S.tab = "providers", setView("settings")));
}

// ---------- gallery & history ----------
function renderGallery() {
  const el = $("#view-gallery"), list = filtered().filter((e) => (e.outputs || []).length);
  const count = list.reduce((a, e) => a + e.outputs.length, 0);
  $("#view-sub").textContent = `${count} image${count === 1 ? "" : "s"}`;
  if (!list.length) { el.innerHTML = S.log.length ? '<div class="empty">No images match.</div>' : emptyState(); bindEmpty(el); return; }
  const days = {};
  for (const e of list) (days[dayKey(new Date(e.ts))] ||= []).push(e);
  el.innerHTML = Object.entries(days).map(([k, es]) => `<div class="day"><h3>${dayLabel(k)}<small>${es.reduce((a, e) => a + e.outputs.length, 0)}</small></h3>
    <div class="thumbs">${es.flatMap((e) => e.outputs.map((_, i) => {
      const t = thumbFor(e, i);
      return `<div class="thumb ${e.params?.background === "transparent" ? "checker" : ""}" data-id="${e._id}" data-i="${i}" title="${esc(e.prompt)}">${t ? `<img loading="lazy" src="${fileUrl(t)}" alt="">` : '<div class="gone">file deleted</div>'}<span class="badge">${esc(provLabel(e.provider))}</span></div>`;
    })).join("")}</div></div>`).join("");
  $$(".thumb", el).forEach((t) => t.onclick = () => openDetail(+t.dataset.id, +t.dataset.i));
}

function renderHistory() {
  const el = $("#view-history"), list = filtered();
  $("#view-sub").textContent = `${list.length} run${list.length === 1 ? "" : "s"}`;
  if (!list.length) { el.innerHTML = S.log.length ? '<div class="empty">Nothing matches.</div>' : emptyState(); bindEmpty(el); return; }
  el.innerHTML = `<table class="list"><tr><th></th><th>Prompt</th><th>Provider</th><th>Task</th><th>Who</th><th>Project</th><th style="text-align:right">Cost</th><th>When</th></tr>
    ${list.slice(0, 500).map((e) => { const t = thumbFor(e); return `<tr class="click" data-id="${e._id}">
      <td>${t ? `<img loading="lazy" src="${fileUrl(t)}" alt="">` : ""}</td>
      <td><div class="clip">${esc(e.prompt)}</div><div class="small faint">${esc(e.model || "")}</div></td>
      <td><span class="chip"><i class="dot" style="background:${provColor(e.provider)}"></i>${esc(provLabel(e.provider))}</span></td>
      <td class="muted">${esc(e.task || "direct")}</td><td class="muted">${esc(e.caller?.agent || "")}</td>
      <td class="muted">${esc(project(e))}</td>
      <td style="text-align:right">${isFree(e) && !e.cost ? '<span class="muted">Plan</span>' : money(e.cost)}</td>
      <td class="muted small">${new Date(e.ts).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })}</td></tr>`; }).join("")}
  </table>${list.length > 500 ? '<p class="muted small">Showing the latest 500.</p>' : ""}`;
  $$("tr.click", el).forEach((r) => r.onclick = () => openDetail(+r.dataset.id, 0));
}

// ---------- modals ----------
function modal(html, onClose) {
  const back = h(`<div class="modal-back"><div class="modal">${html}</div></div>`);
  const close = () => { back.remove(); document.removeEventListener("keydown", key); onClose && onClose(); };
  const key = (ev) => { if (ev.key === "Escape") close(); };
  back.addEventListener("mousedown", (ev) => { if (ev.target === back) close(); });
  document.addEventListener("keydown", key);
  $("#modal-root").appendChild(back);
  $$("[data-close]", back).forEach((b) => b.onclick = close);
  return { el: back, close };
}

function openDetail(id, i) {
  const e = S.log.find((x) => x._id === id);
  if (!e) return;
  const out = (e.outputs || [])[i], exists = !e.exists || e.exists[i] !== false, shown = exists ? out : thumbFor(e, i);
  const params = Object.entries(e.params || {}).filter(([, v]) => v !== null && v !== "" && v !== undefined).map(([k, v]) => `${k} ${typeof v === "object" ? JSON.stringify(v) : v}`).join(", ");
  const m = modal(`
    <div class="modal-head"><div class="ico">${icon.image}</div><div><h2>${esc(provLabel(e.provider))}</h2><div class="muted small">${new Date(e.ts).toLocaleString()} · ${esc(e.model || "")}</div></div>
      <button class="btn icon x" data-close>${icon.x}</button></div>
    <div class="modal-body"><div class="detail">
      <div class="big">${shown ? `<img src="${fileUrl(shown)}" class="${e.params?.background === "transparent" ? "checker" : ""}" alt="">` : '<div class="empty">The file was deleted.</div>'}
        <div class="row">${exists && out ? `<button class="btn small" data-a="open">${icon.open}Open</button><button class="btn small" data-a="reveal">${icon.folder}Show in folder</button>` : ""}
          <button class="btn small" data-a="copy">${icon.copy}Copy prompt</button>${exists && out ? `<button class="btn small" data-a="ref">${icon.ref}Use as reference</button>` : ""}</div>
        ${(e.outputs || []).length > 1 ? `<div class="row">${e.outputs.map((_, j) => `<button class="btn small ${j === i ? "primary" : ""}" data-j="${j}">${j + 1}</button>`).join("")}</div>` : ""}
      </div>
      <div class="field"><div class="prompt-box">${esc(e.prompt)}</div>
        <dl class="kv">
          <dt>Provider</dt><dd>${esc(provLabel(e.provider))}</dd><dt>Model</dt><dd>${esc(e.model || "—")}</dd>
          <dt>Task</dt><dd>${esc(e.task || "direct")}</dd><dt>Cost</dt><dd>${isFree(e) && !e.cost ? "Included in plan / free" : money(e.cost)}</dd>
          <dt>Time</dt><dd>${e.seconds ? e.seconds + " s" : "—"}</dd><dt>Made by</dt><dd>${esc(e.caller?.agent || "—")}</dd>
          <dt>Project</dt><dd>${esc(e.cwd || "—")}</dd>${params ? `<dt>Settings</dt><dd class="small">${esc(params)}</dd>` : ""}
          ${(e.refs || []).length ? `<dt>References</dt><dd>${e.refs.map((r) => `<img src="${fileUrl(r)}" style="width:48px;height:48px;object-fit:cover;border-radius:6px;margin-right:4px" alt="">`).join("")}</dd>` : ""}
          <dt>File</dt><dd class="mono small">${esc(out || "")}</dd>
        </dl></div>
    </div></div>
    <div class="modal-foot"><button class="btn" data-a="edit">Edit prompt</button><button class="btn primary" data-a="again">${icon.spark}Generate again</button></div>`);
  const act = async (a) => {
    try {
      if (a === "open") await api("/api/open", { path: out });
      if (a === "reveal") await api("/api/reveal", { path: out });
      if (a === "copy") { await navigator.clipboard.writeText(e.prompt || ""); toast("Prompt copied"); }
      if (a === "ref") { m.close(); openGenerate({ refs: [out] }); }
      if (a === "edit" || a === "again") {
        m.close();
        const target = e.task || e.provider;
        const g = { prompt: e.prompt, target, refs: (e.refs || []).filter(Boolean), aspect: e.params?.aspect || "" };
        openGenerate(g, a === "again");
      }
    } catch (err) { toast(err.message, true); }
  };
  $$("[data-a]", m.el).forEach((b) => b.onclick = () => act(b.dataset.a));
  $$("[data-j]", m.el).forEach((b) => b.onclick = () => { m.close(); openDetail(id, +b.dataset.j); });
}

// ---------- generate ----------
const ASPECTS = ["", "1:1", "4:5", "3:4", "2:3", "16:9", "9:16", "3:2", "21:9"];
function openGenerate(init = {}, autoRun = false) {
  const st = S.state;
  const g = S.gen = { prompt: "", target: "draft", refs: [], aspect: "", n: 1, quality: "", resolution: "", background: "", ...init, job: null };
  const targets = Object.keys(st.task_info).map((t) => [t, `${t[0].toUpperCase() + t.slice(1)} (${provLabel(st.tasks[t]?.provider || "?")})`])
    .concat(st.providers.map((p) => [p.name, p.label + (p.ready ? "" : " — not set up")]));
  const m = modal(`
    <div class="modal-head"><div class="ico">${icon.spark}</div><div><h2>Generate <span id="g-pill"></span></h2><div class="muted small" id="g-sub">Pick a task to use your settings, or a provider directly.</div></div>
      <button class="btn icon x" data-close>${icon.x}</button></div>
    <div class="modal-body">
      <div class="field"><textarea id="g-prompt" rows="4" placeholder="Describe the image: subject, setting, style, composition, light.">${esc(g.prompt)}</textarea></div>
      <div class="field"><label>References (optional: edit or combine images)</label><div class="refs" id="g-refs"></div></div>
      <div class="opts">
        <div class="field"><label>Use</label><select id="g-target">${targets.map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join("")}</select></div>
        <div class="field"><label>Aspect</label><select id="g-aspect">${ASPECTS.map((a) => `<option value="${a}">${a || "Auto"}</option>`).join("")}</select></div>
        <div class="field"><label>Images</label><select id="g-n">${[1, 2, 3, 4].map((n) => `<option>${n}</option>`).join("")}</select></div>
        <div class="field"><label>Quality</label><select id="g-quality"><option value="">Default</option><option>low</option><option>medium</option><option>high</option></select></div>
        <div class="field"><label>Resolution</label><select id="g-res"><option value="">Default</option><option>1K</option><option>2K</option><option>4K</option></select></div>
        <div class="field"><label>Background</label><select id="g-bg"><option value="">Default</option><option value="transparent">Transparent</option><option value="opaque">Opaque</option></select></div>
      </div>
      <div class="stage hidden" id="g-stage"></div>
    </div>
    <div class="modal-foot"><span class="muted small grow" id="g-hint"></span><button class="btn hidden" id="g-cancel">Stop</button><button class="btn primary" id="g-run">${icon.spark}Generate</button></div>`,
    () => { if (g.job && g.timer) clearInterval(g.timer); });
  const el = m.el;
  $("#g-target", el).value = targets.some(([v]) => v === g.target) ? g.target : "draft";
  $("#g-aspect", el).value = ASPECTS.includes(g.aspect) ? g.aspect : "";
  const drawRefs = () => {
    const box = $("#g-refs", el);
    box.innerHTML = g.refs.map((r, i) => `<div class="ref"><img src="${fileUrl(r)}" alt=""><button data-rm="${i}" title="Remove">×</button></div>`).join("") +
      '<label class="drop" id="g-drop">Drop or click to add<input type="file" accept="image/*" multiple hidden></label>';
    $$("[data-rm]", box).forEach((b) => b.onclick = () => { g.refs.splice(+b.dataset.rm, 1); drawRefs(); });
    const drop = $("#g-drop", box), input = $("input", drop);
    input.onchange = () => upload([...input.files]);
    drop.ondragover = (ev) => { ev.preventDefault(); drop.classList.add("over"); };
    drop.ondragleave = () => drop.classList.remove("over");
    drop.ondrop = (ev) => { ev.preventDefault(); drop.classList.remove("over"); upload([...ev.dataTransfer.files]); };
  };
  const upload = async (files) => {
    for (const f of files.filter((f) => f.type.startsWith("image/"))) {
      try { g.refs.push((await api("/api/upload", f, { filename: f.name })).path); } catch (err) { toast(err.message, true); }
    }
    drawRefs();
  };
  el.addEventListener("paste", (ev) => { const fs = [...(ev.clipboardData?.files || [])]; if (fs.length) { ev.preventDefault(); upload(fs); } });
  drawRefs();
  const hint = () => {
    const t = $("#g-target", el).value, task = st.task_info[t];
    $("#g-hint", el).textContent = task ? task : (st.providers.find((p) => p.name === t)?.status || "");
  };
  $("#g-target", el).onchange = hint; hint();
  $("#g-run", el).onclick = () => run();
  $("#g-cancel", el).onclick = async () => { if (g.job) await api(`/api/jobs/${g.job}/cancel`, {}); };
  $("#g-prompt", el).addEventListener("keydown", (ev) => { if (ev.key === "Enter" && (ev.ctrlKey || ev.metaKey)) run(); });
  $("#g-prompt", el).focus();

  async function run() {
    const body = { prompt: $("#g-prompt", el).value, target: $("#g-target", el).value, refs: g.refs, aspect: $("#g-aspect", el).value,
      n: +$("#g-n", el).value, quality: $("#g-quality", el).value, resolution: $("#g-res", el).value, background: $("#g-bg", el).value };
    if (body.target === "edit" && !body.refs.length) { toast("Edit needs a reference image.", true); return; }
    const stage = $("#g-stage", el);
    stage.classList.remove("hidden");
    stage.innerHTML = '<div class="log" id="g-log"><span class="spinner"></span> Starting…</div>';
    $("#g-run", el).disabled = true; $("#g-cancel", el).classList.remove("hidden");
    $("#g-pill", el).innerHTML = '<span class="status-pill"><span class="spinner"></span>Working</span>';
    try {
      const job = await api("/api/generate", body);
      g.job = job.id;
      g.timer = setInterval(() => poll(job.id), 900);
    } catch (err) { finish({ status: "failed", lines: [err.message], outputs: [] }); }
  }
  async function poll(id) {
    let j;
    try { j = await api(`/api/jobs/${id}`); } catch (err) { return; }
    const logEl = $("#g-log", el);
    if (logEl) logEl.textContent = j.lines.slice(-8).join("\n") || "Working…";
    $("#g-sub", el).textContent = `${j.seconds} s`;
    if (j.status !== "running") { clearInterval(g.timer); finish(j); }
  }
  async function finish(j) {
    $("#g-run", el).disabled = false; $("#g-cancel", el).classList.add("hidden");
    const ok = j.status === "done" && j.outputs.length;
    $("#g-pill", el).innerHTML = `<span class="status-pill ${ok ? "done" : "failed"}">${ok ? "Done" : j.status === "cancelled" ? "Stopped" : "Failed"}</span>`;
    $("#g-sub", el).textContent = ok ? `${j.outputs.length} image${j.outputs.length > 1 ? "s" : ""} in ${Math.round(j.seconds)} s` : "";
    $("#g-run", el).innerHTML = icon.spark + (ok ? "Generate again" : "Try again");
    const stage = $("#g-stage", el);
    if (!ok) { stage.innerHTML = `<div class="log" style="color:var(--bad)">${esc(j.lines.slice(-6).join("\n") || "Something went wrong.")}</div>`; return; }
    await refreshLog();
    stage.innerHTML = j.outputs.map((p, i) => `<div class="result"><img src="${fileUrl(p)}" alt=""><div class="row">
      <button class="btn small icon" title="Open" data-o="${i}">${icon.open}</button><button class="btn small icon" title="Show in folder" data-r="${i}">${icon.folder}</button>
      <button class="btn small icon" title="Use as reference" data-u="${i}">${icon.ref}</button></div></div>`).join("");
    $$("[data-o]", stage).forEach((b) => b.onclick = () => api("/api/open", { path: j.outputs[+b.dataset.o] }).catch((e) => toast(e.message, true)));
    $$("[data-r]", stage).forEach((b) => b.onclick = () => api("/api/reveal", { path: j.outputs[+b.dataset.r] }).catch((e) => toast(e.message, true)));
    $$("[data-u]", stage).forEach((b) => b.onclick = () => { g.refs = [j.outputs[+b.dataset.u]]; drawRefs(); if ($("#g-target", el).value === "draft") $("#g-target", el).value = "edit"; hint(); });
  }
  if (autoRun) run();
}
async function refreshLog() { S.log = await api("/api/log"); await reloadState(); if (S.view !== "settings") render(); }

// ---------- settings ----------
function renderSettings() {
  $("#view-sub").textContent = "";
  $$(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === S.tab));
  const body = $("#settings-body");
  ({ providers: settingsProviders, images: settingsImages, local: settingsLocal, limits: settingsLimits, agents: settingsAgents, general: settingsGeneral })[S.tab](body);
}

function statusChip(p) {
  const cls = p.ready ? "ok" : (/no API key|not installed|no local model|not logged/.test(p.status) ? "" : "warn");
  return `<span class="chip ${cls}">${p.ready ? "Ready" : esc(p.status)}</span>`;
}

function settingsProviders(body) {
  const st = S.state;
  body.innerHTML = `<div class="grid">${st.providers.map((p) => `
    <div class="card prov" data-p="${esc(p.name)}">
      <div class="prov-row"><span class="dot ${p.ready ? "ok" : ""}"></span><span class="name">${esc(p.label)}</span>
        <span class="muted small clip" style="max-width:380px">${esc(p.tagline || "")}</span><span class="grow"></span>
        ${p.tested === false ? '<span class="chip">Untested</span>' : ""}${statusChip(p)}${icon.chev}</div>
      ${S.openProv === p.name ? `<div class="prov-body">${provBody(p)}</div>` : ""}
    </div>`).join("")}
    <div class="card"><h2>Add an OpenAI-compatible provider</h2>
      <div class="form-grid">
        <label>Name</label><input id="cp-name" type="text" placeholder="my-provider (lowercase, digits, dashes)">
        <label>Label</label><input id="cp-label" type="text" placeholder="Shown in menus (optional)">
        <label>Base URL</label><input id="cp-url" type="url" placeholder="https://api.example.com/v1">
        <label>Model</label><input id="cp-model" type="text" placeholder="model id">
        <label>Edit model</label><input id="cp-edit" type="text" placeholder="optional">
        <span></span><div><button class="btn primary" id="cp-add">Add provider</button></div>
      </div></div></div>`;
  $$(".prov-row", body).forEach((r) => r.onclick = () => { const n = r.parentElement.dataset.p; S.openProv = S.openProv === n ? null : n; settingsProviders(body); });
  $$(".prov-body", body).forEach((b) => bindProvBody(b, st.providers.find((p) => p.name === b.parentElement.dataset.p), body));
  $("#cp-add", body).onclick = async () => {
    try {
      await api("/api/provider", { action: "add", name: $("#cp-name").value.trim(), label: $("#cp-label").value.trim(), base_url: $("#cp-url").value.trim(), model: $("#cp-model").value.trim(), edit_model: $("#cp-edit").value.trim() });
      toast("Provider added. Add its key below."); S.openProv = $("#cp-name").value.trim(); await reloadState(); settingsProviders(body);
    } catch (err) { toast(err.message, true); }
  };
}
function provBody(p) {
  const st = S.state;
  const steps = (p.steps || []).map((s) => `<li>${esc(s.text)} ${s.url ? `<button class="btn small" data-url="${esc(s.url)}">${esc(s.button || "Open")}</button>` : ""}${s.action ? `<button class="btn small" data-term="${esc(s.action)}">${s.action.startsWith("install") ? "Install" : "Log in"} in a terminal</button>` : ""}</li>`).join("");
  let html = `<div class="muted small">${esc(p.price_hint || "")}</div>`;
  if (steps) html += `<ol class="steps">${steps}</ol>`;
  if (p.type === "local") html += `<div><button class="btn" data-go-local>Manage models on ${esc(st.device)}</button></div>`;
  if (p.needs_key) {
    html += `<div class="row"><input type="password" class="grow" data-key placeholder="Paste the ${esc(p.label)} API key" autocomplete="off">
      <button class="btn primary" data-save>Save key</button></div>
      <div class="small muted">Stored in the Windows ${esc(st.key_store)} as <span class="mono">imagegenkit-${esc(p.name)}</span>. ${p.env ? `The environment variable <span class="mono">${esc(p.env)}</span> overrides it.` : ""}</div>`;
  }
  html += `<div class="row"><button class="btn small" data-check>Check now</button>${p.needs_key && p.ready ? '<button class="btn small danger" data-del>Remove key</button>' : ""}
    ${!p.builtin && !["openrouter", "recraft", "together", "fal"].includes(p.name) ? '<button class="btn small danger" data-rmprov>Remove provider</button>' : ""}
    <span class="small muted" data-checkout></span></div>`;
  return html;
}
function bindProvBody(b, p, body) {
  $$("[data-url]", b).forEach((x) => x.onclick = () => api("/api/url", { url: x.dataset.url }));
  $$("[data-term]", b).forEach((x) => x.onclick = async () => {
    try { const r = await api("/api/terminal", { action: x.dataset.term }); toast(`Opened a terminal: ${r.command}. Come back here when it's done.`); } catch (err) { toast(err.message, true); }
  });
  const goLocal = $("[data-go-local]", b); if (goLocal) goLocal.onclick = () => { S.tab = "local"; renderSettings(); };
  const save = $("[data-save]", b);
  if (save) save.onclick = async () => {
    const key = $("[data-key]", b).value.trim();
    if (!key) return;
    save.disabled = true;
    try { const r = await api("/api/key", { provider: p.name, key }); toast(r.message.split("\n").pop() || "Key saved"); await reloadState(); settingsProviders(body); }
    catch (err) { toast(err.message, true); save.disabled = false; }
  };
  const del = $("[data-del]", b);
  if (del) del.onclick = async () => { if (!confirm(`Remove the ${p.label} key from ${S.state.key_store}?`)) return; await api("/api/key/delete", { provider: p.name }); await reloadState(); settingsProviders(body); };
  const rm = $("[data-rmprov]", b);
  if (rm) rm.onclick = async () => { if (!confirm(`Remove ${p.label}?`)) return; try { await api("/api/provider", { action: "remove", name: p.name }); await reloadState(); settingsProviders(body); } catch (err) { toast(err.message, true); } };
  $("[data-check]", b).onclick = async () => {
    const out = $("[data-checkout]", b); out.innerHTML = '<span class="spinner"></span>';
    let html;
    try { const [r] = await api("/api/check", { provider: p.name }); html = `<span class="chip ${r.status === "ok" ? "ok" : r.status === "error" ? "bad" : ""}">${esc(r.status.toUpperCase())}</span> ${esc(r.message)}`; }
    catch (err) { html = esc(err.message); }
    try { await reloadState(); } catch (e) { /* keep the old status */ }
    settingsProviders(body);  // the status chip may have changed (e.g. just installed or logged in)
    const again = $(`[data-p="${CSS.escape(p.name)}"] [data-checkout]`, body);
    if (again) again.innerHTML = html;
  };
}

function settingsImages(body) {
  const st = S.state, provs = st.providers;
  const opt = (sel, list) => list.map(([v, l]) => `<option value="${esc(v)}" ${v === sel ? "selected" : ""}>${esc(l)}</option>`).join("");
  const plist = provs.map((p) => [p.name, p.label + (p.ready ? "" : " (not set up)")]);
  body.innerHTML = `<div class="grid">
    <div class="card"><h2>Use for</h2><p class="muted small" style="margin-top:-6px">Which provider makes each kind of image. If it isn't set up, the next one in the list below is used.</p>
      <div class="form-grid">${Object.entries(st.task_info).map(([t, d]) => `<label title="${esc(d)}">${t[0].toUpperCase() + t.slice(1)}<div class="small faint">${esc(d)}</div></label>
        <select data-task="${t}">${opt(st.tasks[t]?.provider, (t === "transparent" ? plist.filter(([n]) => provs.find((p) => p.name === n).transparent) : plist))}</select>`).join("")}</div></div>
    <div class="card"><h2>Fallback order</h2><ul class="order" id="order">${st.order.map((n, i) => `<li><span class="dot ${provs.find((p) => p.name === n)?.ready ? "ok" : ""}"></span>${esc(provLabel(n))}<span class="grow"></span>
        <button class="btn small icon" data-up="${i}" ${i ? "" : "disabled"}>${icon.up}</button><button class="btn small icon" data-down="${i}" ${i < st.order.length - 1 ? "" : "disabled"}>${icon.down}</button>
        <button class="btn small icon" data-out="${i}" title="Remove from the list">${icon.x}</button></li>`).join("")}</ul>
      <div class="row" style="margin-top:8px"><select id="order-add"><option value="">Add a provider…</option>${provs.filter((p) => !st.order.includes(p.name)).map((p) => `<option value="${esc(p.name)}">${esc(p.label)}</option>`).join("")}</select></div></div>
    <div class="card"><h2>Defaults per provider</h2><p class="muted small" style="margin-top:-6px">Empty means the provider's default. Generate and agents can still override them.</p>
      <table class="list"><tr><th>Provider</th><th>Model</th><th>Quality</th><th>Resolution</th><th>Format</th></tr>
      ${provs.filter((p) => !["grok-build"].includes(p.type)).map((p) => `<tr data-pd="${esc(p.name)}"><td>${esc(p.label)}</td>
        <td><input type="text" data-k="model" list="models-${esc(p.name)}" value="${esc(p.defaults.model || "")}" placeholder="${esc(p.model || "default")}"><datalist id="models-${esc(p.name)}">${(p.models || []).map((m) => `<option value="${esc(m)}">`).join("")}</datalist></td>
        <td><select data-k="quality">${opt(p.defaults.quality || "", [["", "Default"], ["low", "Low"], ["medium", "Medium"], ["high", "High"]])}</select></td>
        <td><select data-k="resolution">${opt(p.defaults.resolution || "", [["", "Default"], ["0.5K", "0.5K"], ["1K", "1K"], ["2K", "2K"], ["4K", "4K"]])}</select></td>
        <td><select data-k="format">${opt(p.defaults.format || "", [["", "Default"], ["png", "PNG"], ["jpeg", "JPEG"], ["webp", "WebP"]])}</select></td></tr>`).join("")}
      </table></div>
  </div>`;
  const save = async (changes) => { try { S.state = await api("/api/config", changes); renderChrome(); settingsImages(body); toast("Saved"); } catch (err) { toast(err.message, true); } };
  $$("[data-task]", body).forEach((s) => s.onchange = () => save({ set: { [`tasks.${s.dataset.task}.provider`]: s.value } }));
  const order = [...st.order];
  $$("[data-up]", body).forEach((b) => b.onclick = () => { const i = +b.dataset.up; [order[i - 1], order[i]] = [order[i], order[i - 1]]; save({ set: { order } }); });
  $$("[data-down]", body).forEach((b) => b.onclick = () => { const i = +b.dataset.down; [order[i + 1], order[i]] = [order[i], order[i + 1]]; save({ set: { order } }); });
  $$("[data-out]", body).forEach((b) => b.onclick = () => { order.splice(+b.dataset.out, 1); save({ set: { order } }); });
  $("#order-add", body).onchange = (ev) => { if (ev.target.value) { order.push(ev.target.value); save({ set: { order } }); } };
  $$("[data-pd]", body).forEach((row) => $$("[data-k]", row).forEach((inp) => inp.onchange = () => {
    const key = `provider_defaults.${row.dataset.pd}.${inp.dataset.k}`;
    save(inp.value.trim() ? { set: { [key]: inp.value.trim() } } : { unset: [key] });
  }));
}

async function settingsLocal(body) {
  const st = S.state;
  body.innerHTML = '<div class="card"><span class="spinner"></span> Loading models…</div>';
  let L;
  try { L = S.local = await api("/api/local"); } catch (err) { body.innerHTML = `<div class="card">${esc(err.message)}</div>`; return; }
  const jobs = await api("/api/jobs");
  const running = jobs.filter((j) => j.kind === "download");
  body.innerHTML = `<div class="grid">
    <div class="card"><h2>Free models that run on ${esc(st.device)}</h2>
      <p class="muted" style="margin-top:-4px">Open image models run on your graphics card with stable-diffusion.cpp. No account and no cost per image, nothing leaves ${esc(st.device)}, and they work offline. Images made here are marked as AI-made (metadata and an invisible watermark).</p>
      ${L.supported ? "" : '<p class="chip bad">This PC can\'t run local models (needs 64-bit Windows on x64).</p>'}
      <div class="form-grid"><label>Engine</label><div class="row"><select id="backend"><option value="vulkan">Vulkan: any recent NVIDIA, AMD or Intel GPU</option><option value="cpu">CPU only (slow, no GPU needed)</option></select>
        <span class="small muted">${L.engine.installed ? `Installed: ${esc(L.engine.version)} (${esc(L.engine.backend || "")})` : "Downloads with the first model"}</span></div>
        <label>Memory</label><div class="muted">${L.ram_gb} GB RAM · models in <span class="mono">${esc(L.dir)}</span> (${fmtBytes(L.bytes)} used, ${fmtBytes(L.free)} free)</div></div></div>
    <div id="dl-box">${running.map((j) => dlRow(j)).join("")}</div>
    <div class="card"><h2>Downloaded</h2>${L.models.length ? `<table class="list"><tr><th>Model</th><th>Family</th><th>Size</th><th></th></tr>${L.models.map((m) => `<tr><td>${esc(m.name)} ${m.edit ? '<span class="chip">Edits</span>' : ""} ${m.ready ? "" : '<span class="chip bad">files missing</span>'}<div class="small faint">${esc(m.license || "")}</div></td><td class="muted">${esc(m.family || m.recipe)}</td><td class="muted">${fmtBytes(m.bytes)}</td><td style="text-align:right"><button class="btn small danger" data-rm="${esc(m.id)}">Remove</button></td></tr>`).join("")}</table>` : '<p class="muted">None yet. Pick one below.</p>'}</div>
    <div class="card"><h2>Examples</h2><table class="list">${L.catalog.map((m) => `<tr><td><b>${esc(m.name)}</b> ${m.edit ? '<span class="chip">Edits</span>' : ""}<div class="small muted">${esc(m.note || "")} · ${esc(m.license || "")}${m.ram ? ` · best with ${m.ram} GB+ RAM` : ""}</div></td><td class="muted">${fmtBytes(m.download)}</td>
      <td style="text-align:right">${m.installed ? '<span class="chip ok">Downloaded</span>' : `<button class="btn small primary" data-add="${esc(m.id)}" data-label="${esc(m.name)}" ${L.supported ? "" : "disabled"}>Download</button>`}</td></tr>`).join("")}</table></div>
    <div class="card"><h2>More from Hugging Face</h2><div class="row"><input type="search" id="hf-q" class="grow" placeholder="Search, e.g. klein, z-image, qwen image"><button class="btn" id="hf-go">Search</button></div>
      <div class="row" style="margin-top:8px"><input type="text" id="hf-link" class="grow" placeholder="…or paste a Hugging Face repo or link"><button class="btn" id="hf-add">Add</button></div>
      <div id="hf-results" style="margin-top:12px"></div></div>
  </div>`;
  $("#backend", body).value = st.local_backend;
  $("#backend", body).onchange = async (ev) => { S.state = await api("/api/config", { set: { local_backend: ev.target.value } }); toast("Saved. The engine for this choice downloads the next time you add a model."); };
  $$("[data-rm]", body).forEach((b) => b.onclick = async () => { if (!confirm("Delete this model's files?")) return; try { await api("/api/local/remove", { model: b.dataset.rm }); toast("Removed"); await reloadState(); settingsLocal(body); } catch (err) { toast(err.message, true); } });
  $$("[data-add]", body).forEach((b) => b.onclick = () => startDownload(b.dataset.add, b.dataset.label, body));
  running.forEach((j) => pollDownload(j.id, body));
  const search = async () => {
    const box = $("#hf-results", body); box.innerHTML = '<span class="spinner"></span>';
    try {
      const rows = await api("/api/local/search?q=" + encodeURIComponent($("#hf-q", body).value));
      box.innerHTML = rows.length ? `<table class="list">${rows.map((r) => `<tr><td><b>${esc(r.name)}</b> <span class="muted">by ${esc(r.author)}</span> ${r.gated ? '<span class="chip warn">Needs login</span>' : ""} ${r.noncommercial ? '<span class="chip warn">Non-commercial</span>' : ""}
        <div class="small muted">${r.supported ? `${esc(r.family)}${r.edit ? " · edits" : ""} · ${fmtBytes((r.size || 0) + (r.extra || 0))} (${esc(r.quant || "file")})` : esc("Not supported: " + r.reason)} · ${r.downloads.toLocaleString()} downloads</div></td>
        <td style="text-align:right">${r.installed ? '<span class="chip ok">Added</span>' : r.supported ? `<button class="btn small" data-hf="${esc(r.repo)}">Download</button>` : ""}</td></tr>`).join("")}</table>` : '<p class="muted">Nothing found.</p>';
      $$("[data-hf]", box).forEach((b) => b.onclick = () => startDownload(b.dataset.hf, b.dataset.hf, body));
    } catch (err) { box.textContent = err.message; }
  };
  $("#hf-go", body).onclick = search;
  $("#hf-q", body).onkeydown = (ev) => { if (ev.key === "Enter") search(); };
  $("#hf-add", body).onclick = () => { const v = $("#hf-link", body).value.trim(); if (v) startDownload(v, v, body); };
}
function fmtBytes(n) { n = n || 0; return n >= 1e9 ? (n / 1e9).toFixed(1) + " GB" : Math.round(n / 1e6) + " MB"; }
function dlRow(j) {
  const ev = j.event || {}, pct = ev.total ? Math.round((ev.done / ev.total) * 100) : 0;
  return `<div class="card" data-job="${j.id}" style="margin-bottom:12px"><div class="row"><b>${esc(j.label)}</b><span class="grow"></span><span class="muted small">${ev.total ? `${fmtBytes(ev.done)} of ${fmtBytes(ev.total)} · ${pct}%` : esc(j.status)}</span>
    ${j.status === "running" ? '<button class="btn small" data-stop>Stop</button>' : ""}</div><div class="progress" style="margin-top:8px"><i style="width:${pct}%"></i></div>
    <div class="small muted" style="margin-top:6px">${esc(ev.file ? "Downloading " + ev.file : (j.lines.slice(-1)[0] || ""))}</div></div>`;
}
async function startDownload(model, label, body) {
  try { const j = await api("/api/local/add", { model, label }); $("#dl-box", body).insertAdjacentHTML("beforeend", dlRow(j)); pollDownload(j.id, body); }
  catch (err) { toast(err.message, true); }
}
function pollDownload(id, body) {
  const t = setInterval(async () => {
    let j; try { j = await api(`/api/jobs/${id}`); } catch (e) { clearInterval(t); return; }
    const box = $(`[data-job="${id}"]`, body);
    if (!box) { clearInterval(t); return; }
    box.outerHTML = dlRow(j);
    const nb = $(`[data-job="${id}"]`, body), stop = $("[data-stop]", nb);
    if (stop) stop.onclick = () => api(`/api/jobs/${id}/cancel`, {});
    if (j.status !== "running") {
      clearInterval(t);
      if (j.status === "done") { toast(`${j.label} is ready`); await reloadState(); if (S.tab === "local") settingsLocal(body); }
      else toast(j.lines.slice(-1)[0] || "Download stopped", j.status === "failed");
    }
  }, 1000);
}

function settingsLimits(body) {
  const L = S.state.limits, U = S.state.usage;
  body.innerHTML = `<div class="card"><h2>Monthly limits</h2><p class="muted" style="margin-top:-4px">You get a notice at 80% and 100%. With "Stop paid images", paid providers pause until next month while subscriptions and On ${esc(S.state.device)} keep working, for you and for your agents.</p>
    <div class="form-grid"><label>Spend limit (USD)</label><input id="l-cost" type="number" min="0" step="1" value="${L.monthly_cost || ""}" placeholder="No limit">
      <label>Image limit</label><input id="l-img" type="number" min="0" step="10" value="${L.monthly_images || ""}" placeholder="No limit">
      <label>When reached</label><label class="row"><span class="switch"><input id="l-stop" type="checkbox" ${L.stop_paid ? "checked" : ""}><span></span></span>Stop paid images</label>
      <label>This month</label><div>${money(U.cost)} · ${U.images} images · ${U.runs} runs</div>
      <span></span><div><button class="btn primary" id="l-save">Save</button></div></div></div>`;
  $("#l-save", body).onclick = async () => {
    const c = parseFloat($("#l-cost", body).value), i = parseInt($("#l-img", body).value, 10);
    const limits = {}; if (c > 0) limits.monthly_cost = c; if (i > 0) limits.monthly_images = i; if ($("#l-stop", body).checked) limits.stop_paid = true;
    S.state = await api("/api/config", { set: { limits } }); toast("Saved"); settingsLimits(body);
  };
}

function settingsAgents(body) {
  body.innerHTML = `<div class="card"><h2>Let your AI agents make images</h2><p class="muted" style="margin-top:-4px">Installs the ImageGenKit skill, so Claude Code and Codex use the <span class="mono">imagegenkit</span> command with your settings and limits.</p>
    <table class="list">${S.state.agents.map((a) => `<tr><td><b>${esc(a.label)}</b><div class="small faint mono">${esc(a.path)}</div></td>
      <td>${a.installed ? `<span class="chip ok">Installed ${esc(a.version || "")}</span>` : a.present ? '<span class="chip">Not installed</span>' : '<span class="chip">Not found on this PC</span>'}</td>
      <td style="text-align:right">${a.installed ? `<button class="btn small" data-inst="${a.id}">Update</button> <button class="btn small danger" data-rm="${a.id}">Remove</button>` : `<button class="btn small primary" data-inst="${a.id}" ${a.present ? "" : "disabled"}>Install</button>`}</td></tr>`).join("")}</table>
    <p class="small muted">Test it: ask your agent "make a draft image of a cozy reading nook". Every image it makes shows up in the Gallery.</p></div>`;
  $$("[data-inst]", body).forEach((b) => b.onclick = async () => { try { await api("/api/skill", { agent: b.dataset.inst }); toast("Skill installed"); await reloadState(); settingsAgents(body); } catch (err) { toast(err.message, true); } });
  $$("[data-rm]", body).forEach((b) => b.onclick = async () => { await api("/api/skill", { agent: b.dataset.rm, remove: true }); await reloadState(); settingsAgents(body); });
}

function settingsGeneral(body) {
  const st = S.state;
  const theme = localStore("igk-theme") || "";
  body.innerHTML = `<div class="card"><h2>General</h2><div class="form-grid">
    <label>Save images to</label><div class="row"><input id="g-out" type="text" class="grow" value="${esc(st.user_config.output_dir || "")}" placeholder="${esc(st.output_dir)}"><button class="btn" id="g-open">${icon.folder}Open</button></div>
    <label>Appearance</label><select id="g-theme"><option value="">Match Windows</option><option value="light">Light</option><option value="dark">Dark</option></select>
    <label>Updates</label><label class="row"><span class="switch"><input id="g-auto" type="checkbox" ${st.auto_update ? "checked" : ""}><span></span></span>Update the command, app and skills by themselves (once a day)</label>
    <span></span><div class="row"><button class="btn" id="g-upd">Check for updates now</button><span class="small muted" id="g-updout"></span></div>
    <label>Version</label><div>ImageGenKit ${esc(st.version)} · <a href="#" id="g-home">${esc(st.homepage.replace("https://", ""))}</a></div>
    <label>Settings file</label><div class="mono small muted">~/.config/imagegenkit/config.json</div>
    <span></span><div><button class="btn danger" id="g-quit">Quit ImageGenKit</button></div>
  </div></div>`;
  $("#g-theme", body).value = theme;
  $("#g-theme", body).onchange = (ev) => { localStore("igk-theme", ev.target.value); applyTheme(); };
  $("#g-out", body).onchange = async (ev) => { const v = ev.target.value.trim(); S.state = await api("/api/config", v ? { set: { output_dir: v } } : { unset: ["output_dir"] }); toast("Saved"); };
  $("#g-open", body).onclick = () => api("/api/open", { folder: "output" });
  $("#g-auto", body).onchange = async (ev) => { S.state = await api("/api/config", ev.target.checked ? { unset: ["auto_update"] } : { set: { auto_update: false } }); };
  $("#g-upd", body).onclick = async () => { $("#g-updout").innerHTML = '<span class="spinner"></span>'; const r = await api("/api/update", {}); $("#g-updout").textContent = r.message; };
  $("#g-home", body).onclick = (ev) => { ev.preventDefault(); api("/api/url", { url: st.homepage }); };
  $("#g-quit", body).onclick = async () => { await api("/api/quit", {}); document.body.innerHTML = '<div class="empty"><h2>ImageGenKit has quit.</h2><p>You can close this window.</p></div>'; };
}

function localStore(k, v) {
  try { if (v === undefined) return localStorage.getItem(k); if (v) localStorage.setItem(k, v); else localStorage.removeItem(k); } catch (e) { return null; }
  return null;
}
function applyTheme() { const t = localStore("igk-theme"); if (t) document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme; }

// ---------- start ----------
applyTheme();
$$(".nav").forEach((b) => b.onclick = () => setView(b.dataset.view));
$$(".tab").forEach((b) => b.onclick = () => { S.tab = b.dataset.tab; renderSettings(); });
$("#generate-open").onclick = () => openGenerate();
["#f-provider", "#f-range"].forEach((s) => $(s).onchange = render);
$("#f-search").oninput = () => { clearTimeout(render._t); render._t = setTimeout(render, 150); };
document.addEventListener("keydown", (ev) => { if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "n" && !$(".modal-back")) { ev.preventDefault(); openGenerate(); } });
setInterval(() => api("/api/ping").catch(() => {}), 10000);
window.addEventListener("focus", async () => {  // back from a terminal or a browser: logins and installs show up
  if (!S.state || $(".modal-back") || document.activeElement?.matches?.("input, textarea")) return;
  try { await reloadState(); if (S.view === "settings" && S.tab === "providers") settingsProviders($("#settings-body")); else if (S.view !== "settings") render(); } catch (e) { /* offline */ }
});
let lastSize = 0;
setInterval(async () => {  // agents make images too: pick up new log entries
  if ($(".modal-back")) return;
  try { const log = await api("/api/log?limit=1"); const top = log[0]?._id ?? -1; if (top !== lastSize) { lastSize = top; await refreshLog(); } } catch (e) { /* offline */ }
}, 15000);
loadAll().then(() => { lastSize = S.log[0]?._id ?? -1; }).catch((err) => { document.body.innerHTML = `<div class="empty"><h2>Can't reach ImageGenKit</h2><p>${esc(err.message)}</p></div>`; });
