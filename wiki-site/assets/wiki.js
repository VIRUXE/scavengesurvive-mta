// The language menu opens the same page in the other language. Every page exists in both (an untranslated one shows
// the English), English at the root and Portuguese under /pt/, so swapping the prefix is enough; Material's own
// stay-on-page check needs one sitemap covering both languages, which two separate builds do not have.
document.addEventListener(
  "click",
  function (e) {
    var a = e.target.closest && e.target.closest("a.md-select__link[hreflang]");
    if (!a) return;
    var lang = a.getAttribute("hreflang");
    var path = location.pathname.replace(/^\/pt(\/|$)/, "/");
    if (lang !== "en") path = "/" + lang + path;
    e.preventDefault();
    e.stopImmediatePropagation();
    location.href = path + location.hash;
  },
  true
);

// The map explorer (the website's, site/assets/js/site.js initMap): a page writes
//   <div class="wiki-map"><button data-layer="zones" data-src="images/map/zones.png" data-caption="...">Zones</button>...</div>
// and gets a square stage with every layer stacked (loaded when first shown), drag to pan, wheel, pinch, double-click
// and buttons to zoom, the buttons as layer chips and the caption of the layer shown. The first button is shown first.
function initWikiMaps() {
  document.querySelectorAll(".wiki-map:not(.is-ready)").forEach(function (root) {
    var buttons = Array.prototype.slice.call(root.querySelectorAll("button[data-layer]"));
    if (!buttons.length) return;
    root.classList.add("is-ready");
    root.innerHTML =
      '<div class="wiki-map__stage"><div class="wiki-map__layers"></div>' +
      '<div class="wiki-map__hud"><button data-act="in" aria-label="Zoom in">+</button>' +
      '<button data-act="out" aria-label="Zoom out">−</button><button data-act="reset" aria-label="Reset">⟲</button></div></div>' +
      '<div class="wiki-map__panel"><div class="wiki-map__chips"></div><p class="wiki-map__caption"></p></div>';
    var stage = root.querySelector(".wiki-map__stage");
    var layers = root.querySelector(".wiki-map__layers");
    var chips = root.querySelector(".wiki-map__chips");
    var caption = root.querySelector(".wiki-map__caption");
    var imgs = buttons.map(function (b) {
      var im = document.createElement("img");
      im.alt = b.textContent.trim();
      im.dataset.src = b.getAttribute("data-src");
      im.draggable = false;
      layers.appendChild(im);
      b.className = "wiki-map__chip";
      b.type = "button";
      chips.appendChild(b);
      return im;
    });

    function setLayer(i) {
      imgs.forEach(function (im, j) {
        im.classList.toggle("is-on", i === j);
        if (i === j && im.dataset.src) {
          im.src = im.dataset.src;
          delete im.dataset.src;
        }
      });
      buttons.forEach(function (b, j) {
        b.setAttribute("aria-pressed", String(i === j));
      });
      caption.textContent = buttons[i].getAttribute("data-caption") || "";
    }
    buttons.forEach(function (b, i) {
      b.addEventListener("click", function () {
        setLayer(i);
      });
    });
    setLayer(0);

    var scale = 1, tx = 0, ty = 0, drag = null, pinch = null;
    var pts = new Map();
    function apply() {
      layers.style.transform = "translate(" + tx + "px," + ty + "px) scale(" + scale + ")";
    }
    function clamp() {
      var s = stage.clientWidth, min = s - s * scale;
      tx = Math.min(0, Math.max(min, tx));
      ty = Math.min(0, Math.max(min, ty));
    }
    function zoomAt(f, cx, cy) {
      var ns = Math.min(6, Math.max(1, scale * f)), k = ns / scale;
      tx = cx - (cx - tx) * k;
      ty = cy - (cy - ty) * k;
      scale = ns;
      clamp();
      apply();
    }
    function local(e) {
      var r = stage.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    }
    stage.addEventListener("wheel", function (e) {
      e.preventDefault();
      var p = local(e);
      zoomAt(e.deltaY < 0 ? 1.18 : 1 / 1.18, p[0], p[1]);
    }, { passive: false });
    stage.addEventListener("dblclick", function (e) {
      var p = local(e);
      zoomAt(1.6, p[0], p[1]);
    });
    stage.addEventListener("pointerdown", function (e) {
      if (e.target.closest(".wiki-map__hud")) return;
      pts.set(e.pointerId, e);
      stage.setPointerCapture(e.pointerId);
      if (pts.size === 2) {
        drag = null;
        var v = Array.from(pts.values());
        pinch = { d: Math.hypot(v[0].clientX - v[1].clientX, v[0].clientY - v[1].clientY), s: scale };
      } else {
        drag = { x: e.clientX - tx, y: e.clientY - ty };
      }
    });
    stage.addEventListener("pointermove", function (e) {
      if (!pts.has(e.pointerId)) return;
      pts.set(e.pointerId, e);
      if (pinch && pts.size === 2) {
        var v = Array.from(pts.values());
        var d = Math.hypot(v[0].clientX - v[1].clientX, v[0].clientY - v[1].clientY);
        var r = stage.getBoundingClientRect();
        zoomAt((pinch.s * d) / pinch.d / scale, (v[0].clientX + v[1].clientX) / 2 - r.left, (v[0].clientY + v[1].clientY) / 2 - r.top);
      } else if (drag) {
        tx = e.clientX - drag.x;
        ty = e.clientY - drag.y;
        clamp();
        apply();
      }
    });
    ["pointerup", "pointercancel"].forEach(function (ev) {
      stage.addEventListener(ev, function (e) {
        pts.delete(e.pointerId);
        if (pts.size < 2) pinch = null;
        if (!pts.size) drag = null;
      });
    });
    root.querySelectorAll(".wiki-map__hud button").forEach(function (b) {
      b.addEventListener("click", function () {
        var s = stage.clientWidth / 2;
        if (b.dataset.act === "in") zoomAt(1.4, s, s);
        else if (b.dataset.act === "out") zoomAt(1 / 1.4, s, s);
        else {
          scale = 1;
          tx = 0;
          ty = 0;
          apply();
        }
      });
    });
  });
}

// Material's instant navigation swaps pages without a reload: document$ emits on every page shown.
if (typeof document$ !== "undefined") document$.subscribe(initWikiMaps);
else document.addEventListener("DOMContentLoaded", initWikiMaps);
