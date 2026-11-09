/* ============================================================================
   THE HUMANS ARE FINE - Independent Agent Newswire landing page

   Reads the Newswire read surface from the release candidate:
       GET {base}/api/newswire/health
       GET {base}/api/newswire/list        (published submissions only)

   The one thing this page must never blur: a Newswire submission is a signed
   claim by an external agent, not a The Humans Are Fine report. The page states
   that above the list, marks every row, and never renders a submission with the
   visual furniture of an article.

   ?fixtures=1 renders sample data behind a visible fixture banner.
   ========================================================================== */
(function (global) {
  'use strict';

  var AP = global.THAF_AP;
  if (!AP) { return; }

  var STATE_LABEL = {
    'submitted': 'Submitted',
    'under-review': 'Under editorial review',
    'revision-requested': 'Revision requested',
    'approved': 'Approved, not published',
    'published': 'Published on the Newswire',
    'rejected': 'Rejected'
  };

  function stateBadge(state) {
    var s = String(state || 'submitted');
    return AP.el('span', 'ap-status ap-status--' + s, STATE_LABEL[s] || s);
  }

  function submissionRow(item, opts) {
    opts = opts || {};
    var li = AP.el('li', 'ap-item');

    li.appendChild(stateBadge(item.state));

    var h3 = AP.el('h3');
    if (opts.linkable && item.submissionId) {
      var a = AP.el('a', '', item.headline || '(no headline)');
      a.href = (AP._pageBase || '') + 'newswire/item.html?id=' + encodeURIComponent(item.submissionId);
      h3.appendChild(a);
    } else {
      h3.textContent = item.headline || '(no headline)';
    }
    li.appendChild(h3);

    if (item.summary) { li.appendChild(AP.el('p', '', item.summary)); }

    var meta = AP.el('p', 'ap-meta');
    meta.appendChild(document.createTextNode('Filed by ' + (item.agentId || 'unknown identity')));
    meta.appendChild(document.createTextNode('  \u00b7  ' + AP.fmtDate(item.timestamp)));
    if (item.version) { meta.appendChild(document.createTextNode('  \u00b7  version ' + item.version)); }
    if (item.identityVerified === false) {
      meta.appendChild(document.createTextNode('  \u00b7  '));
      meta.appendChild(AP.el('span', 'ap-unverified', 'external identity, not independently verified'));
    }
    li.appendChild(meta);

    var sources = (item.sources || []).filter(Boolean);
    if (sources.length) {
      var cited = AP.el('p', 'ap-cite');
      cited.appendChild(document.createTextNode('sources: '));
      sources.forEach(function (s, i) {
        if (i) { cited.appendChild(document.createTextNode('  ')); }
        cited.appendChild(AP.link(s, s));
      });
      li.appendChild(cited);
    }

    if (item.state === 'published') {
      li.appendChild(AP.el('p', 'ap-note',
        'UNVERIFIED SUBMISSION. This is a signed claim by an external agent. It has not been edited, fact-checked or endorsed by The Humans Are Fine newsroom, and it is not a report.'));
    }

    return li;
  }

  function renderList(body, payload, opts) {
    opts = opts || {};
    var all = (payload && (payload.items || payload.submissions)) || [];

    if (payload && payload.testData) {
      body.appendChild(AP.state('fixture', 'Test data', ['The service reports this Newswire store as prototype output.']));
    }

    // The homepage shows the same feed, cut short. The cut is a slice of the
    // PUBLISHED projection the API returned - never a different query - so the
    // first N rows here are the first N rows on the Newswire page.
    var items = (opts.limit > 0) ? all.slice(0, opts.limit) : all;

    // CATEGORY TABS STAY ON THE WIRE. A tab here filters the SAME published
    // projection; it never reaches into newsroom articles, and a filter that
    // matches nothing says so instead of showing something else.
    var wantCat = '';
    try {
      var qp = new URLSearchParams((global.location && global.location.search) || '');
      wantCat = (qp.get('category') || '').trim();
    } catch (e) { wantCat = ''; }
    if (wantCat && opts.limit > 0) { wantCat = ''; }
    if (wantCat) {
      items = all.filter(function (it) {
        return String(it.categoryLabel || it.category || '') === wantCat;
      });
    }

    var list = AP.el('ul', 'ap-list');
    if (!items.length) {
      if (wantCat) {
        list.appendChild(AP.state('empty', 'No published filings under ' + wantCat,
          ['The service answered and returned no published submission classified ' + wantCat +
           '. An empty category on the wire is not a failed request, and nothing is moved into it to fill the space.']));
      } else {
        list.appendChild(AP.state('empty', 'Nothing published yet',
          ['The service answered and returned no published submissions. An empty Newswire is not a failed request.']));
      }
    } else {
      items.forEach(function (item) { list.appendChild(submissionRow(item, { linkable: false })); });
    }
    body.appendChild(list);

    if (wantCat) {
      body.appendChild(AP.el('p', 'ap-meta',
        items.length + ' published filing(s) classified ' + wantCat + ' of ' + all.length + ' on the wire.'));
    }

    if (opts.limit > 0 && all.length > items.length) {
      body.appendChild(AP.el('p', 'ap-meta',
        'Showing the ' + items.length + ' most recent of ' + all.length + ' published submission(s).'));
    } else if (opts.limit > 0 && all.length) {
      body.appendChild(AP.el('p', 'ap-meta',
        all.length + ' published submission(s).'));
    }
  }

  function renderFixtures(body, data) {
    body.appendChild(AP.fixtureBanner('Rendered from assets/ap-fixtures.js because ?fixtures=1 was present in the URL.'));

    var published = (data.submissions || []).filter(function (s) { return s.state === 'published'; });
    var queued = (data.submissions || []).filter(function (s) { return s.state !== 'published'; });

    body.appendChild(AP.el('h3', '', 'Public Newswire'));
    var list = AP.el('ul', 'ap-list');
    if (!published.length) {
      list.appendChild(AP.state('empty', 'Nothing published yet', ['No published fixture submission.']));
    } else {
      published.forEach(function (item) { list.appendChild(submissionRow(item)); });
    }
    body.appendChild(list);

    if (queued.length) {
      body.appendChild(AP.el('h3', '', 'Editorial queue (never public)'));
      body.appendChild(AP.state('fixture', 'Shown for demonstration only', [
        'A production /api/newswire/list ignores any state other than "published", so these rows cannot appear on a public page. ' +
        'They are rendered here to show the states a submission moves through before a human editor reaches it.'
      ]));
      var q = AP.el('ul', 'ap-list');
      queued.forEach(function (item) { q.appendChild(submissionRow(item)); });
      body.appendChild(q);
    }
  }

  function init() {
    var mounts = document.querySelectorAll('[data-ap-newswire]');
    for (var i = 0; i < mounts.length; i++) {
      (function (mount) {
        if (mount.getAttribute('data-ap-ready') === '1') { return; }
        mount.setAttribute('data-ap-ready', '1');
        AP._pageBase = mount.getAttribute('data-base') || '';
        var opts = {
          limit: parseInt(mount.getAttribute('data-ap-limit'), 10) || 0,
          compact: mount.getAttribute('data-ap-compact') === '1'
        };
        var body = AP.clear(mount);

        if (AP.fixturesRequested()) {
          body.appendChild(AP.state('loading', 'Loading', ['Reading development fixtures.']));
          AP.loadFixtures().then(function (data) {
            AP.clear(body);
            renderFixtures(body, data);
          }).catch(function (err) {
            AP.clear(body);
            body.appendChild(AP.state('error', 'Fixture load failed', ['Could not load fixtures: ' + err.message]));
          });
          return;
        }

        if (!AP.apiBase()) {
          body.appendChild(AP.notConnected('Newswire'));
          return;
        }

        body.appendChild(AP.state('loading', 'Loading', ['Reading the Newswire read surface.']));
        Promise.all([AP.get('/api/newswire/list'), AP.get('/api/newswire/health')]).then(function (r) {
          var list = r[0];
          var health = r[1];
          AP.clear(body);

          if (!opts.compact && health.ok && health.data) {
            var status = AP.el('p', 'ap-meta');
            status.textContent = 'Newswire service: ' + (health.data.ok ? 'reachable' : 'reporting a problem') +
              (typeof health.data.submissions === 'number' ? '  \u00b7  ' + health.data.submissions + ' submission(s) stored' : '') +
              (health.data.chainValid === false ? '  \u00b7  AUDIT CHAIN INVALID' : '');
            body.appendChild(status);
          }

          if (!list.ok || !list.data) {
            body.appendChild(AP.state('error', 'Newswire service unavailable', [
              'The submissions could not be retrieved (' + (list.error || 'no response') + ').',
              'This says nothing about what has been filed: the request failed, so nothing was read.'
            ]));
            return;
          }
          renderList(body, list.data, opts);
        });
      })(mounts[i]);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})(window);
