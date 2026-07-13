/* ─── Exam Routine ─── */

const _EX_SUPA = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const _EX_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

let _examCache       = null;
let _examTab         = 'regular';
let _examEnrollments = [];
let _examType        = 'mid';

/* ── Date helpers ── */
function fetchExamTab(sheetId) {
  return fetchSheetById(sheetId, '', true);
}

function normExamDate(raw) {
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

function fmtExamDate(s) {
  const m = (s||'').match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
  if (!m) return s;
  const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${parseInt(m[1])} ${MON[parseInt(m[2])-1]} ${m[3]}`;
}

function examDateObj(s) {
  const m = (s||'').match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
  if (!m) return null;
  const d = new Date(+m[3], +m[2]-1, +m[1]); d.setHours(0,0,0,0); return d;
}

/* ── Core parser ── */
function parseExamRoutine(data, targetBatch, targetSection) {
  const table = data?.table;
  if (!table) return null;

  const allRows = (table.rows || []).map(r =>
    (r.c || []).map(c => {
      if (!c || c.v == null) return '';
      return normExamDate(c.v) || String(c.v).trim();
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
      if (/^\s*day[\s\-]*\d+\s*$/i.test(allRows[r][c])) {
        blockStarts.push({ rowIdx: r, colIdx: c });
        break;
      }
    }
  }
  if (blockStarts.length === 0) return null;

  let batchCol = 0, sectionCol = 1;
  for (let r = 0; r < Math.min(allRows.length, 15); r++) {
    const row = allRows[r] || [];
    row.forEach((cell, i) => {
      if (/^\s*batch\s*$/i.test(cell))   batchCol = i;
      if (/^\s*section\s*$/i.test(cell)) sectionCol = i;
    });
  }

  const tbNum = String(targetBatch).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
  const tsStr = String(targetSection).trim().toUpperCase();
  const allExams = [];

  blockStarts.forEach((block, blockIdx) => {
    const dayHeaderIdx = block.rowIdx;
    const nextBlockRow = blockStarts[blockIdx + 1]
      ? blockStarts[blockIdx + 1].rowIdx
      : allRows.length;

    const rowBatches = {};
    let lastBatch = '';
    for (let r = dayHeaderIdx; r < nextBlockRow; r++) {
      const batchCell = String(allRows[r][batchCol] || '').trim();
      if (batchCell && /\d/.test(batchCell) && !/^(date|time|day|section)/i.test(batchCell))
        lastBatch = batchCell;
      rowBatches[r] = lastBatch;
    }

    const dayRow  = allRows[dayHeaderIdx] || [];
    const dayCols = dayRow.reduce((a, cell, i) => {
      if (/^\s*day[\s\-]*\d+\s*$/i.test(cell)) a.push(i);
      return a;
    }, []);

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
      const cbNum = String(rowBatches[r]).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
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

  if (!allExams.length) return null;

  allExams.sort((a, b) => {
    const da = examDateObj(a.date), db = examDateObj(b.date);
    if (!da && !db) return 0;
    if (!da) return 1;
    if (!db) return -1;
    if (da.getTime() !== db.getTime()) return da - db;
    const parseTime = t => {
      const m = String(t).match(/(\d+):(\d+)\s*([AP]M)?/i);
      if (!m) return 0;
      let h = parseInt(m[1]), min = parseInt(m[2]), ampm = (m[3]||'').toUpperCase();
      if (ampm === 'PM' && h < 12) h += 12;
      if (ampm === 'AM' && h === 12) h = 0;
      if (!ampm && h < 7) h += 12;
      return h * 60 + min;
    };
    return parseTime(a.time) - parseTime(b.time);
  });
  return allExams;
}

/* ── Fetch retake enrollments ── */
async function _examFetchEnrollments(userId) {
  try {
    const r = await fetch(
      `${_EX_SUPA}/rest/v1/student_retake_enrollments?student_id=eq.${encodeURIComponent(userId)}&select=*`,
      { headers: { 'apikey': _EX_KEY, 'Authorization': `Bearer ${_EX_KEY}` } }
    );
    return r.ok ? await r.json() : [];
  } catch(e) { return []; }
}

/* ── Main loader ── */
async function loadExamRoutine(body, type) {
  _examType  = type;
  _examCache = null;

  body.innerHTML = `<div class="info-loading-spin"><div class="spin-sm"></div> Loading...</div>`;

  const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  _examEnrollments = [];
  if (user?.id) {
    const rows = await _examFetchEnrollments(user.id);
    _examEnrollments = rows.filter(e => e.batch && e.section && e.course_code);
  }

  const hasRetake = _examEnrollments.length > 0;
  _examTab = hasRetake ? 'retake' : 'regular';

  body.innerHTML = `
    ${hasRetake ? `
    <div id="exam-tab-bar" style="margin-bottom:16px;">
      <div style="display:flex;gap:8px;">
        <button class="ri-tab${_examTab === 'regular' ? ' ri-tab-active' : ''}"
          onclick="examSwitchTab('regular')" id="exam-tab-regular">
          <i class="fa-solid fa-calendar-week"></i> 62B Exams
        </button>
        <button class="ri-tab${_examTab === 'retake' ? ' ri-tab-active' : ''}"
          onclick="examSwitchTab('retake')" id="exam-tab-retake">
          <i class="fa-solid fa-calendar-days"></i> My Full Schedule
          <span class="ri-tab-count">${_examEnrollments.length}</span>
        </button>
      </div>
    </div>` : ''}
    <div id="exam-content"></div>`;

  if (_examTab === 'retake') {
    _examShowRetakeUI(type);
  } else {
    _examShowRegularUI(type);
  }
}

/* ── Tab switch ── */
window.examSwitchTab = function(tab) {
  _examTab = tab;
  document.querySelectorAll('#exam-tab-bar .ri-tab').forEach(t => t.classList.remove('ri-tab-active'));
  document.getElementById(`exam-tab-${tab}`)?.classList.add('ri-tab-active');
  if (tab === 'retake') _examShowRetakeUI(_examType);
  else                  _examShowRegularUI(_examType);
};

/* ── Regular tab: search form ── */
function _examShowRegularUI(type) {
  const content = document.getElementById('exam-content');
  if (!content) return;
  content.innerHTML = `
    <div class="rt-tf-wrap">
      <div class="rt-tf-row">
        <input type="text" id="examBatchInput" class="rt-tf-input" value="62" placeholder="Batch" style="max-width:120px;" />
        <input type="text" id="examSectionInput" class="rt-tf-input" value="B" placeholder="Section" style="max-width:120px;" />
        <button class="rt-tf-btn" id="examSearchBtn" onclick="doExamSearch('${type}')">
          <i class="fa-solid fa-magnifying-glass"></i> Search
        </button>
      </div>
    </div>
    <div id="examRoutineResult"><div class="info-loading-spin"><div class="spin-sm"></div> Loading default routine...</div></div>`;
  document.getElementById('examBatchInput').addEventListener('keydown',  e => { if (e.key === 'Enter') doExamSearch(type); });
  document.getElementById('examSectionInput').addEventListener('keydown', e => { if (e.key === 'Enter') doExamSearch(type); });
  setTimeout(() => doExamSearch(type), 50);
}

/* ── Retake tab: regular 62B exams + enrolled retake/improve exams merged ── */
async function _examShowRetakeUI(type) {
  const content = document.getElementById('exam-content');
  if (!content) return;
  content.innerHTML = `<div class="info-loading-spin"><div class="spin-sm"></div> Fetching your full exam schedule...</div>`;

  const label = type === 'mid' ? 'Mid Term' : 'Final Term';

  try {
    const keyword = type === 'mid' ? 'mid term' : 'final term';

    const [cpgData, examData, sem] = await Promise.all([
      fetchSheet('CPG_Courses').catch(() => null),
      fetchMergedRoutineSheet(keyword),     /* merges Link 1 + extra Routine Link N */
      getSemesterLabel(),
    ]);
    if (!examData) {
      content.innerHTML = `<div class="info-placeholder">
        <i class="fa-solid fa-link-slash" style="opacity:0.2;font-size:2rem;display:block;margin-bottom:14px;"></i>
        <p style="font-weight:600;">No ${label} Routine linked yet.</p>
      </div>`;
      return;
    }

    const courseInfo = {};
    if (cpgData) {
      sheetRows(cpgData)
        .filter(r => r[1] && !['code','title','course'].includes(r[1].toLowerCase()))
        .forEach(r => { courseInfo[r[1].trim().toUpperCase()] = { name: r[0].trim() }; });
    }

    /* ── Regular 62B exams ── */
    const reg62B = parseExamRoutine(examData, '62', 'B') || [];

    /* Read excluded courses from localStorage so unchecked courses are hidden */
    let excluded = new Set();
    try {
      const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
      if (user?.id) excluded = new Set(JSON.parse(localStorage.getItem(`lu62b_excl_${user.id}`) || '[]'));
    } catch(e) {}

    const regularExams = reg62B
      .filter(e => !excluded.has(e.course))
      .map(e => ({ ...e, source: '62b' }));

    /* ── Retake / Improve exams ── */
    const parsedCache = new Map();
    const retakeExams = [];

    for (const enr of _examEnrollments) {
      const key = `${enr.batch}-${enr.section}`;
      if (!parsedCache.has(key)) {
        parsedCache.set(key, parseExamRoutine(examData, enr.batch, enr.section) || []);
      }
      const hit = parsedCache.get(key).find(e =>
        e.course.toUpperCase() === String(enr.course_code).toUpperCase()
      );
      if (hit) {
        retakeExams.push({
          ...hit,
          source:          enr.type || 'retake',
          enrolledBatch:   String(enr.batch),
          enrolledSection: String(enr.section),
        });
      }
    }

    /* ── Merge & sort ── */
    const allExams = [...regularExams, ...retakeExams];
    allExams.sort((a, b) => {
      const da = examDateObj(a.date), db = examDateObj(b.date);
      if (!da && !db) return 0;
      if (!da) return 1;
      if (!db) return -1;
      return da - db;
    });

    _examCache = {
      type, label, exams: allExams, courseInfo,
      targetBatch: '62', targetSection: 'B',
      semester: sem, isRetake: true,
    };

    if (!allExams.length) {
      content.innerHTML = `<div class="info-placeholder">
        <i class="fa-solid fa-calendar-xmark" style="opacity:0.2;font-size:2rem;display:block;margin-bottom:14px;"></i>
        <p>No exam data found for your schedule.</p>
        <p style="font-size:0.75rem;margin-top:6px;opacity:0.65;">The sheet may not have exam data yet.</p>
      </div>`;
      return;
    }

    const rtCount = retakeExams.length;
    const regCount = regularExams.length;
    const _cdRet = window._examCd ? window._examCd.cdBuildInfoBlock(allExams, 'ret') : '';
    content.innerHTML = `
      <div class="rt-sync">
        <div class="rt-sync-dot"></div>
        <span>My Full Exam Schedule &nbsp;·&nbsp; ${label} &nbsp;·&nbsp; ${sem}</span>
      </div>
      ${_cdRet}
      <div class="exam-meta" style="display:flex;gap:8px;flex-wrap:wrap;">
        <span class="exam-count-badge">${allExams.length} Total</span>
        ${regCount ? `<span class="exam-count-badge" style="background:rgba(99,102,241,.15);color:#a78bfa;">${regCount} Regular</span>` : ''}
        ${rtCount  ? `<span class="exam-count-badge" style="background:rgba(244,63,94,.12);color:#f87171;">${rtCount} Retake/Improve</span>` : ''}
      </div>
      <div class="exam-cards">${_examBuildCards(allExams, courseInfo, true)}</div>
      <div class="rt-dl-bar">
        <button class="rt-dl-btn" onclick="downloadExamImage(this)">
          <i class="fa-solid fa-image"></i> Image Download
        </button>
        <button class="rt-dl-btn rt-dl-btn-pdf" onclick="downloadExamPDF(this)">
          <i class="fa-solid fa-file-pdf"></i> PDF Download
        </button>
      </div>`;

  } catch(e) {
    content.innerHTML = `<div class="info-placeholder">
      <i class="fa-solid fa-triangle-exclamation" style="color:#f87171;opacity:0.4;"></i>
      <p style="color:#f87171;font-weight:600;">Could not load exam schedule.</p>
      <p style="font-size:0.78rem;margin-top:6px;">${e.message}</p>
    </div>`;
  }
}

/* ── Build exam cards HTML ── */
function _examBuildCards(exams, courseInfo, showBadge) {
  const today = new Date(); today.setHours(0,0,0,0);
  let cards = '';
  exams.forEach(exam => {
    const color   = courseColor(exam.course);
    const info    = courseInfo[exam.course.toUpperCase()] || {};
    const dObj    = examDateObj(exam.date);
    const isPast  = dObj && dObj < today;
    const isToday = dObj && dObj.getTime() === today.getTime();
    const calendarPayload = dObj ? encodeURIComponent(JSON.stringify({
      course: exam.course,
      name: info.name || '',
      date: dObj.toISOString(),
      time: exam.time || '',
    })) : '';

    let borderC = color + '88';
    let badgeHtml = '';
    if (showBadge && exam.source && exam.source !== '62b') {
      const srcColor = exam.source === 'improve' ? '#fb923c' : '#f43f5e';
      const srcBg    = exam.source === 'improve' ? 'rgba(251,146,60,.15)' : 'rgba(244,63,94,.15)';
      borderC = exam.source === 'improve' ? 'rgba(251,146,60,.65)' : 'rgba(244,63,94,.65)';
      badgeHtml = `<span style="font-size:0.52rem;font-weight:800;padding:2px 6px;border-radius:4px;
        background:${srcBg};color:${srcColor};letter-spacing:0.06em;text-transform:uppercase;">${escH(exam.source)}</span>`;
    }

    cards += `<div class="exam-card${isPast?' is-past':''}${isToday?' is-today':''}" style="border-left-color:${borderC};">
      <div class="exam-card-left">
        <span class="exam-card-daynum">${escH(exam.label)}</span>
        <span class="exam-card-wday">${escH(exam.weekday)}</span>
        <span class="exam-card-date">${escH(fmtExamDate(exam.date))}</span>
      </div>
      <div class="exam-card-right">
        <div style="display:flex;align-items:center;gap:7px;flex-wrap:wrap;">
          <span class="exam-card-code" style="color:${color};">${escH(exam.course)}</span>
          ${badgeHtml}
          ${isToday ? '<span class="exam-today-tag">Today</span>' : ''}
        </div>
        ${info.name ? `<div class="exam-card-name">${escH(info.name)}</div>` : ''}
        <div class="exam-card-time"><i class="fa-regular fa-clock" style="margin-right:5px;"></i>${escH(exam.time)}</div>
        ${dObj && !isPast ? `<button onclick="_examAddCalendar('${calendarPayload}')" style="margin-top:7px;border:1px solid var(--border);background:var(--card);color:var(--accent-bright);border-radius:7px;padding:5px 9px;cursor:pointer;font-size:.68rem;"><i class="fa-solid fa-calendar-plus"></i> Add to Calendar</button>` : ''}
        ${showBadge && exam.enrolledBatch ? `
        <div style="font-size:0.65rem;color:var(--text-secondary);margin-top:3px;opacity:0.7;">
          Batch ${escH(exam.enrolledBatch)}, Section ${escH(exam.enrolledSection)}
        </div>` : ''}
      </div>
    </div>`;
  });
  return cards;
}

