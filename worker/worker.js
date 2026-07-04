

const SUPA_URL = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const ADMIN_STUDENT_ID = '0182320012101068';

const ALLOWED_ORIGINS = [
  'https://lucse62b.xyz',
  'https://www.lucse62b.xyz',
  'http://127.0.0.1:5500',
  'http://localhost:5500',
];

export default {
  async fetch(request, env, ctx) {
    const url    = new URL(request.url);
    const origin = request.headers.get('Origin') || '';
    /* Any localhost port is allowed for the CORS header so local dev (Live Server,
       python -m http.server, etc.) can call the worker. This only affects which
       Origin is echoed back — the sensitive endpoints below still gate on
       ALLOWED_ORIGINS.includes(origin), so this doesn't loosen their access. */
    const isLocalOrigin = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
    const cors   = {
      'Access-Control-Allow-Origin':  (ALLOWED_ORIGINS.includes(origin) || isLocalOrigin) ? origin : ALLOWED_ORIGINS[0],
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Range, Authorization',
      'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges, Content-Type',
      'Access-Control-Max-Age':       '86400',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    try {
      const p = url.pathname;

      // ── GET /lookup?id=STUDENT_ID — single student lookup, never exposes full sheet ──
      if (p === '/lookup') {
        // Only allow requests originating from the portal (blocks direct URL access & external scraping)
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');

        const sid = url.searchParams.get('id');
        if (!sid) return errResp(cors, 400, 'Missing id');
        if (!/^\d{8,16}$/.test(sid)) return errResp(cors, 400, 'Invalid ID');

        // Rate limit: max 10 lookups per hour per IP
        if (env.SMS_RATE) {
          const ip  = request.headers.get('CF-Connecting-IP') || 'unknown';
          const now = Date.now();
          const key = `lookup:h:${ip}:${Math.floor(now / 3600000)}`;
          const raw = await env.SMS_RATE.get(key);
          const cnt = parseInt(raw || '0');
          if (cnt >= 10) return errResp(cors, 429, 'Too many lookups — try again later');
          await env.SMS_RATE.put(key, String(cnt + 1), { expirationTtl: 3600 });
        }

        const id = env.MAIN_SHEET_ID;
        if (!id) return errResp(cors, 500, 'Not configured');
        const tq = `select * where B='${sid}'`;
        const u  = `https://docs.google.com/spreadsheets/d/${id}/gviz/tq?tqx=out:json&sheet=Student%20Info&tq=${encodeURIComponent(tq)}`;
        const r  = await fetch(u);
        const text = await r.text();
        const m = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
        if (!m) return errResp(cors, 502, 'Bad upstream');
        const parsed = JSON.parse(m[1]);
        const rows   = parsed.table?.rows || [];
        if (!rows.length) return jsonResp(cors, { found: false });
        const cells  = (rows[0].c || []).map(c => (c && c.v !== null && c.v !== undefined) ? String(c.f || c.v).trim() : '');
        return jsonResp(cors, { found: true, id: cells[1] || sid, name: cells[2] || 'Student' });
      }

      // Main Sheet is the authoritative access list. The minute cron refreshes
      // this roster in KV, so clients can revalidate without hammering Sheets.
      if (p === '/session-status') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const sid = String(url.searchParams.get('id') || '').trim();
        if (!/^\d{8,16}$/.test(sid)) return errResp(cors, 400, 'Invalid ID');
        const roster = await getActiveStudentRoster(env);
        if (!roster) return errResp(cors, 503, 'Roster temporarily unavailable');
        return jsonResp(cors, {
          active: roster.ids.includes(sid),
          checked_at: new Date(roster.checkedAt).toISOString(),
        });
      }

      // ── GET /sheet?name=TabName ───────────────────────────────────────
      if (p === '/sheet') {
        const name = url.searchParams.get('name');
        if (!name) return errResp(cors, 400, 'Missing name');
        const id = env.MAIN_SHEET_ID;
        if (!id)   return errResp(cors, 500, 'Not configured');
        // Strip phone column (index 3) from Student Info to prevent exposure
        if (name === 'Student Info') return await gvizProxyStrip(id, name, [3], cors, env);
        return await gvizProxy(id, name, cors, env);
      }

      // ── GET /fetch?id=SHEET_ID[&sheet=Tab] ───────────────────────────
      if (p === '/fetch') {
        const id  = url.searchParams.get('id');
        const tab = url.searchParams.get('sheet') || '';
        // raw=1 → ask GVIZ not to auto-detect header rows (&headers=0). Multi-header
        // exam-routine sheets (a Day/Date/Time/Weekday block stacked per batch) get
        // their FIRST block folded into column labels otherwise, hiding that batch
        // entirely (e.g. Batch 61 vanished while 62 still parsed).
        const raw = url.searchParams.get('raw') === '1';
        if (!id) return errResp(cors, 400, 'Missing id');
        if (!/^[A-Za-z0-9_-]{20,60}$/.test(id)) return errResp(cors, 400, 'Invalid sheet ID');
        return await gvizProxy(id, tab, cors, env, raw);
      }

      // FIFA26-START — temporary World Cup 2026 endpoints, delete this whole block after the tournament
      // ── GET /fifa?dates=YYYYMMDD[-YYYYMMDD] — scores · /fifa?event=ID — match detail (ESPN proxy) ──
      if (p === '/fifa') {
        // /fifa?standings=1 → group tables
        if (url.searchParams.get('standings')) {
          const stu = 'https://site.api.espn.com/apis/v2/sports/soccer/fifa.world/standings?season=2026';
          const str = await fetch(stu, { cf: { cacheTtl: 300, cacheEverything: true } });
          if (!str.ok) return errResp(cors, 502, 'Upstream error');
          const std = await str.json();
          const groups = (std.children || []).map(g => ({
            name: g.name || '',
            teams: ((g.standings || {}).entries || []).map(e => {
              const stat = n => {
                const s = (e.stats || []).find(x => x.name === n);
                return s ? s.displayValue : '0';
              };
              return {
                abbr: e.team?.abbreviation || '',
                name: e.team?.displayName || '',
                logo: (e.team?.logos || [])[0]?.href || '',
                p: stat('gamesPlayed'), w: stat('wins'), d: stat('ties'), l: stat('losses'),
                gd: stat('pointDifferential'), pts: stat('points'), rank: parseInt(stat('rank')) || 0,
              };
            }).sort((a, b) => a.rank - b.rank),
          }));
          return new Response(JSON.stringify({ groups }), {
            headers: { ...cors, 'Content-Type': 'application/json',
                       'Cache-Control': 'public, max-age=300' },
          });
        }
        const evId = url.searchParams.get('event') || '';
        if (evId) {
          if (!/^\d{1,12}$/.test(evId)) return errResp(cors, 400, 'Invalid event');
          const su = 'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event=' + evId;
          const sr = await fetch(su, { cf: { cacheTtl: 30, cacheEverything: true } });
          if (!sr.ok) return errResp(cors, 502, 'Upstream error');
          const sd   = await sr.json();
          const KEEP = ['goal', 'own-goal', 'penalty---scored', 'penalty---missed', 'yellow-card', 'red-card', 'substitution'];
          const events = (sd.keyEvents || [])
            .filter(e => KEEP.includes(e.type?.type))
            .map(e => ({
              type: e.type?.type || '',
              t:    e.clock?.displayValue || '',
              text: e.shortText || (e.text || '').slice(0, 140),
            }));
          const STATS = ['possessionPct', 'totalShots', 'shotsOnTarget', 'wonCorners', 'foulsCommitted', 'yellowCards', 'saves'];
          const stats = (sd.boxscore?.teams || []).map(t => {
            const o = { abbr: t.team?.abbreviation || '', home: t.homeAway === 'home' };
            (t.statistics || []).forEach(s => { if (STATS.includes(s.name)) o[s.name] = s.displayValue; });
            return o;
          });
          return new Response(JSON.stringify({ events, stats }), {
            headers: { ...cors, 'Content-Type': 'application/json',
                       'Cache-Control': 'public, max-age=30' },
          });
        }
        const dates = url.searchParams.get('dates') || '';
        if (dates && !/^\d{8}(-\d{8})?$/.test(dates)) return errResp(cors, 400, 'Invalid dates');
        const u = 'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard'
                + (dates ? '?dates=' + dates : '');
        const r = await fetch(u, { cf: { cacheTtl: 60, cacheEverything: true } });
        if (!r.ok) return errResp(cors, 502, 'Upstream error');
        const data = await r.json();
        const matches = (data.events || []).map(ev => {
          const c  = (ev.competitions || [])[0] || {};
          const st = ev.status || {};
          return {
            id:        ev.id,
            date:      ev.date,
            round:     ev.season?.slug || '',
            state:     st.type?.state || 'pre',          // pre | in | post
            completed: !!st.type?.completed,
            clock:     st.displayClock || '',
            detail:    st.type?.shortDetail || '',
            venue:     c.venue?.fullName || '',
            city:      c.venue?.address?.city || '',
            teams: (c.competitors || []).map(t => ({
              abbr:   t.team?.abbreviation || '',
              name:   t.team?.shortDisplayName || t.team?.displayName || '',
              logo:   t.team?.logo || '',
              score:  t.score != null ? String(t.score) : '',
              home:   t.homeAway === 'home',
              winner: !!t.winner,
            })).sort((a, b) => (b.home ? 1 : 0) - (a.home ? 1 : 0)),
          };
        });
        return new Response(JSON.stringify({ matches }), {
          headers: { ...cors, 'Content-Type': 'application/json',
                     'Cache-Control': 'public, max-age=60' },
        });
      }
      // FIFA26-END

      // ── GET /hidden-cols?id=SHEET_ID — hidden column indices per tab ──
      // GVIZ doesn't expose hidden columns, so we read columnMetadata via the
      // Sheets API. Lets the site mirror columns the user hid in the sheet.
      if (p === '/hidden-cols') {
        const id = url.searchParams.get('id');
        if (!id) return errResp(cors, 400, 'Missing id');
        if (!/^[A-Za-z0-9_-]{20,60}$/.test(id)) return errResp(cors, 400, 'Invalid sheet ID');
        return jsonResp(cors, await fetchHiddenColumns(id, env));
      }

      // ── POST /sms  { phone, message } ────────────────────────────────
      if (p === '/sms' && request.method === 'POST') {
        const { phone, message } = await request.json();
        if (!phone || !message) return errResp(cors, 400, 'Missing phone or message');
        /* Only allow Bangladeshi mobile numbers and short OTP messages */
        if (!/^01[3-9]\d{8}$/.test(String(phone).trim()))
          return errResp(cors, 400, 'Invalid phone number');
        if (String(message).length > 160)
          return errResp(cors, 400, 'Message too long');

        // Rate limiting via KV: max 5/hour and 20/day per IP
        if (env.SMS_RATE) {
          const ip  = request.headers.get('CF-Connecting-IP') || 'unknown';
          const now = Date.now();
          const hKey = `sms:h:${ip}:${Math.floor(now / 3600000)}`;
          const dKey = `sms:d:${ip}:${Math.floor(now / 86400000)}`;
          const [hRaw, dRaw] = await Promise.all([env.SMS_RATE.get(hKey), env.SMS_RATE.get(dKey)]);
          const hCount = parseInt(hRaw || '0');
          const dCount = parseInt(dRaw || '0');
          if (hCount >= 5 || dCount >= 20) return errResp(cors, 429, 'Rate limit exceeded');
          await Promise.all([
            env.SMS_RATE.put(hKey, String(hCount + 1), { expirationTtl: 3600 }),
            env.SMS_RATE.put(dKey, String(dCount + 1), { expirationTtl: 86400 }),
          ]);
        }

        const smsUrl =
          `https://bulksmsbd.net/api/smsapi?api_key=${env.SMS_API_KEY}` +
          `&type=text&number=${encodeURIComponent(phone)}` +
          `&senderid=${encodeURIComponent(env.SMS_SENDER_ID)}` +
          `&message=${encodeURIComponent(message)}`;
        await fetch(smsUrl);
        return jsonResp(cors, { ok: true });
      }

      // ── POST /send-otp  { student_id } — looks up phone internally, sends SMS OTP ──
      if (p === '/send-otp' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id } = await request.json();
        if (!student_id) return errResp(cors, 400, 'Missing student_id');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');

        // Rate limit: max 5/day per IP
        if (env.SMS_RATE) {
          const ip   = request.headers.get('CF-Connecting-IP') || 'unknown';
          const dKey = `otp:d:${ip}:${Math.floor(Date.now() / 86400000)}`;
          const dRaw = await env.SMS_RATE.get(dKey);
          const dCnt = parseInt(dRaw || '0');
          if (dCnt >= 5) return errResp(cors, 429, 'Daily OTP limit reached');
          await env.SMS_RATE.put(dKey, String(dCnt + 1), { expirationTtl: 86400 });
        }

        // Look up phone from sheet
        const sid2 = String(student_id);
        const sheetId = env.MAIN_SHEET_ID;
        if (!sheetId) return errResp(cors, 500, 'Not configured');
        const tq2 = `select * where B='${sid2}'`;
        const u2  = `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq?tqx=out:json&sheet=Student%20Info&tq=${encodeURIComponent(tq2)}`;
        const r2  = await fetch(u2);
        const t2  = await r2.text();
        const m2  = t2.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
        if (!m2) return errResp(cors, 502, 'Bad upstream');
        const parsed2 = JSON.parse(m2[1]);
        const rows2   = parsed2.table?.rows || [];
        if (!rows2.length) return errResp(cors, 404, 'Student not found');
        const cells2 = (rows2[0].c || []).map(c => (c && c.v !== null && c.v !== undefined) ? String(c.f || c.v).trim() : '');
        let phone2 = (cells2[3] || '').replace(/\s+/g, '');
        if (phone2.length === 10 && phone2.startsWith('1')) phone2 = '0' + phone2;
        if (phone2.startsWith('+88')) phone2 = phone2.substring(3);
        else if (phone2.startsWith('88') && phone2.length === 13) phone2 = phone2.substring(2);
        if (!/^01[3-9]\d{8}$/.test(phone2)) return errResp(cors, 400, 'No valid phone for this student');

        // Generate OTP and store in KV (5-minute TTL)
        const arr = new Uint32Array(1);
        crypto.getRandomValues(arr);
        const otp = String(arr[0] % 1000000).padStart(6, '0');
        if (env.SMS_RATE) {
          await env.SMS_RATE.put(`otp:${sid2}`, otp, { expirationTtl: 300 });
        }

        // Send SMS
        const smsUrl2 =
          `https://bulksmsbd.net/api/smsapi?api_key=${env.SMS_API_KEY}` +
          `&type=text&number=${encodeURIComponent(phone2)}` +
          `&senderid=${encodeURIComponent(env.SMS_SENDER_ID)}` +
          `&message=${encodeURIComponent(`Your CSE 62B PORTAL OTP is ${otp}`)}`;
        await fetch(smsUrl2);

        const masked = phone2.substring(0, 5) + '***' + phone2.slice(-3);
        return jsonResp(cors, { ok: true, masked });
      }

      // ── POST /verify-otp  { student_id, otp } — server-side OTP check ──
      if (p === '/verify-otp' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id, otp } = await request.json();
        if (!student_id || !otp) return errResp(cors, 400, 'Missing fields');
        if (!env.SMS_RATE) return errResp(cors, 500, 'Not configured');
        const stored = await env.SMS_RATE.get(`otp:${String(student_id)}`);
        if (!stored || stored !== String(otp).trim()) return jsonResp(cors, { valid: false });
        await env.SMS_RATE.delete(`otp:${String(student_id)}`);
        // Issue a short-lived password-set token so a later /set-password write can
        // be authorised server-side (the public anon key can no longer write the hash).
        const pst = crypto.randomUUID();
        await env.SMS_RATE.put(`pwtok:${String(student_id)}`, pst, { expirationTtl: 600 });
        return jsonResp(cors, { valid: true, pst });
      }

      // ── POST /set-password { student_id, pst, password, name? } ──────────────
      // The only path that writes password_hash. `pst` proves a fresh OTP was just
      // verified; the hash is computed inside Postgres (set_student_password RPC,
      // service_role). Direct anon writes to student_passwords are revoked.
      if (p === '/set-password' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id, pst, password, name } = await request.json();
        if (!student_id || !pst || !password) return errResp(cors, 400, 'Missing fields');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (String(password).length < 6) return errResp(cors, 400, 'Password too short');
        if (!env.SMS_RATE || !env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const tok = await env.SMS_RATE.get(`pwtok:${String(student_id)}`);
        if (!tok || tok !== String(pst)) return errResp(cors, 401, 'Verification expired — please request a new OTP');
        await env.SMS_RATE.delete(`pwtok:${String(student_id)}`);
        const r = await fetch(`${SUPA_URL}/rest/v1/rpc/set_student_password`, {
          method: 'POST',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: String(student_id), p_password: String(password), p_name: (name ? String(name) : null) }),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 503, 'Supabase unavailable');
        return jsonResp(cors, { ok: true });
      }

      // ── POST /my-phone  { student_id, birth_date } — returns verified student's own phone ──
      if (p === '/my-phone' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id, birth_date } = await request.json();
        if (!student_id || !birth_date) return errResp(cors, 400, 'Missing fields');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(birth_date))) return errResp(cors, 400, 'Invalid date');

        // Rate limit: max 10/hour per IP
        if (env.SMS_RATE) {
          const ip  = request.headers.get('CF-Connecting-IP') || 'unknown';
          const key = `phone:h:${ip}:${Math.floor(Date.now() / 3600000)}`;
          const raw = await env.SMS_RATE.get(key);
          const cnt = parseInt(raw || '0');
          if (cnt >= 10) return errResp(cors, 429, 'Too many requests');
          await env.SMS_RATE.put(key, String(cnt + 1), { expirationTtl: 3600 });
        }

        // Fetch phone from sheet
        const sid3 = String(student_id);
        const shId = env.MAIN_SHEET_ID;
        if (!shId) return errResp(cors, 500, 'Not configured');
        const tq3 = `select * where B='${sid3}'`;
        const u3  = `https://docs.google.com/spreadsheets/d/${shId}/gviz/tq?tqx=out:json&sheet=Student%20Info&tq=${encodeURIComponent(tq3)}`;
        const r3  = await fetch(u3);
        const t3  = await r3.text();
        const m3  = t3.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
        if (!m3) return errResp(cors, 502, 'Bad upstream');
        const d3 = JSON.parse(m3[1]);
        const rows3 = d3.table?.rows || [];
        if (!rows3.length) return errResp(cors, 404, 'Student not found');
        const cells3 = (rows3[0].c || []).map(c => (c && c.v !== null && c.v !== undefined) ? String(c.f || c.v).trim() : '');
        let phone3 = (cells3[3] || '').replace(/\s+/g, '');
        if (phone3.length === 10 && phone3.startsWith('1')) phone3 = '0' + phone3;
        if (phone3.startsWith('+88')) phone3 = phone3.substring(3);
        else if (phone3.startsWith('88') && phone3.length === 13) phone3 = phone3.substring(2);
        if (!/^01[3-9]\d{8}$/.test(phone3)) return errResp(cors, 400, 'No phone on record');

        // Verify DOB via Supabase (key is a Worker secret, never in client code)
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const dobR = await fetch(`${SUPA_URL}/rest/v1/rpc/get_student_dob`, {
          method: 'POST',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: sid3 }),
        }).catch(() => null);
        if (!dobR || !dobR.ok) return errResp(cors, 503, 'Verification unavailable');
        const storedDob = await dobR.json();
        if (!storedDob || storedDob !== String(birth_date)) return errResp(cors, 401, 'DOB mismatch');

        return jsonResp(cors, { phone: phone3 });
      }

      // ── GET /student-phones — { id: phone } map for the class directory ──
      // The public /sheet endpoint strips the phone column; this dedicated route
      // returns the numbers so the (auth-gated) student directory can show a
      // WhatsApp button per student. Gated to the portal Origin like /my-phone.
      if (p === '/student-phones') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const shIdP = env.MAIN_SHEET_ID;
        if (!shIdP) return errResp(cors, 500, 'Not configured');

        // Rate limit: max 30/hour per IP (a directory refresh is occasional).
        if (env.SMS_RATE) {
          const ip  = request.headers.get('CF-Connecting-IP') || 'unknown';
          const key = `phones:h:${ip}:${Math.floor(Date.now() / 3600000)}`;
          const cnt = parseInt(await env.SMS_RATE.get(key) || '0');
          if (cnt >= 30) return errResp(cors, 429, 'Too many requests');
          await env.SMS_RATE.put(key, String(cnt + 1), { expirationTtl: 3600 });
        }

        const uP = `https://docs.google.com/spreadsheets/d/${shIdP}/gviz/tq?tqx=out:json&sheet=Student%20Info`;
        const rP = await fetch(uP);
        const tP = await rP.text();
        const mP = tP.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
        if (!mP) return errResp(cors, 502, 'Bad upstream');
        const rowsP = JSON.parse(mP[1]).table?.rows || [];
        const phones = {};
        for (const row of rowsP) {
          const cells = (row.c || []).map(c => (c && c.v !== null && c.v !== undefined) ? String(c.f || c.v).trim() : '');
          const id = (cells[1] || '').replace(/\s+/g, '');
          if (!/^\d{8,16}$/.test(id)) continue;          // skip title/header rows
          let ph = (cells[3] || '').replace(/\s+/g, '');
          if (ph.length === 10 && ph.startsWith('1')) ph = '0' + ph;
          if (ph.startsWith('+88')) ph = ph.substring(3);
          else if (ph.startsWith('88') && ph.length === 13) ph = ph.substring(2);
          if (!/^01[3-9]\d{8}$/.test(ph)) continue;       // skip rows without a valid BD number
          phones[id] = ph;
        }
        return jsonResp(cors, { phones });
      }

      // ── POST /result  { student_id, birth_date } ─────────────────────
      if (p === '/result' && request.method === 'POST') {
        const { student_id, birth_date } = await request.json();
        if (!student_id || !birth_date) return errResp(cors, 400, 'Missing student_id or birth_date');
        // Prefer a user-imported result — LU's live endpoint now requires a CAPTCHA,
        // so the uploaded copy is the source of truth (DOB-gated, same as live).
        const imported = await getImportedResult(env, student_id, birth_date);
        if (imported) return new Response(imported, { headers: { ...cors, 'Content-Type': 'text/plain; charset=utf-8' } });
        const text = await luResultCached(env, student_id, birth_date);
        if (text.trimStart().startsWith('<')) return errResp(cors, 503, 'LUS temporarily unavailable');
        return new Response(text, { headers: { ...cors, 'Content-Type': 'text/plain; charset=utf-8' } });
      }

      // ── POST /result-import { student_id, birth_date, data } ─────────────
      //   Stores a result the student fetched from LU themselves (after solving
      //   LU's Cloudflare verification) and parsed in the browser. DOB-gated so
      //   nobody can plant a result under someone else's ID.
      if (p === '/result-import' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id, birth_date, data } = await request.json();
        if (!student_id || !birth_date || !data || typeof data !== 'object') return errResp(cors, 400, 'Missing fields');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(birth_date))) return errResp(cors, 400, 'Invalid date');
        if (!data.success || !data.student || String(data.student.id || '') !== String(student_id))
          return errResp(cors, 400, 'Uploaded result does not match this Student ID');
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const storedDob = await getStoredDob(env, student_id);
        if (storedDob && storedDob !== String(birth_date)) return errResp(cors, 401, 'DOB does not match our records');
        if (!storedDob) {
          await fetch(`${SUPA_URL}/rest/v1/rpc/set_student_dob`, {
            method: 'POST',
            headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ p_student_id: String(student_id), p_dob: String(birth_date) }),
          }).catch(() => {});
        }
        const stored = { ...data, imported: true, imported_at: new Date().toISOString() };
        const r = await fetch(`${SUPA_URL}/rest/v1/student_results`, {
          method: 'POST',
          headers: {
            'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
            'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: JSON.stringify({ student_id: String(student_id), data: stored, uploaded_at: stored.imported_at }),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 503, 'Save failed');
        return jsonResp(cors, { ok: true, imported_at: stored.imported_at });
      }

      // ── GET /gallery?folder=FOLDER_ID[&limit=N] — images from folder or subfolders ──
      //   Each returned image is { id, folder } where `folder` is the name of the
      //   subfolder (event/album) it came from — lets callers caption by event.
      //   Back-compatible: existing callers only read `id`.
      if (p === '/gallery') {
        const folder = url.searchParams.get('folder');
        if (!folder) return errResp(cors, 400, 'Missing folder');
        const limit = Math.min(parseInt(url.searchParams.get('limit') || '8'), 60);
        if (!env.DRIVE_API_KEY) return errResp(cors, 500, 'Not configured');
        const driveHeaders = { 'Referer': 'https://lucse62b.xyz/' };
        // First try direct images in the folder
        const directRes = await fetch(
          `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(`'${folder}' in parents and mimeType contains 'image/' and trashed=false`)}&pageSize=${limit}&fields=files(id)&key=${env.DRIVE_API_KEY}`,
          { headers: driveHeaders }
        );
        const directFiles = (await directRes.json()).files || [];
        if (directFiles.length > 0) return jsonResp(cors, { files: directFiles.map(im => ({ id: im.id, folder: '' })) });
        // Fall back to images inside subfolders (tag each image with its folder name)
        const fRes = await fetch(
          `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(`'${folder}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`)}&fields=files(id,name)&key=${env.DRIVE_API_KEY}`,
          { headers: driveHeaders }
        );
        const subfolders = (await fRes.json()).files || [];
        const batches = await Promise.all(subfolders.map(f =>
          fetch(`https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(`'${f.id}' in parents and mimeType contains 'image/' and trashed=false`)}&pageSize=${limit}&fields=files(id)&key=${env.DRIVE_API_KEY}`,
            { headers: driveHeaders })
            .then(r => r.json()).then(d => (d.files || []).map(im => ({ id: im.id, folder: f.name }))).catch(() => [])
        ));
        return jsonResp(cors, { files: batches.flat() });
      }

      // ── GET /drive?folder=FOLDER_ID ──────────────────────────────────
      if (p === '/drive') {
        const folder = url.searchParams.get('folder');
        if (!folder) return errResp(cors, 400, 'Missing folder');
        const driveUrl =
          `https://www.googleapis.com/drive/v3/files` +
          `?q=%27${folder}%27+in+parents+and+trashed%3Dfalse` +
          `&orderBy=name&fields=files(id%2Cname%2CmimeType)` +
          `&key=${env.DRIVE_API_KEY}`;
        const referer = request.headers.get('Referer') || 'https://lucse62b.xyz/';
        const r = await fetch(driveUrl, { headers: { 'Referer': referer } });
        const d = await r.json();
        return jsonResp(cors, d);
      }

      // ── POST /dob-sync { student_id, dob } — upsert DOB to Supabase ─────────
      // GET /drive-file?id=FILE_ID&mime=MIME&name=NAME
      // Stream a public Drive resource through the Worker. This gives the web
      // resource manager a CORS-safe byte stream for download controls and its
      // built-in PDF/PPTX viewers.
      if (p === '/drive-file') {
        const id = url.searchParams.get('id') || '';
        const mime = url.searchParams.get('mime') || '';
        const name = (url.searchParams.get('name') || 'download')
          .replace(/[\r\n"\\/]/g, '_').slice(0, 180);
        if (!/^[A-Za-z0-9_-]{10,100}$/.test(id)) {
          return errResp(cors, 400, 'Invalid file ID');
        }

        let upstream;
        if (mime === 'application/vnd.google-apps.document') {
          upstream = `https://docs.google.com/document/d/${id}/export?format=pdf`;
        } else if (mime === 'application/vnd.google-apps.presentation') {
          upstream = `https://docs.google.com/presentation/d/${id}/export/pptx`;
        } else if (mime === 'application/vnd.google-apps.spreadsheet') {
          upstream = `https://docs.google.com/spreadsheets/d/${id}/export?format=xlsx`;
        } else if (mime === 'application/vnd.google-apps.drawing') {
          upstream = `https://docs.google.com/drawings/d/${id}/export/png`;
        } else {
          upstream = `https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t`;
        }

        const upstreamHeaders = {};
        const range = request.headers.get('Range');
        if (range) upstreamHeaders.Range = range;
        const r = await fetch(upstream, {
          headers: upstreamHeaders,
          redirect: 'follow',
        });
        if (!r.ok && r.status !== 206) {
          return errResp(cors, r.status, 'Drive download failed');
        }

        const headers = new Headers(cors);
        for (const key of ['Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges', 'ETag']) {
          const value = r.headers.get(key);
          if (value) headers.set(key, value);
        }
        headers.set('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(name)}`);
        headers.set('Cache-Control', 'private, no-store');
        return new Response(r.body, { status: r.status, headers });
      }

      if (p === '/dob-sync' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id, dob } = await request.json();
        if (!student_id || !dob) return errResp(cors, 400, 'Missing fields');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(dob))) return errResp(cors, 400, 'Invalid date');
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const r = await fetch(`${SUPA_URL}/rest/v1/rpc/set_student_dob`, {
          method: 'POST',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: String(student_id), p_dob: String(dob) }),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 503, 'Supabase unavailable');
        return jsonResp(cors, { ok: true });
      }

      // ── POST /dob-check { student_id } — returns { has_dob: bool } ──────────
      if (p === '/dob-check' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { student_id } = await request.json();
        if (!student_id) return errResp(cors, 400, 'Missing student_id');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const r = await fetch(`${SUPA_URL}/rest/v1/rpc/student_has_dob`, {
          method: 'POST',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: String(student_id) }),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 503, 'Supabase unavailable');
        const hasDob = await r.json();
        return jsonResp(cors, { has_dob: !!hasDob });
      }

      // ── POST /dob-get { student_id } — returns { dob } (rate-limited) ────────
      if (p === '/dob-get' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        if (env.SMS_RATE) {
          const ip  = request.headers.get('CF-Connecting-IP') || 'unknown';
          const key = `dobget:h:${ip}:${Math.floor(Date.now() / 3600000)}`;
          const raw = await env.SMS_RATE.get(key);
          const cnt = parseInt(raw || '0');
          if (cnt >= 10) return errResp(cors, 429, 'Too many requests');
          await env.SMS_RATE.put(key, String(cnt + 1), { expirationTtl: 3600 });
        }
        const { student_id } = await request.json();
        if (!student_id) return errResp(cors, 400, 'Missing student_id');
        if (!/^\d{8,16}$/.test(String(student_id))) return errResp(cors, 400, 'Invalid ID');
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const r = await fetch(`${SUPA_URL}/rest/v1/rpc/get_student_dob`, {
          method: 'POST',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: String(student_id) }),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 503, 'Supabase unavailable');
        const dob = await r.json();
        return jsonResp(cors, { dob: dob || null });
      }

      // Native app logout/revocation: remove this device token server-side.
      if (p === '/fcm-token' && request.method === 'DELETE') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { token } = await request.json().catch(() => ({}));
        if (!token || !env.SUPA_KEY) return errResp(cors, 400, 'Missing fields');
        await fetch(`${SUPA_URL}/rest/v1/fcm_tokens?token=eq.${encodeURIComponent(token)}`, {
          method: 'DELETE',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
        }).catch(() => {});
        return jsonResp(cors, { ok: true });
      }

      // ── POST /push-subscribe { endpoint, p256dh, auth, student_id? } ──
      if (p === '/push-subscribe' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { endpoint, p256dh, auth, student_id } = await request.json();
        if (!endpoint || !p256dh || !auth) return errResp(cors, 400, 'Missing fields');
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const row = { endpoint, p256dh, auth };
        if (student_id) row.student_id = String(student_id);
        const r = await fetch(`${SUPA_URL}/rest/v1/push_subscriptions`, {
          method: 'POST',
          headers: {
            'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
            'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
          },
          body: JSON.stringify(row),
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 500, 'Failed to save subscription');
        return jsonResp(cors, { ok: true });
      }

      // ── DELETE /push-subscribe { endpoint } ──────────────────────────
      if (p === '/push-subscribe' && request.method === 'DELETE') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const { endpoint } = await request.json();
        if (!endpoint || !env.SUPA_KEY) return errResp(cors, 400, 'Missing fields');
        await fetch(`${SUPA_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(endpoint)}`, {
          method: 'DELETE',
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
        }).catch(() => {});
        return jsonResp(cors, { ok: true });
      }

      if (p === '/push-preferences' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        if (!env.SMS_RATE) return errResp(cors, 500, 'Not configured');
        const { endpoint, preferences } = await request.json().catch(() => ({}));
        if (!endpoint || !preferences || typeof preferences !== 'object') {
          return errResp(cors, 400, 'Missing fields');
        }
        const safe = {};
        for (const key of ['notices', 'classwork', 'routine', 'updates', 'general']) {
          safe[key] = preferences[key] !== false;
        }
        const hash = await sha256(String(endpoint));
        await env.SMS_RATE.put(`push-pref:${hash}`, JSON.stringify(safe), {
          expirationTtl: 31536000,
        });
        return jsonResp(cors, { ok: true, preferences: safe });
      }

      // ── GET /notifications ────────────────────────────────────────────
      if (p === '/notifications') {
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');
        const since = url.searchParams.get('since') || '';
        let supaUrl = `${SUPA_URL}/rest/v1/notifications?order=created_at.desc&limit=20`;
        if (since) supaUrl += `&created_at=gt.${encodeURIComponent(since)}`;
        const r = await fetch(supaUrl, {
          headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
        }).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 500, 'Failed to fetch');
        return jsonResp(cors, await r.json());
      }

      // ── GET /notices — latest LU notices (parsed from the WordPress RSS feed, KV-cached) ──
      if (p === '/notices') {
        return jsonResp(cors, await fetchLuNotices(env));
      }

      // ── POST/GET /run-monitor — manually trigger the change monitor ──
      //   Owner-only: caller must present SUPA_KEY (the worker's secret key).
      //   Lets us test routine/exam/result detection without waiting for the
      //   hourly cron. Returns immediately; work continues via waitUntil.
      if (p === '/run-monitor') {
        const token = request.headers.get('x-monitor-key') || url.searchParams.get('token') || '';
        if (!env.SUPA_KEY || token !== env.SUPA_KEY) return errResp(cors, 403, 'Forbidden');
        /* ?batch=N → run only the result check for batch N (lets us seed all
           result baselines now without overloading the subrequest limit).
           Otherwise run the normal hour-split monitor. */
        const batchParam = url.searchParams.get('batch');
        if (url.searchParams.get('fast') === '1') {
          ctx.waitUntil(runFastMonitor(env).catch(() => {}));
        } else if (batchParam !== null) {
          ctx.waitUntil(checkResult(env, { batchIndex: parseInt(batchParam, 10) || 0 }).catch(() => {}));
        } else {
          ctx.waitUntil(runMonitor(env));
        }
        return jsonResp(cors, {
          ok: true,
          triggered: true,
          fast: url.searchParams.get('fast') === '1',
          batch: batchParam,
          at: new Date().toISOString(),
        });
      }

      // Owner-only end-to-end push test. Inserts a visible test notification,
      // wakes every web subscription, and sends the same message to the APK's
      // all_users FCM topic.
      if (p === '/push-test' && request.method === 'POST') {
        const token = request.headers.get('x-monitor-key') || '';
        if (!env.SUPA_KEY || token !== env.SUPA_KEY) {
          return errResp(cors, 403, 'Forbidden');
        }
        const payload = await request.json().catch(() => ({}));
        const title = String(payload.title || '🔔 Push notification test').slice(0, 100);
        const body = String(payload.body || 'CSE 62B notification delivery is working.').slice(0, 500);
        const link = String(payload.link || '/');
        await insertNotification(env, 'push_test', title, body, link);
        const delivery = await sendPushToAll(env);
        return jsonResp(cors, { ok: true, delivery, at: new Date().toISOString() });
      }

      // Owner-only APK publisher. The binary is streamed directly to Supabase
      // Storage; release metadata is inserted only after a successful upload.
      if (p === '/release-apk' && request.method === 'POST') {
        const token = request.headers.get('x-release-key') || '';
        if (!env.RELEASE_PUBLISH_KEY || token !== env.RELEASE_PUBLISH_KEY) {
          return errResp(cors, 403, 'Forbidden');
        }
        if (!env.SUPA_KEY) return errResp(cors, 500, 'Not configured');

        const versionName = String(request.headers.get('x-version-name') || '').trim();
        const versionCode = Number(request.headers.get('x-version-code') || 0);
        if (!/^\d+\.\d+\.\d+$/.test(versionName) ||
            !Number.isInteger(versionCode) || versionCode < 1) {
          return errResp(cors, 400, 'Invalid version');
        }
        const size = Number(request.headers.get('content-length') || 0);
        if (size && size > 50 * 1024 * 1024) return errResp(cors, 413, 'APK too large');

        const parseList = value => {
          try {
            const parsed = JSON.parse(value || '[]');
            return Array.isArray(parsed) ? parsed.map(String).slice(0, 20) : [];
          } catch {
            return [];
          }
        };
        const features = parseList(request.headers.get('x-release-features'));
        const fixes = parseList(request.headers.get('x-release-fixes'));
        const objectName = `lucse62b-${versionName}-arm64.apk`;
        const storageHeaders = {
          'apikey': env.SUPA_KEY,
          'Authorization': `Bearer ${env.SUPA_KEY}`,
        };
        const upload = await fetch(
          `${SUPA_URL}/storage/v1/object/app-releases/${encodeURIComponent(objectName)}`,
          {
            method: 'POST',
            headers: {
              ...storageHeaders,
              'Content-Type': 'application/vnd.android.package-archive',
              'Cache-Control': '3600',
              'x-upsert': 'true',
            },
            body: request.body,
          },
        );
        if (!upload.ok) return errResp(cors, 502, `Storage upload failed (${upload.status})`);

        let minVersionCode = 1;
        const latest = await fetch(
          `${SUPA_URL}/rest/v1/app_updates?select=min_version_code&order=version_code.desc&limit=1`,
          { headers: storageHeaders },
        ).catch(() => null);
        if (latest?.ok) {
          const rows = await latest.json();
          minVersionCode = Number(rows?.[0]?.min_version_code || 1);
        }
        const apkUrl = `${SUPA_URL}/storage/v1/object/public/app-releases/${objectName}`;
        const metadata = await fetch(`${SUPA_URL}/rest/v1/app_updates`, {
          method: 'POST',
          headers: {
            ...storageHeaders,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: JSON.stringify({
            version_name: versionName,
            version_code: versionCode,
            min_version_code: minVersionCode,
            apk_url: apkUrl,
            features,
            fixes,
          }),
        });
        if (!metadata.ok) {
          return errResp(cors, 502, `Release metadata failed (${metadata.status})`);
        }

        // Keep only the newest APK object. Supabase recommends deleting files
        // through the Storage API so object metadata is removed consistently.
        let oldRemoved = 0;
        const listed = await fetch(`${SUPA_URL}/storage/v1/object/list/app-releases`, {
          method: 'POST',
          headers: { ...storageHeaders, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            prefix: '',
            limit: 100,
            offset: 0,
            sortBy: { column: 'name', order: 'asc' },
          }),
        }).catch(() => null);
        if (listed?.ok) {
          const objects = await listed.json();
          const old = objects
            .map(item => String(item?.name || ''))
            .filter(name => name.endsWith('.apk') && name !== objectName);
          if (old.length) {
            const removed = await fetch(`${SUPA_URL}/storage/v1/object/app-releases`, {
              method: 'DELETE',
              headers: { ...storageHeaders, 'Content-Type': 'application/json' },
              body: JSON.stringify({ prefixes: old }),
            }).catch(() => null);
            if (removed?.ok) oldRemoved = old.length;
          }
        }

        return jsonResp(cors, {
          ok: true,
          version_name: versionName,
          version_code: versionCode,
          apk_url: apkUrl,
          old_apks_removed: oldRemoved,
        });
      }

      // ── GET /attendance — today's attendance records ──────────────────
      // Secure admin sign-in. The portal password is verified server-side and
      // exchanged for a short-lived HMAC token; the password is never stored.
      if (p === '/admin/login' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        if (!env.SUPA_KEY || !env.ADMIN_SESSION_SECRET) {
          return errResp(cors, 500, 'Admin control is not configured');
        }
        const { student_id, password } = await request.json().catch(() => ({}));
        if (String(student_id || '') !== ADMIN_STUDENT_ID || !password) {
          return errResp(cors, 403, 'Invalid admin credentials');
        }
        if (env.SMS_RATE) {
          const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
          const key = `admin-login:${ip}:${Math.floor(Date.now() / 900000)}`;
          const attempts = Number(await env.SMS_RATE.get(key) || 0);
          if (attempts >= 8) return errResp(cors, 429, 'Too many attempts');
          await env.SMS_RATE.put(key, String(attempts + 1), { expirationTtl: 900 });
        }
        const verified = await fetch(`${SUPA_URL}/rest/v1/rpc/verify_student_password`, {
          method: 'POST',
          headers: {
            'apikey': env.SUPA_KEY,
            'Authorization': `Bearer ${env.SUPA_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            p_student_id: ADMIN_STUDENT_ID,
            p_password: String(password),
          }),
        }).catch(() => null);
        if (!verified?.ok || await verified.json() !== true) {
          return errResp(cors, 403, 'Invalid admin credentials');
        }
        return jsonResp(cors, {
          ok: true,
          token: await createAdminToken(env),
          expires_in: 3600,
        });
      }

      if (p.startsWith('/admin/')) {
        const authorized = await verifyAdminRequest(request, env);
        if (!authorized) return errResp(cors, 401, 'Admin session expired');

        if (p === '/admin/status' && request.method === 'GET') {
          const roster = await getActiveStudentRoster(env);
          const authHeaders = {
            'apikey': env.SUPA_KEY,
            'Authorization': `Bearer ${env.SUPA_KEY}`,
          };
          const [notifications, webPush, fcm, heartbeat, latest] = await Promise.all([
            supabaseCount(env, 'notifications'),
            supabaseCount(env, 'push_subscriptions'),
            supabaseCount(env, 'fcm_tokens'),
            fetch(`${SUPA_URL}/rest/v1/monitor_state?key=eq.cron_fast_heartbeat&select=last_checked,state_data&limit=1`,
              { headers: authHeaders }).then(r => r.ok ? r.json() : []).catch(() => []),
            fetch(`${SUPA_URL}/rest/v1/app_updates?select=version_name,version_code,created_at&order=version_code.desc&limit=1`,
              { headers: authHeaders }).then(r => r.ok ? r.json() : []).catch(() => []),
          ]);
          return jsonResp(cors, {
            ok: true,
            students: roster?.ids?.length || 0,
            notifications,
            web_push_subscriptions: webPush,
            fcm_tokens: fcm,
            heartbeat: heartbeat[0] || null,
            latest_app: latest[0] || null,
            main_sheet_url: env.MAIN_SHEET_ID
              ? `https://docs.google.com/spreadsheets/d/${env.MAIN_SHEET_ID}/edit`
              : '',
          });
        }

        if (p === '/admin/notifications' && request.method === 'GET') {
          const r = await fetch(
            `${SUPA_URL}/rest/v1/notifications?student_id=is.null&select=id,type,title,body,link,created_at&order=created_at.desc&limit=20`,
            { headers: {
              'apikey': env.SUPA_KEY,
              'Authorization': `Bearer ${env.SUPA_KEY}`,
            } },
          );
          if (!r.ok) return errResp(cors, 502, 'Could not load notifications');
          return jsonResp(cors, { items: await r.json() });
        }

        if (p === '/admin/announcement' && request.method === 'POST') {
          const body = await request.json().catch(() => ({}));
          const category = ['notice', 'classwork', 'routine', 'app_update', 'general']
            .includes(body.category) ? body.category : 'general';
          const title = String(body.title || '').trim().slice(0, 100);
          const message = String(body.body || '').trim().slice(0, 500);
          const link = String(body.link || '/').trim().slice(0, 300);
          if (!title || !message) return errResp(cors, 400, 'Title and message are required');
          await insertNotification(env, `admin_${category}`, title, message, link);
          const delivery = await sendPushToAll(env);
          return jsonResp(cors, { ok: true, delivery });
        }

        const notificationDelete = p.match(/^\/admin\/notifications\/([0-9a-f-]+)$/i);
        if (notificationDelete && request.method === 'DELETE') {
          const r = await fetch(
            `${SUPA_URL}/rest/v1/notifications?id=eq.${encodeURIComponent(notificationDelete[1])}&student_id=is.null`,
            {
              method: 'DELETE',
              headers: {
                'apikey': env.SUPA_KEY,
                'Authorization': `Bearer ${env.SUPA_KEY}`,
              },
            },
          );
          if (!r.ok) return errResp(cors, 502, 'Delete failed');
          return jsonResp(cors, { ok: true });
        }

        if (p === '/admin/run-monitor' && request.method === 'POST') {
          ctx.waitUntil(runFastMonitor(env).catch(() => {}));
          return jsonResp(cors, { ok: true, triggered: true });
        }

        return errResp(cors, 404, 'Admin action not found');
      }

      if (p === '/attendance' && request.method === 'GET') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const today = new Date().toISOString().slice(0, 10);
        const r = await fetch(
          `${SUPA_URL}/rest/v1/attendance_records?session_date=eq.${today}&select=student_id,student_name,marked_at&order=marked_at.asc`,
          { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
        ).catch(() => null);
        if (!r || !r.ok) return errResp(cors, 502, 'Database error');
        const rows = await r.json();
        return jsonResp(cors, { date: today, records: rows });
      }

      // ── POST /attendance — mark / unmark / clear ──────────────────────
      if (p === '/attendance' && request.method === 'POST') {
        if (!ALLOWED_ORIGINS.includes(origin)) return errResp(cors, 403, 'Forbidden');
        const ATTENDANCE_ADMIN = '0182320012101068';
        const body = await request.json().catch(() => null);
        if (!body || !body.action) return errResp(cors, 400, 'Missing action');
        const today = new Date().toISOString().slice(0, 10);

        if (body.action === 'mark') {
          const { student_id, student_name, admin_id } = body;
          if (admin_id !== ATTENDANCE_ADMIN) return errResp(cors, 403, 'Forbidden');
          if (!student_id || !student_name) return errResp(cors, 400, 'Missing fields');
          const r = await fetch(`${SUPA_URL}/rest/v1/attendance_records`, {
            method: 'POST',
            headers: {
              'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
              'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
            },
            body: JSON.stringify({ session_date: today, student_id, student_name }),
          }).catch(() => null);
          if (!r || !r.ok) return errResp(cors, 502, 'Database error');
          return jsonResp(cors, { ok: true });
        }

        if (body.action === 'unmark') {
          const { student_id, admin_id } = body;
          if (admin_id !== ATTENDANCE_ADMIN) return errResp(cors, 403, 'Forbidden');
          if (!student_id) return errResp(cors, 400, 'Missing student_id');
          const r = await fetch(
            `${SUPA_URL}/rest/v1/attendance_records?session_date=eq.${today}&student_id=eq.${encodeURIComponent(student_id)}`,
            { method: 'DELETE', headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
          ).catch(() => null);
          if (!r || !r.ok) return errResp(cors, 502, 'Database error');
          return jsonResp(cors, { ok: true });
        }

        if (body.action === 'clear') {
          const { admin_id } = body;
          if (admin_id !== ATTENDANCE_ADMIN) return errResp(cors, 403, 'Forbidden');
          const r = await fetch(
            `${SUPA_URL}/rest/v1/attendance_records?session_date=eq.${today}`,
            { method: 'DELETE', headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
          ).catch(() => null);
          if (!r || !r.ok) return errResp(cors, 502, 'Database error');
          return jsonResp(cors, { ok: true });
        }

        return errResp(cors, 400, 'Unknown action');
      }

      return new Response('Not found', { status: 404, headers: cors });

    } catch (e) {
      return errResp(cors, 500, 'Internal error');
    }
  },

  async scheduled(event, env, ctx) {
    if (event.cron === '* * * * *') {
      ctx.waitUntil(runFastMonitor(env));
    } else {
      ctx.waitUntil(runMonitor(env));
    }
  },
};

