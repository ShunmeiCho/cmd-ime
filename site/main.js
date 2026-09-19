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
  var COPY_MANUAL = {
    "en": "Copying is blocked here. The command is selected; copy it with Command+C.",
    "zh-CN": "此处无法自动复制。命令已选中，请按 Command+C 复制。",
    "ja": "ここでは自動でコピーできません。コマンドを選択したので、Command+C でコピーしてください。"
  };

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
    var status = document.getElementById("copy-status");
    copyText(source.textContent.trim()).then(function () {
      button.classList.add("is-done");
      button.textContent = COPIED[currentLang()];
      if (status) status.textContent = COPIED[currentLang()];
      setTimeout(function () {
        button.classList.remove("is-done");
        button.innerHTML = original;
        if (status) status.textContent = "";
      }, COPIED_MS);
    }, function () {
      // Clipboard blocked: select the command so the user can copy it by hand.
      if (status) status.textContent = COPY_MANUAL[currentLang()];
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

  // Promo video: autoplay muted while on screen, pause off screen. The native
  // controls stay, so Pause is always available; a pause by the viewer sticks.
  // Under reduced motion it keeps the poster and waits for Play.
  function setupPromo() {
    var video = document.getElementById("promo-video");
    if (!video) return;
    var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("IntersectionObserver" in window)) return;
    video.muted = true;
    var viewerPaused = false;
    var ourPause = false;
    video.addEventListener("pause", function () { if (!ourPause) viewerPaused = true; ourPause = false; });
    video.addEventListener("play", function () { viewerPaused = false; });
    new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) {
        if (viewerPaused) return;
        var played = video.play();
        if (played && played.catch) played.catch(function () { /* autoplay refused: controls are there */ });
      } else if (!video.paused) {
        ourPause = true;
        video.pause();
      }
    }, { threshold: 0.35 }).observe(video);
  }

  apply(fromQuery() || readStored() || fromBrowser());
  setupPromo();

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