function _examAddCalendar(encoded) {
  const item = JSON.parse(decodeURIComponent(encoded));
  const date = new Date(item.date);
  const matches = [...String(item.time).matchAll(/(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?/gi)];
  const at = (m, fallback) => {
    let hour = m ? Number(m[1]) : fallback;
    const minute = m ? Number(m[2] || 0) : 0;
    const suffix = m ? String(m[3] || '').toUpperCase() : '';
    if (suffix === 'PM' && hour < 12) hour += 12;
    if (suffix === 'AM' && hour === 12) hour = 0;
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour, minute);
  };
  const start = at(matches[0], 9);
  let end = at(matches[1], start.getHours() + 2);
  if (end <= start) end = new Date(start.getTime() + 2 * 3600000);
  const stamp = d => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const url = 'https://calendar.google.com/calendar/render?action=TEMPLATE' +
    `&text=${encodeURIComponent('Exam: ' + item.course)}` +
    `&details=${encodeURIComponent(item.name)}` +
    `&location=${encodeURIComponent('Leading University')}` +
    `&dates=${stamp(start)}/${stamp(end)}`;
  window.open(url, '_blank', 'noopener');
}

/* ── Regular search (62B Exams tab) ── */
async function doExamSearch(type) {
  const label   = type === 'mid' ? 'Mid Term' : 'Final Term';
  const keyword = type === 'mid' ? 'mid term' : 'final term';
  const resultDiv = document.getElementById('examRoutineResult');
  const btn = document.getElementById('examSearchBtn');

  const targetBatch   = document.getElementById('examBatchInput')?.value.trim() || '62';
  const targetSection = (document.getElementById('examSectionInput')?.value.trim() || 'B').toUpperCase();

  if (!targetBatch || !targetSection) {
    if (resultDiv) resultDiv.innerHTML = `<div class="info-placeholder"><p>Please enter both Batch and Section.</p></div>`;
    return;
  }

  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Searching...'; }
  if (resultDiv) resultDiv.innerHTML = '<div class="info-loading-spin"><div class="spin-sm"></div> Fetching routine...</div>';

  try {
    const [cpgData, examData, sem] = await Promise.all([
      fetchSheet('CPG_Courses').catch(() => null),
      fetchMergedRoutineSheet(keyword),     /* merges Link 1 + extra Routine Link N */
      getSemesterLabel(),
    ]);
    if (!examData) {
      if (resultDiv) resultDiv.innerHTML = `<div class="info-placeholder">
        <i class="fa-solid fa-link-slash" style="opacity:0.2;font-size:2rem;display:block;margin-bottom:14px;"></i>
        <p style="font-weight:600;">No ${label} Routine linked yet.</p>
        <p style="font-size:0.78rem;margin-top:8px;opacity:0.65;">In your Routine tab, add a row with<br>
        <strong style="color:var(--accent-bright);">${keyword}</strong> in col A and the Google Sheet URL in col B.</p>
      </div>`;
      return;
    }

    const courseInfo = {};
    if (cpgData) {
      sheetRows(cpgData)
        .filter(r => r[1] && !['code','title','course'].includes(r[1].toLowerCase()))
        .forEach(r => { courseInfo[r[1].trim().toUpperCase()] = { name: r[0].trim() }; });
    }

    const exams = parseExamRoutine(examData, targetBatch, targetSection);
    if (!exams || !exams.length) {
      if (resultDiv) resultDiv.innerHTML = `<div class="info-placeholder">
        <i class="fa-solid fa-calendar-xmark" style="opacity:0.2;font-size:2rem;display:block;margin-bottom:14px;"></i>
        <p>No exams found for Batch <strong style="color:var(--text);">${escH(targetBatch)}</strong>, Section <strong style="color:var(--text);">${escH(targetSection)}</strong>.</p>
        <p style="font-size:0.75rem;margin-top:6px;opacity:0.65;">Make sure your sheet has "Day 1", "Batch", and "Section" columns matching LU standard format.</p>
      </div>`;
      return;
    }

    _examCache = { type, label, exams, courseInfo, targetBatch, targetSection, semester: sem, isRetake: false };

    const _cdReg = window._examCd ? window._examCd.cdBuildInfoBlock(exams, 'reg') : '';
    if (resultDiv) resultDiv.innerHTML = `
      <div class="rt-sync">
        <div class="rt-sync-dot"></div>
        <span>${label} Exam Routine &nbsp;·&nbsp; Batch ${escH(targetBatch)}, Section ${escH(targetSection)} &nbsp;·&nbsp; ${sem}</span>
      </div>
      ${_cdReg}
      <div class="exam-meta">
        <span class="exam-count-badge">${exams.length} Exam${exams.length !== 1 ? 's' : ''}</span>
      </div>
      <div class="exam-cards">${_examBuildCards(exams, courseInfo, false)}</div>
      <div class="rt-dl-bar">
        <button class="rt-dl-btn" onclick="downloadExamImage(this)">
          <i class="fa-solid fa-image"></i> Image Download
        </button>
        <button class="rt-dl-btn rt-dl-btn-pdf" onclick="downloadExamPDF(this)">
          <i class="fa-solid fa-file-pdf"></i> PDF Download
        </button>
      </div>`;

  } catch(e) {
    if (resultDiv) resultDiv.innerHTML = `<div class="info-placeholder">
      <i class="fa-solid fa-triangle-exclamation" style="color:#f87171;opacity:0.4;"></i>
      <p style="color:#f87171;font-weight:600;">Could not load ${label} routine.</p>
      <p style="font-size:0.78rem;margin-top:6px;">${e.message}</p>
    </div>`;
  } finally {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-magnifying-glass"></i> Search'; }
  }
}

