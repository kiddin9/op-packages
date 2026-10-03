/*
 * luci-theme-shadcnui — theme.js
 * Reads UCI-derived <html data-*> attributes, applies system preference when
 * needed, and persists user overrides to localStorage as a fast path before
 * the next page load (the source of truth stays /etc/config/shadcnui).
 */
(function () {
  'use strict';

  var root = document.documentElement;
  var LS_KEY = 'shadcnui:overrides';

  function readOverrides() {
    try { return JSON.parse(localStorage.getItem(LS_KEY) || '{}'); }
    catch (e) { return {}; }
  }
  function writeOverrides(o) {
    try { localStorage.setItem(LS_KEY, JSON.stringify(o || {})); }
    catch (e) { /* ignore quota / private mode */ }
  }

  function applyMode(mode) {
    // mode: 'light' | 'dark' | 'system'
    if (mode === 'system') {
      var prefersDark = window.matchMedia &&
                        window.matchMedia('(prefers-color-scheme: dark)').matches;
      root.setAttribute('data-theme', prefersDark ? 'dark' : 'light');
    } else {
      root.setAttribute('data-theme', mode === 'dark' ? 'dark' : 'light');
    }
    root.setAttribute('data-mode', mode);
  }

  function applyBase(base) {
    var allowed = ['zinc', 'slate', 'stone', 'gray', 'neutral'];
    if (allowed.indexOf(base) === -1) base = 'zinc';
    root.setAttribute('data-base', base);
  }

  function applyAccent(hsl) {
    // hsl: "240 5.9% 10%" or null to reset
    if (!hsl) {
      root.style.removeProperty('--primary');
      root.style.removeProperty('--ring');
      return;
    }
    root.style.setProperty('--primary', hsl);
    root.style.setProperty('--ring', hsl);
  }

  function applyLoginBg(url) {
    if (!url) {
      root.style.removeProperty('--login-bg');
      return;
    }
    root.style.setProperty('--login-bg', 'url("' + url.replace(/"/g, '\\"') + '")');
  }

  // Public API exposed so config page can preview live.
  window.shadcnuiTheme = {
    setMode: function (mode) {
      var o = readOverrides(); o.mode = mode; writeOverrides(o);
      applyMode(mode);
    },
    setBase: function (base) {
      var o = readOverrides(); o.base = base; writeOverrides(o);
      applyBase(base);
    },
    setAccent: function (hsl) {
      var o = readOverrides(); o.accent = hsl; writeOverrides(o);
      applyAccent(hsl);
    },
    setLoginBg: function (url) {
      var o = readOverrides(); o.loginBg = url; writeOverrides(o);
      applyLoginBg(url);
    },
    getMode: function () { return root.getAttribute('data-mode') || 'system'; },
    getResolved: function () { return root.getAttribute('data-theme') || 'light'; }
  };

  // Boot: server-rendered attrs are authoritative on first paint.
  // We only re-evaluate "system" against the live media query and listen for
  // OS-level changes so the UI follows the OS without a page reload.
  var initialMode = root.getAttribute('data-mode') || 'system';
  if (initialMode === 'system') applyMode('system');

  if (window.matchMedia) {
    var mql = window.matchMedia('(prefers-color-scheme: dark)');
    var listener = function () {
      if ((root.getAttribute('data-mode') || 'system') === 'system') {
        applyMode('system');
      }
    };
    if (mql.addEventListener) mql.addEventListener('change', listener);
    else if (mql.addListener) mql.addListener(listener);
  }
})();
