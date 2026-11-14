/* Street view: the GTA SA world baked by tools/streetview_bake.py (served at streetview/), drawn with three.js.
   The baked data stays in GTA space (metres, Z up); the world group turns it to three's Y up, so a GTA point (x, y, z)
   is the three point (x, z, -y). Heading follows GTA: 0 looks north (+y), 90 west. Models are shared by id and drawn as
   one InstancedMesh per model across every loaded cell; cells near the camera bring full detail, a ring around them the
   game's own LOD models. Loot spawns and live players come from app.js (window.ssmta). */
import * as THREE from "./vendor/three/three.module.min.js";

const BASE = "streetview/";
const EYE = 1.7;
const HI_RING = 1; // cells around the camera at full detail (3 x 3, 600 m)
const LOD_RING = 4; // cells around the camera with LOD models (9 x 9, 1.8 km)
const WALK = 6, RUN = 30, CLIMB = 12; // m/s
const LOOT_REACH = 180; // m: loot pillars drawn around the camera
const LIGHT_KEY = "ssmta.sv.light2";
const LIFT = 0.09; // share of the light added to every prelight, so shaded faces read grey as in game, not black

THREE.ColorManagement.enabled = false; // the game multiplies raw texture and prelight values; so do we

const ui = window.ssmta;
const $ = (id) => document.getElementById(id);
const store = { get(k, d) { try { return localStorage.getItem(k) ?? d; } catch { return d; } }, set(k, v) { try { localStorage.setItem(k, v); } catch { /* private window */ } } };

const sv = {
  open: false, ready: null, index: null, textures: null,
  renderer: null, scene: null, camera: null, world: null,
  yaw: 0, pitch: 0, keys: new Set(), light: +store.get(LIGHT_KEY, 2),
  geometry: new Map(), // model id -> Promise<{geometry, materials} | null>
  models: new Map(), // model id -> {geometry, materials}, once loaded
  texture: new Map(), material: new Map(),
  cells: new Map(), // "hi:cx_cy" / "lod:cx_cy" -> {state, rows: Map<id, Float32Array>}
  instanced: new Map(), dirty: new Set(), centre: null,
  loot: null, lootAt: null, lootIds: [], players: new Map(),
  marker: null, lastMarker: 0, pending: 0, last: 0, stats: { disk: 0, net: 0 },
};

/* ---------- data ---------- */

/* Everything downloaded while exploring is kept in IndexedDB (the Cache API needs https, and the map is plain http), so a
   place visited before loads from disk. Each bake has a database of its own (ssmta-sv-<bake time>); older ones are
   deleted in the background, so a new bake never waits on emptying the last one. */
const idb = (() => {
  let db, name = null;
  const open = () => (db ??= new Promise((res) => {
    try {
      if (!name) { res(null); return; }
      const r = indexedDB.open(name, 1);
      r.onupgradeneeded = () => r.result.createObjectStore("files");
      r.onsuccess = () => res(r.result);
      r.onerror = r.onblocked = () => res(null);
    } catch { res(null); } // private window, storage blocked
  }));
  const run = async (mode, fn) => {
    const d = await open();
    if (!d) return null;
    return new Promise((res) => {
      try {
        const t = d.transaction("files", mode), req = fn(t.objectStore("files"));
        t.oncomplete = () => res(req.result ?? null);
        t.onerror = t.onabort = () => res(null);
      } catch { res(null); }
    });
  };
  const use = (baked) => {
    name = `ssmta-sv-${baked}`;
    try {
      indexedDB.databases?.().then((all) => all.forEach((d) => {
        if (d.name !== name && (d.name.startsWith("ssmta-sv-") || d.name === "ssmta-streetview")) indexedDB.deleteDatabase(d.name);
      })).catch(() => {});
    } catch { /* storage blocked */ }
  };
  return { use, get: (k) => run("readonly", (st) => st.get(k)), put: (k, v) => run("readwrite", (st) => st.put(v, k)) };
})();

