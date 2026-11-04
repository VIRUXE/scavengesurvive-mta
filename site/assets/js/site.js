/* Scavenge & Survive Reborn — site script. No dependencies. */
(function () {
  "use strict";

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const LANGS = ["en", "pt"];

  /* ---------- language ---------- */
  const i18n = { lang: "en", dict: {} };
  function pickLang() {
    const q = new URLSearchParams(location.search).get("lang");
    if (q && LANGS.includes(q)) return q;
    try { const s = localStorage.getItem("ss.lang"); if (s && LANGS.includes(s)) return s; } catch (e) { /* private mode */ }
    const nav = (navigator.language || "en").toLowerCase();
    return nav.startsWith("pt") ? "pt" : "en";
  }
  function t(key, fallback) { return (i18n.dict && i18n.dict[key]) || fallback; }
  function pick(obj) {
    if (obj == null) return "";
    if (typeof obj === "string") return obj;
    return obj[i18n.lang] || obj.en || "";
  }
  function applyDict() {
    $$("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (!el.dataset.en) el.dataset.en = el.innerHTML;
      const v = i18n.lang === "en" ? el.dataset.en : i18n.dict[key];
      if (v != null) el.innerHTML = v;
    });
    $$("[data-i18n-attr]").forEach((el) => {
      el.getAttribute("data-i18n-attr").split(",").forEach((pair) => {
        const [attr, key] = pair.split(":");
        const store = (el._i18nEn = el._i18nEn || {});
        if (store[attr] == null) store[attr] = el.getAttribute(attr) || "";
        const v = i18n.lang === "en" ? store[attr] : i18n.dict[key];
        if (v != null) el.setAttribute(attr, v);
      });
    });
    document.documentElement.lang = i18n.lang === "pt" ? "pt-PT" : "en";
    $$("[data-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.getAttribute("data-lang") === i18n.lang)));
    document.dispatchEvent(new CustomEvent("ss:lang", { detail: i18n.lang }));
  }
  async function setLang(lang) {
    i18n.lang = lang;
    try { localStorage.setItem("ss.lang", lang); } catch (e) { /* ignore */ }
    if (lang !== "en" && !i18n.loaded) {
      try {
        const res = await fetch(rel("lang/" + lang + ".json"));
        i18n.dict = await res.json();
        i18n.loaded = true;
      } catch (e) { i18n.dict = {}; }
    }
    applyDict();
  }
  // every page sits in the site root, so relative paths need no base
  function rel(path) { return path; }

  /* ---------- nav ---------- */
  function initNav() {
    const nav = $(".nav");
    if (!nav) return;
    const onScroll = () => nav.classList.toggle("is-solid", window.scrollY > 40);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    const toggle = $(".nav-toggle");
    const links = $(".nav-links");
    if (toggle && links) {
      toggle.addEventListener("click", () => {
        const open = links.classList.toggle("is-open");
        toggle.classList.toggle("is-open", open);
        toggle.setAttribute("aria-expanded", String(open));
      });
      links.addEventListener("click", (e) => { if (e.target.tagName === "A") { links.classList.remove("is-open"); toggle.classList.remove("is-open"); } });
    }
    const here = location.pathname.split("/").pop() || "index.html";
    $$(".nav-links a").forEach((a) => { if ((a.getAttribute("href") || "").split("?")[0] === here) a.setAttribute("aria-current", "page"); });
    $$("[data-lang]").forEach((b) => b.addEventListener("click", () => setLang(b.getAttribute("data-lang"))));
  }

  /* ---------- hero particles: embers rising, dust drifting ---------- */
  function initParticles() {
    const canvas = $("canvas.hero__fx");
    if (!canvas || reduced) return;
    const ctx = canvas.getContext("2d");
    let w = 0, h = 0, dpr = Math.min(window.devicePixelRatio || 1, 2);
    const embers = [], dust = [];
    const rnd = (a, b) => a + Math.random() * (b - a);
    function resize() {
      w = canvas.clientWidth; h = canvas.clientHeight;
      canvas.width = w * dpr; canvas.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const n = Math.round(Math.min(90, (w * h) / 16000));
      embers.length = 0; dust.length = 0;
      for (let i = 0; i < n; i++) embers.push(spawnEmber(true));
      for (let i = 0; i < n * 1.6; i++) dust.push(spawnDust(true));
    }
    function spawnEmber(any) {
      return { x: rnd(0, w), y: any ? rnd(0, h) : h + 10, r: rnd(0.6, 2.2), vy: rnd(0.25, 0.9), vx: rnd(-0.25, 0.25), life: rnd(0.3, 1), phase: rnd(0, Math.PI * 2), wob: rnd(0.4, 1.4) };
    }
    function spawnDust(any) {
      return { x: any ? rnd(0, w) : -10, y: rnd(0, h), r: rnd(0.5, 1.6), vx: rnd(0.15, 0.55), vy: rnd(-0.08, 0.08), a: rnd(0.05, 0.22) };
    }
    let last = performance.now(), running = true;
    function frame(now) {
      if (!running) return;
      const dt = Math.min(40, now - last) / 16.67; last = now;
      ctx.clearRect(0, 0, w, h);
      for (const d of dust) {
        d.x += d.vx * dt; d.y += d.vy * dt;
        if (d.x > w + 10) Object.assign(d, spawnDust(false));
        ctx.fillStyle = "rgba(220,210,190," + d.a + ")";
        ctx.fillRect(d.x, d.y, d.r, d.r);
      }
      for (const e of embers) {
        e.phase += 0.02 * e.wob * dt;
        e.x += (e.vx + Math.sin(e.phase) * 0.35) * dt; e.y -= e.vy * dt; e.life -= 0.0022 * dt;
        if (e.life <= 0 || e.y < -10) Object.assign(e, spawnEmber(false));
        const a = Math.max(0, Math.min(1, e.life)) * 0.9;
        const g = ctx.createRadialGradient(e.x, e.y, 0, e.x, e.y, e.r * 4);
        g.addColorStop(0, "rgba(255,200,120," + a + ")");
        g.addColorStop(0.4, "rgba(255,110,0," + a * 0.6 + ")");
        g.addColorStop(1, "rgba(255,80,0,0)");
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(e.x, e.y, e.r * 4, 0, Math.PI * 2); ctx.fill();
      }
      requestAnimationFrame(frame);
    }
    resize();
    window.addEventListener("resize", resize);
    document.addEventListener("visibilitychange", () => {
      running = !document.hidden;
      if (running) { last = performance.now(); requestAnimationFrame(frame); }
    });
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => { running = en.isIntersecting && !document.hidden; if (running) { last = performance.now(); requestAnimationFrame(frame); } });
    });
    io.observe(canvas);
  }

  /* ---------- parallax ---------- */
  function initParallax() {
    const bg = $(".hero__bg");
    if (!bg || reduced) return;
    const onScroll = () => { const y = window.scrollY; if (y < window.innerHeight * 1.2) bg.style.transform = "translate3d(0," + y * 0.35 + "px,0)"; };
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* ---------- reveal + counters ---------- */
  function initReveal() {
    const els = $$("[data-reveal]");
    if (!els.length) return;
    if (!("IntersectionObserver" in window)) { els.forEach((e) => e.classList.add("is-in")); return; }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (!en.isIntersecting) return;
        en.target.classList.add("is-in");
        $$("[data-count]", en.target).concat(en.target.matches("[data-count]") ? [en.target] : []).forEach(countUp);
        io.unobserve(en.target);
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.1 });
    els.forEach((e) => io.observe(e));
  }
  function countUp(el) {
    if (el.dataset.done) return;
    el.dataset.done = "1";
    const target = parseFloat(el.getAttribute("data-count"));
    const dec = (String(el.getAttribute("data-count")).split(".")[1] || "").length;
    const fmt = (v) => v.toLocaleString(i18n.lang === "pt" ? "pt-PT" : "en-GB", { minimumFractionDigits: dec, maximumFractionDigits: dec });
    if (reduced) { el.textContent = fmt(target); return; }
    const dur = 1600, t0 = performance.now();
    (function tick(now) {
      const p = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - p, 4);
      el.textContent = fmt(target * e);
      if (p < 1) requestAnimationFrame(tick);
    })(t0);
  }

  /* ---------- tilt ---------- */
  function initTilt() {
    if (reduced || !window.matchMedia("(hover: hover)").matches) return;
    $$(".tilt").forEach((el) => {
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
        el.style.transform = "perspective(900px) rotateX(" + (-y * 6) + "deg) rotateY(" + (x * 8) + "deg) translateY(-4px)";
      });
      el.addEventListener("pointerleave", () => { el.style.transform = ""; });
    });
  }

  /* ---------- map explorer ---------- */
  function initMap() {
    const stage = $(".map__stage");
    if (!stage) return;
    const layers = $(".map__layers", stage);
    const imgs = $$("img[data-layer]", layers);
    const chips = $$(".chip[data-layer]");
    const caption = $(".map__caption");
    function setLayer(name) {
      imgs.forEach((im) => im.classList.toggle("is-on", im.getAttribute("data-layer") === name));
      chips.forEach((c) => c.setAttribute("aria-pressed", String(c.getAttribute("data-layer") === name)));
      const chip = chips.find((c) => c.getAttribute("data-layer") === name);
      if (caption && chip) caption.innerHTML = chip.getAttribute("data-caption") || "";
      imgs.forEach((im) => { if (im.getAttribute("data-layer") === name && im.dataset.src) { im.src = im.dataset.src; delete im.dataset.src; } });
    }
    chips.forEach((c) => c.addEventListener("click", () => setLayer(c.getAttribute("data-layer"))));
    setLayer(chips.length ? chips[0].getAttribute("data-layer") : "overview");
    // pan + zoom
    let scale = 1, tx = 0, ty = 0, drag = null;
    const apply = () => { layers.style.transform = "translate(" + tx + "px," + ty + "px) scale(" + scale + ")"; };
    const clamp = () => {
      const s = stage.clientWidth;
      const min = s - s * scale;
      tx = Math.min(0, Math.max(min, tx)); ty = Math.min(0, Math.max(min, ty));
    };
    function zoomAt(f, cx, cy) {
      const ns = Math.min(6, Math.max(1, scale * f));
      const k = ns / scale;
      tx = cx - (cx - tx) * k; ty = cy - (cy - ty) * k; scale = ns; clamp(); apply();
    }
    stage.addEventListener("wheel", (e) => { e.preventDefault(); const r = stage.getBoundingClientRect(); zoomAt(e.deltaY < 0 ? 1.18 : 1 / 1.18, e.clientX - r.left, e.clientY - r.top); }, { passive: false });
    stage.addEventListener("pointerdown", (e) => { drag = { x: e.clientX - tx, y: e.clientY - ty }; stage.setPointerCapture(e.pointerId); });
    stage.addEventListener("pointermove", (e) => { if (!drag) return; tx = e.clientX - drag.x; ty = e.clientY - drag.y; clamp(); apply(); });
    stage.addEventListener("pointerup", () => { drag = null; });
    stage.addEventListener("pointercancel", () => { drag = null; });
    stage.addEventListener("dblclick", (e) => { const r = stage.getBoundingClientRect(); zoomAt(1.6, e.clientX - r.left, e.clientY - r.top); });
    // pinch
    const pts = new Map(); let pinch = null;
    stage.addEventListener("pointerdown", (e) => { pts.set(e.pointerId, e); if (pts.size === 2) { drag = null; const [a, b] = [...pts.values()]; pinch = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), s: scale }; } });
    stage.addEventListener("pointermove", (e) => { if (!pts.has(e.pointerId)) return; pts.set(e.pointerId, e); if (pinch && pts.size === 2) { const [a, b] = [...pts.values()]; const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); const r = stage.getBoundingClientRect(); const cx = (a.clientX + b.clientX) / 2 - r.left, cy = (a.clientY + b.clientY) / 2 - r.top; zoomAt((pinch.s * d / pinch.d) / scale, cx, cy); } });
    ["pointerup", "pointercancel"].forEach((ev) => stage.addEventListener(ev, (e) => { pts.delete(e.pointerId); if (pts.size < 2) pinch = null; }));
    $$(".map__hud button").forEach((b) => b.addEventListener("click", () => {
      const s = stage.clientWidth / 2;
      if (b.dataset.act === "in") zoomAt(1.4, s, s); else if (b.dataset.act === "out") zoomAt(1 / 1.4, s, s); else { scale = 1; tx = 0; ty = 0; apply(); }
    }));
  }

  /* ---------- lightbox ---------- */
  function initLightbox() {
    let items = [], idx = 0;
    const box = document.createElement("div");
    box.className = "lightbox";
    box.innerHTML = '<figure><img alt=""><figcaption></figcaption></figure><button class="close" aria-label="Close">×</button><button class="prev" aria-label="Previous">‹</button><button class="next" aria-label="Next">›</button>';
    document.body.appendChild(box);
    const img = $("img", box), cap = $("figcaption", box);
    function show(i) {
      idx = (i + items.length) % items.length;
      const it = items[idx];
      img.src = it.full; img.alt = it.caption; cap.textContent = it.caption;
      box.classList.add("is-open");
    }
    function close() { box.classList.remove("is-open"); img.src = ""; }
    $(".close", box).addEventListener("click", close);
    $(".prev", box).addEventListener("click", () => show(idx - 1));
    $(".next", box).addEventListener("click", () => show(idx + 1));
    box.addEventListener("click", (e) => { if (e.target === box) close(); });
    document.addEventListener("keydown", (e) => { if (!box.classList.contains("is-open")) return; if (e.key === "Escape") close(); if (e.key === "ArrowLeft") show(idx - 1); if (e.key === "ArrowRight") show(idx + 1); });
    document.addEventListener("click", (e) => {
      const el = e.target.closest("[data-lightbox]");
      if (!el) return;
      e.preventDefault();
      const group = el.getAttribute("data-lightbox") || "all";
      const all = $$('[data-lightbox="' + group + '"]');
      items = all.map((a) => ({ full: a.getAttribute("data-full") || a.getAttribute("href") || $("img", a).src, caption: a.getAttribute("data-caption") || ($("img", a) && $("img", a).alt) || "" }));
      show(all.indexOf(el));
    });
  }

  /* ---------- placeholders ---------- */
  const CLAPPER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9h18v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/><path d="M3 9l1.6-4.6a1 1 0 0 1 1.2-.6L20 7.4 19 9"/><path d="M7 4.5l2.5 4M11 5.6l2.5 4M15 6.7l2.5 4"/></svg>';
  const RENDER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 4.6v9.2L12 20.4 4 15.8V6.6z"/><path d="M12 11.2L4 6.6M12 11.2l8-4.6M12 11.2v9.2"/></svg>';
  const VIDEO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="13" height="12" rx="2"/><path d="M16 10l5-3v10l-5-3z"/></svg>';
  async function initPlaceholders() {
    const slots = $$("[data-ph]");
    if (!slots.length) return;
    let data = {};
    try { data = await (await fetch(rel("data/placeholders.json"))).json(); } catch (e) { /* offline: keep the inline brief */ }
    const render = () => slots.forEach((el) => {
      const id = el.getAttribute("data-ph");
      const d = data[id] || {};
      const kind = id.split("-")[0];
      const brief = pick(d.brief) || el.getAttribute("data-brief") || "";
      const kindLabel = kind === "shot" ? t("ph.shot", "In-game screenshot") : kind === "render" ? t("ph.render", "Blender render") : t("ph.video", "Video");
      if (d.file) {
        el.classList.add("is-filled");
        if (kind === "video") {
          el.innerHTML = '<div class="video"><div class="video__poster" style="background-image:url(' + (d.poster || "") + ')" data-yt="' + d.file + '" role="button" tabindex="0" aria-label="Play"></div></div>';
        } else {
          el.innerHTML = '<a href="' + d.file + '" data-lightbox="ph" data-caption="' + (pick(d.caption) || brief).replace(/"/g, "&quot;") + '"><img src="' + d.file + '" alt="' + (pick(d.caption) || brief).replace(/"/g, "&quot;") + '" loading="lazy"></a>';
        }
        return;
      }
      el.classList.remove("is-filled");
      el.innerHTML = '<span class="ph__corner">TO SHOOT</span><div class="ph__in">' + (kind === "shot" ? CLAPPER : kind === "render" ? RENDER : VIDEO) + '<span class="ph__kind">' + kindLabel + '</span><span class="ph__id">' + id + '</span><span class="ph__brief">' + brief + "</span></div>";
    });
    render();
    document.addEventListener("ss:lang", render);
    // media page: one slate per entry, so every open slot is visible in one place
    const all = $("[data-ph-all]");
    if (all) {
      all.innerHTML = Object.keys(data).filter((k) => !k.startsWith("_")).map((k) => '<div class="ph ph--wide" data-ph="' + k + '"></div>').join("");
      const slots2 = $$("[data-ph]", all);
      const render2 = () => slots2.forEach((el) => {
        const id = el.getAttribute("data-ph"), d = data[id] || {}, kind = id.split("-")[0];
        const brief = pick(d.brief) || "";
        const kindLabel = kind === "shot" ? t("ph.shot", "In-game screenshot") : kind === "render" ? t("ph.render", "Blender render") : t("ph.video", "Video");
        const cap = (pick(d.caption) || brief).replace(/"/g, "&quot;");
        if (d.file) {
          el.classList.add("is-filled");
          el.innerHTML = kind === "video" ? '<div class="video"><div class="video__poster" style="background-image:url(' + (d.poster || "") + ')" data-yt="' + d.file + '" role="button" tabindex="0" aria-label="Play"></div></div>' : '<a href="' + d.file + '" data-lightbox="ph" data-caption="' + cap + '"><img src="' + d.file + '" alt="' + cap + '" loading="lazy"></a>';
          return;
        }
        el.innerHTML = '<span class="ph__corner">TO SHOOT</span><div class="ph__in">' + (kind === "shot" ? CLAPPER : kind === "render" ? RENDER : VIDEO) + '<span class="ph__kind">' + kindLabel + '</span><span class="ph__id">' + id + '</span><span class="ph__brief">' + brief + "</span></div>";
      });
      render2();
      document.addEventListener("ss:lang", render2);
    }
  }

  /* ---------- video: click-to-load ---------- */
  function initVideo() {
    document.addEventListener("click", (e) => {
      const p = e.target.closest("[data-yt]");
      if (!p) return;
      const id = p.getAttribute("data-yt");
      const wrap = p.parentElement;
      wrap.innerHTML = '<iframe src="https://www.youtube-nocookie.com/embed/' + id + '?autoplay=1&rel=0" title="Video" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>';
    });
  }

  /* ---------- item marquee ---------- */
  async function initMarquee() {
    const m = $(".marquee__track");
    if (!m) return;
    try {
      const idx = await (await fetch(rel("assets/img/index.json"))).json();
      const keys = Object.keys(idx).filter((k) => k.startsWith("items/") && !k.includes("sheet"));
      // deterministic shuffle so every visit sees the same strip order
      let seed = 7;
      keys.sort(() => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280 - 0.5; });
      const chosen = keys.slice(0, 48);
      const html = chosen.map((k) => { const s = idx[k].sizes[Object.keys(idx[k].sizes)[0]]; const name = idx[k].caption.replace(/\d+$/, "").replace(/_/g, " "); return '<figure><img src="assets/img/' + s.file + '" alt="' + name + '" loading="lazy" width="88" height="88"><figcaption>' + name + "</figcaption></figure>"; }).join("");
      m.innerHTML = html + html;
    } catch (e) { m.parentElement.remove(); }
  }

  /* ---------- live player count (optional feed) ---------- */
  async function initLive() {
    const el = $("[data-live-players]");
    if (!el) return;
    try {
      const cfg = await (await fetch(rel("data/servers.json"))).json();
      const srv = cfg.servers && cfg.servers[0];
      if (!srv || !srv.status_url) return;
      const st = await (await fetch(srv.status_url, { cache: "no-store" })).json();
      if (typeof st.players === "number") { el.textContent = st.players + (st.max ? " / " + st.max : ""); $$(".status").forEach((s) => s.classList.add("is-up")); }
    } catch (e) { /* feed not configured yet */ }
  }

  /* ---------- copy buttons ---------- */
  function initCopy() {
    document.addEventListener("click", async (e) => {
      const b = e.target.closest("[data-copy]");
      if (!b) return;
      try { await navigator.clipboard.writeText(b.getAttribute("data-copy")); b.textContent = t("copied", "Copied"); setTimeout(() => { b.textContent = t("copy", "Copy"); }, 1500); } catch (err) { /* clipboard blocked */ }
    });
  }

  /* ---------- changes page ---------- */
  async function initChanges() {
    const root = $("#changes");
    if (!root) return;
    let data;
    try { data = await (await fetch(rel("data/changes.json"))).json(); } catch (e) { root.innerHTML = '<p class="empty">The change list could not be loaded.</p>'; return; }
    const input = $("#changes-search"), chips = $$("#changes-filters .chip"), countEl = $("#changes-count");
    let group = "all";
    const REPO = "https://github.com/VIRUXE/scavengesurvive-mta/";
    function srcLink(s) {
      if (/^[0-9a-f]{7,40}$/.test(s)) return '<a href="' + REPO + "commit/" + s + '" target="_blank" rel="noopener">' + s.slice(0, 7) + "</a>";
      if (s.startsWith("http")) return '<a href="' + s + '" target="_blank" rel="noopener">' + s.replace(/^https?:\/\//, "").slice(0, 48) + "</a>";
      if (s.startsWith("wiki:")) return '<a href="' + REPO + "wiki/" + s.slice(5) + '" target="_blank" rel="noopener">wiki/' + s.slice(5) + "</a>";
      return '<a href="' + REPO + "blob/main/" + s + '" target="_blank" rel="noopener">' + s + "</a>";
    }
    function render() {
      const q = (input.value || "").trim().toLowerCase();
      const rows = data.changes.filter((c) => (group === "all" || c.group === group) && (!q || [pick(c.title), pick(c.was), pick(c.now), c.area].join(" ").toLowerCase().includes(q)));
      countEl.textContent = rows.length + " / " + data.changes.length;
      root.innerHTML = rows.length ? rows.map((c) => (
        '<article class="change" data-group="' + c.group + '"><div class="change__head"><h3>' + pick(c.title) + '</h3><span class="change__area">' + pick(data.areas[c.area] || c.area) + "</span></div>" +
        (c.was ? '<p class="change__was"><b>' + t("changes.was", "Original") + "</b>" + pick(c.was) + "</p>" : "") +
        '<p class="change__now"><b>' + t("changes.now", "Reborn") + "</b>" + pick(c.now) + "</p>" +
        (c.sources && c.sources.length ? '<div class="change__foot">' + c.sources.map((s) => '<span class="src-chip">' + srcLink(s) + "</span>").join("") + "</div>" : "") +
        "</article>")).join("") : '<p class="empty">' + t("changes.none", "Nothing matches.") + "</p>";
    }
    chips.forEach((c) => c.addEventListener("click", () => { group = c.getAttribute("data-group"); chips.forEach((x) => x.setAttribute("aria-pressed", String(x === c))); render(); }));
    input.addEventListener("input", render);
    document.addEventListener("ss:lang", render);
    render();
  }

  /* ---------- media page ---------- */
  async function initMediaPage() {
    const root = $("#media-gallery");
    if (!root) return;
    let idx;
    try { idx = await (await fetch(rel("assets/img/index.json"))).json(); } catch (e) { return; }
    const groups = [
      ["scenes", "media.scenes", "Blender scenes"], ["places", "media.places", "Places in the world"], ["shots", "media.shots", "Screenshots and studio sheets"], ["map", "media.map", "The map, layer by layer"], ["vehicles", "media.vehicles", "Vehicles"],
    ];
    const render = () => {
      root.innerHTML = groups.map(([g, key, label]) => {
        const keys = Object.keys(idx).filter((k) => k.startsWith(g + "/") && !(g === "vehicles" && !k.includes("sheet")));
        if (!keys.length) return "";
        return '<h2 class="section-head" style="margin-top:48px">' + t(key, label) + '</h2><div class="grid gallery">' + keys.map((k) => {
          const sizes = idx[k].sizes, ws = Object.keys(sizes).map(Number).sort((a, b) => b - a);
          const full = "assets/img/" + sizes[String(ws[0])].file, thumb = "assets/img/" + sizes[String(ws[ws.length - 1])].file;
          const cap = idx[k].caption.replace(/"/g, "&quot;");
          return '<figure class="card" data-lightbox="media" data-full="' + full + '" data-caption="' + cap + '"><img src="' + thumb + '" alt="' + cap + '" loading="lazy"><figcaption data-kind="' + g + '">' + cap + "</figcaption></figure>";
        }).join("") + "</div>";
      }).join("");
    };
    render();
    document.addEventListener("ss:lang", render);
  }

  /* ---------- servers page ---------- */
  async function initServers() {
    const root = $("#server-list");
    if (!root) return;
    try {
      const cfg = await (await fetch(rel("data/servers.json"))).json();
      const render = () => {
        root.innerHTML = cfg.servers.map((s) => (
          '<div class="server"><div class="server__name"><span class="status"></span>' + s.name + "</div>" +
          '<div class="server__addr"><span>' + s.address + '</span><button data-copy="' + s.address + '">' + t("copy", "Copy") + "</button></div>" +
          '<dl><dt>' + t("servers.players", "Players") + '</dt><dd data-live-players>—</dd><dt>' + t("servers.lang", "Language") + "</dt><dd>" + pick(s.language) + "</dd><dt>" + t("servers.region", "Region") + "</dt><dd>" + pick(s.region) + "</dd>" + (s.discord ? "<dt>Discord</dt><dd><a href=\"" + s.discord + '" rel="noopener">' + s.discord.replace(/^https?:\/\//, "") + "</a></dd>" : "") + "</dl>" +
          '<div class="row"><a class="btn btn--ember" href="mtasa://' + s.address + '">' + t("join", "Join now") + '</a><a class="btn btn--ghost" href="' + (s.rules || "https://github.com/VIRUXE/scavengesurvive-mta/wiki/Fair-Play") + '" rel="noopener">' + t("servers.rules", "Rules") + "</a></div></div>")).join("");
        initLive();
      };
      render();
      document.addEventListener("ss:lang", render);
    } catch (e) { root.innerHTML = '<p class="empty">No servers listed.</p>'; }
  }

  /* ---------- boot ---------- */
  document.addEventListener("DOMContentLoaded", async () => {
    initNav(); initParticles(); initParallax(); initReveal(); initTilt(); initMap(); initLightbox(); initVideo(); initCopy();
    await setLang(pickLang());
    initPlaceholders(); initMarquee(); initLive(); initChanges(); initMediaPage(); initServers();
    const y = $("[data-year]"); if (y) y.textContent = String(new Date().getFullYear());
  });
})();
