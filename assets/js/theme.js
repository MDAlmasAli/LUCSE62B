/* ── CSE 62B Portal — Theme Manager ── */
(function () {
  var KEY = 'cse62b-theme';

  function current() {
    return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }

  function apply(theme) {
    if (theme === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
    localStorage.setItem(KEY, theme);
    updateAllButtons(theme);
  }

  function updateAllButtons(theme) {
    document.querySelectorAll('.theme-toggle-btn').forEach(function (btn) {
      btn.innerHTML = theme === 'light'
        ? '<i class="fa-solid fa-moon"></i>'
        : '<i class="fa-solid fa-circle-half-stroke"></i>';
      btn.title = theme === 'light' ? 'Switch to Dark Mode' : 'Switch to Light Mode';
    });

    /* Profile appearance card */
    var darkOpt  = document.getElementById('themeOptDark');
    var lightOpt = document.getElementById('themeOptLight');
    var themeDesc = document.getElementById('themeDesc');
    if (darkOpt)  darkOpt.classList.toggle('active',  theme === 'dark');
    if (lightOpt) lightOpt.classList.toggle('active', theme === 'light');
    if (themeDesc) themeDesc.textContent = theme === 'light' ? 'Light mode is active' : 'Dark mode is active';
  }

  /* Public API */
  window.toggleTheme = function () {
    apply(current() === 'dark' ? 'light' : 'dark');
  };

  window.setTheme = function (theme) {
    apply(theme);
  };

  /* Init UI once DOM ready */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { updateAllButtons(current()); });
  } else {
    updateAllButtons(current());
  }
})();

/* Interactive network constellation background (all pages) */
document.head.appendChild(Object.assign(document.createElement('script'), { src: '/assets/js/network-bg.js', defer: true }));

/* FIFA26: temporary World Cup 2026 theme — delete this line (and the two fifa26 asset files) to remove */
document.head.appendChild(Object.assign(document.createElement('script'), { src: '/assets/js/fifa26.js?v=20260712b', defer: true }));