/* a baked file: from IndexedDB when this browser has fetched it before, else from the server (and then kept) */
async function cached(path, as) {
  const hit = await idb.get(path);
  if (hit != null) { sv.stats.disk++; return hit === false ? null : hit; }
  sv.stats.net++;
  const r = await fetch(`${BASE}${path}?b=${sv.index.baked}`); // the bake time keys the HTTP cache too
  if (r.status === 404) { idb.put(path, false); return null; } // an empty cell: remembered too
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  const v = as === "json" ? await r.json() : as === "blob" ? await r.blob() : await r.arrayBuffer();
  idb.put(path, v);
  return v;
}

async function json(path) {
  const r = await fetch(BASE + path, { cache: "no-cache" }); // index.json: always revalidated, so a new bake is seen at once
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json();
}

function boot() {
  sv.ready ??= json("index.json").then(async (index) => {
    if (!index) throw new Error("street view is not baked yet (run python -m tools.streetview_bake)");
    idb.use(index.baked);
    sv.index = index;
    sv.textures = (await cached("textures.json", "json")) || {};
    build();
  });
  return sv.ready;
}

function textureUrl(chain, name) {
  for (const txd of chain) {
    const set = sv.textures[txd];
    if (set && name in set) return { url: `tex/${encodeURIComponent(txd)}/${encodeURIComponent(name)}.webp`, alpha: set[name] === 1 };
  }
  return null;
}

function loadTexture(path) {
  let t = sv.texture.get(path);
  if (!t) {
    t = new THREE.Texture();
    cached(path, "blob").then((blob) => blob && createImageBitmap(blob)).then((bitmap) => {
      if (!bitmap) return;
      t.image = bitmap;
      t.needsUpdate = true;
    }).catch(() => {});
    t.flipY = false; // RenderWare UVs start at the top-left texel (and an ImageBitmap is never flipped)
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.anisotropy = Math.min(4, sv.renderer.capabilities.getMaxAnisotropy());
    sv.texture.set(path, t);
  }
  return t;
}

function material(chain, mat) {
  const tex = mat.t ? textureUrl(chain, mat.t) : null;
  const key = `${tex ? tex.url : "-"}|${mat.c.join(",")}`;
  let m = sv.material.get(key);
  if (!m) {
    m = new THREE.MeshBasicMaterial({ vertexColors: true, map: tex ? loadTexture(tex.url) : null });
    m.userData.base = mat.c.slice(0, 3).map((v) => v / 255);
    if (!tex) m.userData.base = m.userData.base.map((v) => v * 0.55); // untextured: a flat mid tone, not a white blot
    if (tex && tex.alpha) { m.alphaTest = 0.45; m.side = THREE.DoubleSide; }
    m.color.setRGB(...m.userData.base);
    m.onBeforeCompile = lit;
    m.customProgramCacheKey = () => "sv-lit";
    sv.material.set(key, m);
  }
  return m;
}

/* texture x (prelight x light + lift): one uniform shared by every world material, so the Light slider is one write */
const LIGHT = { value: 2 };
function lit(shader) {
  shader.uniforms.svLight = LIGHT;
  shader.fragmentShader = "uniform float svLight;\n" + shader.fragmentShader.replace(
    "#include <color_fragment>",
    `#if defined( USE_COLOR_ALPHA ) || defined( USE_COLOR )
      diffuseColor.rgb *= vColor.rgb * svLight + ${LIFT.toFixed(3)} * svLight;
    #endif`,
  );
}

