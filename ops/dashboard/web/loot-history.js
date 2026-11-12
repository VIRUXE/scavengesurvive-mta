/* Read-only replay of the database's item versions. Map geometry comes from the live spawn catalogue;
   only recorded item locations are replayed. Cooldowns and failed rolls have no historical record. */
"use strict";

(() => {
  const panel = $("lootHistory");
  const movedLayer = L.layerGroup();
  const focusLayer = L.layerGroup();
  let data = null, metadata = new Map(), catalogue = new Map(), filteredEvents = [];
  let cursor = 0, timer = null, request = 0, lastPaint = null, lastTick = 0;

  function stop() {
    clearInterval(timer); timer = null;
    $("lootHistoryPlay").textContent = "Play";
  }

  function matches(item) {
    const zone = $("lootHistoryZone").value, spawn = $("lootHistorySpawn").value;
    return item && (!zone || item.zone === zone) && (!spawn || item.spawn === +spawn);
  }

  function locationText(state) {
    if (!state) return "Deleted · reason not recorded";
    if (state.place === "carried") return `Carried by character #${state.holder}`;
    if (state.place === "stored") return `In container #${state.container}`;
    return `${state.place === "spawn" ? "At spawn" : "On ground"} · ${state.x}, ${state.y}${state.interior || state.dimension ? " (inside / other dimension)" : ""}`;
  }

  function focusEvent(event) {
    const item = metadata.get(event.item), spawn = catalogue.get(item.spawn);
    const position = event.state && event.state.x != null && !event.state.interior && !event.state.dimension ? event.state : null;
    const x = position ? position.x : spawn && spawn[1], y = position ? position.y : spawn && spawn[2];
    if (x == null || y == null) return;
    focusLayer.clearLayers();
    const dot = L.circleMarker(ll(x, y), { radius: 13, color: COLOR.ember, weight: 3, fill: false, interactive: false }).addTo(focusLayer);
    dot.bindTooltip(`${item.type} #${item.id} · ${event.kind}${position ? "" : " · origin spawn"}`, { permanent: true, direction: "top" }).openTooltip();
    map.setView(ll(x, y), Math.max(map.getZoom(), 3), { animate: !REDUCED });
  }

  function renderEvents() {
    const kind = $("lootHistoryKind").value;
    const events = filteredEvents.filter((e) => !kind || e.kind === kind);
    $("lootHistoryEventCount").textContent = events.length.toLocaleString();
    const list = $("lootHistoryEvents");
    list.replaceChildren();
    // Nearest past events first, followed by the next events. This keeps the cursor useful in quiet windows.
    const past = events.filter((e) => e.at <= cursor).reverse();
    const upcoming = events.filter((e) => e.at > cursor);
    const visible = past.slice(0, 60).concat(upcoming.slice(0, Math.max(10, 80 - Math.min(60, past.length))));
    for (const event of visible) {
      const item = metadata.get(event.item);
      const b = el("button", { type: "button", className: event.at > cursor ? "upcoming" : "" });
      b.dataset.kind = event.kind;
      b.append(
        el("time", { textContent: clock(event.at), dateTime: new Date(event.at * 1000).toISOString() }),
        el("strong", { textContent: event.kind }),
        el("span", { className: "event-item", textContent: `${item.type} #${item.id}` }),
        el("span", { className: "event-detail", textContent: `${event.at > cursor ? "Upcoming · " : ""}Spawn #${item.spawn} · ${item.zone.toUpperCase()} · ${locationText(event.state)}` }),
      );
      b.addEventListener("click", () => { stop(); seek(event.at); focusEvent(event); });
      list.append(el("li", {}, b));
    }
    $("lootHistoryEmpty").hidden = events.length > 0;
    $("lootHistoryEmpty").textContent = "No matching events in this window. Try a longer window or another filter.";
  }

  function chart() {
    const bins = Array.from({ length: 72 }, () => ({ spawned: 0, removed: 0 }));
    const span = data.to - data.from;
    for (const e of filteredEvents) {
      const bin = bins[Math.min(bins.length - 1, Math.floor((e.at - data.from) / span * bins.length))];
      if (e.kind === "spawned") bin.spawned++;
      if (e.kind === "removed") bin.removed++;
    }
    const peak = Math.max(1, ...bins.map((b) => Math.max(b.spawned, b.removed)));
    $("lootHistoryChart").replaceChildren(...bins.map((bin, i) => {
      const b = el("button", { type: "button", className: "history-bin", tabIndex: -1 });
      b.title = `${clock(data.from + i / bins.length * span)} · ${bin.spawned} spawned · ${bin.removed} removed`;
      b.setAttribute("aria-label", b.title);
      for (const kind of ["spawned", "removed"]) {
        const bar = el("span", { className: kind });
        bar.style.height = `${bin[kind] ? Math.max(3, bin[kind] / peak * 50) : 0}%`;
        b.append(bar);
      }
      b.addEventListener("click", () => { stop(); seek(data.from + (i + 0.5) / bins.length * span); });
      return b;
    }));
    $("lootHistoryChart").setAttribute("aria-label", `${filteredEvents.filter((e) => e.kind === "spawned").length} spawned and ${filteredEvents.filter((e) => e.kind === "removed").length} removed between ${clock(data.from)} and ${clock(data.to)}. Use the time slider to explore.`);
  }

  function seek(at, force = false) {
    if (!data || !lootHistory.active) return;
    cursor = Math.max(data.from, Math.min(data.to, at));
    const progress = (cursor - data.from) / (data.to - data.from);
    $("lootHistoryRange").value = Math.round(cursor - data.from);
    $("lootHistoryRange").setAttribute("aria-valuetext", clock(cursor));
    $("lootHistoryCursor").style.left = `${progress * 100}%`;
    $("lootHistoryTime").textContent = clock(cursor);
    // No frame should query the server. Start with the window's baseline and apply its recorded transitions.
    let eventCount = 0;
    while (eventCount < data.events.length && data.events[eventCount].at <= cursor) eventCount++;
    if (!force && lastPaint === eventCount) return;
    lastPaint = eventCount;
    const states = new Map(data.initial.map((i) => [i.item, i.state]));
    for (let i = 0; i < eventCount; i++) {
      const event = data.events[i];
      if (event.state) states.set(event.item, event.state); else states.delete(event.item);
    }
    const totals = { spawn: 0, carried: 0, stored: 0, ground: 0 }, atSpawn = new Map();
    movedLayer.clearLayers();
    for (const [id, state] of states) {
      const item = metadata.get(id);
      if (!matches(item)) continue;
      totals[state.place]++;
      if (state.place === "spawn") atSpawn.set(item.spawn, (atSpawn.get(item.spawn) || 0) + 1);
      if (state.place === "ground" && state.x != null && !state.interior && !state.dimension) {
        const dot = L.circleMarker(ll(state.x, state.y), { radius: 5, color: COLOR.ember, weight: 1.5, fillColor: COLOR.ember, fillOpacity: 0.8 });
        dot.bindTooltip(`${item.type} #${id} · dropped loot`);
        movedLayer.addLayer(dot);
      }
    }
    const spawns = [...catalogue.values()].filter((s) => matches({ spawn: s[0], zone: s[5] })).map((s) => [s[0], s[1], s[2], atSpawn.has(s[0]) ? 1 : 0, s[4], s[5], ""]);
    applyLoot({ states: LOOT_STATES, spawns, skippedIndoor: 0 });
    $("lootNote").textContent = `Loot replay · ${clock(cursor)}. Empty means no recorded loot; cooldowns are unavailable.`;
    $("lootHistoryTotals").replaceChildren(...[
      ["At spawn", totals.spawn], ["Carried", totals.carried], ["In containers", totals.stored], ["Dropped", totals.ground],
    ].map(([label, value]) => el("div", {}, el("strong", { textContent: value.toLocaleString() }), el("span", { textContent: label }))));
    renderEvents();
  }

  function filter() {
    if (!data) return;
    stop(); focusLayer.clearLayers();
    filteredEvents = data.events.filter((e) => matches(metadata.get(e.item)));
    chart(); seek(cursor, true);
  }

  async function load() {
    stop();
    const seq = ++request;
    const end = Math.floor(new Date($("lootHistoryEnd").value).getTime() / 1000);
    if (!Number.isFinite(end)) { $("lootHistoryStatus").textContent = "Choose a valid end time."; return; }
    const start = end - +$("lootHistoryWindow").value;
    $("loadLootHistory").disabled = true;
    $("lootHistoryStatus").textContent = "Loading recorded loot movements…";
    try {
      const [history, current] = await Promise.all([
        getJSON(`loot-history?from=${start}&to=${end}`, 30000),
        loot.data ? Promise.resolve(loot.data) : getJSON("loot", 15000),
      ]);
      if (seq !== request || !lootHistory.active) return;
      data = history;
      loot.data = current;
      metadata = new Map(data.items.map((i) => [i.id, i]));
      catalogue = new Map(current.spawns.map((s) => [s[0], s]));
      const zone = $("lootHistoryZone").value;
      $("lootHistoryZone").replaceChildren(el("option", { value: "", textContent: "All zones" }), ...[...new Set(current.spawns.map((s) => s[5]))].sort().map((z) => el("option", { value: z, textContent: z.toUpperCase() })));
      $("lootHistoryZone").value = zone;
      $("lootHistoryRange").max = Math.ceil(data.to - data.from);
      $("lootHistoryBody").hidden = false;
      cursor = data.from;
      filter();
      $("lootHistoryStatus").textContent = `${clock(data.from)} → ${clock(data.to)} · ${data.events.length.toLocaleString()} recorded events. Click an event to find it on the map. Orange dots show dropped loot.`;
    } catch (e) {
      if (seq === request && lootHistory.active) $("lootHistoryStatus").textContent = "Could not load history: " + e.message;
    } finally {
      if (seq === request) $("loadLootHistory").disabled = false;
    }
  }

  lootHistory.open = async (spawn) => {
    map.closePopup();
    if (spawn != null) { $("lootHistorySpawn").value = spawn; $("lootHistoryZone").value = ""; }
    if (lootHistory.active) { filter(); return; }
    if (sessionMode) backToLive();
    $("sessions").hidden = true;
    document.body.classList.remove("rail-open");
    $("railToggle").setAttribute("aria-expanded", "false");
    lootHistory.active = true;
    document.body.classList.add("loot-history-mode");
    panel.hidden = false;
    $("openLootHistory").setAttribute("aria-expanded", "true");
    map.removeLayer(playerLayer);
    if ($("layerLoot").checked) movedLayer.addTo(map);
    focusLayer.addTo(map);
    $("lootHistoryEnd").value = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    $("closeLootHistory").focus();
    await load();
  };

  $("openLootHistory").addEventListener("click", () => lootHistory.open());
  $("closeLootHistory").addEventListener("click", () => {
    stop(); request++;
    lootHistory.active = false;
    panel.hidden = true;
    document.body.classList.remove("loot-history-mode");
    $("openLootHistory").setAttribute("aria-expanded", "false");
    $("loadLootHistory").disabled = false;
    map.removeLayer(movedLayer); map.removeLayer(focusLayer); focusLayer.clearLayers();
    if ($("layerPlayers").checked) playerLayer.addTo(map);
    if (loot.data) applyLoot(loot.data);
    pollLoot();
    $("openLootHistory").focus();
  });
  $("lootHistoryForm").addEventListener("submit", (e) => { e.preventDefault(); load(); });
  ["lootHistoryZone", "lootHistorySpawn"].forEach((id) => $(id).addEventListener("change", filter));
  $("lootHistoryKind").addEventListener("change", () => { stop(); renderEvents(); });
  $("lootHistoryRange").addEventListener("input", (e) => { stop(); focusLayer.clearLayers(); if (data) seek(data.from + +e.target.value); });
  $("lootHistoryPlay").addEventListener("click", () => {
    if (timer) { stop(); return; }
    if (!data) return;
    if (cursor >= data.to) seek(data.from);
    $("lootHistoryPlay").textContent = "Pause";
    lastTick = performance.now();
    timer = setInterval(() => {
      const now = performance.now(), elapsed = Math.min(1, (now - lastTick) / 1000);
      lastTick = now;
      seek(cursor + elapsed * +$("lootHistorySpeed").value);
      if (cursor >= data.to) stop();
    }, 250);
  });
  $("layerLoot").addEventListener("change", (e) => {
    if (lootHistory.active && e.target.checked) movedLayer.addTo(map); else map.removeLayer(movedLayer);
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && lootHistory.active) $("closeLootHistory").click(); });
})();