/* ─── Print template ─── */
function buildExamPrintTemplate() {
  if (!_examCache) return '';
  const { label, exams, courseInfo, targetBatch, targetSection, isRetake } = _examCache;
  const today = new Date(); today.setHours(0,0,0,0);
  const t = getPrintTheme();

  let rows = '';
  exams.forEach((exam, ri) => {
    const color  = courseColor(exam.course);
    const info   = courseInfo[exam.course.toUpperCase()] || {};
    const dObj   = examDateObj(exam.date);
    const isPast = dObj && dObj < today;
    const rowBg  = ri % 2 === 0 ? t.rowEven : t.rowOdd;

    const is62b    = !exam.source || exam.source === '62b';
    const srcColor = exam.source === 'improve' ? '#fb923c' : is62b ? '#a78bfa' : '#f43f5e';
    const srcBg    = exam.source === 'improve' ? 'rgba(251,146,60,.15)' : is62b ? 'rgba(99,102,241,.15)' : 'rgba(244,63,94,.15)';
    const srcLabel = is62b ? '62B' : (exam.source || 'retake').toUpperCase();

    rows += `<tr style="opacity:${isPast?0.85:1};">
      <td style="padding:11px 16px;text-align:center;font-size:11px;font-weight:700;color:${t.examDay};border:1px solid ${t.borderSub};background:${rowBg};white-space:nowrap;">${escH(exam.label)}</td>
      <td style="padding:11px 16px;font-size:12px;color:${t.examDate};border:1px solid ${t.borderSub};background:${rowBg};white-space:nowrap;">${escH(exam.weekday)}, ${escH(fmtExamDate(exam.date))}</td>
      <td style="padding:11px 16px;font-size:12px;color:${t.examTime};font-weight:600;border:1px solid ${t.borderSub};background:${rowBg};white-space:nowrap;">${escH(exam.time)}</td>
      <td style="padding:11px 16px;border:1px solid ${t.borderSub};background:${rowBg};">
        <span style="font-size:13px;font-weight:800;color:${color};">${escH(exam.course)}</span>
        ${info.name?`<div style="font-size:10px;color:${t.textMuted};margin-top:2px;">${escH(info.name)}</div>`:''}
        ${isRetake && exam.enrolledBatch ? `<div style="font-size:9px;color:${t.textMuted};margin-top:2px;">Batch ${escH(exam.enrolledBatch)}, Sec ${escH(exam.enrolledSection)}</div>` : ''}
      </td>
      ${isRetake ? `<td style="padding:11px 16px;text-align:center;border:1px solid ${t.borderSub};background:${rowBg};">
        <span style="font-size:10px;font-weight:800;padding:2px 7px;border-radius:4px;background:${srcBg};color:${srcColor};text-transform:uppercase;">${escH(srcLabel)}</span>
      </td>` : ''}
    </tr>`;
  });

  const subtitle = isRetake
    ? `My Retake &amp; Improve Exams &nbsp;·&nbsp; ${_examCache?.semester || ''}`
    : `Batch ${escH(targetBatch)}, Section ${escH(targetSection)} &nbsp;·&nbsp; ${_examCache?.semester || ''}`;

  const dateStr = new Date().toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'});
  return `<div style="width:860px;background:${t.bg};padding:36px;font-family:'Inter',system-ui,sans-serif;color:${t.text};box-sizing:border-box;">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:26px;padding-bottom:20px;border-bottom:1.5px solid ${t.divider};">
      <div style="display:flex;align-items:center;gap:16px;">
        <div style="width:52px;height:52px;border-radius:14px;background:linear-gradient(135deg,#7c3aed,#4f46e5);display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><rect x="3" y="4" width="18" height="18" rx="2" stroke="white" stroke-width="2"/><path d="M16 2V6M8 2V6M3 10H21" stroke="white" stroke-width="2" stroke-linecap="round"/><path d="M8 14h8M8 17h5" stroke="white" stroke-width="1.5" stroke-linecap="round"/></svg>
        </div>
        <div>
          <div style="font-size:22px;font-weight:800;color:${t.text};letter-spacing:-0.02em;">${escH(label)} Exam Routine</div>
          <div style="font-size:13px;color:#a78bfa;font-weight:600;margin-top:4px;">${subtitle}</div>
        </div>
      </div>
      <div style="text-align:right;">
        <div style="font-size:13px;font-weight:700;color:${t.univText};">Leading University, Sylhet</div>
        <div style="font-size:11.5px;color:${t.univFaint};margin-top:4px;">Department of Computer Science &amp; Engineering</div>
      </div>
    </div>
    <table style="width:100%;border-collapse:collapse;">
      <thead><tr>
        <th style="padding:10px 16px;text-align:center;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:${t.headerText};background:${t.headerBg};border:1px solid ${t.border};">DAY</th>
        <th style="padding:10px 16px;text-align:left;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:${t.headerText};background:${t.headerBg};border:1px solid ${t.border};">DATE</th>
        <th style="padding:10px 16px;text-align:left;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:${t.headerText};background:${t.headerBg};border:1px solid ${t.border};">TIME</th>
        <th style="padding:10px 16px;text-align:left;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:${t.headerText};background:${t.headerBg};border:1px solid ${t.border};">COURSE</th>
        ${isRetake ? `<th style="padding:10px 16px;text-align:center;font-size:10px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:${t.headerText};background:${t.headerBg};border:1px solid ${t.border};">TYPE</th>` : ''}
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <div style="margin-top:18px;display:flex;justify-content:space-between;align-items:center;padding-top:14px;border-top:1px solid ${t.borderSub};">
      <div style="font-size:10.5px;color:${t.footer};font-weight:500;">CSE 62B Portal &nbsp;·&nbsp; lucse62b.xyz</div>
      <div style="font-size:10.5px;color:${t.footer};">Generated: ${dateStr}</div>
    </div>
  </div>`;
}

