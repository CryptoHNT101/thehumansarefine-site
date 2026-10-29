/* Consent-gated, privacy-conscious GA4 bridge. GA4 loads only after explicit opt-in.
 *
 * Audience build (Day 9). Changes, all additive to the consent model, which is
 * unchanged: nothing is measured, and no Google script is fetched, until the
 * reader presses Accept.
 *
 *  1. window.THAF_enableAnalytics / THAF_disableAnalytics are now actually
 *     defined. The consent banner's inline onclick called THAF_enableAnalytics
 *     before this file had ever defined it, so every Accept threw an uncaught
 *     TypeError. Measurement still worked (a second listener existed) but the
 *     error was real and is now gone.
 *  2. Every page reports a page_type, content_group and (for stories)
 *     article_slug, derived from the URL only. Without these, GA4 cannot answer
 *     "how do articles do versus Evidence Files versus topic archives" — it
 *     reports one undifferentiated pile of page_view.
 *     content_group is a built-in GA4 dimension. page_type and article_slug are
 *     custom parameters and must be registered as custom dimensions in the GA4
 *     property before they can be selected in a report.
 *  3. Outbound clicks are measured: a click on a primary source is the clearest
 *     signal that a reader went to check the evidence rather than skim.
 *  4. Scroll depth (25/50/75/100%) is measured, so a story that gets opened and
 *     abandoned can be told apart from one that gets read.
 *
 * What this file still cannot do, and does not pretend to: distinguish a human
 * from a crawler. GA4 applies its own known-bot filtering, but headless
 * browsers, link unfurlers, uptime monitors and AI crawlers that execute
 * JavaScript can still appear. Nothing here inflates or cleans the numbers.
 */
