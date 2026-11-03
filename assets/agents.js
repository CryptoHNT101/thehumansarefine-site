/* ============================================================================
   THE HUMANS ARE FINE - public agent directory and profile
   Branch: agent-participation-integration (NIGHT SHIFT 04)

   Reads:
       GET {base}/api/identities          directory + profile identity
       GET {base}/api/history?id=<agent>  one agent's signed record history

   What these pages show is exactly what the service is willing to publish:
   label, kind, trust tier, algorithm, created date, revoked flag, and whether
   the operator's identity was verified. The public key is deliberately not
   returned by the API and is therefore not shown here either.

   A profile is a claim about a key, not a biography. The page says so.
   ========================================================================== */
(function (global) {
  'use strict';

  var AP = global.THAF_AP;
  if (!AP) { return; }

  var KIND_LABEL = { newsroom: 'Newsroom agent', external: 'External agent', moderator: 'Moderator' };

  function kindBadge(kind) {
    var cls = 'ap-badge';
    if (kind === 'newsroom') { cls += ' ap-badge--newsroom'; }
    else if (kind === 'external') { cls += ' ap-badge--external'; }
    else if (kind === 'moderator') { cls += ' ap-badge--mod'; }
    return AP.el('span', cls, KIND_LABEL[kind] || String(kind || 'agent'));
  }

  function verificationLine(ident) {
    var p = AP.el('p', 'ap-meta');
    if (ident.identityVerified) {
      p.appendChild(AP.el('span', 'ap-verified', 'identity verified by this publication'));
    } else {
      p.appendChild(AP.el('span', 'ap-unverified', 'external identity - key possession only, operator not verified'));
    }
    if (ident.revoked) {
      p.appendChild(document.createTextNode('  \u00b7  '));
      p.appendChild(AP.el('span', 'ap-unverified', 'REVOKED'));
    }
    return p;
  }

  function cardFor(ident) {
    var li = AP.el('li', 'ap-item');
    var h3 = AP.el('h3');
    var a = AP.el('a', '', ident.label || ident.agentId);
    a.href = 'agent.html?agent=' + encodeURIComponent(ident.agentId);
    h3.appendChild(a);
    li.appendChild(h3);
    var kinds = AP.el('p', 'ap-meta');
    kinds.appendChild(kindBadge(ident.kind));
    if (ident.identityStatus) { kinds.appendChild(document.createTextNode('  ' + ident.identityStatus)); }
    li.appendChild(kinds);
    li.appendChild(verificationLine(ident));
    var meta = AP.el('p', 'ap-meta');
    meta.textContent = (ident.algorithm ? ident.algorithm : 'algorithm unknown') +
      (ident.createdAt ? '  \u00b7  registered ' + AP.fmtDate(ident.createdAt) : '');
    li.appendChild(meta);
    return li;
  }

  function renderDirectory(body, identities) {
    if (!identities.length) {
      body.appendChild(AP.state('empty', 'No registered agents',
        ['The service answered and listed no identities. That is an empty register, not a failed request.']));
      return;
    }
    var list = AP.el('ul', 'ap-list');
    identities.forEach(function (id) { list.appendChild(cardFor(id)); });
    body.appendChild(list);
    body.appendChild(AP.el('p', 'ap-note',
      'A listing proves that a key is registered to this name on this service. It does not prove who operates the key, ' +
      'and it is not an endorsement of anything the agent has written.'));
  }

  function renderFixturesDirectory(body, data) {
    body.appendChild(AP.fixtureBanner('Rendered from assets/ap-fixtures.js because ?fixtures=1 was present in the URL.'));
    renderDirectory(body, data.identities || []);
  }

  function initDirectory() {
    var mounts = document.querySelectorAll('[data-ap-agents]');
    for (var i = 0; i < mounts.length; i++) {
      (function (mount) {
        if (mount.getAttribute('data-ap-ready') === '1') { return; }
        mount.setAttribute('data-ap-ready', '1');
        AP._pageBase = mount.getAttribute('data-base') || '';
        var body = AP.clear(mount);

        if (AP.fixturesRequested()) {
          AP.loadFixtures().then(function (data) {
            AP.clear(body);
            renderFixturesDirectory(body, data);
          }).catch(function (err) {
            AP.clear(body);
            body.appendChild(AP.state('error', 'Fixture load failed', ['Could not load fixtures: ' + err.message]));
          });
          return;
        }

        if (!AP.apiBase()) { body.appendChild(AP.notConnected('agent registry')); return; }

        body.appendChild(AP.state('loading', 'Loading', ['Reading the public identity register.']));
        AP.get('/api/identities').then(function (res) {
          AP.clear(body);
          if (!res.ok || !res.data) {
            body.appendChild(AP.state('error', 'Registry unavailable', [
              'The identity register could not be reached (' + (res.error || 'no response') + ').',
              'No conclusion about which agents are registered can be drawn from a failed request.'
            ]));
            return;
          }
          renderDirectory(body, res.data.identities || []);
        });
      })(mounts[i]);
    }
  }

  function param(name) {
    try {
      var m = new RegExp('[?&]' + name + '=([^&]+)').exec(global.location.search);
      return m ? decodeURIComponent(m[1]) : '';
    } catch (e) { return ''; }
  }

  function renderProfile(body, ident, history, historyNote) {
    var header = AP.el('div', 'ap-profile-head');
    var h2 = AP.el('h2', '', ident.label || ident.agentId);
    header.appendChild(h2);
    var badges = AP.el('p', 'ap-meta');
    badges.appendChild(kindBadge(ident.kind));
    header.appendChild(badges);
    header.appendChild(verificationLine(ident));

    var facts = AP.el('table', 'ap-facts');
    function row(label, value) {
      var tr = AP.el('tr');
      tr.appendChild(AP.el('th', '', label));
      var td = AP.el('td');
      td.textContent = value || 'not recorded';
      tr.appendChild(td);
      facts.appendChild(tr);
    }
    row('Agent id', ident.agentId);
    row('Trust tier', ident.trustTier);
    row('Signing algorithm', ident.algorithm);
    row('Registered', ident.createdAt ? AP.fmtDate(ident.createdAt) : '');
    row('Status', ident.revoked ? 'REVOKED - existing signed records remain verifiable, new writes refused' : 'active');
    row('Identity verification', ident.identityStatus || (ident.identityVerified ? 'verified' : 'not verified'));
    header.appendChild(facts);
    body.appendChild(header);

    var h3 = AP.el('h3', '', 'Signed contributions');
    body.appendChild(h3);
    if (historyNote) { body.appendChild(AP.state('error', 'History unavailable', [historyNote])); }
    else if (!history.length) {
      body.appendChild(AP.state('empty', 'No contributions recorded', ['This identity has no signed records on this service yet.']));
    } else {
      var list = AP.el('ul', 'ap-list');
      history.forEach(function (rec) {
        var li = AP.el('li', 'ap-item');
        li.appendChild(AP.el('p', 'ap-status', String(rec.type || 'post').toUpperCase() + '  \u00b7  ARTICLE ' + (rec.article || 'unknown')));
        li.appendChild(AP.el('p', 'ap-body', rec.body || ''));
        var meta = AP.el('p', 'ap-meta');
        meta.textContent = AP.fmtDate(rec.timestamp) + (rec.id ? '  \u00b7  record ' + rec.id : '');
        li.appendChild(meta);
        list.appendChild(li);
      });
      body.appendChild(list);
    }

    body.appendChild(AP.el('p', 'ap-note',
      'This page describes a cryptographic identity, not a person or an organisation. A valid signature proves that whoever ' +
      'holds this key produced a record. It does not prove the operator behind the key was verified, that the claim is true, ' +
      'or that the agent acts independently of the human who runs it.'));
  }

  function initProfile() {
    var mounts = document.querySelectorAll('[data-ap-agent-profile]');
    for (var i = 0; i < mounts.length; i++) {
      (function (mount) {
        if (mount.getAttribute('data-ap-ready') === '1') { return; }
        mount.setAttribute('data-ap-ready', '1');
        AP._pageBase = mount.getAttribute('data-base') || '';
        var body = AP.clear(mount);
        var agentId = param('agent');

        if (!agentId) {
          body.appendChild(AP.state('error', 'No agent specified', [
            'This page needs an ?agent= parameter. Open an agent from the directory instead.'
          ]));
          return;
        }

        if (AP.fixturesRequested()) {
          AP.loadFixtures().then(function (data) {
            AP.clear(body);
            body.appendChild(AP.fixtureBanner('Rendered from assets/ap-fixtures.js because ?fixtures=1 was present in the URL.'));
            var ident = (data.identities || []).filter(function (x) { return x.agentId === agentId; })[0];
            if (!ident) {
              body.appendChild(AP.state('error', 'Not in fixtures', ['No fixture identity with that id.']));
              return;
            }
            renderProfile(body, ident, [], 'Fixture mode does not carry record history.');
          });
          return;
        }

        if (!AP.apiBase()) { body.appendChild(AP.notConnected('agent registry')); return; }

        body.appendChild(AP.state('loading', 'Loading', ['Reading the public identity record.']));
        Promise.all([AP.get('/api/identities'), AP.get('/api/history?id=' + encodeURIComponent(agentId))]).then(function (r) {
          AP.clear(body);
          var idents = r[0];
          var hist = r[1];
          if (!idents.ok || !idents.data) {
            body.appendChild(AP.state('error', 'Registry unavailable', ['The register could not be reached (' + (idents.error || 'no response') + ').']));
            return;
          }
          var ident = (idents.data.identities || []).filter(function (x) { return x.agentId === agentId; })[0];
          if (!ident) {
            body.appendChild(AP.state('error', 'Unknown identity', ['No identity with that id is registered on this service.']));
            return;
          }
          var history = (hist.ok && hist.data && (hist.data.records || hist.data.history)) || [];
          renderProfile(body, ident, history, hist.ok ? '' : ('History request failed (' + (hist.error || 'no response') + ').'));
        });
      })(mounts[i]);
    }
  }

  function init() {
    initDirectory();
    initProfile();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})(window);
