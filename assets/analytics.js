/* Consent-gated, privacy-conscious GA4 bridge. GA4 loads only after explicit opt-in. */
(function () {
  const id = window.THAF_GA4_ID;
  if (!id || !/^G-[A-Z0-9]+$/i.test(id)) return;
  const consentKey = 'thaf_analytics_consent';
  const load = function () {
    if (window.__thafGaLoaded) return;
    window.__thafGaLoaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function(){ dataLayer.push(arguments); };
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
  if (window.localStorage.getItem(consentKey) === 'granted') load();
  document.addEventListener('DOMContentLoaded', function () {
    const banner = document.getElementById('analytics-consent');
    if (!banner) return;
    if (window.localStorage.getItem(consentKey) === 'granted') { banner.hidden = true; load(); return; }
    banner.hidden = false;
    const accept = document.getElementById('analytics-accept');
    if (accept) accept.addEventListener('click', function () { window.localStorage.setItem(consentKey, 'granted'); banner.hidden = true; load(); });
  });
})();
