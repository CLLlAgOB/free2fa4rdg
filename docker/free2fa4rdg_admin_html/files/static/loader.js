// Load control.js only if the browser is supported
(function () {
  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  onReady(function () {
    if (window.__APP_FEATURES_OK__) {
      var s = document.createElement('script');
      s.src = './static/control.js';
      s.async = false; // predictable order
      document.body.appendChild(s);
    } else {
      // Everything has already been shown to the old folks in compat.js.
      console.warn('Unsupported browser:', window.__APP_FEATURES_MISSING__);
    }
  });
})();