/* models/<id>.bin: "SVM1", u32 header length, JSON header, positions f32 x3, uvs f32 x2, colours u8 x4, indices u16|u32 */
function loadModel(id) {
  let p = sv.geometry.get(id);
  if (p) return p;
  p = cached(`models/${id}.bin`, "bin").then((buf) => {
    if (!buf) return null;
    const dv = new DataView(buf);
    const hlen = dv.getUint32(4, true);
    const h = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 8, hlen)));
    let at = 8 + hlen;
    const take = (Type, n) => { const a = new Type(buf, at, n); at += a.byteLength; return a; };
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(take(Float32Array, h.n * 3), 3));
    g.setAttribute("uv", new THREE.BufferAttribute(take(Float32Array, h.n * 2), 2));
    g.setAttribute("color", new THREE.BufferAttribute(take(Uint8Array, h.n * 4), 4, true));
    g.setIndex(new THREE.BufferAttribute(take(h.wide ? Uint32Array : Uint16Array, h.ni), 1));
    const materials = h.mats.map((m) => material(h.chain, m));
    for (const [start, count, mi] of h.groups) g.addGroup(start, count, mi);
    g.computeBoundingSphere();
    const model = { geometry: g, materials };
    sv.models.set(id, model);
    return model;
  }).catch(() => null);
  sv.geometry.set(id, p);
  return p;
}

/* ---------- cells ---------- */

const cellOf = (x, y) => {
  const c = sv.index.cell, n = sv.index.cells, w = sv.index.world;
  return [Math.min(n - 1, Math.max(0, Math.floor((x + w) / c))), Math.min(n - 1, Math.max(0, Math.floor((y + w) / c)))];
};

function wanted(cx, cy) {
  const out = new Map();
  for (let dx = -LOD_RING; dx <= LOD_RING; dx++) {
    for (let dy = -LOD_RING; dy <= LOD_RING; dy++) {
      const x = cx + dx, y = cy + dy;
      if (x < 0 || y < 0 || x >= sv.index.cells || y >= sv.index.cells) continue;
      const near = Math.max(Math.abs(dx), Math.abs(dy)) <= HI_RING;
      out.set(`${near ? "hi" : "lod"}:${x}_${y}`, near);
    }
  }
  return out;
}

function stream(force = false) {
  const p = gtaPos();
  const [cx, cy] = cellOf(p.x, p.y);
  const key = `${cx}_${cy}`;
  if (!force && key === sv.centre) return;
  sv.centre = key;
  const want = wanted(cx, cy);
  for (const [k, cell] of sv.cells) {
    if (!want.has(k)) { sv.cells.delete(k); cell.rows.forEach((_, id) => sv.dirty.add(id)); }
  }
  const load = (k) => {
    if (sv.cells.has(k)) return Promise.resolve();
    const cell = { state: "loading", rows: new Map() };
    sv.cells.set(k, cell);
    const [layer, name] = k.split(":");
    sv.pending++;
    return cached(`${layer === "hi" ? "cells" : "lod"}/${name}.json`, "json").then(async (data) => {
      if (sv.cells.get(k) !== cell) return;
      if (!data) { cell.state = "empty"; return; } // nothing placed in this cell (sea, desert)
      const ids = Object.keys(data).map(Number);
      await Promise.all(ids.map(loadModel));
      if (sv.cells.get(k) !== cell) return;
      for (const id of ids) { cell.rows.set(id, data[id]); sv.dirty.add(id); }
      cell.state = "ready";
    }).catch(() => { cell.state = "failed"; }).finally(() => { sv.pending--; status(); });
  };
  // the full-detail cells first; the LOD ring only once they are in, and only if the camera is still in this cell
  const near = [...want].filter(([, n]) => n).map(([k]) => k), far = [...want].filter(([, n]) => !n).map(([k]) => k);
  Promise.allSettled(near.map(load)).then(() => { if (sv.centre === key) far.forEach(load); });
  status();
}

const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _v = new THREE.Vector3(), _one = new THREE.Vector3(1, 1, 1);

