/* ─── Class Routine ─── */
/* Globals from info.html: getRoutineSheetId, fetchSheet, fetchDayTab,
   ROUTINE_DAY_NAMES, sheetRows, parseClassCell, timeToMin, courseColor,
   escH, DAY_DISPLAY, _doDownloadImg, _doDownloadPDF */

const _RT_SUPA = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const _RT_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

let _routineCache      = null;  /* currently displayed cache */
let _62bCache          = null;  /* always the 62B cache, preserved for restore */
let _improvedCache     = null;
let _routineTab        = 'regular';
let _rtLastEnrollments = [];
window._rtExcluded     = new Set();
let _customCourses     = [];

/* Multi-batch support */
let _allDayResults          = null;
let _allCourseInfo          = {};
let _teacherAcrMap          = {};   /* acronym → { name, desig } from CPG_Teachers */
let _semLabel               = 'Current Semester';
let _availableBatchSections = [];
let _selectedBatch          = '62';
let _selectedSection        = 'B';

/* ── Excluded courses: localStorage + Supabase ── */
function _rtLocalExcluded(userId) {
  try { return new Set(JSON.parse(localStorage.getItem(`lu62b_excl_${userId}`) || '[]')); }
  catch(e) { return new Set(); }
}

async function _rtSaveExcluded(userId, arr) {
  try { localStorage.setItem(`lu62b_excl_${userId}`, JSON.stringify(arr)); } catch(e) {}
  try {
    await fetch(`${_RT_SUPA}/rest/v1/student_manual_courses`, {
      method: 'POST',
      headers: {
        'apikey': _RT_KEY, 'Authorization': `Bearer ${_RT_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      },
      body: JSON.stringify({
        student_id: userId,
        excluded_courses: arr,
        updated_at: new Date().toISOString(),
      }),
    });
  } catch(e) {}
}

async function _rtLoadExcludedFromSupa(userId) {
  try {
    const r = await fetch(
      `${_RT_SUPA}/rest/v1/student_manual_courses?student_id=eq.${encodeURIComponent(userId)}&select=excluded_courses`,
      { headers: { 'apikey': _RT_KEY, 'Authorization': `Bearer ${_RT_KEY}` } }
    );
    if (!r.ok) return;
    const rows = await r.json();
    if (rows.length && Array.isArray(rows[0].excluded_courses)) {
      window._rtExcluded = new Set(rows[0].excluded_courses);
      try { localStorage.setItem(`lu62b_excl_${userId}`, JSON.stringify(rows[0].excluded_courses)); } catch(e) {}
    }
  } catch(e) {}
}

/* ── Custom courses: localStorage + Supabase ── */
function _rtLoadCustomCourses(userId) {
  try { return JSON.parse(localStorage.getItem(`lu62b_custom_courses_${userId}`) || '[]'); }
  catch(e) { return []; }
}
function _rtSaveCustomCourses(userId, courses) {
  try { localStorage.setItem(`lu62b_custom_courses_${userId}`, JSON.stringify(courses)); } catch(e) {}
}
async function _rtSaveCustomToSupa(userId, courses) {
  try {
    await fetch(`${_RT_SUPA}/rest/v1/student_custom_courses`, {
      method: 'POST',
      headers: {
        'apikey': _RT_KEY, 'Authorization': `Bearer ${_RT_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      },
      body: JSON.stringify({ student_id: userId, courses, updated_at: new Date().toISOString() }),
    });
  } catch(e) {}
}
async function _rtLoadCustomFromSupa(userId) {
  try {
    const r = await fetch(
      `${_RT_SUPA}/rest/v1/student_custom_courses?student_id=eq.${encodeURIComponent(userId)}&select=courses`,
      { headers: { 'apikey': _RT_KEY, 'Authorization': `Bearer ${_RT_KEY}` } }
    );
    if (!r.ok) return null;
    const rows = await r.json();
    return rows.length && Array.isArray(rows[0].courses) ? rows[0].courses : null;
  } catch(e) { return null; }
}
function _rtSaveCustomAll(userId, courses) {
  _rtSaveCustomCourses(userId, courses);
  _rtSaveCustomToSupa(userId, courses);
}

/* Custom courses carry a fixed day/time, so they go stale when the semester
   changes. Each one is tagged with the semester it was added in and only that
   semester's are applied; older ones stay stored (hidden), never deleted. */
function _rtCustomThisSem(courses) {
  return (courses || []).filter(c => c.sem === _semLabel);
}

/* Merge custom course entries into a cache copy, rebuilding groups so new times
   get their own column (the grid already handles slots at unlisted times). */
function _rtApplyCustom(baseCache, customCourses) {
  customCourses = _rtCustomThisSem(customCourses);
  if (!baseCache || !customCourses.length) return baseCache;
  const schedule = {};
  ROUTINE_DAY_NAMES.forEach(d => { schedule[d] = baseCache.schedule[d] ? [...baseCache.schedule[d]] : []; });
  customCourses.forEach(c => {
    if (!c.day || !ROUTINE_DAY_NAMES.includes(c.day)) return;
    schedule[c.day].push({
      time: c.time, code: c.code || 'CUSTOM', initials: c.teacher || '',
      room: c.room || '', isBreak: false, source: 'custom',
      name: c.name || '', _customId: c.id,
    });
  });
  const groups = buildTimeframeGroups(schedule, baseCache.dayTimeframes);
  if (!groups.length) return baseCache;
  return { ...baseCache, schedule, groups,
           days: ROUTINE_DAY_NAMES.filter(d => schedule[d]?.some(s => !s.isBreak)) };
}

function _rtRebuildCaches() {
  if (_selectedBatch !== '62' || _selectedSection !== 'B') return;
  _routineCache = _rtApplyCustom(_62bCache, _customCourses);
  if (_rtLastEnrollments.length) {
    _improvedCache = _rtApplyCustom(_buildImprovedCache(_rtLastEnrollments), _customCourses);
  }
  const todayName = ['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][new Date().getDay()];
  const el = document.getElementById('rt-main-content');
  if (el) el.innerHTML = buildGrid(todayName);
}

function _rtRenderCustomList() {
  const list = document.getElementById('rt-cc-list');
  if (!list) return;
  const active = _rtCustomThisSem(_customCourses);
  const hidden = _customCourses.length - active.length;
  const oldNote = hidden ? `<p style="font-size:0.66rem;color:var(--text-secondary);text-align:center;margin:8px 0 0;opacity:.7;">
    ${hidden} custom course${hidden !== 1 ? 's' : ''} from an earlier semester hidden.</p>` : '';
  if (!active.length) {
    list.innerHTML = `<p style="font-size:0.7rem;color:var(--text-secondary);text-align:center;margin:8px 0 0;">No custom courses added yet.</p>${oldNote}`;
    return;
  }
  const dayShort = { SATURDAY:'Sat', SUNDAY:'Sun', MONDAY:'Mon', TUESDAY:'Tue', WEDNESDAY:'Wed', THURSDAY:'Thu', FRIDAY:'Fri' };
  list.innerHTML = oldNote + active.map(c => `
    <div style="display:flex;align-items:center;gap:10px;padding:8px 12px;border-radius:9px;
      border:1px solid var(--border);background:rgba(16,185,129,.05);margin-bottom:6px;">
      <span style="width:6px;height:6px;border-radius:50%;background:#10b981;flex-shrink:0;"></span>
      <div style="flex:1;min-width:0;">
        <div style="font-size:0.75rem;font-weight:700;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${escH(c.name)}</div>
        <div style="font-size:0.65rem;color:var(--text-secondary);margin-top:1px;">
          ${escH(dayShort[c.day] || c.day)} · ${escH(c.time)}${c.teacher ? ` · ${escH(c.teacher)}` : ''}${c.room ? ` · ${escH(c.room)}` : ''}${c.code ? ` · <span style="font-family:monospace;">${escH(c.code)}</span>` : ''}
        </div>
      </div>
      <button onclick="_rtDeleteCustomCourse('${escH(c.id)}')"
        style="background:rgba(244,63,94,.12);border:none;color:#f43f5e;border-radius:6px;
        padding:3px 9px;cursor:pointer;font-size:0.68rem;font-weight:600;flex-shrink:0;font-family:'Inter',sans-serif;">
        Remove
      </button>
    </div>`).join('');
}

/* ── Custom course form: dropdown suggestion helpers ── */
function _rtCcRenderSugg(suggId, items) {
  const sugg = document.getElementById(suggId);
  if (!sugg) return;
  if (!items.length) { sugg.style.display = 'none'; return; }
  sugg.style.display = 'block';
  sugg.innerHTML = items.map(i => `
    <div style="padding:9px 14px;cursor:pointer;font-size:0.78rem;
      border-bottom:1px solid rgba(255,255,255,0.05);transition:background 0.12s;"
      onmouseover="this.style.background='rgba(124,58,237,0.12)'"
      onmouseout="this.style.background=''"
      onmousedown="_rtCcPickItem(this)"
      data-target="${escH(i.target)}" data-value="${escH(i.value)}"
      ${i.also ? `data-also="${escH(i.also)}" data-also-val="${escH(i.alsoVal||'')}"` : ''}
      data-sugg="${escH(suggId)}">
      <div style="font-weight:700;color:var(--text);">${escH(i.label)}</div>
      ${i.sub ? `<div style="font-size:0.68rem;color:var(--text-secondary);margin-top:2px;">${i.sub}</div>` : ''}
    </div>`).join('');
}

window._rtCcPickItem = function(el) {
  const targetEl = document.getElementById(el.dataset.target);
  if (targetEl) targetEl.value = el.dataset.value;
  if (el.dataset.also && el.dataset.alsoVal) {
    const alsoEl = document.getElementById(el.dataset.also);
    if (alsoEl && !alsoEl.value) alsoEl.value = el.dataset.alsoVal;
  }
  const suggEl = document.getElementById(el.dataset.sugg);
  if (suggEl) suggEl.style.display = 'none';
};

window._rtCcBlur = function(suggId) {
  setTimeout(() => { const el = document.getElementById(suggId); if (el) el.style.display = 'none'; }, 150);
};

window._rtCcInputName = function(val) {
  if (!val) { const s = document.getElementById('rt-cc-name-sugg'); if (s) s.style.display = 'none'; return; }
  const q = val.toLowerCase();
  _rtCcRenderSugg('rt-cc-name-sugg',
    Object.entries(_allCourseInfo)
      .filter(([code, i]) => i.name && (i.name.toLowerCase().includes(q) || code.toLowerCase().includes(q)))
      .sort(([, a], [, b]) => {
        const as = a.name.toLowerCase().startsWith(q), bs = b.name.toLowerCase().startsWith(q);
        return as === bs ? a.name.localeCompare(b.name) : as ? -1 : 1;
      })
      .slice(0, 8)
      .map(([code, i]) => ({
        target: 'rt-cc-name', value: i.name, also: 'rt-cc-code', alsoVal: code,
        label: i.name,
        sub: `<span style="font-family:monospace;color:var(--accent-bright);">${escH(code)}</span>`,
      }))
  );
};

window._rtCcInputCode = function(val) {
  if (!val) { const s = document.getElementById('rt-cc-code-sugg'); if (s) s.style.display = 'none'; return; }
  const q = val.toLowerCase();
  _rtCcRenderSugg('rt-cc-code-sugg',
    Object.entries(_allCourseInfo)
      .filter(([code, i]) => code.toLowerCase().includes(q) || (i.name && i.name.toLowerCase().includes(q)))
      .sort(([a], [b]) => {
        const as = a.toLowerCase().startsWith(q), bs = b.toLowerCase().startsWith(q);
        return as === bs ? a.localeCompare(b) : as ? -1 : 1;
      })
      .slice(0, 8)
      .map(([code, i]) => ({
        target: 'rt-cc-code', value: code, also: 'rt-cc-name', alsoVal: i.name,
        label: code, sub: i.name ? escH(i.name) : '',
      }))
  );
};

window._rtCcInputTeacher = function(val) {
  if (!val) { const s = document.getElementById('rt-cc-teacher-sugg'); if (s) s.style.display = 'none'; return; }
  const q = val.toLowerCase();
  _rtCcRenderSugg('rt-cc-teacher-sugg',
    Object.entries(_teacherAcrMap)
      .filter(([acr, t]) => t.name && (t.name.toLowerCase().includes(q) || acr.toLowerCase().includes(q)))
      .sort(([, a], [, b]) => {
        const as = a.name.toLowerCase().startsWith(q), bs = b.name.toLowerCase().startsWith(q);
        return as === bs ? a.name.localeCompare(b.name) : as ? -1 : 1;
      })
      .slice(0, 8)
      .map(([acr, t]) => ({
        target: 'rt-cc-teacher', value: acr,
        label: t.name,
        sub: `<span style="font-family:monospace;color:var(--accent-bright);">${escH(acr)}</span>${t.desig ? ` · ${escH(t.desig)}` : ''}`,
      }))
  );
};

window._rtCcInputTime = function(val) {
  const sugg = document.getElementById('rt-cc-time-sugg');
  if (!sugg) return;
  const allTimeMap = new Map();
  ROUTINE_DAY_NAMES.forEach(day =>
    (_62bCache?.dayTimeframes?.[day] || []).forEach(t => {
      const k = timeToMin(t); if (!allTimeMap.has(k)) allTimeMap.set(k, t);
    })
  );
  const times = [...allTimeMap.entries()].sort(([a], [b]) => a - b).map(([, t]) => t);
  const q = val.replace(/\s/g, '').toLowerCase();
  const filtered = val ? times.filter(t => t.replace(/\s/g, '').toLowerCase().includes(q)) : times;
  if (!filtered.length) { sugg.style.display = 'none'; return; }
  sugg.style.display = 'block';
  sugg.innerHTML = filtered.slice(0, 10).map(t => `
    <div style="padding:9px 14px;cursor:pointer;font-size:0.78rem;font-family:monospace;
      border-bottom:1px solid rgba(255,255,255,0.05);transition:background 0.12s;color:var(--text);"
      onmouseover="this.style.background='rgba(124,58,237,0.12)'"
      onmouseout="this.style.background=''"
      onmousedown="_rtCcPickTime(this)" data-val="${escH(t)}">${escH(t)}</div>`).join('');
};

window._rtCcPickTime = function(el) {
  const timeEl = document.getElementById('rt-cc-time');
  if (timeEl) timeEl.value = el.dataset.val;
  const sugg = document.getElementById('rt-cc-time-sugg');
  if (sugg) sugg.style.display = 'none';
};

window._rtOpenCustomCourses = function() {
  const existing = document.getElementById('rt-custom-panel');
  if (existing) { existing.remove(); return; }

  const inp = `width:100%;box-sizing:border-box;font-size:0.75rem;font-family:'Inter',sans-serif;
    color:var(--text);background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:7px 10px;outline:none;`;
  const suggBox = `display:none;position:absolute;top:calc(100% + 4px);left:0;right:0;
    background:var(--surface,#1e1e2e);border:1px solid var(--border);border-radius:10px;
    box-shadow:0 10px 36px rgba(0,0,0,0.7);z-index:9999;max-height:210px;overflow-y:auto;`;
  const dayOpts = ['SATURDAY','SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY']
    .map(d => `<option value="${d}">${d.charAt(0) + d.slice(1).toLowerCase()}</option>`).join('');

  const panel = document.createElement('div');
  panel.id = 'rt-custom-panel';
  panel.style.cssText = `background:var(--card);border:1px solid var(--border);border-radius:14px;padding:18px;margin-bottom:14px;`;
  panel.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
      <span style="font-size:0.82rem;font-weight:700;color:var(--text);">
        <i class="fa-solid fa-circle-plus" style="color:#10b981;margin-right:6px;font-size:0.75rem;"></i>Custom Courses
      </span>
      <button onclick="document.getElementById('rt-custom-panel').remove()"
        style="background:none;border:none;color:var(--text-secondary);cursor:pointer;font-size:0.9rem;">✕</button>
    </div>
    <p style="font-size:0.7rem;color:var(--text-secondary);margin:0 0 12px;line-height:1.6;">
      Add any course not in the Google Sheet — retake from another batch, OL class, or anything else.
      These show in your routine and <strong>can conflict</strong> with other classes.
    </p>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px;">
      <div style="position:relative;">
        <input id="rt-cc-name" placeholder="Course Name *" autocomplete="off"
          oninput="_rtCcInputName(this.value)" onblur="_rtCcBlur('rt-cc-name-sugg')" style="${inp}">
        <div id="rt-cc-name-sugg" style="${suggBox}"></div>
      </div>
      <div style="position:relative;">
        <input id="rt-cc-code" placeholder="Code (e.g. CSE-3201)" autocomplete="off"
          oninput="_rtCcInputCode(this.value)" onblur="_rtCcBlur('rt-cc-code-sugg')" style="${inp}">
        <div id="rt-cc-code-sugg" style="${suggBox}"></div>
      </div>
      <div style="position:relative;">
        <input id="rt-cc-teacher" placeholder="Teacher (optional)" autocomplete="off"
          oninput="_rtCcInputTeacher(this.value)" onblur="_rtCcBlur('rt-cc-teacher-sugg')" style="${inp}">
        <div id="rt-cc-teacher-sugg" style="${suggBox}"></div>
      </div>
      <input id="rt-cc-room" placeholder="Room (optional)" autocomplete="off" style="${inp}">
      <select id="rt-cc-day" style="${inp}cursor:pointer;">
        <option value="">Select Day *</option>${dayOpts}
      </select>
      <div style="position:relative;">
        <input id="rt-cc-time" placeholder="Time e.g. 09:00 - 10:30 *" autocomplete="off"
          oninput="_rtCcInputTime(this.value)" onfocus="_rtCcInputTime(this.value)" onblur="_rtCcBlur('rt-cc-time-sugg')" style="${inp}">
        <div id="rt-cc-time-sugg" style="${suggBox}"></div>
      </div>
    </div>
    <button onclick="_rtAddCustomCourse()"
      style="width:100%;padding:8px;border-radius:9px;background:linear-gradient(135deg,#10b981,#059669);
      color:#fff;font-weight:700;font-size:0.8rem;border:none;cursor:pointer;font-family:'Inter',sans-serif;margin-bottom:14px;">
      <i class="fa-solid fa-plus"></i> Add to Routine
    </button>
    <div id="rt-cc-list"></div>`;

  document.getElementById('rt-main-content')?.parentNode.insertBefore(panel, document.getElementById('rt-main-content'));
  _rtRenderCustomList();
};

window._rtAddCustomCourse = function() {
  const name    = document.getElementById('rt-cc-name')?.value.trim();
  const code    = document.getElementById('rt-cc-code')?.value.trim();
  const teacher = document.getElementById('rt-cc-teacher')?.value.trim();
  const room    = document.getElementById('rt-cc-room')?.value.trim();
  const day     = document.getElementById('rt-cc-day')?.value;
  const time    = document.getElementById('rt-cc-time')?.value.trim();

  if (!name || !day || !time) { alert('Course Name, Day, and Time are required.'); return; }
  if (!/\d+:\d+/.test(time))  { alert('Time must be a range like 09:00 - 10:30'); return; }

  _customCourses = [..._customCourses, { id: `custom_${Date.now()}`, name, code, teacher, room, day, time, sem: _semLabel }];
  const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  if (user?.id) _rtSaveCustomAll(user.id, _customCourses);

  ['rt-cc-name','rt-cc-code','rt-cc-teacher','rt-cc-room','rt-cc-time'].forEach(id => {
    const el = document.getElementById(id); if (el) el.value = '';
  });
  const dayEl = document.getElementById('rt-cc-day'); if (dayEl) dayEl.value = '';

  _rtRenderCustomList();
  _rtRebuildCaches();
};

window._rtDeleteCustomCourse = function(id) {
  _customCourses = _customCourses.filter(c => c.id !== id);
  const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  if (user?.id) _rtSaveCustomAll(user.id, _customCourses);
  _rtRenderCustomList();
  _rtRebuildCaches();
};

/* ── Fetch enrolled retake/improve sections ── */
async function _rtFetchEnrollments(userId) {
  return window.fetchEnrollments(userId);
}

/* Re-read each enrollment's slots from the live routine (the stored snapshot
   is from whichever semester the student enrolled in) and drop the ones the
   current routine no longer offers, so old-semester sections can't clash. */
function _rtLiveEnrollments(enrollments) {
  if (!_allDayResults) return enrollments;
  const live = buildSectionCourseSlots(_allDayResults);
  return enrollments
    .map(e => ({ ...e, schedule: liveEnrollmentSlots(e, live) }))
    .filter(e => e.schedule.length);
}

/* ── Build improved cache (62B selected courses + enrolled) ── */
function _buildImprovedCache(enrollments) {
  if (!_62bCache || !enrollments.length) return null;

  const excl = window._rtExcluded;
  const schedule = {};
  ROUTINE_DAY_NAMES.forEach(day => {
    if (_62bCache.schedule[day]) {
      schedule[day] = _62bCache.schedule[day]
        .filter(s => s.isBreak || !excl.has(s.code))
        .map(s => ({ ...s, source: '62b' }));
    }
  });

  enrollments.forEach(e => {
    (e.schedule || []).forEach(s => {
      const day = s.day;
      if (!day) return;
      if (!schedule[day]) schedule[day] = [];
      schedule[day].push({
        time: s.time, code: e.course_code,
        initials: s.initials || e.teacher || '',
        room: s.room || '', isBreak: false, source: e.type,
        name: e.course_name || '',
      });
    });
  });

  const groups = buildTimeframeGroups(schedule, _62bCache.dayTimeframes);
  if (!groups.length) return null;

  const days = ROUTINE_DAY_NAMES.filter(d => schedule[d]?.some(s => !s.isBreak));
  return { days, schedule, courseInfo: _62bCache.courseInfo, groups,
           dayTimeframes: _62bCache.dayTimeframes, semester: _62bCache.semester };
}

/* ── Scan all day results to find unique batch/section combos ── */
function _scanBatchSections(dayResults) {
  const seen   = new Set();
  const combos = [];
  dayResults.forEach(data => {
    if (!data?.table) return;
    const rows = data.table.rows || [];
    const cols = data.table.cols || [];
    let timeSlots = cols.slice(3).map(c => (c.label||'').trim());
    let dataStart = 0;
    if (!timeSlots.some(t => /\d+:\d+/.test(t))) {
      for (let r = 0; r < Math.min(rows.length, 3); r++) {
        const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
        if (cells.slice(3).some(c => /\d+:\d+/.test(c))) { dataStart = r + 1; break; }
      }
    }
    for (let r = dataStart; r < rows.length; r++) {
      const cells   = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
      const batch   = (cells[1]?.trim() || '').replace(/\.0+$/, '');
      const section = cells[2]?.trim()?.toUpperCase();
      if (batch && /^\d+$/.test(batch) && section && /^[A-Z]$/.test(section)) {
        const key = `${batch}-${section}`;
        if (!seen.has(key)) { seen.add(key); combos.push({ batch, section }); }
      }
    }
  });
  return combos.sort((a, b) => {
    const bd = parseInt(b.batch) - parseInt(a.batch);
    return bd !== 0 ? bd : a.section.localeCompare(b.section);
  });
}

/* ── Build a schedule object for any batch/section from stored day results ── */
function _buildScheduleFor(batch, section) {
  const schedule      = {};
  const sheetTimes    = new Map(); /* all time slots from sheet, including empty ones */
  const dayTimeframes = {};        /* dayName → that day's full list of time columns */

  ROUTINE_DAY_NAMES.forEach((dayName, idx) => {
    const data = _allDayResults[idx];
    if (!data?.table) return;
    const rows = data.table.rows || [];
    const cols = data.table.cols || [];
    if (!rows.length) return;

    let timeSlots = cols.slice(3).map(c => (c.label||'').trim());
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
      const rowBatch = String(cells[1]?.trim() || '').replace(/\.0+$/, '');
      if (rowBatch === batch && cells[2]?.trim().toUpperCase() === section) targetRows.push(cells);
    }
    if (!targetRows.length) return;

    const mergedCells = targetRows[0].slice(3).map((_, i) =>
      targetRows.map(r => r.slice(3)[i]).find(v => v && v.toUpperCase() !== 'BREAK') || ''
    );

    const daySchedule = [];
    timeSlots.forEach((time, i) => {
      if (!time) return;
      if (i === breakSlotIdx) { daySchedule.push({ isBreak: true, time }); return; }
      const parsed = parseClassCell(mergedCells[i]);
      if (parsed) daySchedule.push({ time, ...parsed, source: '62b' });
    });

    /* Only collect time slots from days where this section actually has classes */
    if (daySchedule.some(s => !s.isBreak)) {
      schedule[dayName] = daySchedule;
      dayTimeframes[dayName] = timeSlots.filter(t => t && /\d+:\d+/.test(t));
      timeSlots.forEach(t => {
        if (t && /\d+:\d+/.test(t)) {
          const k = timeToMin(t);
          if (!sheetTimes.has(k)) sheetTimes.set(k, t);
        }
      });
    }
  });
  return { schedule, sheetTimes, dayTimeframes };
}

/* ── Build a full cache object from a schedule ── */
function _scheduleToCacheWith(schedule, courseInfo, sem, sheetTimes, dayTimeframes) {
  const days = ROUTINE_DAY_NAMES.filter(d => schedule[d]);
  if (!days.length) return null;

  /* Group days by their timeframe so Friday (different time columns) renders
     under its own header instead of being forced into the Sat–Thu grid. */
  const groups = buildTimeframeGroups(schedule, dayTimeframes);
  if (!groups.length) return null;

  return { days, schedule, courseInfo, groups, dayTimeframes, semester: sem };
}

/* Resolve the teacher to display for a slot. The class routine itself is the
   source of truth: the cell carries the teacher's acronym (NJN, MNM, …), which
   is what actually changes when a teacher is swapped. We only expand that
   acronym to a full name via the CPG_Teachers tab (acronym → name, with titles
   like "Dr." already baked in). If the acronym isn't in CPG_Teachers we show
   the acronym itself; only when the cell has no acronym at all do we fall back
   to the CPG_Courses name. (CPG_Courses is never used to override a teacher the
   routine names — that table is maintained separately and would go stale.) */
function _rtResolveTeacher(slot, info) {
  const acr     = (slot.initials || '').trim().toUpperCase();
  const acrName = acr && _teacherAcrMap[acr] ? _teacherAcrMap[acr].name : '';

  if (acrName) return acrName;          /* routine acronym → CPG_Teachers full name */
  if (acr)     return slot.initials;    /* acronym not in CPG_Teachers → show it as-is */
  return info.teacher || '';            /* cell carries no acronym → fall back to CPG_Courses */
}

/* ── Render one course card ── */
function _rtRenderSlot(slot, courseInfo) {
  const color   = courseColor(slot.code);
  const info    = courseInfo[slot.code?.toUpperCase()] || {};
  const teacher = _rtResolveTeacher(slot, info);
  const name    = info.name || slot.name || '';
  const title   = name || slot.code || '';

  let borderColor = color + '55';
  let badge = '';
  if (slot.source === 'retake') {
    borderColor = 'rgba(244,63,94,.55)';
    badge = `<span style="font-size:0.52rem;font-weight:800;padding:1px 5px;border-radius:4px;
      background:rgba(244,63,94,.2);color:#f43f5e;letter-spacing:0.05em;display:block;margin-top:2px;">RETAKE</span>`;
  } else if (slot.source === 'improve') {
    borderColor = 'rgba(251,146,60,.55)';
    badge = `<span style="font-size:0.52rem;font-weight:800;padding:1px 5px;border-radius:4px;
      background:rgba(251,146,60,.2);color:#fb923c;letter-spacing:0.05em;display:block;margin-top:2px;">IMPROVE</span>`;
  } else if (slot.source === 'custom') {
    borderColor = 'rgba(16,185,129,.55)';
    badge = `<span style="font-size:0.52rem;font-weight:800;padding:1px 5px;border-radius:4px;
      background:rgba(16,185,129,.2);color:#10b981;letter-spacing:0.05em;display:block;margin-top:2px;">CUSTOM</span>`;
  }

  return `<div class="rt-gc" style="background:${color}12;border-color:${borderColor};margin-bottom:3px;">
    <span class="rt-gc-name" style="color:${color};font-weight:800;font-size:0.62rem;line-height:1.22;letter-spacing:0.01em;text-align:center;">${escH(title)}</span>
    ${name ? `<span class="rt-gc-code" style="color:${color};opacity:0.55;font-size:0.5rem;font-weight:700;letter-spacing:0.04em;">${escH(slot.code)}</span>` : ''}
    ${badge}
    ${teacher ? `<span class="rt-gc-teacher">${escH(teacher)}</span>` : ''}
    ${slot.room ? `<span class="rt-gc-room">${escH(slot.room)}</span>` : ''}
  </div>`;
}

/* ── Build the routine grid ── */
function buildGrid(todayName) {
  const isImproved = _routineTab === 'improved' && _improvedCache;
  const cache      = isImproved ? _improvedCache : _routineCache;
  if (!cache) return '';

  const { schedule, courseInfo, groups } = cache;
  if (!groups || !groups.length) return '<div class="rt-grid-empty-msg">No schedule data found.</div>';

  const excl  = window._rtExcluded;
  const is62b = _selectedBatch === '62' && _selectedSection === 'B';
  const batchLabel   = `Batch ${_selectedBatch}, Section ${_selectedSection}`;
  const captureTitle = isImproved
    ? `Class Routine — ${batchLabel} + Retake/Improve · ${cache.semester || ''}`
    : `Class Routine — ${batchLabel} · ${cache.semester || ''}`;

  /* One table per timeframe group (Sat–Thu, then a separate Friday if its
     time columns differ), rendered back-to-back inside one wrap. */
  const renderCourses = courses => courses
    .filter(s => (!isImproved && is62b ? (s.source === 'custom' || !excl.has(s.code)) : true))
    .map(s => _rtRenderSlot(s, courseInfo))
    .join('');

  const tables = groups.map((g, gi) => routineTableHTML(g, schedule, todayName, renderCourses, gi)).join('');

  let html = `<div id="rt-capture" class="rt-capture-area">
    <div class="rt-capture-title">
      <i class="fa-solid fa-calendar-week" style="margin-right:6px;color:var(--accent-bright);"></i>${captureTitle}
    </div>
    <div class="rt-grid-wrap">${tables}</div></div>
  <div class="rt-dl-bar">
    <button class="rt-dl-btn" onclick="downloadRoutineImage(this)">
      <i class="fa-solid fa-image"></i> Image Download
    </button>
    <button class="rt-dl-btn rt-dl-btn-pdf" onclick="downloadRoutinePDF(this)">
      <i class="fa-solid fa-file-pdf"></i> PDF Download
    </button>
  </div>`;

  return html;
}

/* ── Tab switch ── */
window.routineSwitchTab = function(tab) {
  _routineTab = tab;
  document.querySelectorAll('#rt-tab-bar .ri-tab').forEach(t => t.classList.remove('ri-tab-active'));
  document.getElementById(`rt-tab-${tab}`)?.classList.add('ri-tab-active');
  const todayName = ['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][new Date().getDay()];
  const el = document.getElementById('rt-main-content');
  if (el) el.innerHTML = buildGrid(todayName);
};

/* ── Batch/section selector: update section options when batch changes ── */
window._rtOnBatchChange = function() {
  const batchSel   = document.getElementById('rt-batch-select');
  const sectionSel = document.getElementById('rt-section-select');
  if (!batchSel || !sectionSel) return;
  const batch = batchSel.value;
  const sections = _availableBatchSections
    .filter(c => c.batch === batch)
    .map(c => c.section);
  const prevSection = sectionSel.value;
  sectionSel.innerHTML = sections.map(s =>
    `<option value="${s}"${s === prevSection ? ' selected' : ''}>${s}</option>`
  ).join('');
  if (!sections.includes(prevSection) && sections.length) sectionSel.value = sections[0];
  window._rtApplyBatchSection();
};

/* ── Switch to selected batch/section ── */
window._rtApplyBatchSection = function() {
  const batch   = document.getElementById('rt-batch-select')?.value;
  const section = document.getElementById('rt-section-select')?.value;
  if (!batch || !section) return;
  if (batch === _selectedBatch && section === _selectedSection) return;

  _selectedBatch   = batch;
  _selectedSection = section;
  const is62b      = batch === '62' && section === 'B';
  const todayName  = ['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][new Date().getDay()];

  if (is62b) {
    /* Restore the 62B cache, merging in any custom courses */
    _routineCache  = _rtApplyCustom(_62bCache, _customCourses);
    _routineTab    = 'regular';
    _improvedCache = null;

    /* Rebuild Improved cache if enrollments are available */
    if (_rtLastEnrollments.length) {
      _improvedCache = _rtApplyCustom(_buildImprovedCache(_rtLastEnrollments), _customCourses);
    }
  } else {
    /* Build a fresh cache for the selected batch/section */
    const { schedule, sheetTimes, dayTimeframes } = _buildScheduleFor(batch, section);
    const newCache = _scheduleToCacheWith(schedule, _allCourseInfo, _semLabel, sheetTimes, dayTimeframes);
    if (!newCache) {
      const el = document.getElementById('rt-main-content');
      if (el) el.innerHTML = `<div class="rt-grid-empty-msg">No schedule found for Batch ${escH(batch)}, Section ${escH(section)}.</div>`;
      return;
    }
    _routineCache  = newCache;
    _routineTab    = 'regular';
    _improvedCache = null;
  }

  /* Show/hide 62B-only controls */
  const user   = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  const tabBar = document.getElementById('rt-tab-bar');
  const myCoursesBtn    = document.getElementById('rt-my-courses-btn');
  const customCoursesBtn = document.getElementById('rt-custom-courses-btn');

  if (is62b) {
    if (myCoursesBtn)     myCoursesBtn.style.display = '';
    if (customCoursesBtn) customCoursesBtn.style.display = '';
    if (tabBar && _improvedCache && _rtLastEnrollments.length) {
      tabBar.innerHTML = `
        <div style="display:flex;gap:8px;">
          <button class="ri-tab" onclick="routineSwitchTab('regular')" id="rt-tab-regular">
            <i class="fa-solid fa-calendar-week"></i> Regular
          </button>
          <button class="ri-tab ri-tab-active" onclick="routineSwitchTab('improved')" id="rt-tab-improved">
            <i class="fa-solid fa-rotate-right"></i> Improved
            <span class="ri-tab-count">${_rtLastEnrollments.length}</span>
          </button>
        </div>`;
      _routineTab = 'improved';
    }
  } else {
    if (myCoursesBtn)     myCoursesBtn.style.display = 'none';
    if (customCoursesBtn) customCoursesBtn.style.display = 'none';
    if (tabBar) tabBar.innerHTML = '';
  }

  const el = document.getElementById('rt-main-content');
  if (el) el.innerHTML = buildGrid(todayName);
};

/* ── Render the batch/section selector bar ── */
function _renderSelectorBar() {
  const batches  = [...new Set(_availableBatchSections.map(c => c.batch))];
  const sections = _availableBatchSections
    .filter(c => c.batch === '62')
    .map(c => c.section);

  const batchOpts   = batches.map(b => `<option value="${b}"${b === '62' ? ' selected' : ''}>${b}</option>`).join('');
  const sectionOpts = sections.map(s => `<option value="${s}"${s === 'B' ? ' selected' : ''}>${s}</option>`).join('');

  return `
    <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:14px;
      padding:10px 14px;background:var(--card);border:1px solid var(--border);border-radius:12px;">
      <i class="fa-solid fa-magnifying-glass" style="color:var(--accent-bright);font-size:0.8rem;"></i>
      <span style="font-size:0.75rem;color:var(--text-secondary);font-weight:600;">Batch</span>
      <select id="rt-batch-select" onchange="_rtOnBatchChange()"
        style="font-size:0.78rem;font-weight:700;color:var(--text);background:var(--bg);
          border:1px solid var(--border);border-radius:8px;padding:4px 8px;cursor:pointer;
          font-family:'Inter',sans-serif;outline:none;">
        ${batchOpts}
      </select>
      <span style="font-size:0.75rem;color:var(--text-secondary);font-weight:600;">Section</span>
      <select id="rt-section-select" onchange="_rtApplyBatchSection()"
        style="font-size:0.78rem;font-weight:700;color:var(--text);background:var(--bg);
          border:1px solid var(--border);border-radius:8px;padding:4px 8px;cursor:pointer;
          font-family:'Inter',sans-serif;outline:none;">
        ${sectionOpts}
      </select>
      <span style="font-size:0.7rem;color:var(--text-secondary);margin-left:2px;">
        — other batches' routines available
      </span>
    </div>`;
}

/* ── My Courses modal ── */
window._rtOpenMyCourses = function() {
  const existing = document.getElementById('rt-my-courses-panel');
  if (existing) { existing.remove(); return; }
  if (!_62bCache) return;

  const allCodes = new Map();
  Object.values(_62bCache.schedule).forEach(slots => {
    slots.forEach(s => {
      if (!s.isBreak && s.code) {
        allCodes.set(s.code, _62bCache.courseInfo[s.code]?.name || '');
      }
    });
  });

  const panel = document.createElement('div');
  panel.id = 'rt-my-courses-panel';
  panel.style.cssText = `background:var(--card);border:1px solid var(--border);border-radius:14px;
    padding:18px;margin-bottom:14px;`;

  const items = [...allCodes.entries()].sort(([a], [b]) => a.localeCompare(b));
  panel.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">
      <span style="font-size:0.82rem;font-weight:700;color:var(--text);">
        <i class="fa-solid fa-pen-to-square" style="color:var(--accent-bright);margin-right:6px;font-size:0.75rem;"></i>
        My 62B Courses This Semester
      </span>
      <button onclick="document.getElementById('rt-my-courses-panel').remove()"
        style="background:none;border:none;color:var(--text-secondary);cursor:pointer;font-size:0.9rem;">✕</button>
    </div>
    <p style="font-size:0.7rem;color:var(--text-secondary);margin:0 0 14px;line-height:1.6;">
      <strong>Uncheck courses you are NOT taking</strong> this semester. This removes false clash warnings in Retake &amp; Improve and hides those courses from your Improved routine.
    </p>
    <div style="display:flex;flex-direction:column;gap:6px;margin-bottom:16px;">
      ${items.map(([code, name]) => `
        <label style="display:flex;align-items:center;gap:10px;cursor:pointer;padding:8px 12px;
          border-radius:9px;border:1px solid var(--border);background:rgba(255,255,255,.025);
          transition:background .12s;" onmouseover="this.style.background='rgba(99,102,241,.08)'"
          onmouseout="this.style.background='rgba(255,255,255,.025)'">
          <input type="checkbox" class="rt-mc-chk" value="${escH(code)}"
            ${!window._rtExcluded.has(code) ? 'checked' : ''}
            style="width:16px;height:16px;accent-color:#6366f1;cursor:pointer;flex-shrink:0;">
          <span style="font-family:monospace;font-size:0.78rem;font-weight:800;color:var(--accent-bright);">${escH(code)}</span>
          ${name ? `<span style="font-size:0.75rem;color:var(--text-secondary);">${escH(name)}</span>` : ''}
        </label>`).join('')}
    </div>
    <button onclick="_rtSaveMyCourses()"
      style="width:100%;padding:9px;border-radius:9px;background:linear-gradient(135deg,#6366f1,#8b5cf6);
      color:#fff;font-weight:700;font-size:0.82rem;border:none;cursor:pointer;font-family:'Inter',sans-serif;">
      <i class="fa-solid fa-check"></i> Save My Courses
    </button>`;

  const mainContent = document.getElementById('rt-main-content');
  mainContent?.parentNode.insertBefore(panel, mainContent);
};

window._rtSaveMyCourses = async function() {
  const excluded = [];
  document.querySelectorAll('.rt-mc-chk').forEach(cb => { if (!cb.checked) excluded.push(cb.value); });
  window._rtExcluded = new Set(excluded);

  const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  if (user?.id) _rtSaveExcluded(user.id, excluded);

  document.getElementById('rt-my-courses-panel')?.remove();

  if (_rtLastEnrollments.length) {
    _improvedCache = _rtApplyCustom(_buildImprovedCache(_rtLastEnrollments), _customCourses);
  }

  const todayName = ['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][new Date().getDay()];
  const el = document.getElementById('rt-main-content');
  if (el) el.innerHTML = buildGrid(todayName);
};

/* ── Main loader ── */
async function loadRoutine(body) {
  try {
    const [cpgData, tchData, dayResults, sem] = await Promise.all([
      fetchSheet('CPG_Courses').catch(() => null),
      fetchSheet('CPG_Teachers').catch(() => null),
      fetchAllRoutineDays(),        /* merges Link 1 + any extra Routine Link N */
      getSemesterLabel(),
    ]);
    _semLabel = sem;

    /* Store globally for re-use when switching batch/section */
    _allDayResults = dayResults;

    const courseInfo = {};
    if (cpgData) {
      sheetRows(cpgData)
        .filter(r => r[1] && !['code','title','course'].includes(r[1].toLowerCase()))
        .forEach(r => {
          courseInfo[r[1].trim().toUpperCase()] = {
            name:    r[0]?.trim() || '',
            teacher: r[4]?.trim() || '',
            desig:   r[5]?.trim() || '',
          };
        });
    }
    _allCourseInfo = courseInfo;

    /* Build acronym → teacher map (CPG_Teachers: A=Acronym, B=Name, C=Designation).
       Used to resolve the section-specific teacher from the routine cell acronym,
       since CPG_Courses only stores one teacher per course (the default section). */
    _teacherAcrMap = {};
    if (tchData) {
      sheetRows(tchData)
        .filter(r => r[0] && !['acronym','initials','code'].includes(r[0].toLowerCase()))
        .forEach(r => {
          _teacherAcrMap[r[0].trim().toUpperCase()] = {
            name:  r[1]?.trim() || '',
            desig: r[2]?.trim() || '',
          };
        });
    }

    /* Scan all available batch/section combos */
    _availableBatchSections = _scanBatchSections(dayResults);

    /* Build 62B schedule */
    const { schedule, sheetTimes, dayTimeframes } = _buildScheduleFor('62', 'B');
    const days = ROUTINE_DAY_NAMES.filter(d => schedule[d]);
    if (!days.length) throw new Error('No classes found for Batch 62, Section B');

    const cache62b = _scheduleToCacheWith(schedule, courseInfo, sem, sheetTimes, dayTimeframes);
    if (!cache62b) throw new Error('No classes found for Batch 62, Section B');

    _62bCache      = cache62b;
    _routineCache  = cache62b;
    _improvedCache = null;
    _rtLastEnrollments = [];
    _routineTab    = 'regular';
    _selectedBatch = '62';
    _selectedSection = 'B';

    /* Load excluded + custom courses from localStorage immediately */
    const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
    if (user?.id) {
      _customCourses = _rtLoadCustomCourses(user.id);
      if (_customCourses.length) _routineCache = _rtApplyCustom(cache62b, _customCourses);

      /* Sync custom courses with Supabase in background.
         Supabase is authoritative; if localStorage has data not yet pushed, push it. */
      _rtLoadCustomFromSupa(user.id).then(supaCourses => {
        if (supaCourses === null) {
          if (_customCourses.length) _rtSaveCustomToSupa(user.id, _customCourses);
          return;
        }
        if (JSON.stringify(supaCourses) !== JSON.stringify(_customCourses)) {
          _customCourses = supaCourses;
          _rtSaveCustomCourses(user.id, supaCourses);
          _routineCache = _rtApplyCustom(_62bCache, _customCourses);
          if (_rtLastEnrollments.length)
            _improvedCache = _rtApplyCustom(_buildImprovedCache(_rtLastEnrollments), _customCourses);
          const el = document.getElementById('rt-main-content');
          if (el) el.innerHTML = buildGrid(todayName);
        }
      });

      /* Save full 62B course list for profile's My Courses card */
      try {
        const codeMap = new Map();
        Object.values(schedule).forEach(slots =>
          slots.forEach(s => { if (!s.isBreak && s.code) codeMap.set(s.code, courseInfo[s.code]?.name || ''); })
        );
        localStorage.setItem(
          `lu62b_62bcourses_${user.id}`,
          JSON.stringify(Array.from(codeMap.entries()).map(([code, name]) => ({ code, name })))
        );
      } catch(e) {}

      window._rtExcluded = _rtLocalExcluded(user.id);
      _rtLoadExcludedFromSupa(user.id).then(() => {
        const el = document.getElementById('rt-main-content');
        if (el) el.innerHTML = buildGrid(todayName);
      });
    }

    const todayName = ['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'][new Date().getDay()];

    body.innerHTML = `
      ${_availableBatchSections.length > 1 ? _renderSelectorBar() : ''}
      <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;margin-bottom:14px;">
        <div class="rt-sync" style="margin:0;">
          <div class="rt-sync-dot"></div>
          <span>Live sync · ${sem} · Updated ${new Date().toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'})}</span>
        </div>
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
          ${user?.id ? `<button id="rt-my-courses-btn" onclick="_rtOpenMyCourses()"
            style="font-size:0.72rem;color:var(--text-secondary);background:rgba(255,255,255,.05);
            border:1px solid var(--border);border-radius:8px;padding:5px 11px;cursor:pointer;
            font-family:'Inter',sans-serif;display:flex;align-items:center;gap:5px;">
            <i class="fa-solid fa-pen-to-square" style="font-size:0.62rem;"></i> My Courses
          </button>` : ''}
          ${user?.id ? `<button id="rt-custom-courses-btn" onclick="_rtOpenCustomCourses()"
            style="font-size:0.72rem;color:#10b981;background:rgba(16,185,129,.08);
            border:1px solid rgba(16,185,129,.35);border-radius:8px;padding:5px 11px;cursor:pointer;
            font-family:'Inter',sans-serif;display:flex;align-items:center;gap:5px;">
            <i class="fa-solid fa-circle-plus" style="font-size:0.62rem;"></i> Custom Course
          </button>` : ''}
        </div>
      </div>
      <div id="rt-tab-bar" style="margin-bottom:16px;"></div>
      <div id="rt-main-content">${buildGrid(todayName)}</div>`;

    /* Background: fetch enrollments — show Improved tab if any */
    if (user?.id) {
      _rtFetchEnrollments(user.id).then(rows => {
        const enrollments = _rtLiveEnrollments(rows);
        if (!enrollments.length) return;
        _rtLastEnrollments = enrollments;
        _improvedCache = _rtApplyCustom(_buildImprovedCache(enrollments), _customCourses);
        if (!_improvedCache) return;

        /* Only show Improved tab if still on 62B */
        if (_selectedBatch !== '62' || _selectedSection !== 'B') return;

        const tabBar = document.getElementById('rt-tab-bar');
        if (!tabBar) return;

        _routineTab = 'improved';

        tabBar.innerHTML = `
          <div style="display:flex;gap:8px;">
            <button class="ri-tab" onclick="routineSwitchTab('regular')" id="rt-tab-regular">
              <i class="fa-solid fa-calendar-week"></i> Regular
            </button>
            <button class="ri-tab ri-tab-active" onclick="routineSwitchTab('improved')" id="rt-tab-improved">
              <i class="fa-solid fa-rotate-right"></i> Improved
              <span class="ri-tab-count">${enrollments.length}</span>
            </button>
          </div>`;

        const mainContent = document.getElementById('rt-main-content');
        if (mainContent) mainContent.innerHTML = buildGrid(todayName);
      });
    }

  } catch(e) {
    body.innerHTML = `<div class="info-placeholder">
      <i class="fa-solid fa-triangle-exclamation" style="color:#f87171;opacity:0.4;"></i>
      <p style="color:#f87171;font-weight:600;">Could not load routine.</p>
      <p style="font-size:0.78rem;margin-top:6px;">${e.message}</p>
    </div>`;
  }
}

function downloadRoutineImage(btn) {
  const isImproved = _routineTab === 'improved' && _improvedCache;
  const cache = isImproved ? _improvedCache : _routineCache;
  const sem   = cache?.semester || 'Routine';
  const slug  = sem.replace(/\s+/g, '');
  const batchLabel = `Batch ${_selectedBatch}, Section ${_selectedSection}`;
  const title = isImproved ? 'My Improved Routine' : 'Class Routine';
  _doDownloadImg(`Routine-CSE${_selectedBatch}${_selectedSection}-${slug}.png`, title, `${batchLabel} · ${sem}`, cache, _rtResolveTeacher, btn);
}
function downloadRoutinePDF(btn) {
  const isImproved = _routineTab === 'improved' && _improvedCache;
  const cache = isImproved ? _improvedCache : _routineCache;
  const sem   = cache?.semester || 'Routine';
  const slug  = sem.replace(/\s+/g, '');
  const batchLabel = `Batch ${_selectedBatch}, Section ${_selectedSection}`;
  const title = isImproved ? 'My Improved Routine' : 'Class Routine';
  _doDownloadPDF(`Routine-CSE${_selectedBatch}${_selectedSection}-${slug}.pdf`, title, `${batchLabel} · ${sem}`, cache, _rtResolveTeacher, btn);
}
