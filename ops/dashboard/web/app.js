/* Staff survey map. World metres: x and y run -3000..3000 (see tools/render_map.py). Leaflet uses a custom CRS so
   zoom 0 is the whole world in one 256 px tile, which is also how a terrain tile pyramid (tiles/{z}/{x}/{y}.jpg,
   row 0 along the north edge) lines up with it. A point is L.latLng(y, x). */
"use strict";

const API = "api/";
const WORLD = 3000;
const K = 256 / (2 * WORLD);
const BOUNDS = [[-WORLD, -WORLD], [WORLD, WORLD]];
const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const COLOR = {
  ember: "#ff6a00", rust: "#7a3b16", hivis: "#e8d44d", lichen: "#6f8a7a", ash: "#5a5853", bone: "#dcd6c8",
  cooldown: "#8a7a55",
};
// state order matches api/loot "states": empty, item lying, taken, cooldown, disabled
const LOOT_STATES = [
  { name: "Empty", color: COLOR.lichen, on: true },
  { name: "Item lying", color: COLOR.hivis, on: true },
  { name: "Taken", color: "#c98a3a", on: true },
  { name: "Cooldown", color: COLOR.cooldown, on: true },
  { name: "Disabled", color: COLOR.ash, on: false },
];

const $ = (id) => document.getElementById(id);
const ll = (x, y) => L.latLng(y, x);
const clock = (unix) => new Date(unix * 1000).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" });
const duration = (s) => {
  s = Math.max(0, Math.round(s));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h ? `${h} h ${String(m).padStart(2, "0")} min` : m ? `${m} min ${String(s % 60).padStart(2, "0")} s` : `${s} s`;
};
const el = (tag, props = {}, ...kids) => {
  const n = Object.assign(document.createElement(tag), props);
  kids.forEach((k) => n.append(k));
  return n;
};

/* ---------- map ---------- */

const CRS = L.Util.extend({}, L.CRS.Simple, { transformation: new L.Transformation(K, WORLD * K, -K, WORLD * K) });
const map = L.map("map", { crs: CRS, minZoom: 0.5, maxZoom: 7, zoomSnap: 0.25, zoomDelta: 0.5, maxBoundsViscosity: 1, attributionControl: true });
map.attributionControl.setPrefix(false);
map.attributionControl.addAttribution("Map art © Rockstar Games; satellite render by the community");

const radar = L.imageOverlay("radar.webp", BOUNDS);
const terrain = L.tileLayer("tiles/{z}/{x}/{y}.jpg?v=terrain-original-restored-1", { minZoom: 0, maxZoom: 7, maxNativeZoom: 5, noWrap: true, bounds: BOUNDS, errorTileUrl: "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==" });
radar.addTo(map);
const baseControl = L.control.layers({ Radar: radar, Terrain: terrain }, {}, { collapsed: false, position: "topright" }).addTo(map);
fetch("tiles/0/0/0.jpg", { method: "HEAD" }).then((r) => {
  if (r.ok) {
    // satellite is the default base map once its tiles are installed
    map.removeLayer(radar);
    terrain.addTo(map);
  } else {
    const label = [...document.querySelectorAll(".leaflet-control-layers-base label span")].find((s) => s.textContent.trim() === "Terrain");
    if (label) label.textContent = " Terrain (not installed)";
  }
}).catch(() => {});

