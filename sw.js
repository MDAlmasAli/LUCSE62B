const CACHE     = 'lu62b-v63';
const _SW_SUPA  = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const _SW_ANON  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

const STATIC_IMAGES = [
  '/assets/images/hero.jpg',
  '/assets/images/lu-logo.png',
  '/assets/images/favicon-photo.png',
  '/assets/images/icon-192.png',
  '/assets/images/icon-512.png',
];

// Install — pre-cache only images (they rarely change)
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC_IMAGES).catch(() => {}))
  );
});

// The pages and assets worth having before they are ever opened, so the first
// time someone loses signal they can still reach the routine or their
// classwork instead of a blank page. Warmed in the background on activate
// (once per deploy), and every one is optional — a miss must never stop the
// service worker taking over.
const CORE = [
  '/',
  '/index.html',
  '/assets/css/style.css',
  '/assets/js/theme.js',
  '/assets/js/sheets.js',
  '/assets/js/script.js',
  '/assets/js/auth.js',
  '/assets/js/analytics.js',
  '/assets/js/event-poster.js',
  '/assets/js/portal-status.js',
  '/assets/js/notifications.js',
  '/assets/js/exam-countdown.js',
  '/pages/info.html',
  '/pages/classwork.html',
  '/pages/attendance.html',
  '/pages/notice.html',
  '/pages/resources.html',
  '/pages/category.html',
  '/pages/students.html',
  '/pages/cover-page.html',
  '/pages/user-guide.html',
  '/pages/profile.html',
  '/pages/info/routine.js',
  '/pages/info/exam.js',
  '/pages/info/semester.js',
  '/pages/info/all-course.js',
  '/pages/info/teachers.js',
  '/pages/info/course-teachers.js',
  '/pages/info/bus.js',
  '/pages/info/bkash.js',
  '/pages/info/group-links.js',
  '/pages/info/retake-improve.js',
  '/pages/info/retake-routine.js',
  '/pages/info/teacher-routine.js',
];

function warmCache() {
  return caches.open(CACHE).then(c =>
    Promise.all(CORE.map(url =>
      fetch(url, { cache: 'no-store' })
        .then(res => (res && res.status === 200) ? c.put(url, res) : null)
        .catch(() => {})
    ))
  );
}

// Activate — clear old caches, then warm the core pages in the background
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
     .then(() => warmCache())
  );
});

/* Store student_id sent from page via postMessage */
let _swStudentId = null;
self.addEventListener('message', e => {
  if (e.data?.type === 'SET_STUDENT_ID') _swStudentId = e.data.studentId || null;
});

/* Push notification received */
self.addEventListener('push', e => {
  const sid = _swStudentId;
  let url = `${_SW_SUPA}/rest/v1/notifications?order=created_at.desc&limit=1`;
  if (sid) url += `&or=(student_id.is.null,student_id.eq.${encodeURIComponent(sid)})`;
  else     url += '&student_id=is.null';

  e.waitUntil(
    fetch(url, { headers: { 'apikey': _SW_ANON, 'Authorization': `Bearer ${_SW_ANON}` } })
    .then(r => r.json())
    .then(([n]) => {
      if (!n) return;
      return self.registration.showNotification(n.title, {
        body: n.body,
        icon: '/assets/images/icon-192.png',
        tag: n.id,
        data: { link: n.link || '/' },
      });
    })
    .catch(() => self.registration.showNotification('CSE 62B Portal', {
      body: 'New update available. Tap to view.',
      icon: '/assets/images/icon-192.png',
    }))
  );
});

// Notification click → open/focus relevant page
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const link = e.notification.data?.link || '/';
  const url  = new URL(link, self.location.origin).href;
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
      for (const c of cs) {
        if (c.url === url && 'focus' in c) return c.focus();
      }
      return clients.openWindow(url);
    })
  );
});

/* Exact URL first, then the same path without its query. Warmed copies are
   stored under the plain path while pages ask for e.g. style.css?v=20260718b,
   so the loose match is what makes a never-visited page work offline - but it
   must stay the second choice, or a stale warmed copy would shadow the fresh
   one the last online visit cached. */
function matchCached(request) {
  return caches.match(request).then(
    hit => hit || caches.match(request, { ignoreSearch: true })
  );
}

// Fetch
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Skip non-http(s) requests (chrome-extension://, etc.)
  if (!url.protocol.startsWith('http')) return;

  // Only ever handle the site's OWN (same-origin) files. Everything cross-origin
  // — live video streams, CDNs (hls.js, fonts, cdnjs), Supabase — goes straight
  // to the network, so the SW can never cache/proxy a stream and break playback.
  if (url.origin !== self.location.origin) return;

  const p = url.pathname;

  // Never cache media, even same-origin
  if (/\.(m3u8|ts|m4s|mp4|aac|key|cmfv|cmfa)(\?|$)/i.test(p)) return;

  // HTML, CSS, JS — network-first (always fresh after deploy, cache as offline fallback)
  if (
    e.request.destination === 'document' ||
    p.endsWith('.css') ||
    p.endsWith('.js')
  ) {
    e.respondWith(
      // Bypass the browser HTTP cache so deploys show up immediately (no hard-refresh)
      fetch(e.request, { cache: 'no-store' }).then(res => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      }).catch(() =>
        matchCached(e.request).then(c => c || (
          e.request.destination === 'document' ? caches.match('/index.html') : null
        ))
      )
    );
    return;
  }

  // Images — cache-first (they don't change often)
  e.respondWith(
    matchCached(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        if (!res || res.status !== 200 || res.type === 'opaque') return res;
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return res;
      }).catch(() => null);
    })
  );
});