/* at most `budget` models a call, so crossing into a new cell spreads its work over a few frames */
function rebuild(budget = 120) {
  if (!sv.dirty.size) return;
  const ids = [...sv.dirty].slice(0, budget);
  ids.forEach((id) => sv.dirty.delete(id));
  for (const id of ids) {
    const old = sv.instanced.get(id);
    if (old) { sv.world.remove(old); old.dispose(); sv.instanced.delete(id); }
    const rows = [];
    for (const cell of sv.cells.values()) { const r = cell.rows.get(id); if (r) rows.push(r); }
    const count = rows.reduce((n, r) => n + r.length / 7, 0);
    const model = count && sv.models.get(id);
    if (!model) continue;
    const mesh = new THREE.InstancedMesh(model.geometry, model.materials, count);
    let i = 0;
    for (const r of rows) {
      for (let j = 0; j < r.length; j += 7) {
        _v.set(r[j], r[j + 1], r[j + 2]);
        _q.set(r[j + 3], r[j + 4], r[j + 5], r[j + 6]);
        mesh.setMatrixAt(i++, _m.compose(_v, _q, _one));
      }
    }
    mesh.computeBoundingSphere();
    mesh.userData.model = id;
    sv.world.add(mesh);
    mesh.updateWorldMatrix(true, false); // raycasts (ground, clicks) may run before the next render
    sv.instanced.set(id, mesh);
  }
}

/* ---------- scene ---------- */

function build() {
  const host = $("svCanvas");
  const r = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
  r.outputColorSpace = THREE.LinearSRGBColorSpace;
  r.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  host.append(r.domElement);
  sv.renderer = r;
  const sky = sv.index.sky;
  sv.scene = new THREE.Scene();
  const grad = document.createElement("canvas");
  grad.width = 2; grad.height = 256;
  const ctx = grad.getContext("2d"), fill = ctx.createLinearGradient(0, 0, 0, 256);
  const css = (c) => `rgb(${c.map((v) => Math.round(v * 255)).join(",")})`;
  fill.addColorStop(0, css(sky.skyTop)); fill.addColorStop(0.55, css(sky.skyBottom)); fill.addColorStop(1, css(sky.skyBottom));
  ctx.fillStyle = fill; ctx.fillRect(0, 0, 2, 256);
  sv.scene.background = new THREE.CanvasTexture(grad);
  sv.scene.fog = new THREE.Fog(new THREE.Color(...sky.skyBottom), 350, Math.max(1200, sky.farClip + 400));
  sv.camera = new THREE.PerspectiveCamera(70, 1, 0.3, 2400);
  sv.camera.rotation.order = "YXZ";
  sv.world = new THREE.Group();
  sv.world.rotation.x = -Math.PI / 2; // GTA Z up -> three Y up
  sv.scene.add(sv.world);
  sv.waterReady = cached("water.json", "json").then((quads) => { sv.water = quads || []; if (quads) sv.world.add(water(quads, sky.water)); });
  sv.loot = new THREE.InstancedMesh(new THREE.CylinderGeometry(0.18, 0.18, 1.4, 8).rotateX(Math.PI / 2).translate(0, 0, 0.7), new THREE.MeshBasicMaterial({ color: 0xffffff }), 2000);
  sv.loot.count = 0;
  sv.loot.frustumCulled = false;
  sv.world.add(sv.loot);
  wire(host);
  new ResizeObserver(resize).observe(host);
  resize();
}

function water(quads, rgba) {
  const pos = [];
  for (const q of quads) {
    const tri = (a, b, c) => pos.push(...q[a], ...q[b], ...q[c]);
    tri(0, 1, 2);
    if (q.length === 4) tri(0, 2, 3);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(rgba[0], rgba[1], rgba[2]), transparent: true, opacity: 0.8, side: THREE.DoubleSide, depthWrite: false });
  const mesh = new THREE.Mesh(g, m);
  mesh.renderOrder = 1;
  return mesh;
}

function resize() {
  const host = $("svCanvas");
  if (!sv.renderer || !host.clientWidth) return;
  sv.renderer.setSize(host.clientWidth, host.clientHeight);
  sv.camera.aspect = host.clientWidth / host.clientHeight;
  sv.camera.updateProjectionMatrix();
}

/* ---------- camera ---------- */

