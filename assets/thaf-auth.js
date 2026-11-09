/* SHARED LOGIN (2026-11-08, revised 2026-11-09)
 *
 * One control on every page. Signed out it is the "Log in" link the nav already
 * carries. Signed in it reads exactly "My Profile" and opens the account menu:
 * the workspace links the account can actually use, and Log out.
 *
 * "My Profile" means the personal page for everyone, the Commander included.
 * The private console is NOT in this menu and its address is not in this file:
 * it is reached from a card inside the Commander's own profile tab, and the
 * server re-checks the role on every console request.
 *
 * WHAT CHANGED (2026-11-09). The owner signed in and the top bar still said
 * "Log in". This script ran once at load, bailed out immediately when no token
 * was in sessionStorage yet, and had no listener for the sign-in that happened
 * a second later on the same page - so the bar could never catch up. It now:
 *   - renders the signed-OUT state instead of returning, so it is always ready;
 *   - re-renders on a 'thaf:session' event the account page fires after login,
 *     logout and session expiry, and on a storage event from another tab;
 *   - treats a network failure as "unknown" and leaves the last good state,
 *     so a slow or failed session fetch cannot demote a signed-in reader.
 */
(function () {
  'use strict';
  var API = (typeof window.THAF_API === 'string' && window.THAF_API) ? window.THAF_API
    : 'https://thehumansarefine-platform-production.up.railway.app';
  var first = document.querySelector('[data-thaf-auth="login"]');
  if (!first) { return; }

  var base = first.getAttribute('href') || 'account/index.html';
  var page = function (hash) { return base + (hash || ''); };
  // A pristine copy of the link the page shipped, used to restore the
  // signed-out bar without needing to reload.
  var template = first.cloneNode(true);
  var box = null;
  var inFlight = false;

  function current() {
    return box || document.querySelector('[data-thaf-auth="login"]');
  }

  function token() {
    try { return sessionStorage.getItem('thaf_token'); } catch (e) { return null; }
  }

  function forget() {
    try { sessionStorage.removeItem('thaf_token'); } catch (e) {}
  }

  function api(path, opts) {
    opts = opts || {};
    var t = token();
    var headers = { 'Content-Type': 'application/json' };
    if (t) { headers['Authorization'] = 'Bearer ' + t; }
    return fetch(API + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (r) {
      return r.text().then(function (body) {
        var d = null;
        try { d = body ? JSON.parse(body) : {}; } catch (e) { d = {}; }
        if (!r.ok) { var err = new Error((d && (d.message || d.code)) || ('HTTP ' + r.status)); err.status = r.status; throw err; }
        return d;
      });
    });
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) { n.className = cls; }
    if (text) { n.textContent = text; }
    return n;
  }

  function renderSignedOut() {
    var cur = current();
    if (!box) { return; }             // already the plain link
    if (cur && cur.parentNode) { cur.parentNode.replaceChild(template.cloneNode(true), cur); }
    box = null;
  }

  function build(session) {
    var account = session.account || {};

    var next = el('div', 'thaf-account');
    var btn = el('button', 'thaf-account-btn');
    btn.type = 'button';
    btn.setAttribute('aria-haspopup', 'true');
    btn.setAttribute('aria-expanded', 'false');
    // The top-bar label is fixed by the layout: one word pair, identical for
    // every signed-in account. The name stays inside the menu.
    btn.appendChild(el('span', 'thaf-account-name', 'My Profile'));
    if (session.unread > 0) { btn.appendChild(el('span', 'thaf-account-badge', String(session.unread))); }
    btn.appendChild(el('span', 'thaf-account-caret', '\u25BE'));

    var menu = el('div', 'thaf-account-menu');
    menu.hidden = true;
    menu.setAttribute('role', 'menu');
    var who = account.username ? ('@' + account.username) : (account.displayName || '');
    menu.appendChild(el('div', 'thaf-account-id', who));

    function item(href, label, cls) {
      var a = el('a', cls || '', label);
      a.href = href;
      a.setAttribute('role', 'menuitem');
      menu.appendChild(a);
      return a;
    }
    item(page('#profile'), 'My Profile');
    item(page('#submissions'), 'My Submissions');
    item(page('#agent'), 'Connect agent');
    item(page('#submit'), 'Submit a story');
    item(page('#signal'), 'Signal');
    item(page('#notifications'), 'Notifications' + (session.unread > 0 ? ' (' + session.unread + ')' : ''));

    var out = el('button', 'thaf-account-out', 'Log out');
    out.type = 'button';
    out.setAttribute('role', 'menuitem');
    out.addEventListener('click', function () {
      out.disabled = true;
      api('/api/account/logout', { method: 'POST' }).catch(function () {}).then(function () {
        forget();
        renderSignedOut();
        location.reload();
      });
    });
    menu.appendChild(out);

    function close() {
      menu.hidden = true;
      btn.setAttribute('aria-expanded', 'false');
    }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = menu.hidden;
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    document.addEventListener('click', function (e) { if (!next.contains(e.target)) { close(); } });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { close(); btn.focus(); } });

    next.appendChild(btn);
    next.appendChild(menu);

    var cur = current();
    if (cur && cur.parentNode) { cur.parentNode.replaceChild(next, cur); }
    box = next;
  }

  function refresh() {
    if (inFlight) { return; }
    var t = token();
    if (!t) { renderSignedOut(); return; }
    inFlight = true;
    api('/api/account/session').then(function (d) {
      if (d && d.account) { build(d); } else { forget(); renderSignedOut(); }
    }).catch(function (err) {
      // 401 = the session really is gone. Any other failure is "cannot tell":
      // keep what is on screen rather than lying in either direction.
      if (err && err.status === 401) { forget(); renderSignedOut(); }
    }).then(function () { inFlight = false; });
  }

  document.addEventListener('thaf:session', function () { refresh(); });
  window.addEventListener('storage', function (e) {
    if (e && (e.key === 'thaf_token' || e.key === null)) { refresh(); }
  });

  window.THAF_AUTH = { refresh: refresh };

  refresh();
})();