/* ── Sheets API v4 helper — real-time, no Google-side caching ─────────────
   Tries v4 first (instant updates). Falls back to GVIZ if v4 fails or the
   API key doesn't have Sheets API enabled.
   ─────────────────────────────────────────────────────────────────────────── */
function bytesToBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function textToBase64Url(text) {
  return bytesToBase64Url(new TextEncoder().encode(text));
}

async function adminHmacKey(env) {
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(env.ADMIN_SESSION_SECRET || ''),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

async function createAdminToken(env) {
  const payload = textToBase64Url(JSON.stringify({
    sub: ADMIN_STUDENT_ID,
    role: 'admin',
    exp: Math.floor(Date.now() / 1000) + 3600,
  }));
  const signature = await crypto.subtle.sign(
    'HMAC',
    await adminHmacKey(env),
    new TextEncoder().encode(payload),
  );
  return `${payload}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

function base64UrlToBytes(value) {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=');
  const binary = atob(base64);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

async function verifyAdminRequest(request, env) {
  if (!env.ADMIN_SESSION_SECRET) return false;
  const auth = request.headers.get('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const [payload, signature, extra] = token.split('.');
  if (!payload || !signature || extra) return false;
  try {
    const valid = await crypto.subtle.verify(
      'HMAC',
      await adminHmacKey(env),
      base64UrlToBytes(signature),
      new TextEncoder().encode(payload),
    );
    if (!valid) return false;
    const claims = JSON.parse(new TextDecoder().decode(base64UrlToBytes(payload)));
    return claims.sub === ADMIN_STUDENT_ID &&
      claims.role === 'admin' &&
      Number(claims.exp) > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

async function supabaseCount(env, table) {
  const r = await fetch(`${SUPA_URL}/rest/v1/${table}?select=*&limit=1`, {
    headers: {
      'apikey': env.SUPA_KEY,
      'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Prefer': 'count=exact',
      'Range': '0-0',
    },
  }).catch(() => null);
  if (!r?.ok) return 0;
  const range = r.headers.get('content-range') || '';
  return Number(range.split('/').pop() || 0);
}

function v4ToTable(values) {
  if (!values || values.length < 1) return { cols: [], rows: [] };
  const headers = values[0] || [];
  /* find max columns across ALL rows so trailing empty header cells don't truncate data */
  const maxCols = values.reduce((m, row) => Math.max(m, row.length), 0);
  const paddedHeaders = Array.from({ length: maxCols }, (_, i) => String(headers[i] || ''));
  return {
    cols: paddedHeaders.map(h => ({ label: h, type: 'string' })),
    rows: values.slice(1).map(row => ({
      c: paddedHeaders.map((_, i) => {
        const v = row[i];
        return (v != null && v !== '') ? { v: String(v) } : null;
      }),
    })),
  };
}

/* Hidden column indices per tab → { "SATURDAY": [10], ... }.
   GVIZ has no hidden flag, so read columnMetadata.hiddenByUser via Sheets API.
   Cached in KV (10 min) so repeated routine loads don't re-hit the API. */
async function fetchHiddenColumns(sheetId, env) {
  if (!env || !env.DRIVE_API_KEY) return {};
  const cacheKey = `hidden:v4:${sheetId}`;
  if (env.SMS_RATE) {
    try { const c = await env.SMS_RATE.get(cacheKey); if (c) return JSON.parse(c); } catch {}
  }
  const out = {};
  try {
    const fields = encodeURIComponent('sheets(properties(title),data(columnMetadata(hiddenByUser)))');
    const url = `https://sheets.googleapis.com/v4/spreadsheets/${sheetId}` +
      `?includeGridData=true&fields=${fields}&key=${env.DRIVE_API_KEY}`;
    const r = await fetch(url, { headers: { 'Referer': 'https://lucse62b.xyz/' } });
    if (r.ok) {
      const d = await r.json();
      (d.sheets || []).forEach(s => {
        const title = s.properties?.title;
        if (!title) return;
        const meta = s.data?.[0]?.columnMetadata || [];
        const hidden = [];
        meta.forEach((c, i) => { if (c && c.hiddenByUser) hidden.push(i); });
        out[title] = hidden;
      });
    }
  } catch {}
  if (env.SMS_RATE) {
    try { await env.SMS_RATE.put(cacheKey, JSON.stringify(out), { expirationTtl: 600 }); } catch {}
  }
  return out;
}

