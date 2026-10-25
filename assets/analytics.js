/* Consent-gated, privacy-conscious GA4 bridge. GA4 loads only after explicit opt-in. */
(function () {
  const id = window.THAF_GA4_ID;
  if (!id || !/^G-[A-Z0-9]+$/i.test(id)) return;
  const consentKey = 'thaf_analytics_consent';
  const safeGet = function () { try { return window.localStorage.getItem(consentKey); } catch (_) { return null; } };
  const safeSet = function (value) { try { window.localStorage.setItem(consentKey, value); } catch (_) {} };
  const safeRemove = function () { try { window.localStorage.removeItem(consentKey); } catch (_) {} };
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
    window.gtag('config', id, { send_page_view: true, anonymize_ip: true, allow_google_signals: false, allow_ad_personalization_signals: false });
    document.addEventListener('click', function (event) {
      const link = event.target.closest('a[data-thaf-event]');
      if (!link) return;
      window.gtag('event', link.dataset.thafEvent, { comic_volume: link.dataset.comicVolume || undefined, comic_chapter: link.dataset.comicChapter || undefined, link_destination: link.href, page_location: window.location.href });
    });
  };
  const setConsent = function (value) {
    safeSet(value);
    const banner = document.getElementById('analytics-consent');
    if (banner) banner.hidden = true;
    if (value === 'granted') load();
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
        safeRemove();
        banner.hidden = false;
        banner.focus();
      });
    });
    const saved = safeGet();
    if (saved) { banner.hidden = true; if (saved === 'granted') load(); return; }
    banner.hidden = false;
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();
})();