// Leaflet bounds contain the viewport. Expand them by its size so the world can
// move freely, while leaving at least 48 px of map visible on each axis.
function updatePanBounds() {
  const size = map.getSize();
  const zoom = map.getZoom();
  const northwest = map.project([WORLD, -WORLD], zoom);
  const southeast = map.project([-WORLD, WORLD], zoom);
  const reachX = Math.max(0, size.x - Math.min(48, size.x / 2));
  const reachY = Math.max(0, size.y - Math.min(48, size.y / 2));
  map.setMaxBounds(L.latLngBounds(
    map.unproject(northwest.subtract([reachX, reachY]), zoom),
    map.unproject(southeast.add([reachX, reachY]), zoom),
  ));
}
map.on("zoomend resize", updatePanBounds);
map.fitBounds(BOUNDS, { paddingTopLeft: [window.innerWidth > 720 ? 300 : 0, 0] });
updatePanBounds();
map.on("mousemove", (e) => { $("coords").textContent = `x ${Math.round(e.latlng.lng)}  y ${Math.round(e.latlng.lat)}`; });

/* ---------- trails ---------- */

const BUCKETS = 10;
const TRAVEL_MODES = [
  { name: "On foot", color: "#35e5ff" },
  { name: "Driving", color: "#ffe45c" },
  { name: "Riding", color: "#82ff63" },
  { name: "Flying", color: "#ff70ed" },
  { name: "Seat unknown", color: COLOR.bone },
];
// GTA SA vehicle models, including staff-spawned vehicles. The Vortex (539) is a hovercraft, not an aircraft.
const RIDING_MODELS = new Set([448, 461, 462, 463, 468, 471, 481, 509, 510, 521, 522, 523, 581, 586]);
const FLYING_MODELS = new Set([417, 425, 447, 460, 464, 465, 469, 476, 487, 488, 497, 501, 511, 512, 513, 519, 520, 548, 553, 563, 577, 592, 593]);

function travelMode(vehicle, seat) {
  if (!vehicle) return 0;
  if (FLYING_MODELS.has(vehicle)) return 3;
  if (RIDING_MODELS.has(vehicle) || seat > 0) return 2;
  return seat === 0 ? 1 : 4; // old traces did not record seats; do not guess that a passenger was driving
}

TRAVEL_MODES.forEach((mode) => {
  const item = el("li", { textContent: mode.name });
  item.style.setProperty("--swatch", mode.color);
  $("trailLegend").append(item);
});

// Keep traces above the dense loot dots, and player markers above their traces.
map.createPane("trails").style.zIndex = 410;
map.createPane("players").style.zIndex = 420;
const trailCanvas = L.canvas({ pane: "trails", padding: 0.3 });
const playerCanvas = L.canvas({ pane: "players", padding: 0.3 });
const canvas = L.canvas({ padding: 0.3 });

/* Points are [x, y, z, interior, dimension, vehicleModel, unix, seat]. A segment is drawn only between two outdoor points
   that are close in space and time (a teleport or a respawn must not leave a line across the map). Segments are
   grouped by age bucket and travel mode so a trail is a handful of polylines, not hundreds. */
function trailLines(points, fraction, weight) {
  const groups = new Map();
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1], b = points[i];
    if (a[3] || a[4] || b[3] || b[4]) continue;
    if (Math.abs(a[0] - b[0]) > 400 || Math.abs(a[1] - b[1]) > 400 || b[6] - a[6] > 60) continue;
    const f = fraction(b[6]);
    const bucket = Math.min(BUCKETS - 1, Math.max(0, Math.floor(f * BUCKETS)));
    const key = bucket * TRAVEL_MODES.length + travelMode(a[5], a[7]);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push([ll(a[0], a[1]), ll(b[0], b[1])]);
  }
  const outlines = [], lines = [];
  for (const [key, segs] of groups) {
    const bucket = Math.floor(key / TRAVEL_MODES.length), mode = key % TRAVEL_MODES.length;
    const age = (bucket + 0.5) / BUCKETS;
    const style = { lineCap: "round", interactive: false, renderer: trailCanvas };
    outlines.push(L.polyline(segs, {
      ...style, color: "#0b1015", weight: weight + 3, opacity: 0.7 + 0.2 * age,
    }));
    lines.push(L.polyline(segs, {
      ...style, color: TRAVEL_MODES[mode].color, weight, opacity: 0.6 + 0.4 * age,
    }));
  }
  return [...outlines, ...lines]; // all outlines underneath all coloured segments
}

