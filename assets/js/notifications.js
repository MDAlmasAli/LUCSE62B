/* ── CSE 62B · Notification System ────────────────────────────────── */
(function () {
  const SUPA_URL  = 'https://ftvtlqxpalwvyserujuh.supabase.co';
  const SUPA_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';
  const WORKER    = 'https://lucse62b-api.sy164425.workers.dev';
  const VAPID_PUB = 'BKvTLWhriB6TC5zTPHg7ueOTkPuscWWohuFAshrCCigaT1cKm_vUTrFYtV6x8yDgmQZiOjPIjxf5sMdYErfFPK4';
  const LS_SEEN    = 'lu62b_notif_last_seen';
  const LS_WN_SEEN = 'lu62b_wn_last_seen';

  let _notifs = [];

  /* ── Login check ── */
  function isLoggedIn() {
    try {
      const raw = localStorage.getItem('lu62b_student') || sessionStorage.getItem('lu62b_student');
      return !!(raw && JSON.parse(raw)?.id);
    } catch { return false; }
  }

  /* ── Boot ── */
  function boot() {
    if (!isLoggedIn()) return;
    renderBell();
    fetchNotifs().then(ns => { _notifs = ns; updateBadge(); });
    /* Tell SW the logged-in student_id so push shows personalized notification */
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.ready.then(reg => {
        reg.active?.postMessage({ type: 'SET_STUDENT_ID', studentId: getStudentId() });
      }).catch(() => {});
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  /* ── Bell button injection ── */
  function renderBell() {
    const bar = document.querySelector('.topbar');
    if (!bar || document.getElementById('notifBellBtn')) return;
    injectStyles();
    injectWhatsNewLink(bar);
    const btn = document.createElement('button');
    btn.id = 'notifBellBtn';
    btn.className = 'notif-bell-btn';
    btn.setAttribute('aria-label', 'Notifications');
    btn.innerHTML = '<i class="fa-solid fa-bell"></i><span class="notif-badge" id="notifBadge" style="display:none"></span>';
    btn.onclick = toggleDropdown;
    const themeBtn = bar.querySelector('.theme-toggle-btn');
    bar.insertBefore(btn, themeBtn || null);
  }

  /* ── What's New nav link ── */
  function injectWhatsNewLink(bar) {
    const ul = bar.querySelector('.topbar-links');
    if (!ul || document.getElementById('whatsNewNavLi')) return;

    const isInPages = window.location.pathname.includes('/pages/');
    const href = (isInPages ? '' : 'pages/') + 'whats-new.html';
    const isActive = window.location.pathname.endsWith('whats-new.html');

    const li = document.createElement('li');
    li.id = 'whatsNewNavLi';
    li.innerHTML = `<a href="${href}" id="whatsNewNavA"${isActive ? ' class="active"' : ''}>What's New</a>`;
    const lastLi = ul.lastElementChild;
    ul.insertBefore(li, lastLi);

    /* Mobile nav */
    const mNav = document.getElementById('mobileNav');
    if (mNav && !document.getElementById('whatsNewMobileA')) {
      const a = document.createElement('a');
      a.id   = 'whatsNewMobileA';
      a.href = href;
      if (isActive) a.className = 'active';
      a.textContent = "What's New";
      const lastA = mNav.querySelector('a:last-child');
      mNav.insertBefore(a, lastA);
    }

    fetchWhatsNewBadge();
  }

  async function fetchWhatsNewBadge() {
    if (window.location.pathname.endsWith('whats-new.html')) return;
    try {
      const lastSeen = localStorage.getItem(LS_WN_SEEN) || '1970-01-01T00:00:00Z';
      const r = await fetch(
        `${SUPA_URL}/rest/v1/site_updates?created_at=gt.${encodeURIComponent(lastSeen)}&limit=1&select=id`,
        { headers: { 'apikey': SUPA_ANON, 'Authorization': `Bearer ${SUPA_ANON}` } }
      );
      if (!r.ok) return;
      const rows = await r.json();
      if (rows.length > 0) {
        const a = document.getElementById('whatsNewNavA');
        if (a) {
          a.classList.add('wn-link-glow');
          const badge = document.createElement('span');
          badge.className = 'wn-nav-badge';
          badge.textContent = 'NEW';
          a.appendChild(badge);
        }
        const mobileA = document.getElementById('whatsNewMobileA');
        if (mobileA) mobileA.classList.add('wn-link-glow');
      }
    } catch {}
  }

  function injectStyles() {
    if (document.getElementById('notif-css')) return;
    const s = document.createElement('style');
    s.id = 'notif-css';
    s.textContent = `
      .notif-bell-btn{position:relative;background:none;border:none;color:var(--text-secondary);
        cursor:pointer;padding:7px;border-radius:9px;transition:background .15s;font-size:1rem;
        display:flex;align-items:center;flex-shrink:0;}
      .notif-bell-btn:hover{background:rgba(255,255,255,.08);}
      .notif-badge{position:absolute;top:3px;right:3px;min-width:15px;height:15px;border-radius:8px;
        background:#f43f5e;color:#fff;font-size:0.58rem;font-weight:800;line-height:1;
        display:flex;align-items:center;justify-content:center;padding:0 3px;
        font-family:'Inter',sans-serif;border:2px solid var(--bg,#0d0d1b);pointer-events:none;}
      #notif-dropdown{position:fixed;background:#15131f;
        border:1px solid var(--border,rgba(255,255,255,.08));border-radius:14px;
        box-shadow:0 12px 40px rgba(0,0,0,.5);z-index:99990;width:320px;overflow:hidden;
        backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
        font-family:'Inter',sans-serif;}
      html[data-theme="light"] #notif-dropdown{background:#ffffff;}
      .nd-header{padding:12px 16px;border-bottom:1px solid var(--border,rgba(255,255,255,.08));
        display:flex;align-items:center;justify-content:space-between;}
      .nd-title{font-size:.82rem;font-weight:700;color:var(--text,#e2d9f3);}
      .nd-mark{font-size:.68rem;color:var(--accent-bright,#a78bfa);background:none;border:none;
        cursor:pointer;font-family:'Inter',sans-serif;padding:0;}
      .nd-list{max-height:360px;overflow-y:auto;}
      .nd-item{padding:11px 16px;border-bottom:1px solid var(--border,rgba(255,255,255,.05));
        cursor:pointer;transition:background .12s;display:block;text-decoration:none;color:inherit;}
      .nd-item:hover{background:rgba(99,102,241,.08);}
      .nd-item.unread{background:rgba(99,102,241,.04);}
      .nd-item-title{font-size:.78rem;font-weight:700;color:var(--text,#e2d9f3);
        margin-bottom:3px;display:flex;align-items:center;gap:6px;}
      .nd-item.unread .nd-item-title::before{content:'';width:6px;height:6px;border-radius:50%;
        background:#a78bfa;flex-shrink:0;}
      .nd-item-body{font-size:.68rem;color:var(--text-secondary,#94a3b8);line-height:1.55;
        white-space:pre-wrap;margin-bottom:3px;}
      .nd-item-time{font-size:.62rem;color:var(--text-secondary,#64748b);}
      .nd-empty{padding:36px 16px;text-align:center;color:var(--text-secondary,#64748b);
        font-size:.78rem;line-height:1.8;}
      .nd-push-row{padding:10px 14px;border-top:1px solid var(--border,rgba(255,255,255,.08));}
      .nd-push-btn{width:100%;padding:8px 12px;border-radius:9px;font-weight:700;font-size:.75rem;
        border:none;cursor:pointer;font-family:'Inter',sans-serif;
        background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;
        display:flex;align-items:center;justify-content:center;gap:6px;}
      .nd-push-btn.unsub{background:rgba(255,255,255,.06);color:var(--text-secondary,#94a3b8);}
      .wn-nav-badge{display:inline-block;background:linear-gradient(135deg,#7c3aed,#a855f7);
        color:#fff;font-size:.5rem;font-weight:800;padding:1px 5px;border-radius:5px;
        letter-spacing:.05em;text-transform:uppercase;margin-left:5px;vertical-align:middle;}
      @keyframes wn-link-glow{
        0%  {color:#fff;    text-shadow:0 0 6px #e9d5ff,0 0 18px rgba(167,139,250,1),0 0 40px rgba(124,58,237,.95),0 0 70px rgba(109,40,217,.7);transform:scale(1.08);}
        40% {color:#f0abfc; text-shadow:0 0 8px #f0abfc,0 0 22px rgba(232,121,249,.9),0 0 45px rgba(192,38,211,.7),0 0 80px rgba(126,34,206,.5);transform:scale(1.1);}
        100%{color:#fff;    text-shadow:0 0 6px #e9d5ff,0 0 18px rgba(167,139,250,1),0 0 40px rgba(124,58,237,.95),0 0 70px rgba(109,40,217,.7);transform:scale(1.08);}
      }
      .wn-link-glow{animation:wn-link-glow 1.2s ease-in-out infinite !important;color:#fff !important;display:inline-block !important;transform-origin:center !important;}
    `;
    document.head.appendChild(s);
  }

  /* ── Get logged-in student ID ── */
  function getStudentId() {
    try { return JSON.parse(localStorage.getItem('lu62b_student') || 'null')?.id || null; }
    catch { return null; }
  }

  function notificationCategory(type) {
    const value = String(type || '').toLowerCase();
    if (value.includes('notice')) return 'notices';
    if (value.includes('classwork') || value.includes('deadline')) return 'classwork';
    if (value.includes('routine') || value.includes('exam')) return 'routine';
    if (value.includes('app_update')) return 'updates';
    return 'general';
  }

  function notificationPreferences() {
    try {
      return JSON.parse(localStorage.getItem('lu62b_notif_preferences') || '{}');
    } catch { return {}; }
  }

  /* ── Fetch public + personal notifications ── */
  async function fetchNotifs() {
    try {
      const studentId = getStudentId();
      let url = `${SUPA_URL}/rest/v1/notifications?order=created_at.desc&limit=20`;
      if (studentId) {
        url += `&or=(student_id.is.null,student_id.eq.${encodeURIComponent(studentId)})`;
      } else {
        url += '&student_id=is.null';
      }
      const r = await fetch(url, {
        headers: { 'apikey': SUPA_ANON, 'Authorization': `Bearer ${SUPA_ANON}` },
      });
      if (!r.ok) return [];
      const prefs = notificationPreferences();
      return (await r.json()).filter(n => prefs[notificationCategory(n.type)] !== false);
    } catch { return []; }
  }

  function parseTimestamp(value) {
    const timestamp = Date.parse(value || '');
    return Number.isFinite(timestamp) ? timestamp : 0;
  }

  function getLastSeenTimestamp() {
    return parseTimestamp(localStorage.getItem(LS_SEEN));
  }

  function markAllSeen() {
    const newestNotification = _notifs.reduce(
      (latest, notification) => Math.max(latest, parseTimestamp(notification.created_at)),
      0,
    );
    /* Cover both the fetched rows and a device clock that is ahead of them. */
    const watermark = Math.max(Date.now(), newestNotification);
    localStorage.setItem(LS_SEEN, new Date(watermark).toISOString());
  }

  function updateBadge() {
    const seen  = getLastSeenTimestamp();
    const count = _notifs.filter(n => parseTimestamp(n.created_at) > seen).length;
    const badge = document.getElementById('notifBadge');
    if (!badge) return;
    badge.textContent = count > 9 ? '9+' : String(count);
    badge.style.display = count > 0 ? 'flex' : 'none';
  }

  /* ── Dropdown ── */
  function toggleDropdown() {
    const existing = document.getElementById('notif-dropdown');
    if (existing) { existing.remove(); return; }
    showDropdown();
  }

  async function showDropdown() {
    const btn = document.getElementById('notifBellBtn');
    if (!btn) return;

    const seen = getLastSeenTimestamp();
    const drop = document.createElement('div');
    drop.id = 'notif-dropdown';

    const isPushSupported = ('Notification' in window) && ('PushManager' in window) && ('serviceWorker' in navigator);
    let isSubscribed = false;
    if (isPushSupported) {
      try {
        const reg = await navigator.serviceWorker.ready;
        isSubscribed = !!(await reg.pushManager.getSubscription());
      } catch {}
    }

    const items = _notifs.length
      ? _notifs.map(n => {
          const isNew = parseTimestamp(n.created_at) > seen;
          return `<a class="nd-item${isNew ? ' unread' : ''}" href="${escH(n.link || '/')}">
            <div class="nd-item-title">${escH(n.title)}</div>
            <div class="nd-item-body">${escH(n.body)}</div>
            <div class="nd-item-time">${relTime(n.created_at)}</div>
          </a>`;
        }).join('')
      : `<div class="nd-empty"><i class="fa-solid fa-bell-slash" style="font-size:1.4rem;opacity:.4;display:block;margin-bottom:8px;"></i>No notifications yet</div>`;

    let pushRow = '';
    if (isPushSupported) {
      if (!isSubscribed) {
        pushRow = `<div class="nd-push-row"><button class="nd-push-btn" onclick="window._notifSubscribe()"><i class="fa-solid fa-bell"></i> Enable Push Notifications</button></div>`;
      } else {
        pushRow = `<div class="nd-push-row"><button class="nd-push-btn unsub" onclick="window._notifUnsubscribe()"><i class="fa-solid fa-bell-slash"></i> Disable Notifications</button></div>`;
      }
    }

    drop.innerHTML = `
      <div class="nd-header">
        <span class="nd-title"><i class="fa-solid fa-bell" style="color:var(--accent-bright);margin-right:6px;font-size:.8rem;"></i>Notifications</span>
        <button class="nd-mark" onclick="window._notifMarkAll()">Mark all read</button>
      </div>
      <div class="nd-list">${items}</div>
      ${pushRow}
      <div class="nd-push-row"><a class="nd-push-btn" href="${location.pathname.includes('/pages/') ? '' : 'pages/'}notification-preferences.html"><i class="fa-solid fa-sliders"></i> Notification Preferences</a></div>`;

    document.body.appendChild(drop);
    positionDrop(drop, btn);

    // Close on outside click
    setTimeout(() => {
      document.addEventListener('click', function _h(e) {
        if (!drop.contains(e.target) && !btn.contains(e.target)) {
          drop.remove();
          document.removeEventListener('click', _h);
        }
      });
    }, 10);

    // Mark all as read
    markAllSeen();
    updateBadge();
  }

  function positionDrop(drop, btn) {
    const rect = btn.getBoundingClientRect();
    const w    = 320;
    let left   = rect.right - w;
    if (left < 8) left = 8;
    if (left + w > window.innerWidth - 8) left = window.innerWidth - w - 8;
    drop.style.left = `${left}px`;
    drop.style.top  = `${rect.bottom + 8}px`;
  }

  window._notifMarkAll = function () {
    markAllSeen();
    updateBadge();
    document.getElementById('notif-dropdown')?.remove();
  };

  /* ── Push Subscribe ── */
  window._notifSubscribe = async function () {
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') { _toast('Notification permission denied.'); return; }
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: _urlB64ToUint8(VAPID_PUB),
      });
      const studentId = getStudentId();
      await fetch(`${WORKER}/push-subscribe`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          endpoint:   sub.endpoint,
          p256dh:     _abToB64url(sub.getKey('p256dh')),
          auth:       _abToB64url(sub.getKey('auth')),
          student_id: studentId || undefined,
        }),
      });
      await fetch(`${WORKER}/push-preferences`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          endpoint: sub.endpoint,
          preferences: notificationPreferences(),
        }),
      }).catch(() => {});
      document.getElementById('notif-dropdown')?.remove();
      _toast('Push notifications enabled!');
    } catch (e) {
      _toast('Could not enable notifications.');
      console.error(e);
    }
  };

  /* ── Push Unsubscribe ── */
  window._notifUnsubscribe = async function () {
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (sub) {
        await fetch(`${WORKER}/push-subscribe`, {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ endpoint: sub.endpoint }),
        });
        await sub.unsubscribe();
      }
      document.getElementById('notif-dropdown')?.remove();
      _toast('Push notifications disabled.');
    } catch (e) {
      _toast('Could not disable notifications.');
      console.error(e);
    }
  };

  /* ── Helpers ── */
  function relTime(iso) {
    const s = Math.floor((Date.now() - new Date(iso)) / 1000);
    if (s < 60)    return 'Just now';
    if (s < 3600)  return `${Math.floor(s / 60)} min ago`;
    if (s < 86400) return `${Math.floor(s / 3600)} hr ago`;
    const d = Math.floor(s / 86400);
    return `${d} day${d > 1 ? 's' : ''} ago`;
  }

  function escH(s) {
    return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function _urlB64ToUint8(b64) {
    const raw = atob((b64 + '='.repeat((4 - b64.length % 4) % 4)).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from({ length: raw.length }, (_, i) => raw.charCodeAt(i));
  }

  function _abToB64url(buf) {
    if (!buf) return '';
    let str = '';
    new Uint8Array(buf).forEach(b => { str += String.fromCharCode(b); });
    return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  function _toast(msg) {
    const t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);' +
      'background:#6366f1;color:#fff;padding:10px 20px;border-radius:10px;font-size:.82rem;' +
      'font-weight:600;z-index:99999;font-family:Inter,sans-serif;white-space:nowrap;';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 3000);
  }
})();
