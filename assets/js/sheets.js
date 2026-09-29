/* ── CSE 62B · Sheets API helper ────────────────────────────────────────────
   All Google Sheet / Drive / SMS calls are proxied through the Cloudflare
   Worker at api.lucse62.xyz so no secret IDs appear in client-side code.

   Offline support: every successful response is cached in localStorage.
   If a network request fails (offline), the last cached version is returned
   and a banner tells the reader how old the data on screen is — silently
   showing last week's routine as if it were today's is worse than saying so.
   ─────────────────────────────────────────────────────────────────────────── */
(function () {
  var W = 'https://lucse62b-api.sy164425.workers.dev';
  var PREFIX = 'lu62b_sc_';

  /* ── localStorage, quota included ──────────────────────────────────────── */

  function cacheEntries() {
    var out = [];
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (!k || k.indexOf(PREFIX) !== 0) continue;
      var t = 0;
      try { t = (JSON.parse(localStorage.getItem(k)) || {}).t || 0; } catch (e) {}
      out.push({ k: k, t: t });
    }
    return out;
  }

  /* Sheets can be large and the 5 MB quota is shared with everything else the
     portal stores, so when a write is refused drop the oldest cached sheets
     and try again rather than losing the newest response. */
  function store(key, value) {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        localStorage.setItem(key, value);
        return true;
      } catch (e) {
        var entries = cacheEntries().filter(function (x) { return x.k !== key; });
        if (!entries.length) return false;
        entries.sort(function (a, b) { return a.t - b.t; });
        try { localStorage.removeItem(entries[0].k); } catch (e2) { return false; }
      }
    }
    return false;
  }

  function get(path) {
    var cacheKey = PREFIX + path;
    return fetch(W + path, { cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (data) {
        store(cacheKey, JSON.stringify({ d: data, t: Date.now() }));
        return data;
      })
      .catch(function (err) {
        var c = null;
        try { c = JSON.parse(localStorage.getItem(cacheKey) || 'null'); } catch (e) {}
        if (c && c.d) {
          showStale(c.t || 0);
          return c.d;
        }
        showFailed();
        throw err;
      });
  }

  /* ── "You are looking at saved data" banner ────────────────────────────── */

  var banner = null;
  var oldestShown = null;   // timestamp of the stalest response on screen
  var dismissed = false;

  function ago(ts) {
    if (!ts) return 'earlier';
    var mins = Math.round((Date.now() - ts) / 60000);
    if (mins < 2) return 'a moment ago';
    if (mins < 60) return mins + ' minutes ago';
    var hours = Math.round(mins / 60);
    if (hours < 24) return hours === 1 ? 'an hour ago' : hours + ' hours ago';
    var days = Math.round(hours / 24);
    return days === 1 ? 'yesterday' : days + ' days ago';
  }

  function render(message) {
    if (dismissed) return;
    if (!banner) {
      banner = document.createElement('div');
      banner.id = 'offline-banner';
      banner.setAttribute('role', 'status');
      banner.style.cssText =
        'position:fixed;left:50%;transform:translateX(-50%);bottom:16px;z-index:9999;' +
        'max-width:min(560px,calc(100vw - 24px));display:flex;align-items:center;gap:10px;' +
        'padding:10px 14px;border-radius:12px;font-size:13px;line-height:1.4;' +
        'background:#3a2c0b;color:#ffd98a;border:1px solid #6b5212;' +
        'box-shadow:0 10px 30px rgba(0,0,0,.35);font-family:inherit';
      var text = document.createElement('span');
      text.id = 'offline-banner-text';
      text.style.cssText = 'flex:1';
      var close = document.createElement('button');
      close.type = 'button';
      close.setAttribute('aria-label', 'Dismiss');
      close.textContent = '×';
      close.style.cssText =
        'background:none;border:0;color:inherit;font-size:19px;line-height:1;' +
        'cursor:pointer;padding:0 2px;opacity:.75';
      close.onclick = function () {
        dismissed = true;
        if (banner) banner.remove();
        banner = null;
      };
      banner.appendChild(text);
      banner.appendChild(close);
      (document.body || document.documentElement).appendChild(banner);
    }
    banner.querySelector('#offline-banner-text').textContent = message;
  }

  function showStale(ts) {
    if (oldestShown === null || (ts && ts < oldestShown)) oldestShown = ts;
    render(
      (navigator.onLine ? 'Can’t reach the server' : 'You are offline') +
      ' — showing data saved ' + ago(oldestShown)
    );
  }

  function showFailed() {
    if (oldestShown !== null) return;   // a staleness message is already up
    render(
      navigator.onLine
        ? 'Can’t reach the server. Some data could not be loaded.'
        : 'You are offline. This page has no saved copy of some data yet.'
    );
  }

  /* Back online → say so once, and offer a reload rather than forcing one
     (a forced reload would throw away anything half-filled on the page). */
  window.addEventListener('online', function () {
    if (!banner || dismissed) return;
    var text = banner.querySelector('#offline-banner-text');
    text.textContent = 'Back online. ';
    var link = document.createElement('a');
    link.href = '#';
    link.textContent = 'Reload for the latest';
    link.style.cssText = 'color:inherit;font-weight:700;text-decoration:underline';
    link.onclick = function (e) { e.preventDefault(); location.reload(); };
    text.appendChild(link);
  });

  window.addEventListener('offline', function () {
    if (oldestShown !== null) showStale(oldestShown);
  });

  /* ── Public API ─────────────────────────────────────────────────────────── */

  /* Fetch a tab from the main student spreadsheet */
  window.fetchSheet = function (name) {
    return get('/sheet?name=' + encodeURIComponent(name));
  };

  /* Fetch a tab from the bot / classwork spreadsheet */
  window.fetchBotSheet = function (name) {
    return get('/sheet?name=' + encodeURIComponent(name) + '&type=bot');
  };

  /* Fetch any sheet by its ID (used for dynamic exam / routine tabs).
     raw=true → ask the Worker for &headers=0 so GVIZ doesn't fold a stacked
     multi-header sheet's first block (e.g. Batch 61) into the column labels. */
  window.fetchSheetById = function (id, tab, raw) {
    var q = '/fetch?id=' + encodeURIComponent(id);
    if (tab) q += '&sheet=' + encodeURIComponent(tab);
    if (raw) q += '&raw=1';
    return get(q);
  };

  /* Hidden column indices per tab → { "SATURDAY": [10], ... }.
     Lets the routine mirror columns the user hid in the Google Sheet. */
  window.fetchHiddenCols = function (id) {
    return get('/hidden-cols?id=' + encodeURIComponent(id));
  };

  /* ── Retake / improve enrollments ────────────────────────────────────────
     These used to be read and written straight from the browser with the anon
     key, which is in this very file. Anyone could therefore list, add or
     delete any student's enrolled courses. They go through the Worker now,
     which only accepts a write for a student the Main Sheet still lists. */

  /* One student's enrollments, or the whole class when studentId is omitted
     (that is what the Classmates tab and the section enrollee map need).
     Resolves to [] on any failure, as the old inline calls did. */
  window.fetchEnrollments = function (studentId) {
    var q = '/enrollments';
    if (studentId) q += '?student_id=' + encodeURIComponent(studentId);
    return fetch(W + q, { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : { enrollments: [] }; })
      .then(function (d) { return (d && d.enrollments) || []; })
      .catch(function () { return []; });
  };

  /* Enroll in a course. Any existing row for the same course is replaced, so
     one course still means one section. */
  window.saveEnrollment = function (row) {
    return fetch(W + '/enrollments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(row || {}),
    })
      .then(function (r) { return r.ok; })
      .catch(function () { return false; });
  };

  window.removeEnrollment = function (studentId, courseCode) {
    return fetch(W + '/enrollments', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ student_id: studentId, course_code: courseCode }),
    })
      .then(function (r) { return r.ok; })
      .catch(function () { return false; });
  };

  /* Send SMS via gateway (credentials hidden in Worker) */
  window.sendProxySMS = function (phone, message) {
    return fetch(W + '/sms', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ phone: phone, message: message }),
    });
  };

  /* List files in a Google Drive folder (API key hidden in Worker) */
  window.fetchDriveFolder = function (folderId) {
    return get('/drive?folder=' + encodeURIComponent(folderId));
  };

  /* List images from subfolders (API key hidden in Worker) */
  window.fetchDriveGallery = function (folderId, limit) {
    var q = '/gallery?folder=' + encodeURIComponent(folderId);
    if (limit) q += '&limit=' + encodeURIComponent(limit);
    return get(q);
  };
})();