const gtaPos = () => ({ x: sv.camera.position.x, y: -sv.camera.position.z, z: sv.camera.position.y });
function place(x, y, z) { sv.camera.position.set(x, z, -y); }
const heading = () => ((THREE.MathUtils.radToDeg(sv.yaw) % 360) + 360) % 360;

const ray = new THREE.Raycaster();
function solids() { return [...sv.instanced.values()]; }

/* the first surface below a GTA point, searched from `above` metres over it; `street` takes the lowest surface with
   head room instead (a map click from high above must land in the street, not on the first roof in the way) */
function ground(x, y, z, above = 1.2, depth = 8, street = false) {
  ray.set(new THREE.Vector3(x, z + above, -y), new THREE.Vector3(0, -1, 0));
  ray.far = above + depth;
  let hits = ray.intersectObjects(solids(), false);
  if (street) {
    const sea = waterLevel(x, y);
    const dry = hits.filter((h) => h.point.y > sea + 0.5); // canal beds and the sea floor are no place to stand
    if (dry.length) hits = dry;
  }
  if (!street || hits.length < 2) return hits.length ? hits[0].point.y : null;
  for (let i = hits.length - 1; i >= 0; i--) {
    const above = i ? hits[i - 1].point.y - hits[i].point.y : Infinity;
    if (above >= 2.5) return hits[i].point.y;
  }
  return hits[0].point.y;
}

/* the highest water.dat surface over a point (-Infinity where there is none) */
function waterLevel(x, y) {
  let best = -Infinity;
  for (const q of sv.water || []) {
    let inside = false;
    for (let i = 0, j = q.length - 1; i < q.length; j = i++) {
      const [xi, yi] = q[i], [xj, yj] = q[j];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    if (inside) best = Math.max(best, q[0][2]);
  }
  return best;
}

function move(dt) {
  const k = sv.keys;
  const f = (k.has("w") || k.has("arrowup") ? 1 : 0) - (k.has("s") || k.has("arrowdown") ? 1 : 0);
  const s = (k.has("d") || k.has("arrowright") ? 1 : 0) - (k.has("a") || k.has("arrowleft") ? 1 : 0);
  const u = (k.has("r") || k.has("pageup") ? 1 : 0) - (k.has("f") || k.has("pagedown") ? 1 : 0);
  if (!f && !s && !u) return false;
  const speed = (k.has("shift") ? RUN : WALK) * dt;
  const p = gtaPos();
  // GTA heading: forward is (-sin, cos), right is (cos, sin)
  const fx = -Math.sin(sv.yaw), fy = Math.cos(sv.yaw);
  const nx = p.x + (fx * f + fy * s) * speed, ny = p.y + (fy * f - fx * s) * speed;
  let nz = p.z + u * CLIMB * dt;
  if (!u) { const g = ground(nx, ny, p.z - EYE); if (g !== null) nz = g + EYE; }
  place(nx, ny, nz);
  return true;
}

async function settle(x, y, zHint) {
  // full-detail cells first, then the ground under the spot (a loot or player z is a fallback, a map click has none)
  const start = performance.now();
  while (performance.now() - start < 30000 && [...sv.cells].some(([k, c]) => k.startsWith("hi:") && c.state === "loading")) await new Promise((r) => setTimeout(r, 100));
  rebuild(Infinity);
  await sv.waterReady;
  const g = zHint == null ? ground(x, y, 0, 900, 1200, true) : ground(x, y, zHint, 3, 40);
  const sea = waterLevel(x, y);
  place(x, y, (g ?? (Number.isFinite(sea) ? sea : zHint ?? 0)) + EYE); // no floor: stand on the water, as a boat would
  // a slow first load can still be bringing the ground in: keep looking for it until the viewer moves
  sv.groundAt = g == null ? { x, y, zHint, until: performance.now() + 60000 } : null;
}

/* ---------- overlays ---------- */

function lootLayer(force = false) {
  const data = ui.loot.data;
  const p = gtaPos();
  if (!data || !sv.loot) return;
  if (!force && sv.lootAt && sv.lootAt.data === data && Math.hypot(sv.lootAt.x - p.x, sv.lootAt.y - p.y) < 30) return;
  sv.lootAt = { data, x: p.x, y: p.y };
  const show = $("layerLoot").checked;
  const color = new THREE.Color();
  let n = 0;
  sv.lootIds = [];
  for (const s of data.spawns) {
    const [id, x, y, state, , , , z] = s;
    if (!show || !ui.LOOT_STATES[state].on || z == null || Math.hypot(x - p.x, y - p.y) > LOOT_REACH || n >= 2000) continue;
    _v.set(x, y, z); _q.identity();
    sv.loot.setMatrixAt(n, _m.compose(_v, _q, state === 1 ? new THREE.Vector3(1.6, 1.6, 1.3) : _one));
    sv.loot.setColorAt(n, color.set(ui.LOOT_STATES[state].color));
    sv.lootIds[n++] = id;
  }
  sv.loot.count = n;
  sv.loot.instanceMatrix.needsUpdate = true;
  if (sv.loot.instanceColor) sv.loot.instanceColor.needsUpdate = true;
}

function label(text) {
  const c = document.createElement("canvas");
  const ctx = c.getContext("2d");
  ctx.font = "600 34px Inter, sans-serif";
  c.width = Math.ceil(ctx.measureText(text).width) + 24; c.height = 48;
  ctx.font = "600 34px Inter, sans-serif";
  ctx.fillStyle = "rgba(20,22,20,0.8)"; ctx.fillRect(0, 0, c.width, c.height);
  ctx.fillStyle = "#dcd6c8"; ctx.textBaseline = "middle"; ctx.fillText(text, 12, 26);
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), depthTest: false, fog: false }));
  s.scale.set(c.width / 48 * 0.6, 0.6, 1);
  s.renderOrder = 10;
  return s;
}

