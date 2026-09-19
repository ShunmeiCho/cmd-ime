/* One glyph field behind the whole page, one canvas, one animation loop.
   - Inside the hero: multilingual rain. Columns fall at irregular speeds and
     lengths, glyphs flicker, heads are brighter and sometimes take a slot colour.
     A language switch in the demo (event "cmdime:switch") briefly biases the rain
     toward that language's script and colour.
   - Below the hero: a sparse, slow, faint ambient drift that now and then flickers
     to another script. Content sits above it on its own surfaces.
   Guardrails: DPR capped at 2, columns capped by width, sparser on phones, the
   hero rain only advances while the hero is on screen, the loop stops when the
   tab is hidden, reduced motion draws one static frame, light mode keeps only a
   faint hero rain.
   State for tests: window.__glyphField. */
(function () {
  "use strict";

  var canvas = document.getElementById("glyph-field");
  var hero = document.querySelector(".hero");
  if (!canvas || !hero || !canvas.getContext) return;
  var ctx = canvas.getContext("2d");

  var SCRIPTS = {
    latin: "ABCDEFGHJKLMNPRSTUVWXYZabcdefghkmnpqrstuvwxyz",
    fr: "éèêàâçôîûœÉÇ",
    de: "äöüßÄÖÜ",
    es: "ñáíóú¿¡",
    cjk: "中文字語言輸入漢法書写读音鍵盤",
    kana: "あいうえおかきくさしすにんアカサタナハマラン",
    hangul: "한글어안녕하세요말자키",
    cyrillic: "ДЖЗИЛПФЦЧШЩЫЭЮЯбвгдж",
    greek: "ΑΒΓΔΘΛΞΠΣΦΨΩαβγδλπσφ",
    arabic: "ابتثجحخدذرزسشصضطعغفقكلمن",
    hebrew: "אבגדהוזחטיכלמנסעפצקרשת",
    devanagari: "कखगघचछजझटठडढणतथदधनपफबभम",
    thai: "กขคฆงจฉชซญดตถทธนบปผฝพฟมย"
  };
  // Demo slot index -> the script its pulse leans toward.
  var SLOT_SCRIPTS = [["latin"], ["cjk"], ["kana"], ["hangul"], ["fr", "latin"], ["de", "latin"]];
  var SLOT_VARS = ["--slot-blue", "--slot-green", "--slot-red", "--slot-purple", "--slot-orange", "--slot-teal"];

  // One switch for the ambient layer below the hero. false: rain in the hero only.
  var AMBIENT_BELOW_HERO = true;
  // Ambient glyphs over the content column are drawn at this fraction of their alpha.
  // 1: the glass panels carry legibility, and the drift should read through them.
  var AMBIENT_TEXT_COLUMN_FACTOR = 1;

  var FONT ='-apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans", "Apple SD Gothic Neo", "Noto Sans", "Segoe UI", sans-serif';
  var FRAME_MS = 33;             // about 30 frames a second is enough for rain
  var MAX_DPR = 2;
  var MAX_COLUMNS = 72;
  var PULSE_MS = 1600;
  var SLOT_HEAD_CHANCE = 0.08;
  var FLICKER_CHANCE = 0.035;
  var AMBIENT_FLICKER_CHANCE = 0.004;
  var PHONE_MAX = 760;

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var lightQuery = window.matchMedia && window.matchMedia("(prefers-color-scheme: light)");

  var state = window.__glyphField = { frames: 0, heroFrames: 0, running: false, columns: 0, ambient: 0, mode: reduce ? "static" : "animated" };

  // ---- Glyphs that actually render with the system fonts ----
  var pools = {};
  var allGlyphs = [];
  (function buildPools() {
    var probe = document.createElement("canvas");
    probe.width = probe.height = 24;
    var p = probe.getContext("2d", { willReadFrequently: true });
    p.font = "18px " + FONT;
    p.textBaseline = "top";
    function sig(ch) {
      p.clearRect(0, 0, 24, 24);
      p.fillText(ch, 2, 2);
      var d = p.getImageData(0, 0, 24, 24).data, sum = 0, n = 0;
      for (var i = 3; i < d.length; i += 4) { sum += d[i] * ((i >> 2) % 97 + 1); if (d[i]) n++; }
      return n ? sum + ":" + n : "";
    }
    var missing = sig(String.fromCodePoint ? String.fromCodePoint(0x10fffd) : "￾");
    Object.keys(SCRIPTS).forEach(function (name) {
      var ok = [];
      Array.from(SCRIPTS[name]).forEach(function (ch) {
        var s = sig(ch);
        if (s && s !== missing) ok.push(ch);
      });
      pools[name] = ok;
      allGlyphs = allGlyphs.concat(ok);
    });
  })();
  if (!allGlyphs.length) return;

  function pick(list) { return list[(Math.random() * list.length) | 0]; }
  function rand(a, b) { return a + Math.random() * (b - a); }

  // ---- Colour ----
  function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
  var slotColours = [];
  var isLight = false;
  function readColours() {
    slotColours = SLOT_VARS.map(cssVar);
    isLight = !!(lightQuery && lightQuery.matches);
  }

  // ---- Pulse from the demo ----
  var pulse = null;
  window.addEventListener("cmdime:switch", function (e) {
    var slot = e.detail && e.detail.slot;
    if (slot >= 0 && slot < SLOT_SCRIPTS.length) pulse = { slot: slot, until: performance.now() + PULSE_MS };
  });
  function nextGlyph(now) {
    if (pulse && now < pulse.until && Math.random() < 0.75) {
      var names = SLOT_SCRIPTS[pulse.slot];
      var pool = pools[pick(names)];
      if (pool && pool.length) return pick(pool);
    }
    return pick(allGlyphs);
  }

  // ---- Geometry ----
  var vw = 0, vh = 0, dpr = 1, phone = false;
  var fontPx = 16, rowH = 20;
  var heroH = 0, heroTextBottom = 0, heroFadeBottom = 0;
  var columns = [];
  var ambient = [];

  var textLeft = 0, textRight = 0;
  function measureHero() {
    var column = document.querySelector("main .section") || hero;
    var cr = column.getBoundingClientRect();
    textLeft = cr.left;
    textRight = cr.right;
    var h = hero.getBoundingClientRect();
    var head = hero.querySelector(".hero-head");
    heroH = h.height;
    heroTextBottom = head ? head.getBoundingClientRect().bottom - h.top : 0;
    heroFadeBottom = heroH;
  }

  function newColumn(x, scatter) {
    return {
      x: x,
      y: scatter ? rand(-heroH * 0.3, heroH) : rand(-heroH * 0.6, 0),
      speed: rand(phone ? 40 : 55, phone ? 150 : 210),   // px per second, irregular on purpose
      len: (rand(6, phone ? 14 : 22)) | 0,
      glyphs: [],
      row: -1,
      head: null
    };
  }

  function resize() {
    // clientWidth, not innerWidth: innerWidth includes the scrollbar, which put the
    // last column under it and clipped its head at the right edge.
    vw = document.documentElement.clientWidth;
    vh = window.innerHeight;
    dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    phone = vw <= PHONE_MAX;
    fontPx = phone ? 15 : 16;
    rowH = Math.round(fontPx * 1.25);
    canvas.width = Math.round(vw * dpr);
    canvas.height = Math.round(vh * dpr);
    canvas.style.width = vw + "px";
    canvas.style.height = vh + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.textBaseline = "top";
    ctx.textAlign = "center";
    measureHero();
    readColours();

    var pitch = phone ? 34 : 22;
    var count = Math.min(MAX_COLUMNS, Math.floor(vw / pitch));
    columns = [];
    for (var i = 0; i < count; i++) {
      var x = Math.min(vw - fontPx, Math.max(fontPx, (i + 0.5) * (vw / count) + rand(-3, 3)));
      columns.push(newColumn(x, true));
    }
    var ambientCount = Math.round((vw * vh) / (phone ? 22000 : 26000));
    ambient = [];
    for (var j = 0; j < ambientCount; j++) {
      ambient.push({ x: rand(12, vw - 12), y: rand(0, vh), speed: rand(5, 14), ch: pick(allGlyphs), a: rand(0.07, 0.14), size: rand(16, 28) | 0 });
    }
    state.columns = columns.length;
    state.ambient = ambient.length;
  }

  // Keep the rain away from the headline, lede and Install button, and fade it at the bottom.
  function heroMask(y) {
    var fadeIn = 90, fadeOut = 110;
    if (y < heroTextBottom) return 0;
    if (y < heroTextBottom + fadeIn) return (y - heroTextBottom) / fadeIn;
    if (y > heroFadeBottom - fadeOut) return Math.max(0, (heroFadeBottom - y) / fadeOut);
    return 1;
  }

  // ---- Drawing ----
  function drawHero(now, dt, top, animate) {
    var base = isLight ? "92, 92, 102" : "127, 127, 138";
    var trailAlpha = isLight ? 0.14 : 0.3;
    var headAlpha = isLight ? 0.3 : 0.8;
    ctx.font = fontPx + "px " + FONT;
    for (var c = 0; c < columns.length; c++) {
      var col = columns[c];
      if (animate) {
        col.y += col.speed * dt;
        if ((col.y - col.len * rowH) > heroH) {
          var fresh = newColumn(col.x, false);
          fresh.x = col.x;
          columns[c] = col = fresh;
        }
        var row = Math.floor(col.y / rowH);
        while (col.row < row) {
          col.row++;
          col.glyphs.unshift(nextGlyph(now));
          if (col.glyphs.length > col.len) col.glyphs.pop();
          var pulsing = pulse && now < pulse.until;
          col.head = pulsing && Math.random() < 0.6 ? slotColours[pulse.slot]
            : Math.random() < SLOT_HEAD_CHANCE ? pick(slotColours) : null;
        }
        for (var f = 1; f < col.glyphs.length; f++) {
          if (Math.random() < FLICKER_CHANCE) col.glyphs[f] = nextGlyph(now);
        }
      }
      for (var i = 0; i < col.glyphs.length; i++) {
        var y = (col.row - i) * rowH;
        if (y < 0 || y > heroH) continue;
        var screenY = top + y;
        if (screenY < -rowH || screenY > vh) continue;
        var m = heroMask(y);
        if (m <= 0) continue;
        if (i === 0) {
          ctx.fillStyle = col.head || (isLight ? "rgba(40, 40, 48, 1)" : "rgba(214, 214, 222, 1)");
          ctx.globalAlpha = headAlpha * m;
        } else {
          ctx.fillStyle = "rgb(" + base + ")";
          ctx.globalAlpha = trailAlpha * m * (1 - i / col.glyphs.length);
        }
        ctx.fillText(col.glyphs[i], col.x, screenY);
      }
    }
    ctx.globalAlpha = 1;
  }

  function drawAmbient(dt, heroTop, heroBottom, animate) {
    if (!AMBIENT_BELOW_HERO || isLight) return; // light page: too close to the text colour
    for (var i = 0; i < ambient.length; i++) {
      var g = ambient[i];
      if (animate) {
        g.y += g.speed * dt;
        if (g.y > vh + 20) { g.y = -20; g.x = rand(12, vw - 12); }
        if (Math.random() < AMBIENT_FLICKER_CHANCE) g.ch = pick(allGlyphs);
      }
      if (g.y > heroTop - 20 && g.y < heroBottom) continue; // the hero has its own rain
      var overText = g.x > textLeft && g.x < textRight;
      ctx.font = g.size + "px " + FONT;
      ctx.fillStyle = "rgba(127, 127, 138, " + (overText ? g.a * AMBIENT_TEXT_COLUMN_FACTOR : g.a) + ")";
      ctx.fillText(g.ch, g.x, g.y);
    }
  }

  function render(now, dt, animate) {
    var h = hero.getBoundingClientRect();
    ctx.clearRect(0, 0, vw, vh);
    var heroOnScreen = h.bottom > 0 && h.top < vh;
    if (heroOnScreen) {
      drawHero(now, dt, h.top, animate);
      if (animate) state.heroFrames++;
    }
    drawAmbient(dt, h.top, h.bottom, animate);
    state.frames++;
  }

  // ---- Loop ----
  var raf = 0, last = 0, acc = 0;
  function frame(now) {
    raf = window.requestAnimationFrame(frame);
    var elapsed = last ? now - last : FRAME_MS;
    last = now;
    acc += elapsed;
    if (acc < FRAME_MS) return;
    var dt = Math.min(acc, 100) / 1000;
    acc = 0;
    render(now, dt, true);
  }
  function start() {
    if (raf || reduce || document.hidden) return;
    last = 0;
    state.running = true;
    raf = window.requestAnimationFrame(frame);
  }
  function stop() {
    if (raf) window.cancelAnimationFrame(raf);
    raf = 0;
    state.running = false;
  }

  // Reduced motion: one static frame, scattered glyphs, redrawn only when the view changes.
  function staticFrame() {
    for (var c = 0; c < columns.length; c++) {
      var col = columns[c];
      col.row = Math.floor(rand(0, heroH / rowH));
      col.glyphs = [];
      for (var i = 0; i < col.len; i++) col.glyphs.push(pick(allGlyphs));
    }
    render(performance.now(), 0, false);
  }
  var staticQueued = false;
  function redrawStatic() {
    if (staticQueued) return;
    staticQueued = true;
    window.requestAnimationFrame(function () { staticQueued = false; render(performance.now(), 0, false); });
  }

  resize();
  window.addEventListener("resize", function () { resize(); if (reduce) staticFrame(); });
  if (lightQuery && lightQuery.addEventListener) lightQuery.addEventListener("change", readColours);
  if ("ResizeObserver" in window) new ResizeObserver(measureHero).observe(hero);

  if (reduce) {
    staticFrame();
    // The canvas is fixed and the hero scrolls, so the still frame follows the page.
    window.addEventListener("scroll", redrawStatic, { passive: true });
  } else {
    document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else start(); });
    start();
  }
})();