/* ---------- live players ---------- */

const live = { players: new Map(), at: null, receivedAt: 0, follow: null, down: false, failed: 0 };
const playerLayer = L.layerGroup().addTo(map);
const sessionLayer = L.layerGroup().addTo(map);
let sessionMode = false;

function lengthForPx(px) { return px / (K * Math.pow(2, map.getZoom())); }

function ensureMarker(p) {
  let m = live.players.get(p.char);
  if (m) return m;
  const dot = L.circleMarker(ll(p.x, p.y), { radius: 6, color: "#141614", weight: 2, fillColor: TRAVEL_MODES[travelMode(p.veh, p.seat)].color, fillOpacity: 1, renderer: playerCanvas, interactive: false });
  const heading = L.polyline([ll(p.x, p.y), ll(p.x, p.y)], { color: COLOR.bone, weight: 2, opacity: 0.9, renderer: playerCanvas, interactive: false });
  dot.bindTooltip(p.name, { permanent: true, direction: "right", offset: [8, 0], className: "player-label" });
  m = { dot, heading, trail: [], cur: ll(p.x, p.y), from: ll(p.x, p.y), to: ll(p.x, p.y), t0: 0, rz: p.rz, data: p, pulse: REDUCED ? 0 : performance.now() };
  playerLayer.addLayer(heading).addLayer(dot);
  live.players.set(p.char, m);
  return m;
}

function applyLive(data) {
  live.at = data.at; live.receivedAt = performance.now();
  const seen = new Set();
  for (const p of data.players) {
    seen.add(p.char);
    const m = ensureMarker(p);
    const inside = p.int || p.dim;
    m.data = p;
    m.from = m.cur; m.to = ll(p.x, p.y); m.t0 = performance.now(); m.rz = p.rz;
    const color = TRAVEL_MODES[travelMode(p.veh, p.seat)].color;
    m.dot.setStyle({ fillColor: inside ? COLOR.ash : color, fillOpacity: p.duty ? 0.25 : 1, color: p.duty ? color : "#141614" });
    m.dot.setTooltipContent(p.name);
    m.trail.forEach((l) => playerLayer.removeLayer(l));
    const now = data.at || Date.now() / 1000;
    const span = 300;
    const weight = live.follow === p.char ? 4.5 : 3.5;
    m.trail = trailLines(p.trail || [], (u) => 1 - Math.min(1, Math.max(0, (now - u) / span)), weight);
    m.trail.forEach((l) => playerLayer.addLayer(l));
  }
  for (const [char, m] of live.players) {
    if (!seen.has(char)) {
      playerLayer.removeLayer(m.dot).removeLayer(m.heading);
      m.trail.forEach((l) => playerLayer.removeLayer(l));
      live.players.delete(char);
      if (live.follow === char) live.follow = null;
    }
  }
  renderRoster(data);
  if (live.follow && live.players.has(live.follow)) map.panTo(live.players.get(live.follow).to, { animate: !REDUCED, duration: 1.5, easeLinearity: 1 });
}

