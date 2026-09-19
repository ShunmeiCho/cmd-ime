(function () {
  "use strict";

  var LANGS = ["en", "zh-CN", "ja"];
  var STORAGE_KEY = "cmdime-lang";
  var RELEASES_URL = "https://github.com/ShunmeiCho/cmd-ime/releases/latest";
  var API_URL = "https://api.github.com/repos/ShunmeiCho/cmd-ime/releases/latest";
  var COPIED_MS = 1600;
  var TITLES = {
    "en": "CmdIME by ShunmeiCho - one key per input source on macOS",
    "zh-CN": "CmdIME by ShunmeiCho - 一个键对应一个输入源",
    "ja": "CmdIME by ShunmeiCho - 入力ソースごとにキーをひとつ"
  };
  var COPIED = { "en": "Copied", "zh-CN": "已复制", "ja": "コピーしました" };

  function normalize(tag) {
    if (!tag) return null;
    var t = String(tag).toLowerCase();
    if (t.indexOf("zh") === 0) return "zh-CN";
    if (t.indexOf("ja") === 0) return "ja";
    if (t.indexOf("en") === 0) return "en";
    return null;
  }

  function readStored() {
    try { return normalize(window.localStorage.getItem(STORAGE_KEY)); } catch (e) { return null; }
  }

  function writeStored(lang) {
    try { window.localStorage.setItem(STORAGE_KEY, lang); } catch (e) { /* storage unavailable */ }
  }

  function fromQuery() {
    var m = /[?&]lang=([^&#]+)/.exec(window.location.search);
    return m ? normalize(decodeURIComponent(m[1])) : null;
  }

  function fromBrowser() {
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language];
    return normalize(list[0]) || "en";
  }

  function currentLang() {
    return document.documentElement.getAttribute("data-ui") || "en";
  }

  function apply(lang) {
    var root = document.documentElement;
    root.setAttribute("data-ui", lang);
    root.setAttribute("lang", lang);
    document.title = TITLES[lang];
    var buttons = document.querySelectorAll("[data-set-lang]");
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i];
      b.setAttribute("aria-pressed", b.getAttribute("data-set-lang") === lang ? "true" : "false");
    }
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      document.body.removeChild(ta);
      if (ok) { resolve(); } else { reject(new Error("copy failed")); }
    });
  }

  function onCopy(button) {
    var source = document.getElementById(button.getAttribute("data-copy"));
    if (!source) return;
    var original = button.innerHTML;
    copyText(source.textContent.trim()).then(function () {
      button.classList.add("is-done");
      button.textContent = COPIED[currentLang()];
      setTimeout(function () {
        button.classList.remove("is-done");
        button.innerHTML = original;
      }, COPIED_MS);
    }, function () {
      // Clipboard blocked: select the command so the user can copy it by hand.
      var range = document.createRange();
      range.selectNodeContents(source);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    });
  }

  function loadLatestZip() {
    if (!window.fetch) return;
    fetch(API_URL, { headers: { "Accept": "application/vnd.github+json" } })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (release) {
        var assets = release && release.assets ? release.assets : [];
        var zip = null;
        for (var i = 0; i < assets.length; i++) {
          if (/\.zip$/i.test(assets[i].name)) { zip = assets[i]; break; }
        }
        if (!zip || !/^https:\/\/github\.com\//.test(zip.browser_download_url)) return;
        document.getElementById("zip-link").href = zip.browser_download_url;
        var version = String(release.tag_name || "").replace(/^v/, "");
        if (/^[0-9A-Za-z.\-]+$/.test(version)) {
          document.getElementById("zip-version").textContent = version;
        }
      })
      .catch(function () {
        document.getElementById("zip-link").href = RELEASES_URL;
      });
  }

  // Keyboard demo: a tap of a modifier alone selects its slot, like the app does.
  var SLOTS = [
    { glyph: "A", name: "English", code: "MetaLeft" },
    { glyph: "中", name: "中文", code: "MetaRight" },
    { glyph: "あ", name: "日本語", code: "ShiftRight" }
  ];
  var TAP_MAX_MS = 600;

  function setupDemo() {
    var demo = document.getElementById("demo");
    if (!demo) return;
    var keys = demo.querySelectorAll("[data-slot]");
    var bubble = document.getElementById("bubble");
    var glyph = document.getElementById("bubble-glyph");
    var name = document.getElementById("bubble-name");
    var inView = false;
    var pending = null;

    function select(index) {
      var key = keys[index];
      for (var i = 0; i < keys.length; i++) {
        keys[i].classList.toggle("is-active", i === index);
        keys[i].setAttribute("aria-pressed", i === index ? "true" : "false");
      }
      bubble.style.setProperty("--slot", key.style.getPropertyValue("--slot"));
      glyph.textContent = SLOTS[index].glyph;
      name.textContent = SLOTS[index].name;
      bubble.hidden = false;
      bubble.classList.remove("is-pop");
      void bubble.offsetWidth; // restart the pop animation
      bubble.classList.add("is-pop");
    }

    demo.addEventListener("click", function (event) {
      var key = event.target.closest("[data-slot]");
      if (key) select(Number(key.getAttribute("data-slot")));
    });

    document.addEventListener("keydown", function (event) {
      if (event.repeat) return;
      pending = null;
      for (var i = 0; i < SLOTS.length; i++) {
        if (SLOTS[i].code === event.code) { pending = { index: i, at: Date.now() }; }
      }
    });
    document.addEventListener("keyup", function (event) {
      var p = pending;
      pending = null;
      if (!inView || !p || SLOTS[p.index].code !== event.code) return;
      if (Date.now() - p.at <= TAP_MAX_MS) select(p.index);
    });
    document.addEventListener("mousedown", function () { pending = null; });

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
      }).observe(demo);
    } else {
      inView = true;
    }
    select(0);
    bubble.classList.remove("is-pop");
  }

  function setupReveal() {
    var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("IntersectionObserver" in window)) return;
    var items = document.querySelectorAll(".section, .install");
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add("is-in"); io.unobserve(entry.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px" });
    for (var i = 0; i < items.length; i++) {
      items[i].classList.add("reveal");
      io.observe(items[i]);
    }
  }

  apply(fromQuery() || readStored() || fromBrowser());
  setupDemo();
  setupReveal();

  document.addEventListener("click", function (event) {
    var langButton = event.target.closest("[data-set-lang]");
    if (langButton) {
      var lang = langButton.getAttribute("data-set-lang");
      if (LANGS.indexOf(lang) !== -1) { apply(lang); writeStored(lang); }
      return;
    }
    var copyButton = event.target.closest("[data-copy]");
    if (copyButton) onCopy(copyButton);
  });

  loadLatestZip();
})();