(function () {
  'use strict';
  const id = window.THAF_GA4_ID;
  if (!id || !/^G-[A-Z0-9]+$/i.test(id)) return;

  const consentKey = 'thaf_analytics_consent';
  const safeGet = function () { try { return window.localStorage.getItem(consentKey); } catch (_) { return null; } };
  const safeSet = function (value) { try { window.localStorage.setItem(consentKey, value); } catch (_) {} };
  const safeRemove = function () { try { window.localStorage.removeItem(consentKey); } catch (_) {} };

  // Derived from the URL. Never a hand-maintained list that could drift.
  const meta = (function () {
    const p = String(window.location.pathname || '/');
    const out = { page_type: 'page', content_group: 'Site', article_slug: '' };
    let m;
    if ((m = p.match(/^\/articles\/([a-z0-9\-]+)-evidence\.html$/i))) {
      out.page_type = 'evidence_file'; out.content_group = 'Evidence Files'; out.article_slug = m[1];
    } else if ((m = p.match(/^\/articles\/([a-z0-9\-]+)\.html$/i))) {
      out.page_type = 'article'; out.content_group = 'Articles'; out.article_slug = m[1];
    } else if (/^\/topics\//i.test(p)) {
      out.page_type = 'topic_archive'; out.content_group = 'Topic archives';
    } else if (/^\/news\//i.test(p)) {
      out.page_type = 'newswire'; out.content_group = 'Newswire';
    } else if (/^\/disclosure-watch\//i.test(p)) {
      out.page_type = 'disclosure_watch'; out.content_group = 'Disclosure Watch';
    } else if (/^\/standards\//i.test(p)) {
      out.page_type = 'standards'; out.content_group = 'Standards';
    } else if (/^\/newsroom\//i.test(p)) {
      out.page_type = 'newsroom'; out.content_group = 'Newsroom';
    } else if (p === '/' || /^\/index\.html$/i.test(p)) {
      out.page_type = 'home'; out.content_group = 'Home';
    }
    return out;
  })();

  const load = function () {
    if (window.__thafGaLoaded) return;
    window.__thafGaLoaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
    window.gtag('consent', 'default', { analytics_storage: 'denied', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied', wait_for_update: 500 });
    window.gtag('consent', 'update', { analytics_storage: 'granted', ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' });
    const script = document.createElement('script');
    script.async = true;
    script.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(id);
    document.head.appendChild(script);
    window.gtag('js', new Date());
    window.gtag('config', id, {
      send_page_view: true,
      anonymize_ip: true,
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      page_type: meta.page_type,
      content_group: meta.content_group,
      article_slug: meta.article_slug || undefined
    });

    const base = function () {
      return { page_type: meta.page_type, content_group: meta.content_group, article_slug: meta.article_slug || undefined, page_location: window.location.href };
    };

    // 1. tagged in-page and outbound clicks
    document.addEventListener('click', function (event) {
      const link = event.target.closest('a[data-thaf-event]');
      if (!link) return;
      const params = base();
      params.comic_volume = link.dataset.comicVolume || undefined;
      params.comic_chapter = link.dataset.comicChapter || undefined;
      params.link_destination = link.href;
      window.gtag('event', link.dataset.thafEvent, params);
    }, true);

    // 2. any off-site link that is not tagged - primarily the Primary source
    //    and Original sources lists, i.e. did the reader go and check it
    document.addEventListener('click', function (event) {
      const link = event.target.closest('a[href]');
      if (!link || link.hasAttribute('data-thaf-event')) return;
      let host;
      try { host = new URL(link.href, window.location.href).hostname; } catch (_) { return; }
      if (!host || host === window.location.hostname) return;
      const params = base();
      params.link_domain = host;
      params.link_url = link.href;
      params.outbound = true;
      window.gtag('event', 'source_click', params);
    }, true);

    // 3. read depth, once per threshold
    const marks = [25, 50, 75, 100];
    const fired = {};
    let queued = false;
    const check = function () {
      queued = false;
      const doc = document.documentElement;
      const body = document.body || {};
      const height = Math.max(doc.scrollHeight || 0, body.scrollHeight || 0);
      const view = window.innerHeight || doc.clientHeight || 0;
      if (height <= view) { return; }
      const pct = Math.min(100, Math.round(((window.pageYOffset || doc.scrollTop || 0) + view) / height * 100));
      for (let i = 0; i < marks.length; i++) {
        const m = marks[i];
        if (pct >= m && !fired[m]) {
          fired[m] = true;
          const params = base();
          params.percent_scrolled = m;
          window.gtag('event', 'read_depth', params);
        }
      }
    };
    window.addEventListener('scroll', function () {
      if (queued) return;
      queued = true;
      (window.requestAnimationFrame || function (f) { setTimeout(f, 100); })(check);
    }, { passive: true });
    check();
  };

  const setConsent = function (value) {
    safeSet(value);
    const banner = document.getElementById('analytics-consent');
    if (banner) banner.hidden = true;
    if (value === 'granted') load();
  };

  // The consent banner calls this name directly, so it must exist.
  window.THAF_enableAnalytics = function () { setConsent('granted'); };
  window.THAF_disableAnalytics = function () {
    safeRemove();
    const banner = document.getElementById('analytics-consent');
    if (banner) { banner.hidden = false; if (banner.focus) banner.focus(); }
  };

  const init = function () {
    const banner = document.getElementById('analytics-consent');
    if (!banner) return;
    const accept = document.getElementById('analytics-accept');
    if (accept) accept.addEventListener('click', function () { setConsent('granted'); });
    const decline = document.getElementById('analytics-decline');
    if (decline) decline.addEventListener('click', function () { setConsent('denied'); });
    document.querySelectorAll('[data-thaf-settings]').forEach(function (link) {
      link.addEventListener('click', function (event) {
        event.preventDefault();
        window.THAF_disableAnalytics();
      });
    });
    const saved = safeGet();
    if (saved) { banner.hidden = true; if (saved === 'granted') load(); return; }
    banner.hidden = false;
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