function frame(now) {
  for (const m of live.players.values()) {
    const t = REDUCED ? 1 : Math.min(1, (now - m.t0) / 1900);
    const far = Math.abs(m.from.lat - m.to.lat) + Math.abs(m.from.lng - m.to.lng) > 300; // a teleport jumps
    m.cur = far || t >= 1 ? m.to : L.latLng(m.from.lat + (m.to.lat - m.from.lat) * t, m.from.lng + (m.to.lng - m.from.lng) * t);
    m.dot.setLatLng(m.cur);
    const len = lengthForPx(16), a = (m.rz * Math.PI) / 180;
    m.heading.setLatLngs([m.cur, L.latLng(m.cur.lat + Math.cos(a) * len, m.cur.lng + Math.sin(a) * len)]);
    m.dot.setRadius(6);
    if (m.pulse) {
      const age = (now - m.pulse) / 1200;
      if (age >= 1) { m.pulse = 0; if (m.ring) { playerLayer.removeLayer(m.ring); m.ring = null; } }
      else {
        if (!m.ring) { m.ring = L.circleMarker(m.cur, { radius: 6, color: TRAVEL_MODES[travelMode(m.data.veh, m.data.seat)].color, weight: 2, fill: false, renderer: playerCanvas, interactive: false }).addTo(playerLayer); }
        m.ring.setLatLng(m.cur).setRadius(6 + 22 * age).setStyle({ opacity: 1 - age });
      }
    }
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

/* roster rows are updated in place so focus and hover survive the 2 s refresh */
const rows = new Map();
function renderRoster(data) {
  const list = $("roster");
  $("onlineCount").textContent = data.players.length;
  $("rosterEmpty").hidden = data.players.length > 0;
  const keep = new Set();
  for (const p of data.players) {
    keep.add(p.char);
    let r = rows.get(p.char);
    if (!r) {
      const li = el("li", { tabIndex: 0 });
      li.setAttribute("role", "button");
      const who = el("span", { className: "who" }), time = el("span", { className: "time" }), meta = el("span", { className: "meta" });
      li.append(who, time, meta);
      const pick = () => { live.follow = live.follow === p.char ? null : p.char; if (live.follow) map.setView(live.players.get(p.char).to, Math.max(map.getZoom(), 3), { animate: !REDUCED }); paintFollow(); };
      li.addEventListener("click", pick);
      li.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pick(); } });
      r = { li, who, time, meta };
      rows.set(p.char, r);
      list.append(li);
    }
    r.li.dataset.char = p.char;
    r.who.textContent = p.name;
    if (p.duty) r.who.append(el("small", { textContent: "on duty" }));
    const elapsed = p.sessionStart && data.at ? data.at - p.sessionStart + (performance.now() - live.receivedAt) / 1000 : null;
    r.time.textContent = elapsed === null ? "" : duration(elapsed);
    const where = p.int || p.dim ? `inside (int ${p.int})` : p.zone || "outside";
    r.meta.textContent = `${where} · ${p.hp} hp · ${p.ping} ms · ${TRAVEL_MODES[travelMode(p.veh, p.seat)].name.toLowerCase()}`;
  }
  for (const [char, r] of rows) if (!keep.has(char)) { r.li.remove(); rows.delete(char); }
  paintFollow();
}
function paintFollow() {
  for (const [char, r] of rows) r.li.setAttribute("aria-pressed", String(live.follow === char));
}
map.on("dragstart", () => { if (live.follow) { live.follow = null; paintFollow(); } });

async function getJSON(path, timeoutMs = 5000) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetch(API + path, { signal: ctl.signal, headers: { Accept: "application/json" } });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    return body;
  } finally { clearTimeout(timer); }
}

function setStatus(state, text) { const s = $("status"); s.dataset.state = state; s.textContent = text; }

async function pollLive() {
  try {
    const data = await getJSON("live?trail=300");
    live.failed = 0;
    if (!data.live) {
      const age = data.at ? Math.round(Date.now() / 1000 - data.at) : null;
      setStatus("stale", age === null ? "Game server not reporting yet" : `Game server not responding, last update ${age} s ago`);
    } else setStatus("live", `Live, ${data.players.length} online`);
    if (!sessionMode) applyLive(data);
    else renderRoster(data);
  } catch {
    live.failed++;
    setStatus("down", "Disconnected, retrying…");
    for (const m of live.players.values()) m.dot.setStyle({ fillOpacity: 0.35 });
  }
}
pollLive();
setInterval(pollLive, 2000);

/* ---------- loot spawns ---------- */