function playersLayer(dt) {
  const show = $("layerPlayers").checked;
  const seen = new Set();
  for (const [char, m] of ui.live.players) {
    const p = m.data;
    if (!show || p.int || p.dim || p.z == null) continue;
    seen.add(char);
    let o = sv.players.get(char);
    if (!o) {
      const color = ui.TRAVEL_MODES[ui.travelMode(p.veh, p.seat)].color;
      const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.35, 1.1, 4, 10).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color }));
      const tag = label(p.name);
      tag.position.set(0, 0, 1.6);
      const g = new THREE.Group();
      g.add(body, tag);
      g.position.set(p.x, p.y, p.z);
      sv.world.add(g);
      o = { g, body, tag, name: p.name };
      sv.players.set(char, o);
    }
    if (o.name !== p.name) { o.g.remove(o.tag); o.tag = label(p.name); o.tag.position.set(0, 0, 1.6); o.g.add(o.tag); o.name = p.name; }
    o.body.material.color.set(ui.TRAVEL_MODES[ui.travelMode(p.veh, p.seat)].color);
    _v.set(p.x, p.y, p.z);
    if (o.g.position.distanceTo(_v) > 50) o.g.position.copy(_v);
    else o.g.position.lerp(_v, Math.min(1, dt * 2));
  }
  for (const [char, o] of sv.players) if (!seen.has(char)) { sv.world.remove(o.g); sv.players.delete(char); }
}

/* ---------- input ---------- */