/* ─── Download ─── */
async function downloadExamImage(btn) {
  if (!_examCache) return;
  const orig = btn.innerHTML;
  btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Preparing...';
  try {
    await loadScript('https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js');
    const t = getPrintTheme();
    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'position:fixed;left:-99999px;top:0;z-index:-1;';
    wrapper.innerHTML = buildExamPrintTemplate();
    document.body.appendChild(wrapper);
    const canvas = await html2canvas(wrapper.firstElementChild, {backgroundColor:t.bg,scale:3,useCORS:true,logging:false,allowTaint:true});
    document.body.removeChild(wrapper);
    const a = document.createElement('a');
    const slug = (_examCache.semester || 'Exam').replace(/\s+/g, '');
    const prefix = _examCache.isRetake ? 'Retake' : `${_examCache.targetBatch}${_examCache.targetSection}`;
    a.download = `${_examCache.label.replace(' ','-')}-Exam-${prefix}-${slug}.png`;
    a.href = canvas.toDataURL('image/png'); a.click();
  } catch(e) { alert('Download failed: ' + e.message); }
  finally { btn.disabled = false; btn.innerHTML = orig; }
}

async function downloadExamPDF(btn) {
  if (!_examCache) return;
  const orig = btn.innerHTML;
  btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Preparing...';
  try {
    await Promise.all([
      loadScript('https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js'),
      loadScript('https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js'),
    ]);
    const t = getPrintTheme();
    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'position:fixed;left:-99999px;top:0;z-index:-1;';
    wrapper.innerHTML = buildExamPrintTemplate();
    document.body.appendChild(wrapper);
    const canvas = await html2canvas(wrapper.firstElementChild, {backgroundColor:t.bg,scale:3,useCORS:true,logging:false,allowTaint:true});
    document.body.removeChild(wrapper);
    const { jsPDF } = window.jspdf;
    const w = canvas.width/3, h = canvas.height/3;
    const pdf = new jsPDF({orientation: w > h ? 'landscape' : 'portrait', unit:'px', format:[w+20,h+20]});
    pdf.addImage(canvas.toDataURL('image/png'), 'PNG', 10, 10, w, h);
    const slug = (_examCache.semester || 'Exam').replace(/\s+/g, '');
    const prefix = _examCache.isRetake ? 'Retake' : `${_examCache.targetBatch}${_examCache.targetSection}`;
    pdf.save(`${_examCache.label.replace(' ','-')}-Exam-${prefix}-${slug}.pdf`);
  } catch(e) { alert('Download failed: ' + e.message); }
  finally { btn.disabled = false; btn.innerHTML = orig; }
}