const loot = { markers: new Map(), groups: [], data: null };
const lootHistory = { active: false, open: null };
LOOT_STATES.forEach((s, i) => { loot.groups[i] = L.layerGroup(); if (s.on) loot.groups[i].addTo(map); });
const lootRadius = (state) => {
  const base = Math.max(1.5, Math.min(7, 1.2 * (map.getZoom() - 0.5)));
  return state === 1 ? base + 3 : state === 0 ? base * 0.7 : base + 1;
};
// empty spawns are the background (11k of them); anything with an item, taken or cooling down must read at a glance
const lootStyle = (state) => ({
  fillColor: LOOT_STATES[state].color, radius: lootRadius(state),
  fillOpacity: state === 0 ? 0.55 : 0.95, weight: state === 1 ? 1.5 : 0.75, color: "#141614", opacity: state === 0 ? 0.45 : 1,
});

function chipsRender(counts) {
  const box = $("lootChips");
  if (!box.children.length) {
    LOOT_STATES.forEach((s, i) => {
      const b = el("button", { type: "button", className: "chip" });
      b.style.setProperty("--swatch", s.color);
      b.setAttribute("aria-pressed", String(s.on));
      b.dataset.i = i;
      b.addEventListener("click", () => {
        s.on = !s.on; b.setAttribute("aria-pressed", String(s.on));
        if (s.on && $("layerLoot").checked) loot.groups[i].addTo(map); else map.removeLayer(loot.groups[i]);
      });
      box.append(b);
    });
  }
  [...box.children].forEach((b, i) => { b.replaceChildren(`${LOOT_STATES[i].name} `, el("b", { textContent: counts[i].toLocaleString() })); });
}

function showSpawn(id, latlng) {
  if (lootHistory.active) { lootHistory.open(id); return; }
  const popup = L.popup({ maxWidth: 320 }).setLatLng(latlng).setContent("Loading…").openOn(map);
  getJSON("loot/" + id).then((d) => {
    const dl = el("dl");
    const add = (k, v) => dl.append(el("dt", { textContent: k }), el("dd", { textContent: v }));
    add("Spawn", `#${d.id}`); add("Table", d.table); add("Zone", d.zone); add("State", d.state);
    if (d.cooldownSeconds) add("Cooldown ends", `in ${duration(d.cooldownSeconds)}`);
    add("Chance", `${Math.round(d.weight)} %`); add("Position", `${d.x}, ${d.y}, ${d.z}`);
    const box = el("div", { className: "popup" }, el("h3", { textContent: d.lying.length ? "Item lying here" : "Nothing lying here" }), dl);
    if (d.lying.length) box.append(el("ul", {}, ...d.lying.map((i) => el("li", { textContent: `${i.type} (item ${i.id})` }))));
    if (d.takenCount) box.append(el("p", { className: "note", textContent: `${d.takenCount} more taken from here and still around.` }));
    const history = el("button", { type: "button", className: "btn", textContent: "View loot timeline" });
    history.addEventListener("click", () => { map.closePopup(); lootHistory.open(id); });
    box.append(history);
    popup.setContent(box);
  }).catch((e) => popup.setContent("Could not load: " + e.message));
}

