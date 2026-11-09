/* SHARED LOGIN (2026-11-08, revised 2026-11-08)
 *
 * One control on every page. Signed out it is the "Log in" link the nav already
 * carries. Signed in it reads exactly "My Profile" and opens the account menu:
 * the workspace links the account can actually use, and Log out.
 *
 * "My Profile" means the personal page for everyone, the Commander included.
 * The private console is NOT in this menu and its address is not in this file:
 * it is reached from a card inside the Commander's own profile tab, and the
 * server re-checks the role on every console request.
 */
(function () {
  'use strict';
  var API = (typeof window.THAF_API === 'string' && window.THAF_API) ? window.THAF_API
    : 'https://thehumansarefine-platform-production.up.railway.app';
  var link = document.querySelector('[data-thaf-auth="login"]');
  if (!link) { return; }

  var base = link.getAttribute('href') || 'account/index.html';
  var prefix = base.replace(/account\/index\.html.*$/, '');
  var page = function (hash) { return base + (hash || ''); };

  var token = null;
  try { token = sessionStorage.getItem('thaf_token'); } catch (e) { token = null; }
  if (!token) { return; }

  function api(path, opts) {
    opts = opts || {};
    var headers = { 'Content-Type': 'application/json' };
    if (token) { headers['Authorization'] = 'Bearer ' + token; }
    return fetch(API + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body ? JSON.stringify(opts.body) : undefined
    }).then(function (r) {
      return r.text().then(function (t) {
        var d = null;
        try { d = t ? JSON.parse(t) : {}; } catch (e) { d = {}; }
        if (!r.ok) { var err = new Error((d && (d.message || d.code)) || ('HTTP ' + r.status)); err.status = r.status; throw err; }
        return d;
      });
    });
  }

  function forget() {
    token = null;
    try { sessionStorage.removeItem('thaf_token'); } catch (e) {}
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) { n.className = cls; }
    if (text) { n.textContent = text; }
    return n;
  }

  function build(session) {
    var account = session.account || {};

    var box = el('div', 'thaf-account');
    var btn = el('button', 'thaf-account-btn');
    btn.type = 'button';
    btn.setAttribute('aria-haspopup', 'true');
    btn.setAttribute('aria-expanded', 'false');
    // The top-bar label is fixed by the layout: one word pair, identical for
    // every signed-in account. The name and address stay inside the menu.
    btn.appendChild(el('span', 'thaf-account-name', 'My Profile'));
    if (session.unread > 0) { btn.appendChild(el('span', 'thaf-account-badge', String(session.unread))); }
    btn.appendChild(el('span', 'thaf-account-caret', '\u25BE'));

    var menu = el('div', 'thaf-account-menu');
    menu.hidden = true;
    menu.setAttribute('role', 'menu');
    menu.appendChild(el('div', 'thaf-account-id', (account.displayName && account.email) ? account.email : (account.role ? 'role: ' + account.role : '')));

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
    document.addEventListener('click', function (e) { if (!box.contains(e.target)) { close(); } });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { close(); btn.focus(); } });

    box.appendChild(btn);
    box.appendChild(menu);
    link.parentNode.replaceChild(box, link);
  }

  api('/api/account/session').then(function (d) {
    if (d && d.account) { build(d); } else { forget(); }
  }).catch(function (err) {
    // 401 = no live session: leave the Log in link exactly as it is.
    if (err && err.status === 401) { forget(); }
  });
})();
