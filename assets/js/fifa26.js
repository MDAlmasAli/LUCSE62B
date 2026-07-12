/* ════════════════════════════════════════════════════════════════════
   FIFA WORLD CUP 2026 — TEMPORARY THEME + LIVE MATCH CENTER
   ⚽ Self-contained: injects its own CSS, banner, and modal.
   🗑️ To remove after the tournament:
      1. Delete this file + assets/css/fifa26.css
      2. Delete the FIFA26 loader line at the bottom of assets/js/theme.js
      3. (Optional) remove the /fifa route from worker/worker.js
   ════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  /* ── CONFIG ── */
  var ENABLED  = true;                      // master switch — false = theme off
  var WC_END   = '2026-07-21';              // auto-off 2 days after the final
  var WORKER   = 'https://lucse62b-api.sy164425.workers.dev';
  var TZ       = 'Asia/Dhaka';
  var WC_RANGE = '20260611-20260720';       // full tournament (UTC dates)

  if (!ENABLED) return;
  if (new Date() > new Date(WC_END + 'T23:59:59+06:00')) return;   // tournament over

  /* ── helpers ── */
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (m) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m];
    });
  }
  function bdTime(iso) {
    try {
      return new Intl.DateTimeFormat('en-US', { timeZone: TZ, hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(iso));
    } catch (e) { return ''; }
  }
  function bdDateKey(iso) {
    try {
      return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
    } catch (e) { return ''; }
  }
  function bdDateLabel(iso) {
    try {
      return new Intl.DateTimeFormat('en-GB', { timeZone: TZ, weekday: 'long', day: 'numeric', month: 'long' }).format(new Date(iso));
    } catch (e) { return ''; }
  }
  function todayKey() { return bdDateKey(new Date().toISOString()); }
  function roundLabel(slug) {
    if (!slug) return '';
    return slug.replace(/-/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }
  /* knockout slots aren't decided yet — turn ESPN codes into readable labels:
     "1A" → Group A Winner · "2K" → Group K Runner-up · "3RD A/B/…" → 3rd Place */
  function teamLabel(t) {
    var n = ((t && t.name) || '').trim(), m;
    if ((m = n.match(/^1([A-L])$/i)))      return 'Group ' + m[1].toUpperCase() + ' Winner';
    if ((m = n.match(/^2([A-L])$/i)))      return 'Group ' + m[1].toUpperCase() + ' Runner-up';
    if ((m = n.match(/^3RD\s*(.+)$/i)))    return '3rd Place ' + m[1];
    if ((m = n.match(/^W\s?(\d+)$/i)))     return 'Winner M' + m[1];
    if ((m = n.match(/^L\s?(\d+)$/i)))     return 'Loser M' + m[1];
    return n;
  }

  /* ── data fetch (with tiny localStorage cache) ── */
  function fetchMatches(dates, ttlMs) {
    var key = 'f26_c_' + dates;
    try {
      var c = JSON.parse(localStorage.getItem(key) || 'null');
      if (c && Date.now() - c.t < ttlMs) return Promise.resolve(c.m);
    } catch (e) {}
    return fetch(WORKER + '/fifa?dates=' + dates)
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (d) {
        var m = d.matches || [];
        try { localStorage.setItem(key, JSON.stringify({ t: Date.now(), m: m })); } catch (e) {}
        return m;
      });
  }
  /* UTC window covering BD "today" generously (yesterday→tomorrow UTC) */
  function dateWindow(backDays, forwardDays) {
    var d = new Date(), p = function (n) { return (n < 10 ? '0' : '') + n; };
    var a = new Date(d.getTime() - (backDays || 0) * 864e5);
    var b = new Date(d.getTime() + (forwardDays || 0) * 864e5);
    var f = function (x) { return '' + x.getUTCFullYear() + p(x.getUTCMonth() + 1) + p(x.getUTCDate()); };
    return f(a) + '-' + f(b);
  }
  function todayWindow() { return dateWindow(1, 1); }
  function upcomingWindow() { return dateWindow(1, 8); }

  /* ── Supabase (class squad + predictions) ── */
  var SUPA     = 'https://ftvtlqxpalwvyserujuh.supabase.co';
  var SUPA_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

  function getUser() {
    try { return JSON.parse(localStorage.getItem('lu62b_student') || 'null'); } catch (e) { return null; }
  }
  function supaGet(path) {
    return fetch(SUPA + '/rest/v1/' + path, {
      headers: { 'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY },
    }).then(function (r) { if (!r.ok) throw new Error('supa ' + r.status); return r.json(); });
  }
  function supaUpsert(table, row) {
    return fetch(SUPA + '/rest/v1/' + table, {
      method: 'POST',
      headers: {
        'apikey': SUPA_KEY, 'Authorization': 'Bearer ' + SUPA_KEY,
        'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
      },
      body: JSON.stringify(row),
    });
  }

  /* ── my team ── */
  function myTeam() {
    try { return JSON.parse(localStorage.getItem('f26_team') || 'null'); } catch (e) { return null; }
  }
  function setMyTeam(t) {
    localStorage.setItem('f26_team', JSON.stringify(t));
    var u = getUser();
    if (u && u.id) {
      supaUpsert('fifa26_teams', {
        student_id: u.id, student_name: u.name || '',
        team_abbr: t.abbr, team_name: t.name,
      }).catch(function () {});
    }
  }

  /* class squad (everyone's teams) — cached 5 min */
  var _squad = null, _squadT = 0;
  function fetchSquad(force) {
    if (_squad && !force && Date.now() - _squadT < 3e5) return Promise.resolve(_squad);
    return supaGet('fifa26_teams?select=student_id,student_name,team_abbr,team_name&order=updated_at.desc')
      .then(function (rows) { _squad = rows || []; _squadT = Date.now(); return _squad; })
      .catch(function () { return _squad || []; });
  }

  /* unique team list derived from the schedule (skips TBD knockout slots) */
  function teamsFromMatches(ms) {
    var seen = {}, out = [];
    ms.forEach(function (m) {
      (m.teams || []).forEach(function (t) {
        /* skip knockout placeholders: "1A", "2K", "3RD A/B/C/D/F", TBD — real teams have a country flag logo */
        if (!t.abbr || !t.name || seen[t.abbr]) return;
        if (/^\d|^3rd|tbd|winner|runner/i.test(t.name) || !/countries/.test(t.logo || '')) return;
        seen[t.abbr] = 1;
        out.push({ abbr: t.abbr, name: t.name, logo: t.logo || '' });
      });
    });
    return out.sort(function (a, b) { return a.name.localeCompare(b.name); });
  }
  function isMyMatch(m) {
    var mt = myTeam();
    return !!(mt && (m.teams || []).some(function (t) { return t.abbr === mt.abbr; }));
  }

  /* ── theme-only bits (also applied when banner dismissed) ── */
  function applyThemeOnly() {
    document.documentElement.setAttribute('data-fifa26', '1');
    if (!document.getElementById('fifa26-css')) {
      var l = document.createElement('link');
      l.id = 'fifa26-css'; l.rel = 'stylesheet'; l.href = '/assets/css/fifa26.css';
      document.head.appendChild(l);
    }
    if (!document.getElementById('fifa26-bg') && document.body) {
      var bg = document.createElement('div');
      bg.id = 'fifa26-bg';
      document.body.appendChild(bg);
    }
  }

  /* ── BANNER ── */
  var liveSeen = false;

  function tickItem(m) {
    var t = m.teams || [], a = t[0] || {}, b = t[1] || {};
    var mid;
    if (m.state === 'in') {
      mid = '<span class="f26-live-dot"></span><span class="f26-tick-score">' + esc(a.score) + '–' + esc(b.score) + '</span><span class="f26-tick-min">' + esc(m.clock) + '</span>';
      liveSeen = true;
    } else if (m.state === 'post') {
      mid = '<span class="f26-tick-score">' + esc(a.score) + '–' + esc(b.score) + '</span><span style="color:#94a3b8;font-size:.66rem;font-weight:800;">FT</span>';
    } else {
      mid = '<span class="f26-tick-time">' + esc(bdTime(m.date)) + '</span>';
    }
    return '<span class="f26-tick-item">'
      + (a.logo ? '<img src="' + esc(a.logo) + '" alt="">' : '') + esc(a.abbr || a.name)
      + mid
      + esc(b.abbr || b.name) + (b.logo ? '<img src="' + esc(b.logo) + '" alt="">' : '')
      + '</span>';
  }

  function nextMatchCountdownHTML(matches) {
    var now = Date.now();
    var next = matches.filter(function (m) { return m.state === 'pre' && new Date(m.date).getTime() > now; })
                      .sort(function (x, y) { return new Date(x.date) - new Date(y.date); })[0];
    if (!next) return '<span class="f26-tick-item">FIFA World Cup 2026 · United States · Canada · Mexico 🏆</span>';
    var t = next.teams || [], a = t[0] || {}, b = t[1] || {};
    return '<span class="f26-tick-item">Next: '
      + esc(a.name) + ' vs ' + esc(b.name)
      + ' <span class="f26-tick-time">' + esc(bdDateLabel(next.date)) + ', ' + esc(bdTime(next.date)) + '</span></span>';
  }

  function renderTicker(matches) {
    var el = document.getElementById('f26-track');
    if (!el) return;
    liveSeen = false;
    var tk = todayKey();
    var today = matches.filter(function (m) { return bdDateKey(m.date) === tk; });
    var wrap = el.parentElement;
    if (today.length) {
      /* my team's matches first + a YOUR TEAM flash */
      var mt = myTeam(), extra = '';
      if (mt) {
        today.sort(function (x, y) { return (isMyMatch(y) ? 1 : 0) - (isMyMatch(x) ? 1 : 0); });
        if (isMyMatch(today[0])) {
          extra = '<span class="f26-tick-item f26-tick-mine">⭐ ' + esc(mt.abbr) + ' — YOUR TEAM plays today!</span>' +
                  '<span style="color:rgba(34,211,238,.4);">•</span>';
        }
      }
      /* class banter: both teams supported by classmates */
      if (_squad && _squad.length) {
        var cnt = {};
        _squad.forEach(function (r) { cnt[r.team_abbr] = (cnt[r.team_abbr] || 0) + 1; });
        today.forEach(function (m) {
          var t = m.teams || [], a = t[0] || {}, b = t[1] || {};
          if (cnt[a.abbr] && cnt[b.abbr]) {
            extra += '<span class="f26-tick-item">🔥 ' + esc(a.abbr) + ' <b style="color:#22d3ee;">' + cnt[a.abbr] + ' : ' + cnt[b.abbr] + '</b> ' + esc(b.abbr) + ' classmates!</span>' +
                     '<span style="color:rgba(34,211,238,.4);">•</span>';
          }
        });
      }
      var sep  = '<span style="color:rgba(34,211,238,.4);">•</span>';
      var html = extra + today.map(tickItem).join(sep);
      /* Render one copy first and measure it WITHOUT the scroll padding. Only
         duplicate (for a seamless marquee loop) when a single copy actually
         overflows the bar — otherwise a couple of matches on a wide screen show
         up twice side by side. Fits → show once, centred and static. */
      el.innerHTML = html;
      el.classList.add('f26-static');
      if (wrap) wrap.classList.add('f26-nomask');
      requestAnimationFrame(function () {
        if (wrap && el.scrollWidth > wrap.clientWidth + 2) {
          el.innerHTML = html + sep + html;        /* loop seamlessly */
          el.classList.remove('f26-static');
          wrap.classList.remove('f26-nomask');
          el.style.setProperty('--f26-speed', Math.max(22, today.length * 9) + 's');
        }
      });
    } else {
      el.innerHTML = nextMatchCountdownHTML(matches);
      el.classList.add('f26-static');
      if (wrap) wrap.classList.add('f26-nomask');
      /* if the static text doesn't fit (mobile), fall back to scrolling */
      requestAnimationFrame(function () {
        if (wrap && el.scrollWidth > wrap.clientWidth + 2) {
          el.classList.remove('f26-static');
          wrap.classList.remove('f26-nomask');
          el.style.setProperty('--f26-speed', '16s');
        }
      });
    }
  }

  function refreshBanner() {
    fetchSquad();   /* warm the cache so the ticker can show class banter */
    fetchMatches(upcomingWindow(), liveSeen ? 6e4 : 3e5).then(function (m) {
      renderTicker(m);
      updateHomeStrip(m);
    }).catch(function () {});
  }

  function buildBanner() {
    if (document.getElementById('fifa26-banner')) return;
    var b = document.createElement('div');
    b.id = 'fifa26-banner';
    b.innerHTML =
      '<span class="f26-ball">⚽</span>' +
      '<span class="f26-title"><b>WORLD CUP 26</b><small>USA · CAN · MEX</small></span>' +
      '<span class="f26-ticker f26-nomask"><span class="f26-track f26-static" id="f26-track">' +
        '<span class="f26-tick-item">Loading matches…</span></span></span>' +
      '<button class="f26-cta" id="f26-open"><i class="fa-solid fa-trophy"></i><span>&nbsp;Match Center</span></button>';
    document.body.insertBefore(b, document.body.firstChild);

    b.addEventListener('click', function () { openMC(); });
    document.getElementById('f26-open').addEventListener('click', function (e) { e.stopPropagation(); openMC(); });
  }

  /* homepage explore strip — sits after the next-class / exam-countdown info, so
     the home order reads graduation → deadlines → next class → FIFA. */
  function buildHomeStrip() {
    var grad = document.querySelector('.grad-strip');
    if (!grad || document.getElementById('fifa26-home')) return;
    var s = document.createElement('div');
    s.id = 'fifa26-home';
    s.innerHTML =
      '<span class="f26-home-ball">⚽</span>' +
      '<span class="f26-home-txt"><b>FIFA WORLD CUP 26</b>' +
        '<small id="f26-home-sub">Live scores · My Team · Predictions · Class Leaderboard</small></span>' +
      '<span class="f26-pass"><span class="f26-passball"><span class="f26-passball-i">⚽</span></span></span>' +
      '<span class="f26-home-cta">Explore <i class="fa-solid fa-arrow-right"></i></span>';
    s.addEventListener('click', function () { openMC(); });
    var anchor = document.getElementById('examCdHomeWrap')
              || document.getElementById('qiStrip')
              || grad;
    anchor.insertAdjacentElement('afterend', s);
  }

  /* Live subtitle on the homepage Explore strip — driven by the same data as
     the banner ticker. Live matches first, then today's fixtures, else static. */
  var HOME_STATIC = 'Live scores · My Team · Predictions · Class Leaderboard';
  function updateHomeStrip(matches) {
    var sub = document.getElementById('f26-home-sub');
    if (!sub) return;
    var tk = todayKey();
    var today = (matches || []).filter(function (m) { return bdDateKey(m.date) === tk; })
                               .sort(function (x, y) { return new Date(x.date) - new Date(y.date); });
    var scoreOf = function (m) { var t = m.teams || [], a = t[0] || {}, b = t[1] || {}; return esc(a.abbr) + ' ' + esc(a.score) + '–' + esc(b.score) + ' ' + esc(b.abbr); };

    var live = today.filter(function (m) { return m.state === 'in'; });
    if (live.length) {
      sub.innerHTML = '<span class="f26-home-live"></span>' +
        live.map(function (m) { return '<b>' + scoreOf(m) + '</b> ' + esc(m.clock); }).join('  ·  ');
      return;
    }
    var pre = today.filter(function (m) { return m.state === 'pre'; });
    if (pre.length) {
      sub.innerHTML = 'Today · ' + pre.slice(0, 3).map(function (m) {
        var t = m.teams || [], a = t[0] || {}, b = t[1] || {};
        return esc(a.abbr) + ' v ' + esc(b.abbr) + ' <b>' + esc(bdTime(m.date)) + '</b>';
      }).join('  ·  ');
      return;
    }
    var post = today.filter(function (m) { return m.state === 'post'; });
    if (post.length) {
      sub.innerHTML = 'Full-time · ' + post.map(function (m) { return '<b>' + scoreOf(m) + '</b>'; }).join('  ·  ');
      return;
    }
    var now = Date.now();
    var next = (matches || []).filter(function (m) { return m.state === 'pre' && new Date(m.date).getTime() > now; })
                              .sort(function (x, y) { return new Date(x.date) - new Date(y.date); })[0];
    if (next) {
      var t = next.teams || [], a = t[0] || {}, b = t[1] || {};
      sub.innerHTML = 'Next match · ' + esc(a.abbr || a.name) + ' v ' + esc(b.abbr || b.name) +
        ' <b>' + esc(bdDateLabel(next.date)) + ', ' + esc(bdTime(next.date)) + '</b>';
      return;
    }
    sub.textContent = HOME_STATIC;
  }

  /* ── MATCH CENTER ── */
  var mcTab = 'today', mcTimer = null, cdTimer = null, expandedId = null;

  /* ── live match detail (timeline + stats) ── */
  var detailCache = {};
  function fetchDetail(id) {
    var c = detailCache[id];
    if (c && Date.now() - c.t < 3e4) return Promise.resolve(c.d);
    return fetch(WORKER + '/fifa?event=' + encodeURIComponent(id))
      .then(function (r) { if (!r.ok) throw new Error('http'); return r.json(); })
      .then(function (d) { detailCache[id] = { t: Date.now(), d: d }; return d; });
  }
  var EV_ICO = {
    'goal': '⚽', 'own-goal': '⚽', 'penalty---scored': '⚽',
    'penalty---missed': '❌', 'yellow-card': '🟨', 'red-card': '🟥', 'substitution': '🔄',
  };
  var EV_TAG = { 'own-goal': 'OG', 'penalty---scored': 'PEN', 'penalty---missed': 'PEN MISS' };

  function renderDetail(el, id) {
    el.innerHTML = '<div class="f26-loading" style="padding:12px;font-size:1rem;"><i class="fa-solid fa-futbol"></i></div>';
    fetchDetail(id).then(function (d) {
      var html = '';
      var s = d.stats || [];
      if (s.length === 2) {
        var h = s.filter(function (x) { return x.home; })[0] || s[0];
        var a = s.filter(function (x) { return !x.home; })[0] || s[1];
        if (h.possessionPct != null && a.possessionPct != null) {
          var hp = parseFloat(h.possessionPct) || 50;
          html += '<div class="f26-poss"><b>' + esc(h.possessionPct) + '%</b>' +
            '<div class="f26-poss-bar"><span style="width:' + hp + '%"></span></div>' +
            '<b>' + esc(a.possessionPct) + '%</b></div>' +
            '<div class="f26-poss-lbl">Possession</div>';
        }
        var ROWS = [['totalShots', 'Shots'], ['shotsOnTarget', 'On Target'],
                    ['wonCorners', 'Corners'], ['foulsCommitted', 'Fouls'], ['saves', 'Saves']];
        var srows = ROWS.filter(function (r) { return h[r[0]] != null || a[r[0]] != null; })
          .map(function (r) {
            return '<div class="f26-srow"><b>' + esc(h[r[0]] || '0') + '</b><span>' + r[1] + '</span><b>' + esc(a[r[0]] || '0') + '</b></div>';
          }).join('');
        if (srows) html += '<div class="f26-stats">' + srows + '</div>';
      }
      var evs = (d.events || []).slice().reverse();   /* latest first */
      if (evs.length) {
        html += '<div class="f26-tl">' + evs.map(function (e) {
          return '<div class="f26-ev"><span class="f26-ev-t">' + esc(e.t) + '</span>' +
            '<span class="f26-ev-i">' + (EV_ICO[e.type] || '·') + '</span>' +
            '<span class="f26-ev-x">' + esc(e.text) + (EV_TAG[e.type] ? ' <i>(' + EV_TAG[e.type] + ')</i>' : '') + '</span></div>';
        }).join('') + '</div>';
      }
      el.innerHTML = html || '<div class="f26-empty" style="padding:14px;">No match events yet.</div>';
    }).catch(function () {
      el.innerHTML = '<div class="f26-empty" style="padding:14px;">Could not load details.</div>';
    });
  }

  function attachExpand(body) {
    if (body.dataset.f26x) return;
    body.dataset.f26x = '1';
    body.addEventListener('click', function (e) {
      if (e.target.closest('a')) return;
      var card = e.target.closest('.f26-match[data-mid]');
      if (!card) return;
      var det = card.querySelector('.f26-detail');
      if (det) { det.remove(); card.classList.remove('f26-open'); expandedId = null; return; }
      expandedId = card.dataset.mid;
      det = document.createElement('div');
      det.className = 'f26-detail';
      card.appendChild(det);
      card.classList.add('f26-open');
      renderDetail(det, expandedId);
    });
  }

  function reExpand(body) {
    if (!expandedId) return;
    var card = body.querySelector('.f26-match[data-mid="' + expandedId + '"]');
    if (!card) return;
    var det = document.createElement('div');
    det.className = 'f26-detail';
    card.appendChild(det);
    card.classList.add('f26-open');
    renderDetail(det, expandedId);
  }

  function statusBadge(m) {
    if (m.state === 'in')   return '<span class="f26-status live"><span class="f26-live-dot"></span>' + esc(m.clock || 'LIVE') + '</span>';
    if (m.state === 'post') return '<span class="f26-status ft">FT</span>';
    return '<span class="f26-status pre">' + esc(bdTime(m.date)) + '</span>';
  }

  function matchCard(m, withRound, inToday) {
    var t = m.teams || [], a = t[0] || {}, b = t[1] || {};
    var mid = (m.state === 'pre')
      ? '<span class="f26-vs-time">' + esc(bdTime(m.date)) + '</span>'
      : '<span class="f26-score">' + esc(a.score) + ' – ' + esc(b.score) + '</span>';
    var venue = (m.venue || m.city)
      ? '<span class="f26-venue">' + (withRound && m.round ? '<span class="f26-round-pill">' + esc(roundLabel(m.round)) + '</span> · ' : '')
        + '<i class="fa-solid fa-location-dot" style="opacity:.5;"></i> ' + esc(m.venue) + (m.city ? ', ' + esc(m.city) : '') + '</span>'
      : '';
    var expandable = m.state !== 'pre';   /* live + finished → timeline & stats */
    var hint = expandable ? '<span class="f26-venue" style="opacity:.55;"><i class="fa-solid fa-chevron-down"></i> tap for events &amp; stats</span>' : '';
    return '<div class="f26-match' + (m.state === 'in' ? ' f26-live' : '') + (isMyMatch(m) ? ' f26-mine' : '') + '"' +
      (expandable ? ' data-mid="' + esc(m.id) + '"' : '') + '>' +
      (isMyMatch(m) ? '<span class="f26-mine-star">⭐</span>' : '') +
      '<span class="f26-team' + (a.winner ? ' f26-win' : '') + '">' + (a.logo ? '<img src="' + esc(a.logo) + '" alt="">' : '<span class="f26-tbd">⏳</span>') + '<b>' + esc(teamLabel(a)) + '</b></span>' +
      '<span class="f26-mid">' + mid + statusBadge(m) + '</span>' +
      '<span class="f26-team away' + (b.winner ? ' f26-win' : '') + '"><b>' + esc(teamLabel(b)) + '</b>' + (b.logo ? '<img src="' + esc(b.logo) + '" alt="">' : '<span class="f26-tbd">⏳</span>') + '</span>' +
      venue + hint + '</div>';
  }

  function fmtCD(ms) {
    if (ms < 0) ms = 0;
    var s = Math.floor(ms / 1000),
        d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600),
        m = Math.floor(s % 3600 / 60), ss = s % 60;
    var p = function (n) { return (n < 10 ? '0' : '') + n; };
    return (d > 0 ? d + 'd ' : '') + p(h) + ':' + p(m) + ':' + p(ss);
  }

  function renderToday() {
    var body = document.getElementById('f26-mc-body');
    if (!body) return;
    fetchMatches(upcomingWindow(), 5e4).then(function (matches) {
      if (mcTab !== 'today') return;
      var tk = todayKey();
      var today = matches.filter(function (m) { return bdDateKey(m.date) === tk; })
                         .sort(function (x, y) { return new Date(x.date) - new Date(y.date); });
      var html = '';

      /* countdown to next kickoff */
      var now = Date.now();
      var next = matches.filter(function (m) { return m.state === 'pre' && new Date(m.date).getTime() > now; })
                        .sort(function (x, y) { return new Date(x.date) - new Date(y.date); })[0];
      if (next) {
        var nt = next.teams || [];
        html += '<div class="f26-cd"><span class="f26-cd-label"><i class="fa-regular fa-clock"></i> Next kickoff — ' +
          esc((nt[0] || {}).abbr || '') + ' vs ' + esc((nt[1] || {}).abbr || '') + '</span>' +
          '<span class="f26-cd-digits" id="f26-cd" data-at="' + new Date(next.date).getTime() + '">--:--:--</span></div>';
      }

      if (!today.length) {
        html += '<div class="f26-empty">No matches today (Bangladesh time) — check the full schedule ⚽</div>';
      } else {
        html += today.map(function (m) { return matchCard(m, true, true); }).join('');
      }
      body.innerHTML = html;
      attachExpand(body);
      reExpand(body);
      startCD();
    }).catch(function () {
      if (mcTab === 'today') body.innerHTML = '<div class="f26-empty">Could not load matches — try again shortly.</div>';
    });
  }

  function startCD() {
    clearInterval(cdTimer);
    var el = document.getElementById('f26-cd');
    if (!el) return;
    var at = parseInt(el.dataset.at, 10);
    var step = function () {
      var el2 = document.getElementById('f26-cd');
      if (!el2) { clearInterval(cdTimer); return; }
      el2.textContent = fmtCD(at - Date.now());
    };
    step();
    cdTimer = setInterval(step, 1000);
  }

  function renderSchedule() {
    var body = document.getElementById('f26-mc-body');
    if (!body) return;
    body.innerHTML = '<div class="f26-loading"><i class="fa-solid fa-futbol"></i></div>';
    fetchMatches(WC_RANGE, 18e5).then(function (matches) {
      if (mcTab !== 'schedule') return;
      var sorted = matches.slice().sort(function (x, y) { return new Date(x.date) - new Date(y.date); });
      var tk = todayKey(), html = '', lastKey = '', anchorDone = false;
      sorted.forEach(function (m) {
        var k = bdDateKey(m.date);
        if (k !== lastKey) {
          lastKey = k;
          var isToday = k === tk;
          html += '<div class="f26-date-h"' + (isToday && !anchorDone ? ' id="f26-today-anchor"' : '') + '>' +
            (isToday ? '🔥 TODAY · ' : '') + esc(bdDateLabel(m.date)) + '</div>';
          if (isToday) anchorDone = true;
        }
        html += matchCard(m, true);
      });
      body.innerHTML = html || '<div class="f26-empty">Schedule unavailable.</div>';
      attachExpand(body);
      var anchor = document.getElementById('f26-today-anchor');
      if (anchor) anchor.scrollIntoView({ block: 'start' });
    }).catch(function () {
      if (mcTab === 'schedule') body.innerHTML = '<div class="f26-empty">Could not load schedule — try again shortly.</div>';
    });
  }

  /* ══════════ MY TEAM tab ══════════ */
  /* per-team tournament status + a fun title-chance % (performance-based:
     group pts + goal difference among teams still alive) */
  function teamStatusMap(standings, matches) {
    var info = {};
    (standings || []).forEach(function (g) {
      (g.teams || []).forEach(function (t) {
        info[t.abbr] = {
          group: (g.name || '').replace(/^Group /i, ''), rank: t.rank,
          pts: parseInt(t.pts) || 0, p: t.p, w: t.w, d: t.d, l: t.l,
          gd: parseInt(t.gd) || 0, alive: true,
        };
      });
    });
    /* losing any knockout match = out */
    (matches || []).forEach(function (m) {
      if (!m.round || m.round === 'group-stage' || m.state !== 'post') return;
      (m.teams || []).forEach(function (t) {
        if (info[t.abbr] && !t.winner) info[t.abbr].alive = false;
      });
    });
    var sum = 0;
    Object.keys(info).forEach(function (k) {
      var x = info[k];
      x.weight = x.alive ? 1 + x.pts * 2 + Math.max(x.gd, 0) : 0;
      sum += x.weight;
    });
    Object.keys(info).forEach(function (k) {
      var x = info[k];
      x.chance = sum ? Math.round(x.weight / sum * 1000) / 10 : 0;
    });
    return info;
  }

  function squadHTML(squad, teams, statusMap) {
    var me = getUser() || {};
    var html = '<div class="f26-sec-h"><i class="fa-solid fa-users"></i> CLASS SQUAD — who supports whom</div>';
    if (!squad.length) return html + '<div class="f26-empty">No one has picked a team yet — be the first! 😎</div>';
    var logoOf = {};
    teams.forEach(function (t) { logoOf[t.abbr] = t.logo; });
    var byTeam = {};
    squad.forEach(function (r) {
      if (!byTeam[r.team_abbr]) byTeam[r.team_abbr] = { name: r.team_name, members: [] };
      byTeam[r.team_abbr].members.push({ n: r.student_name || r.student_id, me: r.student_id === me.id });
    });
    statusMap = statusMap || {};
    var rows = Object.keys(byTeam).map(function (ab) {
      return { ab: ab, name: byTeam[ab].name, members: byTeam[ab].members, st: statusMap[ab] || null };
    }).sort(function (a, b) {
      var ca = a.st ? a.st.chance : 0, cb = b.st ? b.st.chance : 0;
      return cb - ca || b.members.length - a.members.length;
    });
    var max = Math.max.apply(null, rows.map(function (r) { return r.members.length; })) || 1;
    return html + rows.map(function (r) {
      var names = r.members.map(function (m) {
        return '<span class="f26-sq-name' + (m.me ? ' me' : '') + '">' + esc(m.n) + (m.me ? ' (you)' : '') + '</span>';
      }).join('');
      var chanceChip = '', statusLine = '';
      if (r.st) {
        chanceChip = r.st.alive
          ? '<span class="f26-sq-chance">🏆 ' + r.st.chance + '%</span>'
          : '<span class="f26-sq-elim">❌ OUT</span>';
        statusLine = r.st.alive
          ? '<div class="f26-sq-status">Group ' + esc(r.st.group) + ' · #' + esc(r.st.rank) +
            ' · ' + r.st.pts + ' pts · W' + esc(r.st.w) + ' D' + esc(r.st.d) + ' L' + esc(r.st.l) +
            ' · GD ' + (r.st.gd > 0 ? '+' : '') + r.st.gd + '</div>'
          : '<div class="f26-sq-status">Eliminated from the tournament 😢</div>';
      }
      return '<div class="f26-sq-row' + (r.st && !r.st.alive ? ' f26-sq-out' : '') + '">' +
        '<div class="f26-sq-top">' +
          (logoOf[r.ab] ? '<img src="' + esc(logoOf[r.ab]) + '" alt="">' : '') +
          '<b>' + esc(r.name || r.ab) + '</b>' +
          '<span class="f26-sq-cnt">' + r.members.length + '</span>' +
          chanceChip +
        '</div>' +
        statusLine +
        '<div class="f26-sq-bar"><span style="width:' + Math.round(r.members.length / max * 100) + '%"></span></div>' +
        '<div class="f26-sq-names">' + names + '</div>' +
      '</div>';
    }).join('') +
    '<p class="f26-sq-note">🏆 % = title chance among teams still alive, based on group points & goal difference so far — updates as the tournament unfolds.</p>';
  }

  var myTeamView = 'matches';   /* 'matches' | 'squad' — remembered per session */

  function renderMyTeam() {
    var body = document.getElementById('f26-mc-body');
    if (!body) return;
    Promise.all([
      fetchMatches(WC_RANGE, 18e5), fetchSquad(true),
      fetchStandings().catch(function () { return []; }),
    ]).then(function (res) {
      if (mcTab !== 'myteam') return;
      var matches = res[0], squad = res[1], standings = res[2];
      var statusMap = teamStatusMap(standings, matches);
      var teams = teamsFromMatches(matches);
      var mt = myTeam(), html = '';

      if (mt) {
        var logo = (teams.filter(function (t) { return t.abbr === mt.abbr; })[0] || {}).logo || '';
        html += '<div class="f26-team-hero">' +
          (logo ? '<img src="' + esc(logo) + '" alt="">' : '') +
          '<div><small>YOU SUPPORT</small><b>' + esc(mt.name) + '</b></div>' +
          '<button class="f26-team-change" id="f26-change-team">Change</button>' +
        '</div>';
      }

      /* sub-tabs: My Matches | Class Squad */
      html += '<div class="f26-subtabs">' +
        '<button class="f26-subtab' + (myTeamView === 'matches' ? ' on' : '') + '" id="f26-st-matches">' +
          '<i class="fa-solid fa-futbol"></i> ' + (mt ? esc(mt.abbr) + ' Matches' : 'Pick Team') + '</button>' +
        '<button class="f26-subtab' + (myTeamView === 'squad' ? ' on' : '') + '" id="f26-st-squad">' +
          '<i class="fa-solid fa-users"></i> Class Squad</button>' +
      '</div>';

      if (myTeamView === 'squad') {
        html += squadHTML(squad, teams, statusMap);
      } else if (!mt) {
        html += '<p class="f26-sec-note">Pick the team you support ⚽ — your matches glow gold, the banner cheers for you, and you join the Class Squad.</p>';
        html += '<div class="f26-flag-grid">' + teams.map(function (t) {
          return '<button class="f26-flag" data-abbr="' + esc(t.abbr) + '" data-name="' + esc(t.name) + '">' +
            (t.logo ? '<img src="' + esc(t.logo) + '" alt="">' : '') +
            '<b>' + esc(t.abbr) + '</b><small>' + esc(t.name) + '</small></button>';
        }).join('') + '</div>';
      } else {
        var mine = matches.filter(isMyMatch).sort(function (x, y) { return new Date(x.date) - new Date(y.date); });
        var next = mine.filter(function (m) { return m.state === 'pre' && new Date(m.date) > new Date(); })[0];
        if (next) {
          html += '<div class="f26-cd"><span class="f26-cd-label"><i class="fa-regular fa-clock"></i> ' +
            esc(mt.abbr) + '’s next match — ' + esc(bdDateLabel(next.date)) + '</span>' +
            '<span class="f26-cd-digits" id="f26-cd" data-at="' + new Date(next.date).getTime() + '">--:--:--</span></div>';
        }
        if (mine.length) {
          var tk = todayKey(), lastKey = '';
          mine.forEach(function (m) {
            var k = bdDateKey(m.date);
            if (k !== lastKey) {
              lastKey = k;
              html += '<div class="f26-date-h">' + (k === tk ? '🔥 TODAY · ' : '') + esc(bdDateLabel(m.date)) + '</div>';
            }
            html += matchCard(m, true, k === tk);
          });
        } else {
          html += '<div class="f26-empty">No matches found for ' + esc(mt.name) + '.</div>';
        }
      }

      body.innerHTML = html;
      startCD();
      attachExpand(body);

      document.getElementById('f26-st-matches').addEventListener('click', function () {
        myTeamView = 'matches'; renderMyTeam();
      });
      document.getElementById('f26-st-squad').addEventListener('click', function () {
        myTeamView = 'squad'; renderMyTeam();
      });
      body.querySelectorAll('.f26-flag').forEach(function (el) {
        el.addEventListener('click', function () {
          setMyTeam({ abbr: el.dataset.abbr, name: el.dataset.name });
          renderMyTeam();
          refreshBanner();
        });
      });
      var chg = document.getElementById('f26-change-team');
      if (chg) chg.addEventListener('click', function () {
        localStorage.removeItem('f26_team');
        myTeamView = 'matches';
        renderMyTeam();
      });
    }).catch(function () {
      if (mcTab === 'myteam') body.innerHTML = '<div class="f26-empty">Could not load — try again shortly.</div>';
    });
  }

  /* ══════════ PREDICT tab ══════════ */
  var predictView = 'predict';   /* 'predict' | 'board' — remembered per session */
  var _preds = null, _predsT = 0;
  function fetchPreds(force) {
    if (_preds && !force && Date.now() - _predsT < 6e4) return Promise.resolve(_preds);
    return supaGet('fifa26_predictions?select=student_id,student_name,match_id,home_score,away_score,updated_at')
      .then(function (rows) { _preds = rows || []; _predsT = Date.now(); return _preds; })
      .catch(function () { return _preds || []; });
  }
  /* 3 pts exact score · 1 pt correct outcome · prediction must predate kickoff */
  function scorePred(p, m) {
    if (!m || m.state !== 'post') return null;
    if (new Date(p.updated_at) > new Date(m.date)) return null;   /* edited after kickoff */
    var t = m.teams || [], h = parseInt((t[0] || {}).score, 10), a = parseInt((t[1] || {}).score, 10);
    if (isNaN(h) || isNaN(a)) return null;
    if (p.home_score === h && p.away_score === a) return 3;
    return Math.sign(p.home_score - p.away_score) === Math.sign(h - a) ? 1 : 0;
  }

  function renderPredict() {
    var body = document.getElementById('f26-mc-body');
    if (!body) return;
    Promise.all([fetchMatches(WC_RANGE, 18e5), fetchPreds(true)]).then(function (res) {
      if (mcTab !== 'predict') return;
      var matches = res[0], preds = res[1];
      var me = getUser() || {};
      var byId = {};
      matches.forEach(function (m) { byId[m.id] = m; });

      /* leaderboard */
      var board = {};
      preds.forEach(function (p) {
        var pts = scorePred(p, byId[p.match_id]);
        if (pts == null) return;
        if (!board[p.student_id]) board[p.student_id] = { name: p.student_name || p.student_id, pts: 0, exact: 0, n: 0 };
        board[p.student_id].pts += pts;
        board[p.student_id].n++;
        if (pts === 3) board[p.student_id].exact++;
      });
      var ranked = Object.keys(board).map(function (id) { return { id: id, b: board[id] }; })
        .sort(function (x, y) { return y.b.pts - x.b.pts || y.b.exact - x.b.exact; });

      var html = '<p class="f26-sec-note">🎯 Predict the score before kickoff — <b>3 pts</b> exact score, <b>1 pt</b> correct result. Climb the class leaderboard!</p>';

      /* sub-tabs: Predictions | Leaderboard */
      html += '<div class="f26-subtabs">' +
        '<button class="f26-subtab' + (predictView === 'predict' ? ' on' : '') + '" id="f26-pt-predict">' +
          '<i class="fa-solid fa-wand-magic-sparkles"></i> Predictions</button>' +
        '<button class="f26-subtab' + (predictView === 'board' ? ' on' : '') + '" id="f26-pt-board">' +
          '<i class="fa-solid fa-ranking-star"></i> Leaderboard</button>' +
      '</div>';

      if (predictView === 'board') {
      html += '<div class="f26-sec-h"><i class="fa-solid fa-ranking-star"></i> CLASS LEADERBOARD</div>';
      if (ranked.length) {
        html += '<div class="f26-lb">';
        ranked.slice(0, 10).forEach(function (r, i) {
          var medal = ['🥇', '🥈', '🥉'][i] || (i + 1);
          html += '<div class="f26-lb-row' + (r.id === me.id ? ' me' : '') + '">' +
            '<span class="f26-lb-rank">' + medal + '</span>' +
            '<span class="f26-lb-name">' + esc(r.b.name) + (r.id === me.id ? ' (you)' : '') + '</span>' +
            '<span class="f26-lb-meta">' + r.b.exact + ' exact · ' + r.b.n + ' scored</span>' +
            '<span class="f26-lb-pts">' + r.b.pts + '</span>' +
          '</div>';
        });
        html += '</div>';
      } else {
        /* no finished matches yet — show who has placed predictions */
        var parts = {};
        preds.forEach(function (p) {
          if (!parts[p.student_id]) parts[p.student_id] = { name: p.student_name || p.student_id, n: 0 };
          parts[p.student_id].n++;
        });
        var plist = Object.keys(parts).map(function (id) { return { id: id, x: parts[id] }; })
          .sort(function (a, b) { return b.x.n - a.x.n; });
        if (plist.length) {
          html += '<div class="f26-lb">';
          plist.slice(0, 10).forEach(function (r) {
            html += '<div class="f26-lb-row' + (r.id === me.id ? ' me' : '') + '">' +
              '<span class="f26-lb-rank">🎯</span>' +
              '<span class="f26-lb-name">' + esc(r.x.name) + (r.id === me.id ? ' (you)' : '') + '</span>' +
              '<span class="f26-lb-meta">' + r.x.n + ' prediction' + (r.x.n !== 1 ? 's' : '') + ' placed</span>' +
              '<span class="f26-lb-pts">–</span>' +
            '</div>';
          });
          html += '</div><p class="f26-sq-note">Points appear here as soon as the first match finishes ⚽</p>';
        } else {
          html += '<div class="f26-empty">No predictions yet — be the first! 🎯</div>';
        }
      }

      /* my scored history — lives with the leaderboard */
      var hist = preds.filter(function (p) { return p.student_id === me.id; })
        .map(function (p) { return { p: p, m: byId[p.match_id], pts: scorePred(p, byId[p.match_id]) }; })
        .filter(function (x) { return x.pts != null; })
        .sort(function (x, y) { return new Date(y.m.date) - new Date(x.m.date); }).slice(0, 8);
      if (hist.length) {
        html += '<div class="f26-sec-h"><i class="fa-solid fa-clock-rotate-left"></i> YOUR RESULTS</div>';
        hist.forEach(function (x) {
          var t = x.m.teams || [], a = t[0] || {}, b = t[1] || {};
          html += '<div class="f26-hist"><span>' + esc(a.abbr) + ' <b>' + esc(a.score) + '–' + esc(b.score) + '</b> ' + esc(b.abbr) + '</span>' +
            '<span class="f26-hist-you">you: ' + x.p.home_score + '–' + x.p.away_score + '</span>' +
            '<span class="f26-hist-pts p' + x.pts + '">+' + x.pts + '</span></div>';
        });
      }

      } else {   /* predictView === 'predict' */

      /* my predictions map */
      var minePred = {};
      preds.forEach(function (p) { if (p.student_id === me.id) minePred[p.match_id] = p; });

      /* predictable matches: upcoming (pre) + any live match you've already predicted
         (so your saved pick stays visible, locked, once kickoff starts) */
      var upcoming = matches.filter(function (m) {
        return m.state === 'pre' || (m.state === 'in' && minePred[m.id]);
      }).sort(function (x, y) {
        var lx = x.state === 'in' ? 0 : 1, ly = y.state === 'in' ? 0 : 1;
        if (lx !== ly) return lx - ly;            /* live ones first */
        return new Date(x.date) - new Date(y.date);
      }).slice(0, 12);

      html += '<div class="f26-sec-h"><i class="fa-solid fa-wand-magic-sparkles"></i> MAKE YOUR PREDICTIONS</div>';
      if (!upcoming.length) html += '<div class="f26-empty">No upcoming matches to predict.</div>';
      var selOpts = function (v) {
        var o = '';
        for (var i = 0; i <= 9; i++) o += '<option value="' + i + '"' + (v === i ? ' selected' : '') + '>' + i + '</option>';
        return o;
      };
      upcoming.forEach(function (m) {
        var t = m.teams || [], a = t[0] || {}, b = t[1] || {};
        var p = minePred[m.id];
        var live = m.state === 'in';
        var locked = live || new Date(m.date) <= new Date();
        html += '<div class="f26-pred' + (live ? ' f26-pred-live' : '') + '" data-mid="' + esc(m.id) + '" data-at="' + new Date(m.date).getTime() + '">' +
          '<div class="f26-pred-when">' + (live ? '<span class="f26-live-dot"></span> LIVE NOW' : esc(bdDateLabel(m.date)) + ' · ' + esc(bdTime(m.date))) + '</div>' +
          '<div class="f26-pred-mid">' +
            '<span class="f26-team">' + (a.logo ? '<img src="' + esc(a.logo) + '" alt="">' : '<span class="f26-tbd">⏳</span>') + '<b>' + esc(teamLabel(a)) + '</b></span>' +
            (locked
              ? '<span class="f26-pred-lock"><i class="fa-solid fa-lock"></i></span>'
              : '<span class="f26-pred-io"><select class="f26-ps" data-side="h">' + selOpts(p ? p.home_score : undefined) + '</select>' +
                '<i>–</i><select class="f26-ps" data-side="a">' + selOpts(p ? p.away_score : undefined) + '</select></span>') +
            '<span class="f26-team away"><b>' + esc(teamLabel(b)) + '</b>' + (b.logo ? '<img src="' + esc(b.logo) + '" alt="">' : '<span class="f26-tbd">⏳</span>') + '</span>' +
          '</div>' +
          (locked
            ? '<div class="f26-pred-foot">' + (live
                ? '<span class="f26-live-dot"></span> Live ' + esc(a.score) + '–' + esc(b.score) + ' · your pick: ' + (p ? '<b>' + p.home_score + '–' + p.away_score + '</b>' : '—') + ' <i class="fa-solid fa-lock" style="font-size:.8em;opacity:.7"></i>'
                : 'Kickoff passed — predictions locked' + (p ? ' · yours: ' + p.home_score + '–' + p.away_score : '')) + '</div>'
            : '<button class="f26-pred-save">' + (p ? '✓ Saved ' + p.home_score + '–' + p.away_score + ' — change?' : 'Save Prediction') + '</button>') +
        '</div>';
      });

      }   /* end predictView branches */

      body.innerHTML = html;

      document.getElementById('f26-pt-predict').addEventListener('click', function () {
        predictView = 'predict'; renderPredict();
      });
      document.getElementById('f26-pt-board').addEventListener('click', function () {
        predictView = 'board'; renderPredict();
      });

      body.querySelectorAll('.f26-pred-save').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var card = btn.closest('.f26-pred');
          if (Date.now() >= parseInt(card.dataset.at, 10)) {
            btn.textContent = '🔒 Kickoff passed — locked';
            btn.disabled = true;
            return;
          }
          var h = parseInt(card.querySelector('.f26-ps[data-side="h"]').value, 10);
          var a = parseInt(card.querySelector('.f26-ps[data-side="a"]').value, 10);
          var u = getUser();
          if (!u || !u.id) { btn.textContent = 'Log in first'; return; }
          btn.disabled = true;
          btn.textContent = 'Saving…';
          supaUpsert('fifa26_predictions', {
            student_id: u.id, student_name: u.name || '',
            match_id: card.dataset.mid, home_score: h, away_score: a,
          }).then(function (r) {
            btn.disabled = false;
            btn.textContent = r.ok ? ('✓ Saved ' + h + '–' + a + ' — change?') : 'Failed — try again';
            _predsT = 0;   /* bust cache */
          }).catch(function () { btn.disabled = false; btn.textContent = 'Failed — try again'; });
        });
      });
    }).catch(function () {
      if (mcTab === 'predict') body.innerHTML = '<div class="f26-empty">Could not load — try again shortly.</div>';
    });
  }

  /* ══════════ GROUPS tab ══════════ */
  var _stand = null, _standT = 0;
  function fetchStandings() {
    if (_stand && Date.now() - _standT < 3e5) return Promise.resolve(_stand);
    return fetch(WORKER + '/fifa?standings=1')
      .then(function (r) { if (!r.ok) throw new Error('http'); return r.json(); })
      .then(function (d) { _stand = d.groups || []; _standT = Date.now(); return _stand; });
  }

  function renderGroups() {
    var body = document.getElementById('f26-mc-body');
    if (!body) return;
    Promise.all([fetchStandings(), fetchMatches(WC_RANGE, 18e5)]).then(function (res) {
      if (mcTab !== 'groups') return;
      var groups = res[0], matches = res[1];
      var mt = myTeam();
      var html = '<div class="f26-sec-h"><i class="fa-solid fa-table-list"></i> GROUP STANDINGS</div><div class="f26-groups">';
      groups.forEach(function (g) {
        html += '<div class="f26-group"><div class="f26-group-h">' + esc(g.name) + '</div>' +
          '<div class="f26-group-row f26-group-head"><span></span><span>Team</span><b>P</b><b>W</b><b>D</b><b>L</b><b>GD</b><b>Pts</b></div>' +
          g.teams.map(function (t) {
            return '<div class="f26-group-row' + (mt && t.abbr === mt.abbr ? ' mine' : '') + '">' +
              (t.logo ? '<img src="' + esc(t.logo) + '" alt="">' : '<span></span>') +
              '<span>' + esc(t.abbr) + '</span>' +
              '<b>' + esc(t.p) + '</b><b>' + esc(t.w) + '</b><b>' + esc(t.d) + '</b><b>' + esc(t.l) + '</b><b>' + esc(t.gd) + '</b>' +
              '<b class="pts">' + esc(t.pts) + '</b></div>';
          }).join('') + '</div>';
      });
      html += '</div>';

      /* knockout rounds from the schedule */
      var ko = matches.filter(function (m) { return m.round && m.round !== 'group-stage'; });
      if (ko.length) {
        var rounds = {}, order = [];
        ko.sort(function (x, y) { return new Date(x.date) - new Date(y.date); }).forEach(function (m) {
          if (!rounds[m.round]) { rounds[m.round] = []; order.push(m.round); }
          rounds[m.round].push(m);
        });
        html += '<div class="f26-sec-h" style="margin-top:20px;"><i class="fa-solid fa-sitemap"></i> KNOCKOUT STAGE</div>';
        var tk = todayKey();
        order.forEach(function (r) {
          html += '<div class="f26-date-h">' + esc(roundLabel(r)) + '</div>';
          var lastK = '';
          rounds[r].forEach(function (m) {
            var k = bdDateKey(m.date);
            if (k !== lastK) {
              lastK = k;
              html += '<div class="f26-ko-date">' + (k === tk ? '🔥 TODAY · ' : '') + esc(bdDateLabel(m.date)) + '</div>';
            }
            html += matchCard(m, false, k === tk);
          });
        });
      }

      body.innerHTML = html;
      attachExpand(body);
    }).catch(function () {
      if (mcTab === 'groups') body.innerHTML = '<div class="f26-empty">Could not load standings — try again shortly.</div>';
    });
  }

  var TAB_R = { today: renderToday, schedule: renderSchedule, myteam: renderMyTeam, predict: renderPredict, groups: renderGroups };
  function switchTab(tab) {
    mcTab = tab;
    Object.keys(TAB_R).forEach(function (k) {
      var b = document.getElementById('f26-tab-' + k);
      if (b) b.classList.toggle('on', k === tab);
    });
    document.getElementById('f26-mc-body').innerHTML = '<div class="f26-loading"><i class="fa-solid fa-futbol"></i></div>';
    (TAB_R[tab] || renderToday)();
  }

  function buildMC() {
    if (document.getElementById('fifa26-mc')) return;
    var mc = document.createElement('div');
    mc.id = 'fifa26-mc';
    mc.innerHTML =
      '<div class="f26-mc-card">' +
        '<div class="f26-mc-head">' +
          '<img src="https://a.espncdn.com/i/leaguelogos/soccer/500-dark/4.png" alt="WC26">' +
          '<span class="f26-mc-head-t"><b>FIFA WORLD CUP 2026</b><small>MATCH CENTER · BANGLADESH TIME</small></span>' +
          '<button class="f26-mc-close" id="f26-mc-close"><i class="fa-solid fa-xmark"></i></button>' +
        '</div>' +
        '<div class="f26-tabs">' +
          '<button class="f26-tab on" id="f26-tab-today"><i class="fa-solid fa-bolt"></i><span> Today</span></button>' +
          '<button class="f26-tab" id="f26-tab-schedule"><i class="fa-regular fa-calendar-days"></i><span> Schedule</span></button>' +
          '<button class="f26-tab" id="f26-tab-myteam"><i class="fa-solid fa-heart"></i><span> My Team</span></button>' +
          '<button class="f26-tab" id="f26-tab-predict"><i class="fa-solid fa-bullseye"></i><span> Predict</span></button>' +
          '<button class="f26-tab" id="f26-tab-groups"><i class="fa-solid fa-table-list"></i><span> Groups</span></button>' +
        '</div>' +
        '<div class="f26-mc-body" id="f26-mc-body"></div>' +
      '</div>';
    document.body.appendChild(mc);

    document.getElementById('f26-mc-close').addEventListener('click', closeMC);
    mc.addEventListener('click', function (e) { if (e.target === mc) closeMC(); });
    Object.keys(TAB_R).forEach(function (k) {
      var b = document.getElementById('f26-tab-' + k);
      if (b) b.addEventListener('click', function () { switchTab(k); });
    });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeMC(); });
  }

  function openMC() {
    buildMC();
    var mc = document.getElementById('fifa26-mc');
    requestAnimationFrame(function () { mc.classList.add('active'); });
    document.body.style.overflow = 'hidden';
    switchTab(mcTab);
    clearInterval(mcTimer);
    mcTimer = setInterval(function () { if (mcTab === 'today') renderToday(); }, 6e4);
  }
  function closeMC() {
    var mc = document.getElementById('fifa26-mc');
    if (mc) mc.classList.remove('active');
    document.body.style.overflow = '';
    clearInterval(mcTimer); clearInterval(cdTimer);
  }

  /* ── boot ── */
  var bannerTimer = null;
  /* don't insert the banner until fifa26.css is actually loaded — otherwise
     a refresh can briefly show the banner as raw unstyled text (FOUC) */
  function whenCssReady(cb) {
    var l = document.getElementById('fifa26-css');
    var done = false;
    var run = function () { if (!done) { done = true; cb(); } };
    if (!l || l.sheet) return run();
    l.addEventListener('load', run, { once: true });
    l.addEventListener('error', run, { once: true });
    setTimeout(run, 3000);   /* safety net */
  }
  function boot() {
    applyThemeOnly();
    /* restore my team from Supabase on a fresh device/browser */
    var u = getUser();
    if (u && u.id && !myTeam()) {
      supaGet('fifa26_teams?student_id=eq.' + encodeURIComponent(u.id) + '&select=team_abbr,team_name')
        .then(function (rows) {
          if (rows && rows[0]) {
            localStorage.setItem('f26_team', JSON.stringify({ abbr: rows[0].team_abbr, name: rows[0].team_name }));
            refreshBanner();
          }
        }).catch(function () {});
    }
    whenCssReady(function () {
      buildBanner();
      buildHomeStrip();
      refreshBanner();
      bannerTimer = setInterval(refreshBanner, 9e4);
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
