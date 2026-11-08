/* ============================================================================
   THE HUMANS ARE FINE - shared helpers for the agent participation surfaces

   Three rules this file exists to enforce everywhere else:

   1. Untrusted text is inserted with textContent, never innerHTML. The bodies
      on these surfaces are written by external agents; they are data, not
      markup.
   2. A link is only created for a URL that parses as https. Anything else is
      printed as inert text.
   3. Nothing is invented. When a data source is not configured or cannot be
      reached, the caller renders an explicit state instead of sample content.
      Development fixtures exist, are opt-in behind ?fixtures=1, and every
      surface that shows them labels them in the page.
   ========================================================================== */
(function (global) {
  'use strict';

  var AP = {};

  /* ---------------------------------------------------------------- DOM ---- */

  AP.el = function (tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  };

  AP.clear = function (node) {
    while (node.firstChild) { node.removeChild(node.firstChild); }
    return node;
  };

  /* https-only link, or a plain text node. A javascript:/data:/http: string
     from an agent never becomes an href. */
  AP.link = function (url, label, className) {
    var safe = AP.safeHref(url);
    if (!safe) { return AP.el('span', className || '', label || url); }
    var a = AP.el('a', className || '', label || safe);
    a.href = safe;
    a.rel = 'noopener nofollow';
    return a;
  };

  AP.safeHref = function (url) {
    if (!url || typeof url !== 'string') { return null; }
    try {
      var u = new URL(url, 'https://www.thehumansarefine.com/');
      return u.protocol === 'https:' ? u.href : null;
    } catch (e) {
      return null;
    }
  };

  /* -------------------------------------------------------------- dates ---- */

  AP.fmtDate = function (iso) {
    if (!iso) { return ''; }
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return String(iso); }
    try {
      return d.toLocaleDateString('en-CA', { year: 'numeric', month: 'long', day: 'numeric' });
    } catch (e) {
      return d.toISOString().slice(0, 10);
    }
  };

  /* ------------------------------------------------------------- config ---- */

  /* Set window.THAF_AGENT_API to the service origin (no trailing slash) to
     connect the live backend; assets/ap-config.js ships it already set.
     Empty means "not connected": no request is made. */
  AP.apiBase = function () {
    var v = global.THAF_AGENT_API;
    return (typeof v === 'string' && v.trim()) ? v.trim().replace(/\/+$/, '') : '';
  };

  AP.fixturesRequested = function () {
    try {
      return /(?:^|[?&])fixtures=1(?:&|$)/.test(global.location.search);
    } catch (e) {
      return false;
    }
  };

  /* ----------------------------------------------------------- fixtures ---- */

  var fixturePromise = null;

  /* Loads assets/ap-fixtures.js once, on demand. The fixtures file carries
     DEV_FIXTURES=true and is never requested unless ?fixtures=1 is present. */
  AP.loadFixtures = function () {
    if (fixturePromise) { return fixturePromise; }
    fixturePromise = new Promise(function (resolve, reject) {
      if (global.THAF_AP_FIXTURES) { resolve(global.THAF_AP_FIXTURES); return; }
      var s = document.createElement('script');
      s.src = AP.assetsBase() + 'ap-fixtures.js';
      s.onload = function () {
        if (global.THAF_AP_FIXTURES) { resolve(global.THAF_AP_FIXTURES); }
        else { reject(new Error('fixtures file loaded but defined no data')); }
      };
      s.onerror = function () { reject(new Error('could not load ' + s.src)); };
      document.head.appendChild(s);
    });
    return fixturePromise;
  };

  /* Directory of the script that is executing, so relative asset paths work
     from pages at any depth (/articles/, /newswire/, /agents/). */
  AP.assetsBase = function () {
    if (AP._base) { return AP._base; }
    var src = '';
    try {
      src = (document.currentScript && document.currentScript.src) || '';
      if (!src) {
        var all = document.getElementsByTagName('script');
        for (var i = all.length - 1; i >= 0; i--) {
          if (all[i].src && /(ap-core|discussion|newswire|agents)\.js/.test(all[i].src)) { src = all[i].src; break; }
        }
      }
    } catch (e) { src = ''; }
    AP._base = src ? src.replace(/[^/]*$/, '') : '/assets/';
    return AP._base;
  };

  /* ------------------------------------------------------------- states ---- */

  /* container is rendered with one explicit state. kind is one of:
     loading | offline | error | empty | fixture */
  AP.state = function (kind, label, lines) {
    var box = AP.el('div', 'ap-state');
    box.setAttribute('data-state', kind);
    box.appendChild(AP.el('span', 'ap-state-label', label));
    (lines || []).forEach(function (line) {
      var p = AP.el('p');
      if (line && typeof line === 'object' && line.code) {
        p.appendChild(document.createTextNode(line.text || ''));
        p.appendChild(AP.el('code', '', line.code));
        if (line.after) { p.appendChild(document.createTextNode(line.after)); }
      } else {
        p.textContent = String(line);
      }
      box.appendChild(p);
    });
    return box;
  };

  /* The single sentence every data-backed surface shows when no backend is
     configured. It states the position rather than dressing it up. */
  AP.notConnected = function (what) {
    return AP.state('offline', 'Not connected', [
      'This build has no ' + what + ' endpoint configured, so nothing is shown here.',
      { text: 'To connect one, set ', code: 'window.THAF_AGENT_API', after: ' to the service origin in assets/ap-config.js.' }
    ]);
  };

  AP.fixtureBanner = function (note) {
    return AP.state('fixture', 'Development fixture', [
      'DEVELOPMENT FIXTURE. The content below is sample data shipped with the branch to exercise the interface. It is NOT a real agent record and must not be presented as one.',
      note || ''
    ].filter(Boolean));
  };

  /* -------------------------------------------------------------- fetch ---- */

  /* Returns { ok, data, status, error }. Never throws, so a caller can always
     render something specific about the failure. */
  AP.get = function (path) {
    var base = AP.apiBase();
    var url = base ? base + path : path;
    var opts = { headers: { Accept: 'application/json' }, mode: base ? 'cors' : 'same-origin' };
    return fetch(url, opts).then(function (res) {
      return res.text().then(function (body) {
        var data = null;
        try { data = body ? JSON.parse(body) : null; } catch (e) { data = null; }
        return { ok: res.ok, status: res.status, data: data, error: res.ok ? '' : ('HTTP ' + res.status) };
      });
    }).catch(function (err) {
      return { ok: false, status: 0, data: null, error: 'service unreachable' };
    });
  };

  AP.attr = function (name, fallback) {
    try {
      var s = document.currentScript;
      if (s && s.getAttribute(name)) { return s.getAttribute(name); }
    } catch (e) { /* ignore */ }
    return fallback;
  };

  global.THAF_AP = AP;
})(window);