function applyLoot(data) {
  const counts = data.states.map(() => 0);
  const seen = new Set();
  for (const [id, x, y, state] of data.spawns) {
    counts[state]++; seen.add(id);
    let m = loot.markers.get(id);
    if (!m) {
      m = { state: -1, marker: L.circleMarker(ll(x, y), { renderer: canvas, weight: 0, radius: lootRadius() }) };
      m.marker.on("click", () => showSpawn(id, m.marker.getLatLng()));
      loot.markers.set(id, m);
    }
    if (m.state !== state) {
      if (m.state >= 0) loot.groups[m.state].removeLayer(m.marker);
      m.state = state;
      m.marker.setStyle(lootStyle(state));
      loot.groups[state].addLayer(m.marker);
      if (state !== 0 && m.marker._map) m.marker.bringToFront();
    }
  }
  for (const [id, m] of loot.markers) if (!seen.has(id)) { loot.groups[m.state].removeLayer(m.marker); loot.markers.delete(id); }
  chipsRender(counts);
  $("lootNote").textContent = data.skippedIndoor ? `${data.skippedIndoor.toLocaleString()} spawns inside buildings are not on the map.` : "";
}
async function pollLoot() {
  try {
    loot.data = await getJSON("loot", 15000);
    if (!lootHistory.active) applyLoot(loot.data);
  } catch { if (!lootHistory.active) $("lootNote").textContent = "Loot spawns unavailable: the database did not answer."; }
}
pollLoot();
setInterval(pollLoot, 30000);
map.on("zoomend", () => loot.markers.forEach((m) => m.marker.setRadius(lootRadius(m.state))));

$("layerPlayers").addEventListener("change", (e) => e.target.checked && !lootHistory.active ? playerLayer.addTo(map) : map.removeLayer(playerLayer));
$("layerLoot").addEventListener("change", (e) => LOOT_STATES.forEach((s, i) => (e.target.checked && s.on ? loot.groups[i].addTo(map) : map.removeLayer(loot.groups[i]))));

/* ---------- past sessions ---------- */

let trackDot = null, trackPoints = [];

function backToLive() {
  sessionMode = false;
  document.body.classList.remove("session-mode");
  sessionLayer.clearLayers(); trackDot = null; trackPoints = [];
  $("scrub").hidden = true;
  playerLayer.eachLayer((l) => l.setStyle && l.setStyle({ opacity: 1 }));
  document.querySelectorAll("#sessionList button").forEach((b) => b.setAttribute("aria-pressed", "false"));
  pollLive();
}

async function openSession(s, button) {
  if (lootHistory.active) $("closeLootHistory").click();
  document.querySelectorAll("#sessionList button").forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
  const end = s.leftAt || Math.round(Date.now() / 1000);
  let track;
  try { track = await getJSON(`track?account=${s.accountId}&from=${s.joinedAt}&to=${end}`, 20000); }
  catch (e) { $("sessionEmpty").hidden = false; $("sessionEmpty").textContent = "Could not load that session: " + e.message; return; }
  sessionMode = true;
  document.body.classList.add("session-mode");
  sessionLayer.clearLayers();
  trackPoints = track.points;
  let sparse = false;
  if (!trackPoints.length && track.sparse && track.sparse.length) {
    // no full trail (the session predates trail recording): show the stops the database does know
    trackPoints = track.sparse; sparse = true;
    $("sessionEmpty").hidden = true;
    $("scrubNote").hidden = false;
    $("scrubNote").textContent = `No full trail was recorded for this session. Showing ${trackPoints.length} known stops: vehicle use, and where the character died or last saved.`;
  } else if (!trackPoints.length) {
    $("sessionEmpty").hidden = false; $("sessionEmpty").textContent = "Nothing is known about where this player was during that session."; $("scrub").hidden = true; return;
  } else { $("sessionEmpty").hidden = true; $("scrubNote").hidden = true; }
  const t0 = trackPoints[0][6], t1 = trackPoints[trackPoints.length - 1][6], span = Math.max(1, t1 - t0);
  if (sparse) {
    const out = trackPoints.filter((p) => !p[3] && !p[4]);
    L.polyline(out.map((p) => ll(p[0], p[1])), { color: COLOR.bone, weight: 3, dashArray: "8 7", opacity: 0.85, renderer: trailCanvas, interactive: false }).addTo(sessionLayer);
    for (const p of trackPoints) {
      const stop = L.circleMarker(ll(p[0], p[1]), { radius: 7, color: COLOR.bone, weight: 2, fillColor: "#3f5a4b", fillOpacity: 1, renderer: playerCanvas });
      stop.bindTooltip(`${p[7]}, ${clock(p[6])}${p[3] || p[4] ? " (inside)" : ""}`);
      stop.addTo(sessionLayer);
    }
  } else trailLines(trackPoints, (u) => (u - t0) / span, 4).forEach((l) => sessionLayer.addLayer(l));
  trackDot = L.circleMarker(ll(trackPoints[0][0], trackPoints[0][1]), { radius: 10, color: "#141614", weight: 3, fillColor: COLOR.ember, fillOpacity: 1, renderer: playerCanvas, interactive: false }).addTo(sessionLayer);
  const range = $("scrubRange");
  range.max = trackPoints.length - 1; range.value = 0;
  scrubTo(0);
  $("scrub").hidden = false;
  const outdoor = trackPoints.filter((p) => !p[3] && !p[4]);
  if (outdoor.length) map.fitBounds(L.latLngBounds(outdoor.map((p) => ll(p[0], p[1]))).pad(0.15), { paddingTopLeft: [window.innerWidth > 720 ? 300 : 0, 0] });
  playerLayer.eachLayer((l) => l.setStyle && l.setStyle({ opacity: 0.25 }));
  $("sessions").hidden = true; // the History button brings it back; it would sit on top of the track
}
function scrubTo(i) {
  const p = trackPoints[i];
  if (!p) return;
  trackDot.setLatLng(ll(p[0], p[1]));
  const sparse = typeof p[7] === "string";
  const mode = TRAVEL_MODES[travelMode(p[5], p[7])];
  trackDot.setStyle({ fillColor: sparse ? COLOR.ember : mode.color });
  $("scrubLabel").textContent = (sparse ? p[7] : mode.name) + ", " + clock(p[6]) + (p[3] || p[4] ? " (inside)" : "");
}
$("scrubRange").addEventListener("input", (e) => scrubTo(+e.target.value));
$("backToLive").addEventListener("click", backToLive);

