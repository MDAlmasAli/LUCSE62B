/**
 * Shared Authentication State Checker
 * - Keeps header login/profile button in sync
 * - Option A: Force re-login after 7 days
 * - Option B: Main Sheet re-validation every minute and on tab focus
 */
(function () {
  if (window.lu62b_auth_initialized) return;
  window.lu62b_auth_initialized = true;

  const WORKER_URL = 'https://lucse62b-api.sy164425.workers.dev';
  const SEVEN_DAYS = 7 * 24 * 60 * 60 * 1000;
  const VALIDATION_INTERVAL = 60 * 1000;

  const rawData    = localStorage.getItem('lu62b_student') || sessionStorage.getItem('lu62b_student');
  const isInPages  = window.location.pathname.includes('/pages/');
  const isLoggedIn = !!rawData;
  var session      = null;

  try { session = rawData ? JSON.parse(rawData) : null; } catch (e) {}

  const isDemoSession = !!(
    session &&
    (session.isDemo || String(session.id || '').toUpperCase() === 'DEMO')
  );

  // ── Force logout helper ──────────────────────────────────────────────
  var logoutStarted = false;

  async function revokeWebPush() {
    if (!('serviceWorker' in navigator)) return;
    try {
      const reg = await navigator.serviceWorker.ready;
      reg.active?.postMessage({ type: 'SET_STUDENT_ID', studentId: null });
      const sub = await reg.pushManager.getSubscription();
      if (!sub) return;
      await Promise.allSettled([
        fetch(WORKER_URL + '/push-subscribe', {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ endpoint: sub.endpoint }),
          keepalive: true,
        }),
        sub.unsubscribe(),
      ]);
    } catch (e) {}
  }

  function forceLogout(reason) {
    if (logoutStarted) return;
    logoutStarted = true;
    localStorage.removeItem('lu62b_student');
    sessionStorage.removeItem('lu62b_student');
    localStorage.removeItem('lu62b_last_validation');
    const loginPath = isInPages ? 'login.html' : 'pages/login.html';
    Promise.race([
      revokeWebPush(),
      new Promise(function (resolve) { setTimeout(resolve, 1200); }),
    ]).finally(function () {
      window.location.replace(loginPath + '?lo=' + reason);
    });
  }

  // ── Sheet validation (proxied via Worker) ────────────────────────────
  function checkStudentInSheet(studentId) {
    var timeout = new Promise(function (resolve) {
      setTimeout(function () { resolve(null); }, 5000);
    });
    var check = fetch(WORKER_URL + '/session-status?id=' + encodeURIComponent(studentId), {
      cache: 'no-store',
    })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        return data && typeof data.active === 'boolean' ? data.active : null;
      })
      .catch(function () { return null; });
    return Promise.race([timeout, check]);
  }

  var validationRunning = false;

  function runBackgroundValidation(session) {
    if (!session || !session.id || isDemoSession || validationRunning || logoutStarted) return;
    // Skip on login/password-setup pages — no point checking there
    const page = window.location.pathname.split('/').pop();
    if (page === 'login.html' || page === 'password-setup.html') return;

    validationRunning = true;
    checkStudentInSheet(session.id).then(function (found) {
      if (found === true) {
        localStorage.setItem('lu62b_last_validation', JSON.stringify({ t: Date.now() }));
      } else if (found === false) {
        forceLogout('removed');
      }
    }).finally(function () {
      validationRunning = false;
    });
  }

  // ── Session checks (A + B) ───────────────────────────────────────────
  if (isLoggedIn) {
    if (session && session.id) {
      // A — 7-day expiry
      if (session.loginTime && Date.now() - session.loginTime > SEVEN_DAYS) {
        forceLogout('expired');
        return;
      }

      // B — authoritative Main Sheet validation (every minute + tab focus)
      var lastVal = null;
      try { lastVal = JSON.parse(localStorage.getItem('lu62b_last_validation')); } catch (e) {}
      var shouldValidate = !lastVal || !lastVal.t || (Date.now() - lastVal.t > VALIDATION_INTERVAL);

      if (shouldValidate) {
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', function () { runBackgroundValidation(session); });
        } else {
          runBackgroundValidation(session);
        }
      }

      if (!isDemoSession) {
        setInterval(function () { runBackgroundValidation(session); }, VALIDATION_INTERVAL);
        window.addEventListener('focus', function () { runBackgroundValidation(session); });
        document.addEventListener('visibilitychange', function () {
          if (document.visibilityState === 'visible') runBackgroundValidation(session);
        });
      }
    }

    document.documentElement.classList.add('lu62b-logged-in');
    if (isDemoSession) document.documentElement.classList.add('lu62b-demo-session');

    var profilePath = isInPages ? 'profile.html' : 'pages/profile.html';

    function updateNavButtons() {
      var profileLabel = '<i class="fa-solid fa-user"></i> Profile';
      if (isDemoSession) {
        profileLabel += ' <span class="lu62b-demo-badge">Demo</span>';
      }

      var navBtn = document.getElementById('navLoginBtn');
      if (navBtn) {
        navBtn.innerHTML = profileLabel;
        navBtn.href      = profilePath;
        navBtn.style.color = 'var(--green)';
      }
      var mobileBtn = document.getElementById('mobileLoginBtn');
      if (mobileBtn) {
        mobileBtn.innerHTML = profileLabel;
        mobileBtn.href      = profilePath;
        mobileBtn.style.color = 'var(--green)';
      }
      var statusPill = document.querySelector('.topbar-status');
      if (statusPill && isDemoSession) {
        statusPill.innerHTML = '<div class="status-dot"></div>Portal Active <span class="lu62b-demo-badge">Demo</span>';
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', updateNavButtons);
    } else {
      updateNavButtons();
    }
  }

  // ── DOB Gate ─────────────────────────────────────────────────────────
  const SKIP_DOB = ['login.html', 'password-setup.html'];
  const _curPage = window.location.pathname.split('/').pop();

  function _workerPost(endpoint, body) {
    return fetch(WORKER_URL + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); });
  }

  // Verifies DOB against LU portal via worker /result endpoint.
  // Returns 'ok' | 'wrong' | 'error'
  async function _luVerifyDob(sid, dob) {
    try {
      var res = await fetch(WORKER_URL + '/result', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ student_id: sid, birth_date: dob }),
      });
      if (!res.ok) return 'error';
      var data = await res.json();
      if (data && data.success) {
        try {
          var IMPROVE = new Set(['B-', 'C+', 'C', 'D']);
          var retake = [], improve = [];
          Object.values(data.results || {}).forEach(function (ys) {
            var sems = Array.isArray(ys) ? ys : Object.values(ys);
            sems.forEach(function (sem) {
              (sem.courses || []).forEach(function (c) {
                var code = (c.course_code || '').trim().toUpperCase();
                if (!code) return;
                if (c.grade === 'F') retake.push(code);
                else if (IMPROVE.has(c.grade)) improve.push(code);
              });
            });
          });
          localStorage.setItem('lu62b_retake_codes',  JSON.stringify(retake));
          localStorage.setItem('lu62b_improve_codes', JSON.stringify(improve));
        } catch (e) {}
        return 'ok';
      }
      return 'wrong';
    } catch (e) {
      return 'error';
    }
  }

  function _showDobGate(sid) {
    // DOB already LU-verified once and stored in Supabase — used as a trusted
    // fallback when the LU portal is down or misbehaving, so users are never
    // locked out of their own account by an LU outage.
    var _supaDob = null;

    function _passGate(dob) {
      localStorage.setItem('lu62b_dob_'    + sid, dob);
      localStorage.setItem('lu62b_dob_ok_' + sid, '1');
      _workerPost('/dob-sync', { student_id: sid, dob: dob }).catch(function () {});
      var g = document.getElementById('_lu-dob-gate');
      if (g) g.remove();
    }

    var style = document.createElement('style');
    style.textContent = `
      @keyframes _dobFadeIn{from{opacity:0;transform:translateY(24px) scale(.97)}to{opacity:1;transform:none}}
      #_lu-dob-gate{position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;padding:20px;
        background:rgba(6,4,24,0.96);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);}
      ._dob-card{background:var(--card,#13111f);border:1px solid var(--border,rgba(124,58,237,0.2));
        border-radius:28px;padding:44px 36px 36px;max-width:440px;width:100%;text-align:center;
        box-shadow:0 32px 80px rgba(0,0,0,0.65);position:relative;overflow:hidden;
        animation:_dobFadeIn 0.4s cubic-bezier(.34,1.2,.64,1) both;}
      ._dob-card::before{content:'';position:absolute;top:0;left:0;right:0;height:130px;
        background:linear-gradient(135deg,rgba(124,58,237,0.18),rgba(236,72,153,0.13));
        border-bottom:1px solid var(--border,rgba(124,58,237,0.15));pointer-events:none;}
      ._dob-icon{width:68px;height:68px;background:linear-gradient(135deg,#7c3aed,#a855f7);
        border-radius:18px;margin:6px auto 18px;display:flex;align-items:center;justify-content:center;
        font-size:1.8rem;position:relative;z-index:1;box-shadow:0 10px 28px rgba(124,58,237,0.45);}
      ._dob-brand{font-family:'Space Grotesk',sans-serif;font-weight:700;
        color:var(--accent-bright,#a78bfa);font-size:0.74rem;letter-spacing:0.12em;
        text-transform:uppercase;margin-bottom:6px;position:relative;z-index:1;}
      ._dob-title{font-family:'Space Grotesk',sans-serif;font-weight:700;font-size:1.55rem;
        color:var(--text,#f0e6ff);margin:0 0 10px;position:relative;z-index:1;}
      ._dob-desc{font-size:0.84rem;color:var(--text-secondary,rgba(196,181,253,0.7));
        line-height:1.7;margin:0 0 26px;position:relative;z-index:1;}
      ._dob-selects{display:grid;grid-template-columns:1fr 1fr 1fr;gap:9px;margin-bottom:13px;}
      ._dob-selects select{width:100%;padding:11px 8px;
        background:rgba(255,255,255,0.05);border:1px solid var(--border,rgba(124,58,237,0.2));
        border-radius:10px;color:var(--text,#e2d9f3);font-family:'Inter',sans-serif;
        font-size:0.88rem;cursor:pointer;transition:border-color 0.2s;appearance:auto;}
      ._dob-selects select:focus{outline:none;border-color:var(--accent,#7c3aed);}
      ._dob-selects select option{background:#13111f;color:#e2d9f3;}
      html[data-theme="light"] ._dob-selects select{background:rgba(0,0,0,0.04);color:#1a1a2e;}
      html[data-theme="light"] ._dob-selects select option{background:#ffffff;color:#1a1a2e;}
      ._dob-err{color:#f43f5e;font-size:0.8rem;font-weight:500;margin-bottom:10px;min-height:16px;text-align:left;}
      ._dob-btn{width:100%;padding:13px 20px;
        background:linear-gradient(135deg,var(--accent,#7c3aed),var(--accent2,#a855f7));
        color:#fff;border:none;border-radius:11px;font-weight:700;font-family:'Inter',sans-serif;
        font-size:0.95rem;cursor:pointer;transition:all 0.25s;
        display:flex;align-items:center;justify-content:center;gap:8px;}
      ._dob-btn:hover{transform:translateY(-2px);box-shadow:0 8px 22px rgba(124,58,237,0.4);}
      ._dob-btn:disabled{opacity:0.55;cursor:not-allowed;transform:none;box-shadow:none;}
      ._dob-note{color:var(--muted,rgba(167,139,250,0.4));font-size:0.72rem;margin-top:14px;}
      ._dob-spin{width:15px;height:15px;border:2px solid rgba(255,255,255,0.3);border-top-color:#fff;
        border-radius:50%;animation:_dobSpin 0.7s linear infinite;display:inline-block;}
      @keyframes _dobSpin{to{transform:rotate(360deg)}}
      @media(max-width:480px){._dob-card{padding:34px 20px 28px;border-radius:22px;}._dob-title{font-size:1.35rem;}}
    `;
    document.head.appendChild(style);

    var gate = document.createElement('div');
    gate.id = '_lu-dob-gate';
    // Start with a loading/checking state — gate is blocking from the very first moment
    gate.innerHTML =
      '<div class="_dob-card">' +
        '<div class="_dob-icon">🎂</div>' +
        '<div class="_dob-brand">CSE 62B · PORTAL</div>' +
        '<h2 class="_dob-title">Checking Profile…</h2>' +
        '<p class="_dob-desc" style="margin-bottom:8px;">Please wait a moment.</p>' +
        '<div style="display:flex;justify-content:center;padding:18px 0;">' +
          '<span class="_dob-spin" style="width:24px;height:24px;border-width:3px;"></span>' +
        '</div>' +
      '</div>';

    // Switch the card to the DOB input form
    function _toInputForm(prefillDob, errMsg) {
      var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      var dayOpts = '<option value="">Day</option>'   + Array.from({length:31},function(_,i){var d=String(i+1).padStart(2,'0');return '<option value="'+d+'">'+(i+1)+'</option>';}).join('');
      var moOpts  = '<option value="">Month</option>' + months.map(function(m,i){var v=String(i+1).padStart(2,'0');return '<option value="'+v+'">'+m+'</option>';}).join('');
      var curYear = new Date().getFullYear();
      var yrOpts  = '<option value="">Year</option>'  + Array.from({length:curYear-1959},function(_,i){var y=curYear-i;return '<option value="'+y+'">'+y+'</option>';}).join('');

      gate.querySelector('._dob-card').innerHTML =
        '<div class="_dob-icon">🎂</div>' +
        '<div class="_dob-brand">CSE 62B · PORTAL</div>' +
        '<h2 class="_dob-title">One Quick Step</h2>' +
        '<p class="_dob-desc">Enter your <strong style="color:var(--accent-bright,#a78bfa);">Date of Birth</strong> exactly as written on your certificate.<br>This verifies your identity with the LU portal.</p>' +
        '<div class="_dob-selects">' +
          '<select id="_dobDay">'   + dayOpts + '</select>' +
          '<select id="_dobMonth">' + moOpts  + '</select>' +
          '<select id="_dobYear">'  + yrOpts  + '</select>' +
        '</div>' +
        '<div class="_dob-err" id="_dobErr">' + (errMsg || '') + '</div>' +
        '<button class="_dob-btn" id="_dobBtn"><i class="fa-solid fa-arrow-right-to-bracket"></i> Verify &amp; Continue</button>' +
        '<p class="_dob-note"><i class="fa-solid fa-lock" style="font-size:0.65rem;"></i> Verified with LU portal · Stored securely</p>';

      if (prefillDob) {
        var p = prefillDob.split('-');
        if (p.length === 3) {
          document.getElementById('_dobYear').value  = p[0];
          document.getElementById('_dobMonth').value = p[1];
          document.getElementById('_dobDay').value   = p[2];
        }
      }

      document.getElementById('_dobBtn').addEventListener('click', async function () {
        var day   = document.getElementById('_dobDay').value;
        var month = document.getElementById('_dobMonth').value;
        var year  = document.getElementById('_dobYear').value;
        var btn   = document.getElementById('_dobBtn');
        var err   = document.getElementById('_dobErr');
        err.textContent = '';
        if (!day || !month || !year) { err.textContent = 'Please select your complete date of birth.'; return; }
        var dob = year + '-' + month + '-' + day;
        btn.disabled = true;
        btn.innerHTML = '<span class="_dob-spin"></span> Verifying with LU portal…';

        var result = await _luVerifyDob(sid, dob);
        if (result !== 'ok' && _supaDob && dob === _supaDob) {
          // LU portal failed but the entered DOB matches the previously
          // LU-verified record in Supabase — accept it.
          result = 'ok';
        }
        if (result === 'ok') {
          _passGate(dob);
        } else if (result === 'wrong') {
          err.textContent = 'Date of Birth is incorrect. Please check your certificate and try again.';
          btn.disabled = false;
          btn.innerHTML = '<i class="fa-solid fa-arrow-right-to-bracket"></i> Verify &amp; Continue';
        } else {
          err.textContent = 'LU portal is temporarily unavailable. Please try again in a few minutes.';
          btn.disabled = false;
          btn.innerHTML = '<i class="fa-solid fa-arrow-right-to-bracket"></i> Verify &amp; Continue';
        }
      });
    }

    var inject = async function () {
      document.body.appendChild(gate);

      // 1. Try localStorage DOB first
      var storedDob = localStorage.getItem('lu62b_dob_' + sid);

      // 2. Always fetch the Supabase record — it's the trusted fallback
      try {
        var chk = await _workerPost('/dob-check', { student_id: sid });
        if (chk && chk.has_dob) {
          var got = await _workerPost('/dob-get', { student_id: sid });
          if (got && got.dob) _supaDob = got.dob;
        }
      } catch (e) {}
      if (!storedDob) storedDob = _supaDob;

      // 3. If we have a candidate DOB, silently verify it with the LU API
      if (storedDob) {
        var result = await _luVerifyDob(sid, storedDob);
        if (result !== 'ok' && _supaDob && storedDob === _supaDob) {
          // LU portal down/misbehaving but this DOB was already LU-verified
          // once (Supabase only stores it after a successful verification) —
          // trust it instead of locking the user out.
          result = 'ok';
        }
        if (result === 'ok') {
          _passGate(storedDob);
          return;
        }
        // Wrong DOB — clear it so user starts fresh; network error — pre-fill so they can retry
        if (result === 'wrong') { localStorage.removeItem('lu62b_dob_' + sid); storedDob = null; }
      }

      // 4. Show input form (pre-fill if available for easy retry on network error)
      _toInputForm(storedDob || null, null);
    };

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', inject);
    } else {
      inject();
    }
  }

  // Gate fires whenever DOB has not been LU-verified in this browser
  if (isLoggedIn && session && session.id && !isDemoSession && !SKIP_DOB.includes(_curPage)) {
    if (localStorage.getItem('lu62b_dob_ok_' + session.id) !== '1') {
      _showDobGate(session.id);
    }
  }

  // ── Hamburger menu ───────────────────────────────────────────────────
  function initHamburger() {
    var ham   = document.getElementById('hamburger');
    var mNav  = document.getElementById('mobileNav');
    var mClose = document.getElementById('mobileNavClose');
    if (!ham || !mNav || !mClose) return;

    ham.addEventListener('click', function (e) {
      e.stopPropagation();
      ham.classList.toggle('open');
      mNav.classList.toggle('open');
    });
    mClose.addEventListener('click', function (e) {
      e.stopPropagation();
      ham.classList.remove('open');
      mNav.classList.remove('open');
    });
    mNav.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function () {
        ham.classList.remove('open');
        mNav.classList.remove('open');
      });
    });
    document.addEventListener('click', function (e) {
      if (!ham.contains(e.target) && !mNav.contains(e.target) && mNav.classList.contains('open')) {
        ham.classList.remove('open');
        mNav.classList.remove('open');
      }
    });
  }

  // ── Mobile Bottom Navigation Bar ─────────────────────────────────────
  function injectBottomNav() {
    if (document.getElementById('mobileBottomNav')) return;

    var path = window.location.pathname;
    var page = path.split('/').pop().replace('.html', '') || 'index';
    var root = isInPages ? '../' : '';
    var sub  = isInPages ? '' : 'pages/';

    var isAttendanceAdmin = !!(session && session.id === '0182320012101068');

    var items = [
      { href: root + 'index.html',    icon: 'fa-house',            label: 'Home',      id: 'index',     show: true },
      isAttendanceAdmin
        ? { href: sub + 'attendance.html', icon: 'fa-clipboard-list', label: 'Attendance', id: 'attendance', show: true }
        : { href: sub + 'resources.html',  icon: 'fa-book-open',      label: 'Materials',  id: 'resources',  show: isLoggedIn },
      { href: sub + 'cover-page.html', icon: 'fa-file-pdf',        label: 'Cover Page', id: 'cover-page', show: true },
      { href: sub + 'info.html', icon: 'fa-circle-info', label: 'Info', id: 'info', show: isLoggedIn },
      isLoggedIn
        ? { href: sub + 'profile.html', icon: 'fa-user',               label: 'Profile', id: 'profile', show: true }
        : { href: sub + 'login.html',   icon: 'fa-right-to-bracket',   label: 'Login',   id: 'login',   show: true },
    ];

    var nav = document.createElement('nav');
    nav.id        = 'mobileBottomNav';
    nav.className = 'mobile-bottom-nav';
    nav.setAttribute('aria-label', 'Mobile navigation');

    items.filter(function (i) { return i.show; }).forEach(function (item) {
      var isActive = page === item.id || (page === '' && item.id === 'index');
      var a = document.createElement('a');
      a.href      = item.href;
      a.className = 'mbn-item' + (isActive ? ' active' : '');
      a.setAttribute('aria-label', item.label);
      a.innerHTML = '<i class="fa-solid ' + item.icon + '"></i><span>' + item.label + '</span>';
      nav.appendChild(a);
    });

    document.body.appendChild(nav);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { initHamburger(); injectBottomNav(); });
  } else {
    initHamburger();
    injectBottomNav();
  }
})();
