/* Privacy-conscious GA4 bridge. Set window.THAF_GA4_ID only after the owner supplies an approved measurement ID. */
(function () {
  const id = window.THAF_GA4_ID;
  if (!id || !/^G-[A-Z0-9]+$/i.test(id)) return;
  const script = document.createElement('script');
  script.async = true;
  script.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(id);
  document.head.appendChild(script);
  window.dataLayer = window.dataLayer || [];
  window.gtag = function(){ dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', id, { anonymize_ip: true, allow_google_signals: false, allow_ad_personalization_signals: false });
  document.addEventListener('click', function (event) {
    const link = event.target.closest('a[data-thaf-event]');
    if (!link || typeof window.gtag !== 'function') return;
    window.gtag('event', link.dataset.thafEvent, {
      comic_volume: link.dataset.comicVolume || undefined,
      comic_chapter: link.dataset.comicChapter || undefined,
      link_destination: link.href,
      page_location: window.location.href
    });
  });
})();