function wire(host) {
  const canvas = sv.renderer.domElement;
  canvas.tabIndex = 0;
  let drag = null;
  canvas.addEventListener("pointerdown", (e) => { drag = { x: e.clientX, y: e.clientY, moved: 0 }; canvas.setPointerCapture(e.pointerId); canvas.focus(); });
  canvas.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag.moved += Math.abs(dx) + Math.abs(dy); drag.x = e.clientX; drag.y = e.clientY;
    const k = (sv.camera.fov / 70) * 0.0042;
    sv.yaw += dx * k;
    sv.pitch = Math.max(-1.45, Math.min(1.45, sv.pitch + dy * k));
  });
  canvas.addEventListener("pointerup", (e) => { const d = drag; drag = null; if (d && d.moved < 5) pick(e); });
  canvas.addEventListener("wheel", (e) => { e.preventDefault(); sv.camera.fov = Math.max(25, Math.min(95, sv.camera.fov + Math.sign(e.deltaY) * 5)); sv.camera.updateProjectionMatrix(); }, { passive: false });
  const key = (e) => (e.key === "Shift" ? "shift" : e.key.toLowerCase());
  window.addEventListener("keydown", (e) => {
    if (!sv.open || e.target.closest?.("input, select, textarea")) return;
    if (e.key === "Escape") { close(); return; }
    if (["w", "a", "s", "d", "r", "f", "shift", "arrowup", "arrowdown", "arrowleft", "arrowright", "pageup", "pagedown"].includes(key(e))) { sv.keys.add(key(e)); e.preventDefault(); }
  });
  window.addEventListener("keyup", (e) => sv.keys.delete(key(e)));
  window.addEventListener("blur", () => sv.keys.clear());
  $("svClose").addEventListener("click", close);
  const who = $("svPlayer");
  const fill = () => {
    const keep = who.value;
    const outside = [...ui.live.players.values()].map((m) => m.data).filter((p) => !p.int && !p.dim && p.z != null);
    who.replaceChildren(new Option(outside.length ? "Choose…" : "No one outside", ""), ...outside.map((p) => new Option(p.name, p.char)));
    who.value = keep;
  };
  who.addEventListener("focus", fill);
  who.addEventListener("pointerdown", fill);
  who.addEventListener("change", () => {
    const m = ui.live.players.get(+who.value);
    who.value = "";
    if (!m) return;
    const p = m.data, a = THREE.MathUtils.degToRad(p.rz || 0);
    // stand 6 m behind the player, looking the way they face
    open(p.x + Math.sin(a) * 6, p.y - Math.cos(a) * 6, { z: p.z - 1, heading: p.rz || 0 });
  });
  const light = $("svLight");
  light.value = sv.light;
  LIGHT.value = sv.light;
  light.addEventListener("input", () => { sv.light = LIGHT.value = +light.value; store.set(LIGHT_KEY, light.value); });
}

/* a click: a loot pillar opens its details, anything else moves the camera to the spot (like street view's arrows) */
function pick(e) {
  const rect = sv.renderer.domElement.getBoundingClientRect();
  const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
  ray.setFromCamera(ndc, sv.camera);
  ray.far = 400;
  const hit = ray.intersectObjects([sv.loot, ...solids()], false)[0];
  if (!hit) return;
  if (hit.object === sv.loot) { spawnCard(sv.lootIds[hit.instanceId]); return; }
  const x = hit.point.x, y = -hit.point.z;
  const g = ground(x, y, hit.point.y, 2, 30);
  place(x, y, (g ?? hit.point.y) + EYE);
}

function spawnCard(id) {
  const card = $("svCard");
  card.hidden = false;
  card.replaceChildren("Loading…");
  ui.getJSON("loot/" + id).then((d) => {
    const dl = document.createElement("dl");
    const add = (k, v) => { dl.append(Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })); };
    add("Spawn", `#${d.id}`); add("Table", d.table); add("Zone", d.zone); add("State", d.state);
    if (d.cooldownSeconds) add("Cooldown ends", `in ${ui.duration(d.cooldownSeconds)}`);
    if (d.lying.length) add("Lying", d.lying.map((i) => `${i.type} (${i.id})`).join(", "));
    const shut = Object.assign(document.createElement("button"), { type: "button", className: "btn ghost", textContent: "Close" });
    shut.addEventListener("click", () => { card.hidden = true; });
    card.replaceChildren(Object.assign(document.createElement("h3"), { textContent: d.lying.length ? "Item lying here" : "Loot spawn" }), dl, shut);
  }).catch((err) => card.replaceChildren("Could not load: " + err.message));
}