async function searchSessions() {
  const list = $("sessionList");
  list.replaceChildren();
  $("sessionEmpty").hidden = true;
  let sessions;
  try { sessions = await getJSON(`sessions?days=${$("sessionDays").value}&name=${encodeURIComponent($("sessionName").value.trim())}`, 20000); }
  catch (e) { $("sessionEmpty").hidden = false; $("sessionEmpty").textContent = "Could not load sessions: " + e.message; return; }
  if (!sessions.length) { $("sessionEmpty").hidden = false; $("sessionEmpty").textContent = "No sessions in that window."; return; }
  for (const s of sessions) {
    const b = el("button", { type: "button" });
    b.setAttribute("aria-pressed", "false");
    b.append(
      el("span", { className: "name", textContent: s.name }),
      el("span", { className: "sub", textContent: clock(s.joinedAt) }),
      el("span", { className: "sub", textContent: s.leftAt ? duration(s.leftAt - s.joinedAt) : "still online", style: "text-align:left" }),
      el("span", { className: "sub", textContent: s.points ? `${s.points.toLocaleString()} points` : s.known ? `${s.known} known stops` : "no location data" }),
    );
    b.addEventListener("click", () => openSession(s, b));
    list.append(el("li", {}, b));
  }
}
$("openSessions").addEventListener("click", () => { if (lootHistory.active) $("closeLootHistory").click(); $("sessions").hidden = false; $("sessionName").focus(); if (!$("sessionList").children.length) searchSessions(); });
$("closeSessions").addEventListener("click", () => { $("sessions").hidden = true; $("openSessions").focus(); });
$("sessionForm").addEventListener("submit", (e) => { e.preventDefault(); searchSessions(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("sessions").hidden) $("closeSessions").click(); });

/* ---------- phone: roster as a bottom sheet ---------- */

$("railToggle").addEventListener("click", () => {
  const open = document.body.classList.toggle("rail-open");
  $("railToggle").setAttribute("aria-expanded", String(open));
});
