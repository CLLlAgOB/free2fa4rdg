// ES5-compatible feature detection. No let/const/arrows.
(function () {
  function has(path) {
    var parts = path.split('.'), obj = window, i;
    for (i = 0; i < parts.length; i++) {
      obj = (obj && obj[parts[i]]) ? obj[parts[i]] : null;
    }
    return !!obj;
  }

  var missing = [];
  if (!('fetch' in window)) missing.push('Fetch API');
  if (!('Promise' in window)) missing.push('Promise');
  if (!('AbortController' in window)) missing.push('AbortController');
  if (!('URLSearchParams' in window)) missing.push('URLSearchParams');
  if (!('TextEncoder' in window)) missing.push('TextEncoder');
  if (!has('crypto.subtle')) missing.push('WebCrypto (crypto.subtle)');
  if (!('replaceChildren' in (window.Element || {}).prototype)) missing.push('Element.replaceChildren');
  if (!('sessionStorage' in window)) missing.push('sessionStorage');

  var supported = (missing.length === 0);
  window.__APP_FEATURES_OK__ = supported;
  window.__APP_FEATURES_MISSING__ = missing;

  if (!supported) {
    var show = function () {
      try {
        var banner = document.createElement('div');
        banner.className = 'unsupported-banner';
        banner.innerHTML =
          '<strong>Your browser is outdated.</strong> Your browser is outdated: ' +
          missing.join(', ') +
          '. Update your browser (Chrome/Edge/Firefox/Safari) or use another one. ';

        document.body.insertBefore(banner, document.body.firstChild);

        // Hide working sections so as not to confuse the user
        var hide = function (id) {
          var el = document.getElementById(id);
          if (el) { el.style.display = 'none'; }
        };
        hide('loginSection');
        hide('mainContent');
        hide('changePasswordSection');
      } catch (e) {
        // Very ancient: at least alert
        alert('Your browser is too old for this page. Please update it.');
      }
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', show);
    } else {
      show();
    }
  }
})();