/* ---------- loop and HUD ---------- */

function status(text) {
  const p = sv.camera ? gtaPos() : null;
  const loading = sv.pending ? ` · loading ${sv.pending} cells` : "";
  $("svStatus").textContent = text || (p ? `x ${p.x.toFixed(0)}  y ${p.y.toFixed(0)}  z ${(p.z - EYE).toFixed(1)}  ·  heading ${heading().toFixed(0)}°${loading}` : "");
}

function minimap(now) {
  if (now - sv.lastMarker < 100) return;
  sv.lastMarker = now;
  const p = gtaPos();
  const at = ui.ll(p.x, p.y);
  if (!sv.marker) {
    sv.marker = L.marker(at, { icon: L.divIcon({ className: "sv-cone", html: "<span></span>", iconSize: [36, 36] }), interactive: false, zIndexOffset: 2000 }).addTo(ui.map);
  }
  sv.marker.setLatLng(at);
  const span = sv.marker.getElement()?.firstChild;
  if (span) span.style.transform = `rotate(${-heading()}deg)`;
  if (!ui.map.getBounds().pad(-0.2).contains(at)) ui.map.panTo(at, { animate: false });
}

function tick(now) {
  if (!sv.open) return;
  const dt = Math.min(0.1, (now - (sv.frameAt || now)) / 1000);
  sv.frameAt = now;
  sv.camera.rotation.set(sv.pitch, sv.yaw, 0);
  if (move(dt)) { stream(); sv.groundAt = null; }
  if (sv.groundAt && now - (sv.groundTry || 0) > 500) {
    sv.groundTry = now;
    const a = sv.groundAt;
    const g = a.zHint == null ? ground(a.x, a.y, 0, 900, 1200, true) : ground(a.x, a.y, a.zHint, 3, 40);
    if (g != null) { place(a.x, a.y, g + EYE); sv.groundAt = null; } else if (now > a.until) sv.groundAt = null;
  }
  rebuild();
  lootLayer();
  playersLayer(dt);
  sv.renderer.render(sv.scene, sv.camera);
  minimap(now);
  if (now - sv.last > 250) { sv.last = now; status(); }
  requestAnimationFrame(tick);
}

/* ---------- open / close ---------- */

async function open(x, y, opts = {}) {
  document.body.classList.add("sv-open");
  $("sv").hidden = false;
  ui.map.invalidateSize();
  status("Loading street view…");
  try { await boot(); } catch (e) { status(e.message); return; }
  resize();
  if (opts.heading != null) sv.yaw = THREE.MathUtils.degToRad(opts.heading);
  sv.pitch = 0;
  place(x, y, (opts.z ?? 0) + EYE);
  stream(true);
  lootLayer(true);
  const first = !sv.open;
  sv.open = true;
  if (first) { sv.frameAt = 0; requestAnimationFrame(tick); }
  sv.renderer.domElement.focus();
  await settle(x, y, opts.z);
  lootLayer(true);
  history.replaceState(null, "", `#sv=${x.toFixed(1)},${y.toFixed(1)},${heading().toFixed(0)}`);
}

function close() {
  sv.open = false;
  sv.keys.clear();
  document.body.classList.remove("sv-open");
  $("sv").hidden = true;
  $("svCard").hidden = true;
  if (sv.marker) { ui.map.removeLayer(sv.marker); sv.marker = null; }
  ui.map.invalidateSize();
  if (location.hash.startsWith("#sv=")) history.replaceState(null, "", location.pathname + location.search);
}

window.streetView = { open, close, isOpen: () => sv.open, debug: { sv, THREE } };

const deep = /^#sv=(-?[\d.]+),(-?[\d.]+)(?:,(-?[\d.]+))?/.exec(location.hash);
if (deep) open(+deep[1], +deep[2], { heading: deep[3] == null ? 0 : +deep[3] });