async function tryV4(sheetId, tab, env) {
  if (!env || !env.DRIVE_API_KEY) return null;
  try {
    const range = encodeURIComponent(tab || 'Sheet1');
    /* `&_t=` cache-buster is essential: `cache: 'no-store'` is a no-op at our
       compatibility_date (it needs ≥ 2024-11-11), so without a unique URL this
       v4 request can be served stale from Cloudflare's edge / Google's cache —
       while every GVIZ path and the change monitor already bust cache this way.
       That asymmetry is exactly what makes the routine notification fire while
       the live info-page routine keeps showing the old schedule. */
    const r = await fetch(
      `https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${range}?key=${env.DRIVE_API_KEY}&_t=${Date.now()}`,
      { cache: 'no-store' }
    );
    if (!r.ok) return null;
    const d = await r.json();
    const table = v4ToTable(d.values || []);
    return table.rows.length > 0 ? table : null;
  } catch (e) { return null; }
}

async function gvizProxy(sheetId, tab, cors, env, rawHeaders) {
  const v4 = await tryV4(sheetId, tab, env);
  if (v4) {
    return new Response(JSON.stringify({ table: v4 }), {
      headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  }
  // CPG_Teachers: use raw Sheets export (not GVIZ) so text-format phones survive
  // GVIZ JSON *and* GVIZ CSV both apply type inference — dropping "01772-757936" etc.
  // The raw /export?format=csv endpoint returns actual cell values without inference.
  if (tab === 'CPG_Teachers') {
    const csvTable = await tryGvizCsv(sheetId, tab, env);
    if (csvTable) {
      return new Response(JSON.stringify({ table: csvTable }), {
        headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
      });
    }
  }
  try {
    let u = `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq?tqx=out:json&_t=${Date.now()}`;
    if (tab) u += `&sheet=${encodeURIComponent(tab)}`;
    // &headers=0 keeps every row as data so a stacked multi-header sheet's first
    // block (e.g. Batch 61) isn't silently folded into the column labels. (The v4
    // path above already returns raw rows, so this only matters on the fallback.)
    if (rawHeaders) u += `&headers=0`;
    const r    = await fetch(u);
    const text = await r.text();
    const m    = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
    if (!m) return errResp(cors, 502, 'Bad upstream response');
    return new Response(m[1], { headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
  } catch (e) {
    return errResp(cors, 502, 'Upstream fetch failed');
  }
}

async function tryGvizCsv(sheetId, tab, env) {
  try {
    let u;
    const gid = env?.CPG_TEACHERS_GID;
    if (tab === 'CPG_Teachers' && gid) {
      // Raw /export bypasses GVIZ type inference — returns exact cell text (dashes, leading zeros)
      u = `https://docs.google.com/spreadsheets/d/${sheetId}/export?format=csv&gid=${gid}&_t=${Date.now()}`;
    } else {
      u = `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq?tqx=out:csv&_t=${Date.now()}`;
      if (tab) u += `&sheet=${encodeURIComponent(tab)}`;
    }
    const r = await fetch(u);
    if (!r.ok) return null;
    const csv = await r.text();
    return parseCsvToTable(csv);
  } catch (e) { return null; }
}

function parseCsvToTable(csv) {
  const parseRow = (line) => {
    const result = []; let field = '', inQ = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '"') { if (inQ && line[i + 1] === '"') { field += '"'; i++; } else inQ = !inQ; }
      else if (ch === ',' && !inQ) { result.push(field); field = ''; }
      else field += ch;
    }
    result.push(field);
    return result;
  };
  const lines = [];
  let cur = '', inQ = false;
  for (let i = 0; i < csv.length; i++) {
    const ch = csv[i];
    if (ch === '"') { if (inQ && csv[i + 1] === '"') { cur += '"'; i++; } else inQ = !inQ; }
    else if ((ch === '\n' || ch === '\r') && !inQ) { if (cur || ch === '\n') { lines.push(cur); cur = ''; } }
    else cur += ch;
  }
  if (cur.trim()) lines.push(cur);
  if (lines.length < 2) return null;
  const headers = parseRow(lines[0]);
  const rows = lines.slice(1).filter(l => l.trim()).map(line => ({
    c: parseRow(line).map(v => v !== '' ? { v } : null),
  }));
  return rows.length > 0 ? { cols: headers.map(h => ({ label: h, type: 'string' })), rows } : null;
}

async function gvizProxyStrip(sheetId, tab, stripCols, cors, env) {
  const v4 = await tryV4(sheetId, tab, env);
  if (v4) {
    if (v4.cols) v4.cols = v4.cols.map((c, i) => stripCols.includes(i) ? { label: '', type: 'string' } : c);
    if (v4.rows) v4.rows = v4.rows.map(row => ({
      ...row, c: (row.c || []).map((cell, i) => stripCols.includes(i) ? null : cell),
    }));
    return new Response(JSON.stringify({ table: v4 }), {
      headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  }
  try {
    let u = `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq?tqx=out:json&_t=${Date.now()}`;
    if (tab) u += `&sheet=${encodeURIComponent(tab)}`;
    const r    = await fetch(u);
    const text = await r.text();
    const m    = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
    if (!m) return errResp(cors, 502, 'Bad upstream response');
    const data = JSON.parse(m[1]);
    if (data.table) {
      if (data.table.cols) data.table.cols = data.table.cols.map((c, i) => stripCols.includes(i) ? { label: '', type: 'string' } : c);
      if (data.table.rows) data.table.rows = data.table.rows.map(row => ({
        ...row,
        c: (row.c || []).map((cell, i) => stripCols.includes(i) ? null : cell)
      }));
    }
    return new Response(JSON.stringify(data), { headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
  } catch (e) {
    return errResp(cors, 502, 'Upstream fetch failed');
  }
}

/* LU result portal now requires a WordPress _ajax_nonce (scraped from the
   /result/ page's inline lu_ajax object) plus the page cookies. We cache the
   pair per-isolate for 10 min; on an invalid_nonce we bust and re-scrape once. */
let _luNonce = null, _luCookies = '', _luNonceAt = 0;
const LU_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

async function getLuNonce(env, force) {
  const now = Date.now();
  if (!force && _luNonce && now - _luNonceAt < 600000) {
    return { nonce: _luNonce, cookies: _luCookies };
  }
  // Shared nonce across worker isolates (cuts /result/ page scrapes → less LU load)
  if (!force && env && env.SMS_RATE) {
    try {
      const j = await env.SMS_RATE.get('lu:nonce');
      if (j) { const o = JSON.parse(j); _luNonce = o.n; _luCookies = o.c || ''; _luNonceAt = now; return { nonce: o.n, cookies: o.c || '' }; }
    } catch (e) {}
  }
  const r = await fetch('https://lus.ac.bd/result/', {
    headers: { 'user-agent': LU_UA, 'accept': 'text/html' },
  });
  const html = await r.text();
  const m = html.match(/lu_ajax\s*=\s*\{[^}]*?"nonce":"([a-f0-9]+)"/);
  if (!m) throw new Error('nonce-not-found');
  const raw = r.headers.get('set-cookie') || '';
  const cookies = raw.split(/,(?=\s*[^;,\s]+=)/)
    .map(c => c.split(';')[0].trim()).filter(Boolean).join('; ');
  _luNonce = m[1]; _luCookies = cookies; _luNonceAt = now;
  if (env && env.SMS_RATE) {
    try { await env.SMS_RATE.put('lu:nonce', JSON.stringify({ n: _luNonce, c: _luCookies }), { expirationTtl: 600 }); } catch (e) {}
  }
  return { nonce: _luNonce, cookies };
}

async function luGetResult(env, student_id, birth_date, force) {
  const { nonce, cookies } = await getLuNonce(env, force);
  const body = new URLSearchParams({ action: 'get-result', _ajax_nonce: nonce, student_id, birth_date });
  const headers = {
    'content-type': 'application/x-www-form-urlencoded',
    'x-requested-with': 'XMLHttpRequest',
    'user-agent': LU_UA,
    'referer': 'https://lus.ac.bd/result/',
  };
  if (cookies) headers['cookie'] = cookies;
  const r = await fetch('https://lus.ac.bd/wp-admin/admin-ajax.php', { method: 'POST', body, headers });
  return await r.text();
}

/* Fetch a result with short-lived KV caching to absorb the LU per-IP rate limit.
   A student loading several pages (DOB gate, result, retake) collapses into one
   upstream call per ~5 min. Serves a slightly-stale cached copy if LU rate-limits. */
async function luResultCached(env, student_id, birth_date) {
  const key = `res:${student_id}:${birth_date}`;
  if (env && env.SMS_RATE) {
    try {
      const hit = await env.SMS_RATE.get(key);
      if (hit) return hit;                    // fresh cache → no upstream call
    } catch (e) {}
  }
  let text;
  try {
    text = await luGetResult(env, student_id, birth_date, false);
    if (/invalid_nonce/.test(text)) text = await luGetResult(env, student_id, birth_date, true);
  } catch (e) { text = null; }

  let ok = false;
  if (text && !text.trimStart().startsWith('<')) {
    try { ok = !!JSON.parse(text).success; } catch (e) { ok = false; }
  }
  if (ok) {
    if (env && env.SMS_RATE) {
      try {
        await env.SMS_RATE.put(key, text, { expirationTtl: 300 });                       // serve-first, 5 min
        await env.SMS_RATE.put(`res_bak:${student_id}:${birth_date}`, text, { expirationTtl: 86400 }); // 24h rate-limit fallback
      } catch (e) {}
    }
    return text;
  }
  // Upstream failed / rate_limited → fall back to last good cache if any
  if (env && env.SMS_RATE) {
    try {
      const stale = await env.SMS_RATE.get(`res_bak:${student_id}:${birth_date}`);
      if (stale) return stale;
    } catch (e) {}
  }
  return text || '{"success":false,"error":"unavailable","message":"LU portal unavailable. Please try again shortly."}';
}

/* DOB on file for a student (via SECURITY DEFINER RPC, service_role). */
async function getStoredDob(env, student_id) {
  if (!env.SUPA_KEY) return null;
  const r = await fetch(`${SUPA_URL}/rest/v1/rpc/get_student_dob`, {
    method: 'POST',
    headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_student_id: String(student_id) }),
  }).catch(() => null);
  if (!r || !r.ok) return null;
  const d = await r.json().catch(() => null);
  return d ? String(d) : null;
}

/* A previously-imported result for this student, returned only if the DOB matches
   (same gate as live results). Returns the stored JSON as text, or null. */
async function getImportedResult(env, student_id, birth_date) {
  const dob = await getStoredDob(env, student_id);
  if (!dob || dob !== String(birth_date)) return null;
  const r = await fetch(
    `${SUPA_URL}/rest/v1/student_results?student_id=eq.${encodeURIComponent(student_id)}&select=data&limit=1`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!r || !r.ok) return null;
  const rows = await r.json().catch(() => null);
  if (!rows || !rows.length || !rows[0].data) return null;
  return JSON.stringify(rows[0].data);
}

function jsonResp(cors, data) {
  return new Response(JSON.stringify(data), {
    headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function errResp(cors, status, msg) {
  return new Response(JSON.stringify({ error: msg }), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/* ════════════════════════════════════════════════════════════════════
   LU NOTICES  (https://lus.ac.bd/notice/ — read via the WordPress RSS feed)
   The site has no public REST endpoint for notices, but every WordPress
   install exposes /notice/feed/. We parse that RSS to a small JSON array
   and cache it in KV (~20 min) so the home widget loads instantly and we
   don't hammer lus.ac.bd. Notices are images, so we pull the first <img>.
   ════════════════════════════════════════════════════════════════════ */
async function fetchLuNotices(env) {
  const cacheKey = 'lu_notices:v1';
  if (env.SMS_RATE) {
    try { const c = await env.SMS_RATE.get(cacheKey); if (c) return JSON.parse(c); } catch {}
  }
  let notices = [];
  try {
    const r = await fetch('https://lus.ac.bd/notice/feed/', {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; LUCSE62B/1.0; +https://lucse62b.xyz)',
        'Accept': 'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
      },
    });
    if (r.ok) notices = parseRssNotices(await r.text());
  } catch {}
  const out = { notices, fetched: new Date().toISOString() };
  /* Only cache a non-empty result so a transient upstream hiccup doesn't
     pin an empty list for the full TTL. */
  if (env.SMS_RATE && notices.length) {
    try { await env.SMS_RATE.put(cacheKey, JSON.stringify(out), { expirationTtl: 1200 }); } catch {}
  }
  return out;
}

/* Regex RSS parser — Workers have no DOMParser. Pulls title / link / date and
   the first image out of each <item>. Returns up to 10 newest notices. */
function parseRssNotices(xml) {
  const notices = [];
  const blocks = String(xml).split(/<item[\s>]/i).slice(1);
  for (const raw of blocks) {
    const block   = raw.split(/<\/item>/i)[0];
    const title   = decodeXmlEntities(rssTag(block, 'title'));
    const link    = decodeXmlEntities(rssTag(block, 'link'));
    const date    = rssTag(block, 'pubDate');
    const content = rssContentEncoded(block);
    let image = '';
    const imgM = content.match(/<img[^>]+src=["']([^"']+)["']/i);
    if (imgM) image = imgM[1];
    if (!image) {
      const encM = block.match(/<enclosure[^>]+url=["']([^"']+\.(?:jpe?g|png|webp))["'][^>]*>/i)
                || block.match(/<media:content[^>]+url=["']([^"']+\.(?:jpe?g|png|webp))["'][^>]*>/i);
      if (encM) image = encM[1];
    }
    if (image) image = decodeXmlEntities(image);
    if (title && link) notices.push({ title, link, date, image });
    if (notices.length >= 10) break;
  }
  return notices;
}

function rssTag(block, tag) {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  return m ? stripCdata(m[1]).trim() : '';
}

function rssContentEncoded(block) {
  const m = block.match(/<content:encoded[^>]*>([\s\S]*?)<\/content:encoded>/i);
  return m ? stripCdata(m[1]) : '';
}

function stripCdata(s) {
  return String(s).replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1');
}

function decodeXmlEntities(s) {
  return String(s)
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&#0?39;/g, "'").replace(/&#x27;/gi, "'")
    .replace(/&#8217;/g, '’').replace(/&#8216;/g, '‘')
    .replace(/&#8220;/g, '“').replace(/&#8221;/g, '”')
    .replace(/&#8211;/g, '–').replace(/&#8212;/g, '—')
    .replace(/&#8230;/g, '…').replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .trim();
}

/* ════════════════════════════════════════════════════════════════════
   NOTIFICATION MONITOR  (runs via Cloudflare Cron every hour)
   ════════════════════════════════════════════════════════════════════ */

const MONITOR_DAYS = ['SATURDAY','SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY'];

const ACTIVE_ROSTER_KEY = 'active_student_roster_v1';

async function fetchActiveStudentIds(env) {
  if (!env.MAIN_SHEET_ID) throw new Error('MAIN_SHEET_ID is not configured');
  let ids = [];

  // Sheets API v4 reflects edits immediately and avoids GVIZ cache delays.
  if (env.DRIVE_API_KEY) {
    try {
      const range = encodeURIComponent("'Student Info'!B:B");
      const u = `https://sheets.googleapis.com/v4/spreadsheets/${env.MAIN_SHEET_ID}` +
        `/values/${range}?majorDimension=ROWS&key=${env.DRIVE_API_KEY}`;
      const r = await fetch(u, { headers: { 'Referer': 'https://lucse62b.xyz/' } });
      if (r.ok) {
        const data = await r.json();
        ids = (data.values || [])
          .map(row => String((row || [])[0] || '').trim())
          .filter(id => /^\d{8,16}$/.test(id));
      }
    } catch {}
  }

  // Public-sheet fallback for projects where the Sheets API is unavailable.
  if (!ids.length) {
    const tq = encodeURIComponent('select B where B is not null');
    const u = `https://docs.google.com/spreadsheets/d/${env.MAIN_SHEET_ID}` +
      `/gviz/tq?tqx=out:json&sheet=${encodeURIComponent('Student Info')}&tq=${tq}&_t=${Date.now()}`;
    const r = await fetch(u);
    if (!r.ok) throw new Error(`Roster GVIZ ${r.status}`);
    const text = await r.text();
    const match = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
    if (!match) throw new Error('Bad roster GVIZ response');
    const data = JSON.parse(match[1]);
    ids = (data.table?.rows || [])
      .map(row => String(row?.c?.[0]?.f || row?.c?.[0]?.v || '').trim())
      .filter(id => /^\d{8,16}$/.test(id));
  }

  ids = [...new Set(ids)];
  // Never publish an empty roster on an upstream parsing/outage error, because
  // that would incorrectly log out the whole class.
  if (!ids.length) throw new Error('Active roster is empty');
  return ids;
}

async function unlinkRemovedStudents(env, previousIds, currentIds) {
  if (!env.SUPA_KEY || !previousIds?.length) return;
  const active = new Set(currentIds);
  const removed = previousIds.filter(id => !active.has(id) && /^\d{8,16}$/.test(id));
  if (!removed.length) return;
  const filter = encodeURIComponent(`in.(${removed.join(',')})`);
  const headers = {
    'apikey': env.SUPA_KEY,
    'Authorization': `Bearer ${env.SUPA_KEY}`,
  };
  await Promise.allSettled([
    fetch(`${SUPA_URL}/rest/v1/fcm_tokens?student_id=${filter}`, {
      method: 'DELETE', headers,
    }),
    fetch(`${SUPA_URL}/rest/v1/push_subscriptions?student_id=${filter}`, {
      method: 'DELETE', headers,
    }),
  ]);
}

async function refreshActiveStudentRoster(env) {
  const ids = await fetchActiveStudentIds(env);
  let previous = null;
  if (env.SMS_RATE) {
    try {
      const raw = await env.SMS_RATE.get(ACTIVE_ROSTER_KEY);
      if (raw) previous = JSON.parse(raw);
    } catch {}
  }
  const roster = { ids, checkedAt: Date.now() };
  if (env.SMS_RATE) {
    await env.SMS_RATE.put(ACTIVE_ROSTER_KEY, JSON.stringify(roster), {
      expirationTtl: 86400,
    });
  }
  await unlinkRemovedStudents(env, previous?.ids || [], ids);
  return roster;
}

async function getActiveStudentRoster(env) {
  if (env.SMS_RATE) {
    try {
      const raw = await env.SMS_RATE.get(ACTIVE_ROSTER_KEY);
      if (raw) {
        const roster = JSON.parse(raw);
        if (Array.isArray(roster.ids) &&
            Number(roster.checkedAt) > Date.now() - 90000) {
          return roster;
        }
      }
    } catch {}
  }
  try {
    return await refreshActiveStudentRoster(env);
  } catch {
    return null;
  }
}

async function runFastMonitor(env) {
  if (!env.SUPA_KEY) return;
  const started = new Date().toISOString();
  const checks = await Promise.allSettled([
    refreshActiveStudentRoster(env),
    checkSiteUpdates(env),
    checkAppUpdates(env),
    checkDeadlines(env),
    checkDeadlineReminders(env),
    checkNotices(env),
    checkClassRoutine(env),
    checkExamRoutine(env, 'mid'),
    checkExamRoutine(env, 'final'),
  ]);
  const failed = checks.filter(r => r.status === 'rejected').length;
  await fetch(`${SUPA_URL}/rest/v1/monitor_state`, {
    method: 'POST',
    headers: {
      'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      key: 'cron_fast_heartbeat',
      state_hash: `${started}:${failed}`,
      state_data: { at: started, checks: checks.length, failed },
      last_checked: new Date().toISOString(),
      last_changed: new Date().toISOString(),
    }),
  }).catch(() => {});
}

async function runMonitor(env) {
  if (!env.SUPA_KEY) return;
  const hour = new Date().getUTCHours();
  const branch = (hour % 2 === 0) ? 'even' : 'odd';
  let note = '';

  /* Split work across hours so one cron run never exceeds Cloudflare's
     per-invocation subrequest limit (50 on the free plan): routine / exam /
     enrolled checks on even hours, the heavier per-student result check on
     odd hours. Each branch fits comfortably under the limit on its own. */
  try {
    /* What's New announcements have no push path of their own — broadcast them
       every hour (cheap: one read + at most one wake-push to all subscribers). */
    // Public update monitors run every minute in runFastMonitor.
    if (hour % 2 === 0) {
      /* Enrolled retake/improve course routine + exam changes — per-student */
      await checkEnrolledCourses(env).catch(() => {});
      note = 'enrolled-course-checks';
    } else {
      note = await checkResult(env).catch(e => 'error:' + ((e && e.message) || e)) || '';
    }
  } finally {
    /* Heartbeat: every cron run records its hour/branch/outcome so we can SEE
       from the DB whether the (odd-hour) result check is actually firing and
       what it did — instead of guessing why notifications stop. */
    await recordHeartbeat(env, hour, branch, note);
  }
}

/* Upsert a single 'cron_heartbeat' row reflecting the most recent cron run. */
async function recordHeartbeat(env, hour, branch, note) {
  await fetch(`${SUPA_URL}/rest/v1/monitor_state`, {
    method: 'POST',
    headers: {
      'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      key: 'cron_heartbeat',
      state_hash: `${branch}:${hour}`,
      state_data: { hour, branch, note: String(note || ''), at: new Date().toISOString() },
      last_checked: new Date().toISOString(),
      last_changed: new Date().toISOString(),
    }),
  }).catch(() => {});
}

/* ── SHA-256 hash ── */
async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}

/* ── Supabase monitor_state helpers ── */
async function supabaseGetState(env, key) {
  const r = await fetch(`${SUPA_URL}/rest/v1/monitor_state?key=eq.${key}&limit=1`, {
    headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
  }).catch(() => null);
  if (!r || !r.ok) return null;
  const rows = await r.json();
  return rows[0] || null;
}

async function supabaseUpsertState(env, key, hash, data) {
  await fetch(`${SUPA_URL}/rest/v1/monitor_state`, {
    method: 'POST',
    headers: {
      'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      key, state_hash: hash, state_data: data,
      last_checked: new Date().toISOString(),
      last_changed: new Date().toISOString(),
    }),
  }).catch(() => {});
}

async function insertNotification(env, type, title, body, link) {
  await fetch(`${SUPA_URL}/rest/v1/notifications`, {
    method: 'POST',
    headers: {
      'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ type, title, body, link }),
  }).catch(() => {});
}

/* ── Sheet fetch helper (no CORS needed for scheduled) ── */
async function fetchSheetGviz(sheetId, tab) {
  let url = `https://docs.google.com/spreadsheets/d/${sheetId}/gviz/tq?tqx=out:json&_t=${Date.now()}`;
  if (tab) url += `&sheet=${encodeURIComponent(tab)}`;
  const r = await fetch(url);
  const text = await r.text();
  const m = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
  return m ? JSON.parse(m[1]).table : null;
}

/* ── Get routine sheet ID from main sheet (first link only) ── */
async function getRoutineSheetIdByKeyword(env, keyword) {
  return (await getRoutineSheetIdsByKeyword(env, keyword))[0] || null;
}

/* ── All routine sheet IDs for a keyword (col B, C, … each a separate link) ──
   A row may hold several spreadsheet links; extra ones carry additional
   sections/batches that live only in a second sheet. */
async function getRoutineSheetIdsByKeyword(env, keyword) {
  const mainId = env.MAIN_SHEET_ID;
  if (!mainId) return [];
  const ids = [];
  try {
    const table = await fetchSheetGviz(mainId, 'Routine');
    for (const row of (table?.rows || [])) {
      const cells = (row.c || []).map(c => c?.v != null ? String(c.v).trim() : '');
      if (!cells[0]?.toLowerCase().includes(keyword)) continue;
      for (let i = 1; i < cells.length; i++) {
        const m = (cells[i] || '').match(/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
        if (m && !ids.includes(m[1])) ids.push(m[1]);
      }
      break;
    }
  } catch {}
  return ids;
}

/* ── Merge several GVIZ tables (same format) into one ── */
function mergeGvizTables(tables) {
  const valid = tables.filter(t => t);
  if (!valid.length) return null;
  const base = valid.reduce((a, b) => ((b.cols?.length || 0) > (a.cols?.length || 0) ? b : a), valid[0]);
  const rows = [];
  valid.forEach(t => (t.rows || []).forEach(r => rows.push(r)));
  return { cols: base.cols || [], rows };
}

/* ── Fetch + merge every day tab across all sheets linked for a keyword ──
   Returns one merged table per MONITOR_DAY (aligned to MONITOR_DAYS). */
async function fetchMergedDayTabs(env, ids) {
  if (!ids.length) return MONITOR_DAYS.map(() => null);
  const perSheet = await Promise.all(
    ids.map(id => Promise.all(MONITOR_DAYS.map(d => fetchSheetGviz(id, d).catch(() => null))))
  );
  return MONITOR_DAYS.map((_, i) => mergeGvizTables(perSheet.map(s => s[i])));
}

/* ── Fetch + merge a single-tab sheet (e.g. exam routine) across all IDs ── */
async function fetchMergedSingleTab(ids) {
  if (!ids.length) return null;
  const tables = await Promise.all(ids.map(id => fetchSheetGviz(id).catch(() => null)));
  return mergeGvizTables(tables);
}

/* ── Parse 62B slots from a single day tab ── */
function parse62BSlots(table, dayName) {
  if (!table) return [];
  const rows = table.rows || [];
  const cols = table.cols || [];

  let timeSlots = cols.slice(3).map(c => (c.label || '').trim());
  let dataStart = 0;
  if (!timeSlots.some(t => /\d+:\d+/.test(t))) {
    for (let r = 0; r < Math.min(rows.length, 3); r++) {
      const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
      if (cells.slice(3).some(c => /\d+:\d+/.test(c))) {
        timeSlots = cells.slice(3); dataStart = r + 1; break;
      }
    }
  }

  let breakSlotIdx = -1;
  const targetRows = [];
  for (let r = dataStart; r < rows.length; r++) {
    const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
    cells.slice(3).forEach((cell, i) => { if (cell.toUpperCase() === 'BREAK') breakSlotIdx = i; });
    if (cells[1]?.trim().replace(/\.0+$/,'') === '62' && cells[2]?.trim().toUpperCase() === 'B') targetRows.push(cells);
  }
  if (!targetRows.length) return [];

  const merged = targetRows[0].slice(3).map((_, i) =>
    targetRows.map(r => r.slice(3)[i]).find(v => v && v.toUpperCase() !== 'BREAK') || ''
  );

  const slots = [];
  timeSlots.forEach((time, i) => {
    if (!time || i === breakSlotIdx || !merged[i]) return;
    const parts = merged[i].trim().split(/\s+/).filter(Boolean);
    if (!parts[0]) return;
    slots.push({ day: dayName, time: time.trim(), code: parts[0], teacher: parts[1] || '', room: parts.slice(2).join(' ') });
  });
  return slots;
}

/* ── Compute slot diff ── */
function computeSlotDiff(oldSlots, newSlots) {
  const byKey  = arr => Object.fromEntries(arr.map(s => [`${s.day}|${s.time}|${s.code}`, s]));
  const byCode = arr => {
    const m = {};
    arr.forEach(s => { if (!m[s.code]) m[s.code] = []; m[s.code].push(s); });
    return m;
  };

  const oldMap     = byKey(oldSlots),  newMap     = byKey(newSlots);
  const oldByCode  = byCode(oldSlots), newByCode  = byCode(newSlots);
  const changes    = [];
  const matched    = new Set();

  /* Exact key match → check teacher/room changes */
  for (const [k, o] of Object.entries(oldMap)) {
    const n = newMap[k];
    if (!n) continue;
    matched.add(k);
    const fc = [];
    if (o.teacher !== n.teacher && (o.teacher || n.teacher)) fc.push(`Teacher: ${o.teacher||'?'} → ${n.teacher||'?'}`);
    if (o.room    !== n.room    && (o.room    || n.room   )) fc.push(`Room: ${o.room||'?'} → ${n.room||'?'}`);
    if (fc.length) changes.push(`• ${n.code} (${n.day}): ${fc.join(', ')}`);
  }

  /* Unmatched old slots → try to find same code in new (day/time moved) */
  for (const [k, o] of Object.entries(oldMap)) {
    if (matched.has(k)) continue;
    const candidates = (newByCode[o.code] || []).filter(n => !matched.has(`${n.day}|${n.time}|${n.code}`));
    if (candidates.length === 1) {
      const n = candidates[0];
      matched.add(`${n.day}|${n.time}|${n.code}`);
      const fc = [];
      if (o.day  !== n.day)  fc.push(`Day: ${o.day} → ${n.day}`);
      if (o.time !== n.time) fc.push(`Time: ${o.time} → ${n.time}`);
      if (o.teacher !== n.teacher && (o.teacher || n.teacher)) fc.push(`Teacher: ${o.teacher||'?'} → ${n.teacher||'?'}`);
      if (o.room    !== n.room    && (o.room    || n.room   )) fc.push(`Room: ${o.room||'?'} → ${n.room||'?'}`);
      if (fc.length) changes.push(`• ${o.code}: ${fc.join(', ')}`);
    } else {
      changes.push(`• ${o.code}: Removed from ${o.day} at ${o.time}`);
    }
  }

  /* Unmatched new slots → added */
  for (const [k, n] of Object.entries(newMap)) {
    if (matched.has(k)) continue;
    changes.push(`• ${n.code}: Added on ${n.day} at ${n.time}`);
  }

  return changes;
}

/* ── Class Routine Monitor ──
   Watches 62B's own routine (parse62BSlots). 62B always lives in the first
   ("Link 1") sheet, so a second Routine Link carries only other sections and
   never affects this notification — we read just the first link to stay well
   under the per-run subrequest limit. (Extra links are merged where it matters:
   the enrolled-courses monitor below.) */
async function checkClassRoutine(env) {
  const sheetId = (await getRoutineSheetIdByKeyword(env, 'class routine')) || '1jjOmSUg3U_uyzM0mtaj1FldEOD1nNeMCAhybEiQTW3M';
  const dayTabs = await Promise.all(MONITOR_DAYS.map(d => fetchSheetGviz(sheetId, d).catch(() => null)));
  const allSlots = MONITOR_DAYS.flatMap((day, i) => parse62BSlots(dayTabs[i], day));
  if (!allSlots.length) return;

  const sorted = [...allSlots].sort((a, b) => `${a.day}${a.time}${a.code}`.localeCompare(`${b.day}${b.time}${b.code}`));
  const hash   = await sha256(JSON.stringify(sorted));
  const stored = await supabaseGetState(env, 'class_routine');

  if (!stored) { await supabaseUpsertState(env, 'class_routine', hash, { slots: sorted }); return; }
  if (stored.state_hash === hash) return;

  const changes = computeSlotDiff(stored.state_data?.slots || [], sorted);
  if (!changes.length) { await supabaseUpsertState(env, 'class_routine', hash, { slots: sorted }); return; }

  const body = changes.slice(0, 8).join('\n') + (changes.length > 8 ? `\n…and ${changes.length - 8} more` : '');
  await insertNotification(env, 'class_routine', '📅 Class Routine Updated', body, '/pages/info.html');
  await supabaseUpsertState(env, 'class_routine', hash, { slots: sorted });
  await sendPushToAll(env);
}

/* Normalize an exam date cell (GVIZ may give "Date(2026,2,27)" or a serial)
   to DD-MM-YYYY; pass already-formatted strings straight through. */
function examNormDate(raw) {
  if (raw == null || raw === '') return '';
  const str = String(raw).trim();
  const dm = str.match(/^Date\((\d+),(\d+),(\d+)/);
  if (dm) {
    const d = new Date(+dm[1], +dm[2], +dm[3]);
    return `${String(d.getDate()).padStart(2,'0')}-${String(d.getMonth()+1).padStart(2,'0')}-${d.getFullYear()}`;
  }
  const num = parseFloat(str);
  if (!isNaN(num) && num > 40000 && num < 60000) {
    const d   = new Date(Math.round((num - 25569) * 86400 * 1000));
    const utc = new Date(d.getTime() + d.getTimezoneOffset() * 60000);
    return `${String(utc.getDate()).padStart(2,'0')}-${String(utc.getMonth()+1).padStart(2,'0')}-${utc.getFullYear()}`;
  }
  return str;
}

/* Parse one batch/section's exams from a single-tab exam-routine matrix
   (Day-1…Day-N columns, Batch/Section rows). Mirrors parseExamRoutine in
   pages/info/exam.js so the monitor sees exactly what the info page shows.
   Returns slots { code, day, time } where `day` folds in weekday + date so a
   reschedule reads as a clear diff. Handles multiple Day-N blocks in one sheet. */
function parseExamSlots(table, targetBatch, targetSection) {
  if (!table) return [];
  const allRows = (table.rows || []).map(r =>
    (r.c || []).map(c => (c && c.v != null) ? (examNormDate(c.v) || String(c.v).trim()) : '')
  );
  const colLabels = (table.cols || []).map(c => String(c.label || '').trim());
  if (colLabels.some(l => /day[\s\-]*\d+/i.test(l))) {
    allRows.unshift(colLabels.map(l => { const m = l.match(/day[\s\-]*(\d+)/i); return m ? `Day-${m[1]}` : ''; }));
  }

  const blockStarts = [];
  for (let r = 0; r < allRows.length; r++) {
    for (let c = 0; c < allRows[r].length; c++) {
      if (/^\s*day[\s\-]*\d+\s*$/i.test(allRows[r][c])) { blockStarts.push(r); break; }
    }
  }
  if (!blockStarts.length) return [];

  let batchCol = 0, sectionCol = 1;
  for (let r = 0; r < Math.min(allRows.length, 15); r++) {
    (allRows[r] || []).forEach((cell, i) => {
      if (/^\s*batch\s*$/i.test(cell))   batchCol = i;
      if (/^\s*section\s*$/i.test(cell)) sectionCol = i;
    });
  }

  const tbNum = String(targetBatch).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
  const tsStr = String(targetSection).trim().toUpperCase();
  const slots = [];

  blockStarts.forEach((dayHeaderIdx, bi) => {
    const nextBlockRow = blockStarts[bi + 1] || allRows.length;

    const rowBatches = {};
    let lastBatch = '';
    for (let r = dayHeaderIdx; r < nextBlockRow; r++) {
      const bc = String(allRows[r][batchCol] || '').trim();
      if (bc && /\d/.test(bc) && !/^(date|time|day|section)/i.test(bc)) lastBatch = bc;
      rowBatches[r] = lastBatch;
    }

    const dayRow  = allRows[dayHeaderIdx] || [];
    const dayCols = dayRow.reduce((a, cell, i) => { if (/^\s*day[\s\-]*\d+\s*$/i.test(cell)) a.push(i); return a; }, []);
    if (!dayCols.length) return;

    let dateRowIdx = dayHeaderIdx + 1, timeRowIdx = dayHeaderIdx + 2, weekdayRowIdx = dayHeaderIdx + 3;
    const sampleCol = dayCols[0];
    for (let i = 1; i <= 5; i++) {
      const rIdx = dayHeaderIdx + i;
      if (rIdx >= allRows.length || rIdx >= nextBlockRow) break;
      const cell = String(allRows[rIdx][sampleCol] || '').trim();
      if (/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/.test(cell)) dateRowIdx = rIdx;
      else if (/\d{1,2}:\d{2}/.test(cell) || /am|pm/i.test(cell)) timeRowIdx = rIdx;
      else if (/^(sun|mon|tue|wed|thu|fri|sat)/i.test(cell)) weekdayRowIdx = rIdx;
    }

    const dataStartRow = Math.max(dayHeaderIdx, dateRowIdx, timeRowIdx, weekdayRowIdx) + 1;
    const dateRow    = allRows[dateRowIdx]    || [];
    const timeRow    = allRows[timeRowIdx]    || [];
    const weekdayRow = allRows[weekdayRowIdx] || [];

    for (let r = dataStartRow; r < nextBlockRow; r++) {
      const row = allRows[r];
      if (!row) continue;
      const section = (row[sectionCol] || '').trim();
      if (!section || /^(section|day|date|time)$/i.test(section)) continue;
      const cbNum = String(rowBatches[r]).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
      const csStr = section.toUpperCase();
      const sectionMatch = csStr === tsStr || csStr.split(/[+&,]/).map(s => s.trim()).includes(tsStr);
      if (cbNum && cbNum === tbNum && sectionMatch) {
        dayCols.forEach(ci => {
          const course = String(row[ci] || '').replace(/\s*\(\d+\)\s*/g, '').trim();
          if (course && course !== '--' && course !== '–') {
            slots.push({
              code: course,
              day:  `${(weekdayRow[ci] || '').trim()} ${(dateRow[ci] || '').trim()}`.trim(),
              time: (timeRow[ci] || '').trim(),
            });
          }
        });
      }
    }
  });
  return slots;
}

/* ── Exam Routine Monitor ──
   Exam routines are a single matrix tab (Day-1…Day-N columns, Batch/Section
   rows), NOT per-day tabs like the class routine — so we read the merged
   single tab across all linked sheets and parse 62B's exams the same way the
   info page does. Watches Batch 62, Section B (notifications go to all 62B). */
async function checkExamRoutine(env, type) {
  const keyword = type === 'mid' ? 'mid term' : 'final term';
  const label   = type === 'mid' ? 'Mid Term' : 'Final Term';
  const stateKey = `${type}_routine`;

  const ids = await getRoutineSheetIdsByKeyword(env, keyword);
  if (!ids.length) return;

  const table    = await fetchMergedSingleTab(ids);
  const allSlots = parseExamSlots(table, '62', 'B');

  if (!allSlots.length) {
    const stored = await supabaseGetState(env, stateKey);
    if (!stored) await supabaseUpsertState(env, stateKey, 'empty', { slots: [] });
    return;
  }

  const sorted = [...allSlots].sort((a, b) => `${a.day}${a.time}${a.code}`.localeCompare(`${b.day}${b.time}${b.code}`));
  const hash   = await sha256(JSON.stringify(sorted));
  const stored = await supabaseGetState(env, stateKey);

  if (!stored || !stored.state_data?.slots?.length) {
    const preview = sorted.slice(0, 5).map(s => `• ${s.code}: ${s.day} at ${s.time}`).join('\n');
    await insertNotification(env, stateKey, `📋 ${label} Routine Published`, preview, '/pages/info.html');
    await supabaseUpsertState(env, stateKey, hash, { slots: sorted });
    await sendPushToAll(env);
    return;
  }
  if (stored.state_hash === hash) return;

  const changes = computeSlotDiff(stored.state_data?.slots || [], sorted);
  if (!changes.length) { await supabaseUpsertState(env, stateKey, hash, { slots: sorted }); return; }

  const body = changes.slice(0, 8).join('\n') + (changes.length > 8 ? `\n…and ${changes.length - 8} more` : '');
  await insertNotification(env, stateKey, `📋 ${label} Routine Updated`, body, '/pages/info.html');
  await supabaseUpsertState(env, stateKey, hash, { slots: sorted });
  await sendPushToAll(env);
}

/* ── LU Notices Monitor ──
   Watches the latest LU notices (same feed the home widget reads). On the
   first run it just seeds the baseline; afterwards any notice whose link is
   new fires a single public notification + push. We key on link (stable
   per-notice) rather than title so a re-titled notice isn't re-announced. */
async function checkNotices(env) {
  if (!env.SUPA_KEY) return;
  const { notices } = await fetchLuNotices(env);
  if (!notices || !notices.length) return;

  const links = notices.map(n => n.link).filter(Boolean);
  const hash   = await sha256(JSON.stringify(links));
  const stored = await supabaseGetState(env, 'lu_notices');

  if (!stored) { await supabaseUpsertState(env, 'lu_notices', hash, { links }); return; }
  if (stored.state_hash === hash) return;

  const known = new Set(stored.state_data?.links || []);
  const fresh = notices.filter(n => n.link && !known.has(n.link));
  await supabaseUpsertState(env, 'lu_notices', hash, { links });
  if (!fresh.length) return;

  const title = fresh.length === 1 ? '📢 New LU Notice' : `📢 ${fresh.length} New LU Notices`;
  const body  = fresh.slice(0, 5).map(n => `• ${n.title}`).join('\n')
              + (fresh.length > 5 ? `\n…and ${fresh.length - 5} more` : '');
  /* Open our own Notice page (the student sees every notice there). */
  await insertNotification(env, 'lu_notice', title, body, '/pages/notice.html');
  await sendPushToAll(env);
}

/* ── Classwork Deadlines Monitor ──
   Fires when a new row is added to the "Deadlines" tab (a classwork event —
   assignment / tutorial / lab report / viva / lab final / project — was posted),
   so students get an in-app + push notification. Seeds a baseline on first run so
   existing deadlines aren't re-announced. */
async function checkDeadlines(env) {
  if (!env.SUPA_KEY || !env.MAIN_SHEET_ID) return;
  const u = `https://docs.google.com/spreadsheets/d/${env.MAIN_SHEET_ID}/gviz/tq?tqx=out:json&sheet=Deadlines`;
  const r = await fetch(u).catch(() => null);
  if (!r || !r.ok) return;
  const t = await r.text();
  const m = t.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
  if (!m) return;
  let rows;
  try { rows = JSON.parse(m[1]).table?.rows || []; } catch (e) { return; }

  const items = [];
  for (const row of rows) {
    const cells = (row.c || []).map(c => (c && c.v !== null && c.v !== undefined) ? String(c.f || c.v).trim() : '');
    const course = cells[0] || '', type = cells[1] || '', title = cells[2] || '';
    if (!title) continue;
    if (course.toLowerCase() === 'course' || type.toLowerCase() === 'type') continue; // header row
    items.push({ course, type, title, key: `${course}|${type}|${title}|${cells[3] || ''}` });
  }
  if (!items.length) return;

  const keys   = items.map(i => i.key);
  const hash   = await sha256(JSON.stringify(keys));
  const stored = await supabaseGetState(env, 'classwork_deadlines');

  if (!stored) { await supabaseUpsertState(env, 'classwork_deadlines', hash, { keys }); return; }
  if (stored.state_hash === hash) return;

  const known = new Set(stored.state_data?.keys || []);
  const fresh = items.filter(i => !known.has(i.key));
  await supabaseUpsertState(env, 'classwork_deadlines', hash, { keys });
  if (!fresh.length) return;

  const title = fresh.length === 1 ? '📝 New Classwork Posted' : `📝 ${fresh.length} New Classwork Items`;
  const body  = fresh.slice(0, 5)
                  .map(i => `• ${i.type ? i.type + ': ' : ''}${i.title}${i.course ? ' (' + i.course + ')' : ''}`)
                  .join('\n')
              + (fresh.length > 5 ? `\n…and ${fresh.length - 5} more` : '');
  await insertNotification(env, 'classwork', title, body, '/pages/classwork.html');
  await sendPushToAll(env);
}

/* ── What's New Monitor ──
   Site updates (the What's New page) are inserted straight into the DB and have
   no push path of their own. Each cron run checks whether the newest site_update
   is newer than the last one we announced; if so it wakes every subscriber (the
   service worker then shows the latest notification — the DB trigger already
   inserted the matching 'whats_new' row). Seeds a baseline on first run so old
   updates aren't re-announced. */
function dhakaClockParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Dhaka',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(date);
  return Object.fromEntries(parts.map(p => [p.type, p.value]));
}

function addDateKeyDays(key, days) {
  const [y, m, d] = key.split('-').map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + days));
  return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-${String(next.getUTCDate()).padStart(2, '0')}`;
}

function deadlineDateKey(raw, formatted) {
  const value = String(raw || '').trim();
  const gviz = value.match(/^Date\((\d+),(\d+),(\d+)/);
  if (gviz) {
    return `${gviz[1]}-${String(Number(gviz[2]) + 1).padStart(2, '0')}-${String(Number(gviz[3])).padStart(2, '0')}`;
  }
  const iso = value.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
  const parsed = new Date(formatted || value);
  if (Number.isNaN(parsed.getTime())) return '';
  const p = dhakaClockParts(parsed);
  return `${p.year}-${p.month}-${p.day}`;
}

/* At 18:00 Asia/Dhaka, remind everyone about classwork due the next day.
   Sent keys are persisted so cron retries never duplicate a reminder. */
async function checkDeadlineReminders(env) {
  if (!env.SUPA_KEY || !env.MAIN_SHEET_ID) return;
  const clock = dhakaClockParts();
  if (Number(clock.hour) !== 18) return;
  const today = `${clock.year}-${clock.month}-${clock.day}`;
  const tomorrow = addDateKeyDays(today, 1);

  const u = `https://docs.google.com/spreadsheets/d/${env.MAIN_SHEET_ID}/gviz/tq?tqx=out:json&sheet=Deadlines&_t=${Date.now()}`;
  const r = await fetch(u).catch(() => null);
  if (!r || !r.ok) return;
  const text = await r.text();
  const match = text.match(/setResponse\(([\s\S]+)\)\s*;?\s*$/);
  if (!match) return;
  let rows;
  try { rows = JSON.parse(match[1]).table?.rows || []; } catch { return; }

  const due = [];
  for (const row of rows) {
    const cells = row.c || [];
    const textAt = i => {
      const cell = cells[i];
      return cell && cell.v !== null && cell.v !== undefined
        ? String(cell.f || cell.v).trim() : '';
    };
    const course = textAt(0), type = textAt(1), title = textAt(2);
    if (!title || course.toLowerCase() === 'course' || type.toLowerCase() === 'type') continue;
    if (deadlineDateKey(cells[3]?.v, cells[3]?.f) !== tomorrow) continue;
    due.push({
      course, type, title,
      deadline: textAt(3),
      key: `${course}|${type}|${title}|${textAt(3)}`,
    });
  }

  const state = await supabaseGetState(env, 'deadline_reminder');
  const known = state?.state_data?.date === today
    ? new Set(state.state_data?.keys || []) : new Set();
  const fresh = due.filter(item => !known.has(item.key));
  const keys = [...new Set([...known, ...due.map(item => item.key)])];
  const hash = await sha256(`${today}|${JSON.stringify(keys)}`);
  await supabaseUpsertState(env, 'deadline_reminder', hash, {
    date: today, tomorrow, keys,
  });
  if (!fresh.length) return;

  const title = fresh.length === 1
    ? '⏰ Classwork due tomorrow'
    : `⏰ ${fresh.length} classwork items due tomorrow`;
  const body = fresh.slice(0, 6).map(item =>
    `• ${item.course ? item.course + ' · ' : ''}${item.type ? item.type + ': ' : ''}${item.title}`
  ).join('\n') + (fresh.length > 6 ? `\n…and ${fresh.length - 6} more` : '');
  await insertNotification(env, 'deadline_reminder', title, body, '/pages/classwork.html');
  await sendPushToAll(env);
}

async function checkSiteUpdates(env) {
  if (!env.SUPA_KEY) return;
  const r = await fetch(
    `${SUPA_URL}/rest/v1/site_updates?select=created_at&order=created_at.desc&limit=1`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!r || !r.ok) return;
  const rows = await r.json();
  if (!rows.length || !rows[0].created_at) return;
  const latest = rows[0].created_at;
  const stored = await supabaseGetState(env, 'site_updates');
  if (!stored) { await supabaseUpsertState(env, 'site_updates', String(latest), { last: latest }); return; }
  const lastSeen = stored.state_data?.last || '';
  if (lastSeen && new Date(latest).getTime() <= new Date(lastSeen).getTime()) return;
  await supabaseUpsertState(env, 'site_updates', String(latest), { last: latest });
  await sendPushToAll(env);
}

/* ── Result Monitor — every student with a saved DOB (no push needed) ──
   Reads student_passwords fresh each run, so newly-registered students are
   picked up automatically. To respect the subrequest limit, students are
   processed in hourly round-robin batches (≤45 students → fully covered
   every ~8h; results rarely change minute-to-minute). A personal in-app
   notification is always inserted; a push is also sent if the student has
   subscribed. opts.batchIndex forces a specific batch (manual seeding). ── */
async function checkAppUpdates(env) {
  if (!env.SUPA_KEY) return;
  const r = await fetch(
    `${SUPA_URL}/rest/v1/app_updates?select=version_name,version_code,features,fixes,created_at&order=version_code.desc&limit=1`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!r || !r.ok) return;
  const rows = await r.json();
  if (!rows.length) return;
  const latest = rows[0];
  const versionCode = Number(latest.version_code || 0);
  if (!versionCode) return;
  const stored = await supabaseGetState(env, 'app_updates');
  if (!stored) {
    await supabaseUpsertState(env, 'app_updates', String(versionCode), { version_code: versionCode });
    return;
  }
  const previous = Number(stored.state_data?.version_code || stored.state_hash || 0);
  if (versionCode <= previous) return;
  await supabaseUpsertState(env, 'app_updates', String(versionCode), { version_code: versionCode });
  const changes = [...(latest.features || []), ...(latest.fixes || [])].slice(0, 4);
  const title = `🚀 App update v${latest.version_name || versionCode}`;
  const body = changes.length
    ? changes.map(x => `• ${x}`).join('\n')
    : 'A new CSE 62B Portal update is available.';
  await insertNotification(env, 'app_update', title, body, '/pages/whats-new.html');
  await sendPushToAll(env);
}

async function checkResult(env, opts = {}) {
  if (!env.SUPA_KEY) return 'no-key';

  /* Every student who has a DOB on file (fresh read → new sign-ups included) */
  const sr = await fetch(
    `${SUPA_URL}/rest/v1/student_passwords?select=student_id,dob&dob=not.is.null&order=student_id.asc`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!sr || !sr.ok) return 'students-fetch-failed';
  const students = (await sr.json()).filter(s => s.student_id && s.dob);
  if (!students.length) return 'no-students';

  /* student_id → push endpoints (optional; in-app notification works without) */
  const pr = await fetch(
    `${SUPA_URL}/rest/v1/push_subscriptions?select=endpoint,student_id&student_id=not.is.null`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  const endpointMap = {};
  if (pr && pr.ok) {
    (await pr.json()).forEach(s => {
      if (!endpointMap[s.student_id]) endpointMap[s.student_id] = [];
      endpointMap[s.student_id].push(s.endpoint);
    });
  }

  /* Round-robin a SMALL batch so each scheduled run is short and reliably
     finishes inside the cron's time budget (the previous 12-student batch with
     500ms sleeps could run ~60s on slow LU responses and get killed before any
     baseline was saved). Smaller batch + ~5 batches still covers every student
     a couple of times a day, which is plenty for results. A manual call passes
     batchIndex to step through every batch (e.g. to seed/catch-up now). */
  const BATCH = 6;
  const batchCount = Math.max(1, Math.ceil(students.length / BATCH));
  const idx = (opts.batchIndex != null)
    ? ((opts.batchIndex % batchCount) + batchCount) % batchCount
    : Math.floor(new Date().getUTCHours() / 2) % batchCount;
  const slice = students.slice(idx * BATCH, idx * BATCH + BATCH);

  const startedAt = Date.now();
  let processed = 0, notified = 0, errors = 0, timedOut = false;
  for (const s of slice) {
    /* Hard time budget: stop gracefully rather than be killed mid-loop, so
       every baseline we DID reach is already persisted. */
    if (Date.now() - startedAt > 22000) { timedOut = true; break; }
    try {
      const n = await checkStudentResult(env, s.student_id, s.dob, endpointMap[s.student_id] || []);
      processed++;
      if (n) notified += n;
    } catch { errors++; }
    await new Promise(r => setTimeout(r, 300)); /* be gentle on the LU portal */
  }
  return `batch=${idx}/${batchCount} size=${slice.length} processed=${processed} notified=${notified} errors=${errors}${timedOut ? ' TIMEBUDGET' : ''}`;
}

async function checkStudentResult(env, studentId, dob, endpoints) {
  if (!dob) return;

  /* Fetch result from LU portal (nonce-aware, retries once on invalid_nonce).
     Monitor needs fresh data to detect changes, so it bypasses the result cache. */
  let text;
  try {
    text = await luGetResult(env, studentId, dob, false);
    if (/invalid_nonce/.test(text)) text = await luGetResult(env, studentId, dob, true);
  } catch { return; }
  if (text.trimStart().startsWith('<')) return;

  let data;
  try { data = JSON.parse(text); } catch { return; }
  /* LU shape: { success, results: { "<year>": [ {courses:[{course_code,
     course_title,grade,...}], name:"Spring 2022", ... }, ... ], ... } } */
  if (!data?.success || !data.results || typeof data.results !== 'object') return;

  /* Flatten every graded course across all years/semesters */
  const courses = [];
  for (const yearVal of Object.values(data.results)) {
    const sems = Array.isArray(yearVal) ? yearVal : Object.values(yearVal || {});
    for (const sem of sems) {
      const semName = (sem && sem.name) ? String(sem.name).trim() : '';
      for (const c of (sem?.courses || [])) {
        const code  = (c.course_code || '').trim().toUpperCase();
        const grade = (c.grade || '').trim();
        if (!code || !grade) continue;
        courses.push({ code, name: (c.course_title || '').trim(), grade, sem: semName });
      }
    }
  }
  if (!courses.length) return;
  courses.sort((a, b) => (a.sem + a.code).localeCompare(b.sem + b.code));

  /* Compare with stored state — a new course OR a changed grade = new result */
  const stateKey = `result_${studentId}`;
  const sig      = courses.map(c => `${c.sem}|${c.code}|${c.grade}`);
  const hash     = await sha256(JSON.stringify(sig));
  const stored   = await supabaseGetState(env, stateKey);

  if (!stored) {
    await supabaseUpsertState(env, stateKey, hash, { courses });
    return;
  }
  if (stored.state_hash === hash) return;

  const storedSig = new Set((stored.state_data?.courses || [])
    .map(c => `${c.sem || ''}|${c.code}|${c.grade || ''}`));
  const newCourses = courses.filter(c => !storedSig.has(`${c.sem}|${c.code}|${c.grade}`));
  if (!newCourses.length) {
    await supabaseUpsertState(env, stateKey, hash, { courses });
    return;
  }

  /* Insert personalized notification (student_id set → only that student sees it) */
  const count    = newCourses.length;
  const title    = `🎓 ${count === 1 ? 'New Result Published!' : `${count} New Results Published!`}`;
  const semLabel = newCourses[0].sem;
  const nbody    = newCourses.slice(0, 8).map(c => `• ${c.code}${c.name ? ' · ' + c.name : ''}: ${c.grade}`).join('\n')
    + (count > 8 ? `\n…and ${count - 8} more` : '')
    + (semLabel ? `\n${semLabel}` : '');
  await insertPersonalNotification(env, studentId, 'result', title, nbody, '/pages/result-dashboard.html');

  /* Send push only to this student's endpoints */
  const expired = [];
  for (const ep of endpoints) {
    const status = await sendWebPush(ep, env);
    if (status === 410) expired.push(ep);
  }
  for (const ep of expired) {
    await fetch(`${SUPA_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}`, {
      method: 'DELETE',
      headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
    }).catch(() => {});
  }

  await supabaseUpsertState(env, stateKey, hash, { courses });
  return count;   /* number of new results announced — surfaced in the heartbeat */
}

async function insertPersonalNotification(env, studentId, type, title, body, link) {
  await fetch(`${SUPA_URL}/rest/v1/notifications`, {
    method: 'POST',
    headers: {
      'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ type, title, body, link, student_id: studentId }),
  }).catch(() => {});
}

/* ════════════════════════════════════════════════════════════════════
   ENROLLED RETAKE / IMPROVE MONITOR  (per-student "My Courses")
   Source of truth: student_retake_enrollments  (= Profile → My Courses)
   Notifies a student ONLY about the exact course / batch / section
   they enrolled in, when its class routine or mid/final exam changes
   (incl. being removed from the sheet). Nothing if not enrolled.
   ════════════════════════════════════════════════════════════════════ */

async function checkEnrolledCourses(env) {
  if (!env.SUPA_KEY) return;

  /* 1. All enrollments (= every student's "My Courses") */
  const enrRes = await fetch(
    `${SUPA_URL}/rest/v1/student_retake_enrollments?select=student_id,course_code,course_name,batch,section,type`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!enrRes || !enrRes.ok) return;
  const enrollments = await enrRes.json();
  if (!enrollments.length) return;

  /* 2. Push endpoints grouped by student (in-app notif still works without push) */
  const subRes = await fetch(
    `${SUPA_URL}/rest/v1/push_subscriptions?select=endpoint,student_id&student_id=not.is.null`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  const subs = (subRes && subRes.ok) ? await subRes.json() : [];
  const endpointsByStudent = {};
  subs.forEach(s => { (endpointsByStudent[s.student_id] ||= []).push(s.endpoint); });

  /* 3. Fetch sheets ONCE — merge ALL links per keyword (Link 1 + Routine Link N),
        because an enrolled section may live only in a second sheet. */
  let classIds = await getRoutineSheetIdsByKeyword(env, 'class routine');
  if (!classIds.length) classIds = ['1jjOmSUg3U_uyzM0mtaj1FldEOD1nNeMCAhybEiQTW3M'];
  const classDayTabs = await fetchMergedDayTabs(env, classIds);
  const classSlots = buildClassSectionSlots(classDayTabs);

  const midTable   = await fetchMergedSingleTab(await getRoutineSheetIdsByKeyword(env, 'mid term'));
  const finalTable = await fetchMergedSingleTab(await getRoutineSheetIdsByKeyword(env, 'final term'));
  const examCache = {};

  /* 4. Per-enrollment diff */
  for (const enr of enrollments) {
    await processEnrollment(env, enr, {
      classSlots, midTable, finalTable, examCache, endpointsByStudent,
    }).catch(() => {});
  }
}

async function processEnrollment(env, enr, ctx) {
  const studentId = enr.student_id;
  const batch     = String(enr.batch || '').trim();
  const section   = String(enr.section || '').trim();
  const code      = String(enr.course_code || '').trim().toUpperCase();
  if (!studentId || !batch || !section || !code) return;

  const typeLabel  = enr.type === 'improve' ? 'Improve' : 'Retake';
  const courseName = enr.course_name || '';
  const endpoints  = ctx.endpointsByStudent[studentId] || [];
  const secKey     = `${batch}-${section}`;
  const stateBase  = `${sanitizeKey(studentId)}_${sanitizeKey(batch)}${sanitizeKey(section)}_${sanitizeKey(code)}`;

  /* ── Class routine ── */
  const curClassSlots = (ctx.classSlots[secKey]?.[code] || [])
    .map(s => ({ day: s.day, time: s.time, teacher: s.teacher, room: s.room, code }))
    .sort((a, b) => `${a.day}${a.time}`.localeCompare(`${b.day}${b.time}`));

  await diffClassAndNotify(env, {
    key: `enr_class_${stateBase}`, studentId, endpoints,
    code, batch, section, typeLabel, courseName, current: curClassSlots,
  });

  /* ── Mid / Final exams ── */
  if (ctx.midTable) {
    const exam = getExamForCourse(ctx.examCache, 'mid', ctx.midTable, batch, section, code);
    await diffExamAndNotify(env, {
      key: `enr_mid_${stateBase}`, examType: 'mid', studentId, endpoints,
      code, batch, section, typeLabel, courseName, current: exam,
    });
  }
  if (ctx.finalTable) {
    const exam = getExamForCourse(ctx.examCache, 'final', ctx.finalTable, batch, section, code);
    await diffExamAndNotify(env, {
      key: `enr_final_${stateBase}`, examType: 'final', studentId, endpoints,
      code, batch, section, typeLabel, courseName, current: exam,
    });
  }
}

async function diffClassAndNotify(env, p) {
  const { key, studentId, endpoints, code, batch, section, typeLabel, courseName, current } = p;
  const hash   = await sha256(JSON.stringify(current));
  const stored = await supabaseGetState(env, key);

  if (!stored) { await supabaseUpsertState(env, key, hash, { slots: current }); return; }
  if (stored.state_hash === hash) return;

  const changes = computeSlotDiff(stored.state_data?.slots || [], current);
  await supabaseUpsertState(env, key, hash, { slots: current });
  if (!changes.length) return;

  const title = `🔁 ${typeLabel} Class Updated`;
  const body  = `${code}${courseName ? ' · ' + courseName : ''} (${batch}${section})\n`
              + changes.slice(0, 6).join('\n');
  await insertPersonalNotification(env, studentId, 'retake_class', title, body, '/pages/info.html');
  await pushToEndpoints(env, endpoints);
}

async function diffExamAndNotify(env, p) {
  const { key, examType, studentId, endpoints, code, batch, section, typeLabel, courseName, current } = p;
  const norm   = current ? { date: current.date, time: current.time } : null;
  const hash   = await sha256(JSON.stringify(norm));
  const stored = await supabaseGetState(env, key);

  if (!stored) { await supabaseUpsertState(env, key, hash, { exam: norm }); return; }
  if (stored.state_hash === hash) return;

  const old = stored.state_data?.exam || null;
  await supabaseUpsertState(env, key, hash, { exam: norm });

  const label = examType === 'mid' ? 'Mid' : 'Final';
  const lines = [];
  if (old && !norm) {
    lines.push(`Removed from ${label} exam routine`);
  } else if (!old && norm) {
    lines.push(`Scheduled: ${fmtExamDateWorker(norm.date)}${norm.time ? ', ' + norm.time : ''}`);
  } else if (old && norm) {
    if (old.date !== norm.date) lines.push(`Date: ${fmtExamDateWorker(old.date)} → ${fmtExamDateWorker(norm.date)}`);
    if (old.time !== norm.time) lines.push(`Time: ${old.time || '?'} → ${norm.time || '?'}`);
  }
  if (!lines.length) return;

  const title = `📝 ${typeLabel} ${label} Exam Updated`;
  const body  = `${code}${courseName ? ' · ' + courseName : ''} (${batch}${section})\n` + lines.join('\n');
  await insertPersonalNotification(env, studentId, `retake_${examType}`, title, body, '/pages/info.html');
  await pushToEndpoints(env, endpoints);
}

async function pushToEndpoints(env, endpoints) {
  if (!env.VAPID_PRIVATE_KEY || !endpoints || !endpoints.length) return;
  const expired = [];
  for (const ep of endpoints) {
    const status = await sendWebPush(ep, env);
    if (status === 410) expired.push(ep);
  }
  for (const ep of expired) {
    await fetch(`${SUPA_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}`, {
      method: 'DELETE',
      headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
    }).catch(() => {});
  }
}

function sanitizeKey(s) { return String(s).replace(/[^a-zA-Z0-9]/g, ''); }

/* ── Class routine: build {`batch-section`: {CODE: [{day,time,teacher,room}]}} ── */
function buildClassSectionSlots(dayTabs) {
  const sectionCourseSlots = {};
  MONITOR_DAYS.forEach((dayName, idx) => {
    const table = dayTabs[idx];
    if (!table) return;
    const rows = table.rows || [];
    const cols = table.cols || [];
    if (!rows.length) return;

    let timeSlots = cols.slice(3).map(c => (c.label || '').trim());
    let dataStart = 0;
    if (!timeSlots.some(t => /\d+:\d+/.test(t))) {
      for (let r = 0; r < Math.min(rows.length, 3); r++) {
        const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
        if (cells.slice(3).some(c => /\d+:\d+/.test(c))) {
          timeSlots = cells.slice(3); dataStart = r + 1; break;
        }
      }
    }

    /* Break slot detection by majority vote */
    const breakCounts = {};
    for (let r = dataStart; r < rows.length; r++) {
      (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '').slice(3)
        .forEach((cell, i) => { if (cell.toUpperCase() === 'BREAK') breakCounts[i] = (breakCounts[i] || 0) + 1; });
    }
    let breakSlotIdx = -1, maxBrk = 0;
    Object.entries(breakCounts).forEach(([k, cnt]) => { if (cnt > maxBrk) { maxBrk = cnt; breakSlotIdx = parseInt(k); } });

    for (let r = dataStart; r < rows.length; r++) {
      const cells   = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
      const batch   = (cells[1] || '').replace(/\.0+$/, '');
      const section = (cells[2] || '').trim().toUpperCase();
      if (!batch || !section) continue;
      const key = `${batch}-${section}`;

      cells.slice(3).forEach((cell, i) => {
        if (!cell || cell.toUpperCase() === 'BREAK' || i === breakSlotIdx) return;
        const parsed = parseClassCellWorker(cell);
        if (!parsed?.code) return;
        const time = timeSlots[i] || '';
        if (!time || !/\d+:\d+/.test(time)) return;
        const codeUp = parsed.code.toUpperCase();

        if (!sectionCourseSlots[key]) sectionCourseSlots[key] = {};
        if (!sectionCourseSlots[key][codeUp]) sectionCourseSlots[key][codeUp] = [];
        const dup = sectionCourseSlots[key][codeUp].some(s => s.day === dayName && s.time === time);
        if (!dup) sectionCourseSlots[key][codeUp].push({
          day: dayName, time, teacher: parsed.initials || '', room: parsed.room || '',
        });
      });
    }
  });
  return sectionCourseSlots;
}

/* Parse "CSE-3214 MSR ACL-3" → { code, initials, room } */
function parseClassCellWorker(cell) {
  if (!cell) return null;
  cell = cell.trim();
  if (!cell || cell === '--' || cell === '–') return null;
  const parts = cell.split(/\s+/).filter(Boolean);
  if (parts.length >= 3) return { code: parts[0], initials: parts[1], room: parts.slice(2).join(' ') };
  if (parts.length === 2) return { code: parts[0], initials: '', room: parts[1] };
  return parts.length ? { code: parts[0], initials: '', room: '' } : null;
}

/* ── Exam routine: find a course's exam for a batch/section (cached) ── */
function getExamForCourse(cache, examType, table, batch, section, code) {
  const ck = `${examType}|${batch}-${section}`;
  if (!cache[ck]) cache[ck] = parseExamRoutineWorker(table, batch, section) || [];
  const hit = cache[ck].find(e => e.course.toUpperCase() === code.toUpperCase());
  return hit ? { date: hit.date, time: hit.time, weekday: hit.weekday, label: hit.label } : null;
}

function normExamDateWorker(raw) {
  if (!raw) return '';
  const num = parseFloat(String(raw).trim());
  if (!isNaN(num) && num > 40000 && num < 60000) {
    const d   = new Date(Math.round((num - 25569) * 86400 * 1000));
    const utc = new Date(d.getTime() + d.getTimezoneOffset() * 60000);
    return `${String(utc.getDate()).padStart(2,'0')}-${String(utc.getMonth()+1).padStart(2,'0')}-${utc.getFullYear()}`;
  }
  const dm = String(raw).match(/^Date\((\d+),(\d+),(\d+)/);
  if (dm) {
    const d = new Date(+dm[1], +dm[2], +dm[3]);
    return `${String(d.getDate()).padStart(2,'0')}-${String(d.getMonth()+1).padStart(2,'0')}-${d.getFullYear()}`;
  }
  return String(raw).trim();
}

function fmtExamDateWorker(s) {
  const m = (s || '').match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
  if (!m) return s || '';
  const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${parseInt(m[1])} ${MON[parseInt(m[2]) - 1]} ${m[3]}`;
}

/* Ported from pages/info/exam.js parseExamRoutine — takes a gviz table directly */
function parseExamRoutineWorker(table, targetBatch, targetSection) {
  if (!table) return null;

  const allRows = (table.rows || []).map(r =>
    (r.c || []).map(c => {
      if (!c || c.v == null) return '';
      return normExamDateWorker(c.v) || String(c.v).trim();
    })
  );

  const colLabels = (table.cols || []).map(c => String(c.label || '').trim());
  if (colLabels.some(l => /day[\s\-]*\d+/i.test(l))) {
    const synRow = colLabels.map(l => {
      const m = l.match(/day[\s\-]*(\d+)/i);
      return m ? `Day-${m[1]}` : '';
    });
    allRows.unshift(synRow);
  }

  const blockStarts = [];
  for (let r = 0; r < allRows.length; r++) {
    for (let c = 0; c < allRows[r].length; c++) {
      if (/^\s*day[\s\-]*\d+\s*$/i.test(allRows[r][c])) { blockStarts.push({ rowIdx: r, colIdx: c }); break; }
    }
  }
  if (blockStarts.length === 0) return null;

  let batchCol = 0, sectionCol = 1;
  for (let r = 0; r < Math.min(allRows.length, 15); r++) {
    (allRows[r] || []).forEach((cell, i) => {
      if (/^\s*batch\s*$/i.test(cell))   batchCol = i;
      if (/^\s*section\s*$/i.test(cell)) sectionCol = i;
    });
  }

  const tbNum = String(targetBatch).replace(/[^0-9]/g, '');
  const tsStr = String(targetSection).trim().toUpperCase();
  const allExams = [];

  blockStarts.forEach((block, blockIdx) => {
    const dayHeaderIdx = block.rowIdx;
    const nextBlockRow = blockStarts[blockIdx + 1] ? blockStarts[blockIdx + 1].rowIdx : allRows.length;

    const rowBatches = {};
    let lastBatch = '';
    for (let r = dayHeaderIdx; r < nextBlockRow; r++) {
      const batchCell = String(allRows[r][batchCol] || '').trim();
      if (batchCell && /\d/.test(batchCell) && !/^(date|time|day|section)/i.test(batchCell)) lastBatch = batchCell;
      rowBatches[r] = lastBatch;
    }

    const dayRow  = allRows[dayHeaderIdx] || [];
    const dayCols = dayRow.reduce((a, cell, i) => { if (/^\s*day[\s\-]*\d+\s*$/i.test(cell)) a.push(i); return a; }, []);

    let dateRowIdx = dayHeaderIdx + 1, timeRowIdx = dayHeaderIdx + 2, weekdayRowIdx = dayHeaderIdx + 3;
    if (dayCols.length > 0) {
      const sampleCol = dayCols[0];
      for (let i = 1; i <= 5; i++) {
        const rIdx = dayHeaderIdx + i;
        if (rIdx >= allRows.length || rIdx >= nextBlockRow) break;
        const cell = String(allRows[rIdx][sampleCol]).trim();
        if (/Date\(/i.test(cell) || /\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/.test(cell)) dateRowIdx = rIdx;
        else if (/\d{1,2}:\d{2}/.test(cell) || /am|pm/i.test(cell)) timeRowIdx = rIdx;
        else if (/^(sun|mon|tue|wed|thu|fri|sat)/i.test(cell)) weekdayRowIdx = rIdx;
      }
    }

    const dataStartRow = Math.max(dayHeaderIdx, dateRowIdx, timeRowIdx, weekdayRowIdx) + 1;
    const dateRow    = allRows[dateRowIdx]    || [];
    const timeRow    = allRows[timeRowIdx]    || [];
    const weekdayRow = allRows[weekdayRowIdx] || [];

    const examDays = dayCols.map(col => ({
      col, label: dayRow[col] || '', date: dateRow[col] || '',
      time: timeRow[col] || '', weekday: weekdayRow[col] || '',
    }));

    for (let r = dataStartRow; r < nextBlockRow; r++) {
      const row = allRows[r];
      if (!row) continue;
      const section = (row[sectionCol] || '').trim();
      if (!section || /^(section|day|date|time)$/i.test(section)) continue;
      const cbNum = String(rowBatches[r]).replace(/[^0-9]/g, '');
      const csStr = section.toUpperCase();
      const batchMatch   = cbNum && cbNum === tbNum;
      const sectionMatch = csStr === tsStr || csStr.split(/[+&,]/).map(s => s.trim()).includes(tsStr);
      if (batchMatch && sectionMatch) {
        examDays.forEach(day => {
          const raw    = row[day.col] || '';
          const course = raw.replace(/\s*\(\d+\)\s*/g, '').trim();
          if (course && course !== '--' && course !== '–') allExams.push({ ...day, course });
        });
      }
    }
  });

  return allExams.length ? allExams : null;
}

/* ════════════════════════════════════════════════════════════════════
   VAPID + WEB PUSH
   ════════════════════════════════════════════════════════════════════ */

function b64urlEncode(data) {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let str = '';
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function b64urlDecode(str) {
  const s = str.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(s + '='.repeat((4 - s.length % 4) % 4)), c => c.charCodeAt(0));
}

async function signVapidJwt(endpoint, env) {
  const { protocol, host } = new URL(endpoint);
  const now = Math.floor(Date.now() / 1000);
  const hdr = b64urlEncode(new TextEncoder().encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const pld = b64urlEncode(new TextEncoder().encode(JSON.stringify({ aud: `${protocol}//${host}`, exp: now + 43200, sub: env.VAPID_SUBJECT })));

  const pub = b64urlDecode(env.VAPID_PUBLIC_KEY);
  const jwk = { kty: 'EC', crv: 'P-256', x: b64urlEncode(pub.slice(1, 33)), y: b64urlEncode(pub.slice(33, 65)), d: env.VAPID_PRIVATE_KEY, key_ops: ['sign'] };
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${hdr}.${pld}`));
  return `vapid t=${hdr}.${pld}.${b64urlEncode(new Uint8Array(sig))},k=${env.VAPID_PUBLIC_KEY}`;
}

async function sendWebPush(endpoint, env) {
  try {
    const auth = await signVapidJwt(endpoint, env);
    const res  = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Authorization': auth, 'TTL': '86400', 'Content-Length': '0' },
    });
    return res.status;
  } catch { return 0; }
}

let _fcmAccessToken = '';
let _fcmAccessTokenExpires = 0;

function pemToBytes(pem) {
  const normalized = String(pem || '').replace(/\\n/g, '\n');
  const body = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  return Uint8Array.from(atob(body), c => c.charCodeAt(0));
}

async function firebaseAccessToken(env) {
  if (_fcmAccessToken && Date.now() < _fcmAccessTokenExpires - 60000) {
    return _fcmAccessToken;
  }
  if (!env.FIREBASE_CLIENT_EMAIL || !env.FIREBASE_PRIVATE_KEY) return '';
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlEncode(new TextEncoder().encode(JSON.stringify({
    alg: 'RS256', typ: 'JWT',
  })));
  const claims = b64urlEncode(new TextEncoder().encode(JSON.stringify({
    iss: env.FIREBASE_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(env.FIREBASE_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${b64urlEncode(new Uint8Array(signature))}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) return '';
  const data = await response.json();
  _fcmAccessToken = data.access_token || '';
  _fcmAccessTokenExpires = Date.now() + Number(data.expires_in || 3600) * 1000;
  return _fcmAccessToken;
}

async function latestPublicNotification(env) {
  const r = await fetch(
    `${SUPA_URL}/rest/v1/notifications?student_id=is.null&select=type,title,body,link&order=created_at.desc&limit=1`,
    { headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` } }
  ).catch(() => null);
  if (!r || !r.ok) return null;
  const rows = await r.json();
  return rows[0] || null;
}

async function sendFcmToAll(env, notification) {
  if (!env.FIREBASE_PROJECT_ID ||
      !env.FIREBASE_CLIENT_EMAIL ||
      !env.FIREBASE_PRIVATE_KEY) {
    return { status: 'not_configured' };
  }
  try {
    const accessToken = await firebaseAccessToken(env);
    if (!accessToken) return { status: 'auth_failed' };
    const title = String(notification?.title || 'CSE 62B Portal');
    const body = String(notification?.body || 'New update available.');
    const link = String(notification?.link || '/');
    const category = notificationCategory(notification?.type);
    const sendTopic = topic => fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            topic,
            notification: { title, body },
            data: {
              title,
              body,
              link,
              type: String(notification?.type || 'general'),
              category,
            },
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: 'lu62b_default',
                sound: 'default',
              },
            },
            apns: { payload: { aps: { sound: 'default' } } },
          },
        }),
      },
    );
    // all_users keeps older APKs working; new APKs unsubscribe from it and
    // receive only the categories enabled in Notification Preferences.
    const [legacy, preferred] = await Promise.all([
      sendTopic('all_users'),
      sendTopic(`notif_${category}`),
    ]);
    if (legacy.ok && preferred.ok) {
      return { status: 'sent', code: preferred.status, category };
    }
    return {
      status: 'partial',
      legacy_code: legacy.status,
      category_code: preferred.status,
      category,
    };
  } catch {
    return { status: 'error' };
  }
}

function notificationCategory(type) {
  const value = String(type || '').toLowerCase();
  if (value.includes('notice')) return 'notices';
  if (value.includes('classwork') || value.includes('deadline')) return 'classwork';
  if (value.includes('routine') || value.includes('exam')) return 'routine';
  if (value.includes('app_update')) return 'updates';
  return 'general';
}

async function sendPushToAll(env) {
  if (!env.SUPA_KEY) return { web: { status: 'not_configured' }, fcm: { status: 'not_configured' } };
  const notification = await latestPublicNotification(env);
  const category = notificationCategory(notification?.type);
  const fcmPromise = sendFcmToAll(env, notification);
  if (!env.VAPID_PRIVATE_KEY) {
    return { web: { status: 'not_configured' }, fcm: await fcmPromise };
  }
  const r = await fetch(`${SUPA_URL}/rest/v1/push_subscriptions?select=endpoint`, {
    headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
  }).catch(() => null);
  if (!r || !r.ok) {
    return { web: { status: 'subscription_fetch_failed' }, fcm: await fcmPromise };
  }
  const subs = await r.json();
  const expired = [];
  let delivered = 0;
  let skipped = 0;
  await Promise.allSettled(subs.map(async sub => {
    if (env.SMS_RATE) {
      try {
        const hash = await sha256(String(sub.endpoint));
        const raw = await env.SMS_RATE.get(`push-pref:${hash}`);
        if (raw && JSON.parse(raw)[category] === false) {
          skipped++;
          return;
        }
      } catch {}
    }
    const status = await sendWebPush(sub.endpoint, env);
    if (status >= 200 && status < 300) delivered++;
    if (status === 410) expired.push(sub.endpoint);
  }));
  for (const ep of expired) {
    await fetch(`${SUPA_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(ep)}`, {
      method: 'DELETE',
      headers: { 'apikey': env.SUPA_KEY, 'Authorization': `Bearer ${env.SUPA_KEY}` },
    }).catch(() => {});
  }
  return {
    web: {
      status: 'sent',
      delivered,
      total: subs.length,
      skipped,
      expired: expired.length,
    },
    fcm: await fcmPromise,
  };
}
