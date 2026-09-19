/* Hero demo.
   Six slots, each on its own one-shot modifier, laid out as on a Mac keyboard.
   - A tap is keydown then keyup of the same event.code, no other key in between,
     within TAP_MAX_MS. Chords and held keys never switch.
   - Physical keys are matched by event.code only; the lit cap is looked up by
     data-slot, never by DOM position.
   - The output is scripted text; the page never reads typing, so it does not
     depend on the Mac's selected input source.
   - Autoplay story: one mixed-language sentence per page language, typed at a
     natural cadence, switching mid-sentence (cap presses, bubble pops, typing goes
     on). Then the remaining languages one by one, so all six appear per cycle.
   - Manual use (a key tap or a cap click) latches manual mode: each switch
     replaces the sample. Only Replay restarts autoplay.
   State for tests: stage.dataset.mode is "auto", "manual", "paused" or "static";
   window.__cmdimeDemo exposes the sentences. */
(function () {
  "use strict";

  var SLOTS = [
    { code: "MetaLeft", glyph: "A", title: "English", phrase: "Hello" },
    { code: "MetaRight", glyph: "中", title: "中文", phrase: "你好" },
    { code: "ShiftRight", glyph: "あ", title: "日本語", phrase: "こんにちは" },
    { code: "AltLeft", glyph: "한", title: "한국어", phrase: "안녕하세요" },
    { code: "AltRight", glyph: "Fr", title: "Français", phrase: "Bonjour" },
    { code: "ShiftLeft", glyph: "De", title: "Deutsch", phrase: "Hallo" }
  ];
  // One short sentence per page language, as [slot, text] segments.
  var SENTENCES = {
    "en": [[0, "Thanks, "], [4, "merci, "], [5, "danke! "], [0, "See you, "], [3, "안녕"]],
    "zh-CN": [[1, "明天的 "], [0, "meeting"], [1, " 改到下午，"], [2, "よろしく！"]],
    "ja": [[2, "明日の "], [0, "demo"], [2, " のあとで "], [1, "谢谢"], [2, " と伝えてね。"]]
  };
  window.__cmdimeDemo = { sentences: SENTENCES };

  var TAP_MAX_MS = 600;
  var TYPE_MS = 95;            // natural cadence, plus jitter
  var TYPE_JITTER_MS = 70;
  var SWITCH_BEAT_MS = 140;    // a beat for the key press between segments
  var SENTENCE_HOLD_MS = 2200;
  var SHOWCASE_HOLD_MS = 1300;
  var CYCLE_PAUSE_MS = 1600;
  var PRESS_MS = 170;
  var BUBBLE_GAP = 8;
  var EDGE = 12;

  var stage = document.getElementById("stage");
  if (!stage) return;
  var field = document.getElementById("field");
  var textEl = document.getElementById("field-text");
  var caret = document.getElementById("caret");
  var bubble = document.getElementById("bubble");
  var glyphEl = document.getElementById("bubble-glyph");
  var titleEl = document.getElementById("bubble-title");
  var replay = document.getElementById("replay");
  var playBtn = document.getElementById("play-demo");
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var current = 0;
  var manual = false;
  var playOnce = false;   // reduced motion: one run of the story, on request
  var visible = true;
  var pending = null;

  function pageLang() { return document.documentElement.getAttribute("data-ui") || "en"; }
  function capFor(i) { return stage.querySelector('[data-slot="' + i + '"]'); }
  function slotColour(i) { return capFor(i).style.getPropertyValue("--slot"); }
  function setMode(mode) { stage.dataset.mode = mode; }

  // ---- Bubble, anchored under the caret after layout ----
  function placeBubble() {
    var f = field.getBoundingClientRect();
    var c = caret.getBoundingClientRect();
    var w = bubble.offsetWidth;
    var h = bubble.offsetHeight;
    var maxLeft = field.clientWidth - w - EDGE;
    var cx = c.left - f.left;
    var left = Math.max(EDGE, Math.min(cx - w / 2, maxLeft));
    var top;
    // Just above the caret while it is on the first line, as in the reference. On a
    // later line that would cover the line above, so it goes beside the caret if there
    // is room, otherwise just below it.
    var firstLineTop = textEl.getClientRects().length ? textEl.getClientRects()[0].top : c.top;
    if (c.top <= firstLineTop + 2) {
      top = c.top - f.top - h - BUBBLE_GAP;
    } else if (cx + BUBBLE_GAP + w <= field.clientWidth - EDGE) {
      left = cx + BUBBLE_GAP;
      top = c.top - f.top + (c.height - h) / 2;
    } else {
      top = c.bottom - f.top + BUBBLE_GAP;
    }
    top = Math.max(EDGE / 2, Math.min(top, field.clientHeight - h - EDGE / 2));
    bubble.style.left = Math.round(left) + "px";
    bubble.style.top = Math.round(top) + "px";
  }
  function placeBubbleSoon() { window.requestAnimationFrame(placeBubble); }

  // ---- Text: tinted segments, one per switch ----
  function clearText() { textEl.textContent = ""; placeBubbleSoon(); }
  function startSegment(slot) {
    var span = document.createElement("span");
    span.className = "seg";
    span.style.setProperty("--seg", slotColour(slot));
    textEl.appendChild(span);
    return span;
  }
  function lastSegment() { return textEl.lastElementChild; }
  function typeChar(ch) {
    var seg = lastSegment() || startSegment(current);
    seg.textContent += ch;
    placeBubbleSoon();
  }

  // ---- Switching (same path for keys, caps and autoplay) ----
  function press(index) {
    var cap = capFor(index);
    cap.classList.add("is-pressed");
    setTimeout(function () { cap.classList.remove("is-pressed"); }, PRESS_MS);
  }
  function select(index) {
    current = index;
    var caps = stage.querySelectorAll("[data-slot]");
    for (var k = 0; k < caps.length; k++) {
      var on = Number(caps[k].getAttribute("data-slot")) === index;
      caps[k].classList.toggle("is-active", on);
      caps[k].setAttribute("aria-pressed", on ? "true" : "false");
    }
    var colour = slotColour(index);
    field.style.setProperty("--slot", colour);
    bubble.style.setProperty("--slot", colour);
    glyphEl.textContent = SLOTS[index].glyph;
    titleEl.textContent = SLOTS[index].title;
    bubble.dataset.slot = String(index);
    bubble.classList.remove("is-shown");
    void bubble.offsetWidth; // restart the pop transition
    bubble.classList.add("is-shown");
    placeBubbleSoon();
    window.dispatchEvent(new CustomEvent("cmdime:switch", { detail: { slot: index } }));
  }

  // ---- The script: a list of steps run by one timer, so it can pause and resume ----
  // Step kinds: clear, switch (slot, press, fresh segment), char, wait.
  function sentenceSteps(lang) {
    var steps = [{ kind: "clear" }];
    SENTENCES[lang].forEach(function (seg) {
      steps.push({ kind: "switch", slot: seg[0] });
      Array.from(seg[1]).forEach(function (ch) { steps.push({ kind: "char", ch: ch }); });
    });
    steps.push({ kind: "wait", ms: SENTENCE_HOLD_MS });
    return steps;
  }
  function showcaseSteps(lang) {
    var used = {};
    SENTENCES[lang].forEach(function (seg) { used[seg[0]] = true; });
    var rest = [0, 1, 2, 3, 4, 5].filter(function (i) { return !used[i]; });
    for (var i = rest.length - 1; i > 0; i--) { // a little variety in the order
      var j = Math.floor(Math.random() * (i + 1));
      var t = rest[i]; rest[i] = rest[j]; rest[j] = t;
    }
    var steps = [];
    rest.forEach(function (slot) {
      steps.push({ kind: "clear" }, { kind: "switch", slot: slot });
      Array.from(SLOTS[slot].phrase).forEach(function (ch) { steps.push({ kind: "char", ch: ch }); });
      steps.push({ kind: "wait", ms: SHOWCASE_HOLD_MS });
    });
    steps.push({ kind: "wait", ms: CYCLE_PAUSE_MS });
    return steps;
  }

  var script = [];
  var cursor = 0;
  var stepTimer = null;

  function runStep(step) {
    if (step.kind === "clear") { clearText(); return 0; }
    if (step.kind === "switch") { press(step.slot); select(step.slot); startSegment(step.slot); return SWITCH_BEAT_MS; }
    if (step.kind === "char") { typeChar(step.ch); return TYPE_MS + Math.random() * TYPE_JITTER_MS; }
    return step.ms;
  }
  function tick() {
    stepTimer = null;
    if (!canAutoplay()) { if (!manual) setMode("paused"); return; }
    setMode("auto");
    if (cursor >= script.length) {
      if (playOnce) { finishPlayOnce(); return; }
      script = sentenceSteps(pageLang()).concat(showcaseSteps(pageLang()));
      cursor = 0;
    }
    var step = script[cursor];
    cursor += 1;
    field.classList.toggle("is-typing", step.kind === "char");
    stepTimer = setTimeout(tick, runStep(step));
  }
  function stopScript() {
    if (stepTimer) { clearTimeout(stepTimer); stepTimer = null; }
    field.classList.remove("is-typing");
  }
  // Finish the word being typed, so an interruption never leaves half a word.
  function finishWord() {
    while (cursor < script.length && script[cursor].kind === "char") { typeChar(script[cursor].ch); cursor += 1; }
  }
  function canAutoplay() { return (!reduceMotion || playOnce) && !manual && visible && !document.hidden; }
  function resumeAuto() {
    if ((reduceMotion && !playOnce) || manual || stepTimer) return;
    if (canAutoplay()) tick(); else setMode("paused");
  }
  function restartStory() { stopScript(); script = []; cursor = 0; resumeAuto(); }

  // ---- Manual mode: each switch replaces the sample ----
  var manualTimer = null;
  function playSample(index) {
    if (manualTimer) { clearInterval(manualTimer); manualTimer = null; }
    select(index);
    clearText();
    startSegment(index);
    var word = SLOTS[index].phrase;
    if (reduceMotion) { typeChar(word); return; }
    var i = 0;
    field.classList.add("is-typing");
    manualTimer = setInterval(function () {
      typeChar(word.charAt(i));
      i += 1;
      if (i >= word.length) { clearInterval(manualTimer); manualTimer = null; field.classList.remove("is-typing"); }
    }, TYPE_MS);
  }

  // Reduced motion: no autoplay, but the story plays once when asked. State changes
  // are instant (no pop, no rain pulse); the typing stays because it is the content.
  function playDemoOnce() {
    stopScript();
    manual = false;
    playOnce = true;
    playBtn.hidden = true;
    script = sentenceSteps(pageLang());
    cursor = 0;
    resumeAuto();
  }
  function finishPlayOnce() {
    playOnce = false;
    stopScript();
    setMode("static");
    playBtn.hidden = false;
  }

  function goManual() {
    if (playOnce) { playOnce = false; stopScript(); finishWord(); playBtn.hidden = false; }
    if (manual) return;
    manual = true;
    stopScript();
    finishWord();
    setMode("manual");
    if (!reduceMotion) replay.hidden = false;
  }
  function replayDemo() {
    if (manualTimer) { clearInterval(manualTimer); manualTimer = null; }
    manual = false;
    replay.hidden = true;
    restartStory();
  }

  // ---- Input ----
  playBtn.addEventListener("click", playDemoOnce);
  stage.addEventListener("pointerdown", function (event) {
    if (!event.target.closest("#replay, #play-demo")) goManual();
  });
  stage.addEventListener("focusin", function (event) {
    if (!event.target.closest("#replay, #play-demo")) goManual();
  });
  stage.addEventListener("click", function (event) {
    if (event.target.closest("#replay")) { replayDemo(); return; }
    var cap = event.target.closest("[data-slot]");
    if (!cap) return;
    goManual();
    playSample(Number(cap.getAttribute("data-slot")));
  });

  function slotForCode(code) {
    for (var i = 0; i < SLOTS.length; i++) if (SLOTS[i].code === code) return i;
    return -1;
  }
  document.addEventListener("keydown", function (event) {
    if (event.repeat) return;
    var index = slotForCode(event.code);
    pending = index >= 0 ? { index: index, code: event.code, at: Date.now() } : null;
    if (index >= 0 && visible) {
      goManual();
      capFor(index).classList.add("is-pressed");
    }
  }, true);
  document.addEventListener("keyup", function (event) {
    var index = slotForCode(event.code);
    if (index >= 0) capFor(index).classList.remove("is-pressed");
    var p = pending;
    pending = null;
    if (!visible || !p || p.code !== event.code) return;
    if (Date.now() - p.at > TAP_MAX_MS) return;
    playSample(p.index);
  }, true);
  document.addEventListener("mousedown", function () { pending = null; }, true);
  window.addEventListener("blur", function () { pending = null; });

  window.addEventListener("resize", placeBubbleSoon);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeBubbleSoon);

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) { stopScript(); if (!manual && !reduceMotion) setMode("paused"); }
    else resumeAuto();
  });
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      visible = entries[0].isIntersecting;
      if (visible) resumeAuto();
      else { stopScript(); if (!manual && !reduceMotion) setMode("paused"); }
    }).observe(stage);
  }

  // ---- Reduced motion: the finished sentence, still ----
  function staticSentence() {
    clearText();
    var segs = SENTENCES[pageLang()];
    segs.forEach(function (seg) { startSegment(seg[0]); typeChar(seg[1]); });
    select(segs[segs.length - 1][0]);
  }

  // A page language change starts that language's sentence.
  new MutationObserver(function () {
    if (reduceMotion) staticSentence();
    else if (!manual) restartStory();
  }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-ui"] });

  // ---- Start ----
  if (reduceMotion) {
    staticSentence();
    setMode("static");
    playBtn.hidden = false;
  } else {
    setMode("paused");
    resumeAuto();
  }
})();
