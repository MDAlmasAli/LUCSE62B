/* ── CSE 62B · Exam Countdown ─────────────────────────────────────────────
   Provides:
   1. Home-page widget — shown when any exam is ≤ 7 days away
   2. window._examCd helpers — used by exam.js for in-section countdowns
   ─────────────────────────────────────────────────────────────────────────── */
(function () {

  /* ── Date helpers ── */
  function normDate(raw) {
    if (!raw) return '';
    const num = parseFloat(String(raw).trim());
    if (!isNaN(num) && num > 40000 && num < 60000) {
      const d = new Date(Math.round((num - 25569) * 86400 * 1000));
      const u = new Date(d.getTime() + d.getTimezoneOffset() * 60000);
      return `${String(u.getDate()).padStart(2,'0')}-${String(u.getMonth()+1).padStart(2,'0')}-${u.getFullYear()}`;
    }
    const dm = String(raw).match(/^Date\((\d+),(\d+),(\d+)/);
    if (dm) {
      const d = new Date(+dm[1], +dm[2], +dm[3]);
      return `${String(d.getDate()).padStart(2,'0')}-${String(d.getMonth()+1).padStart(2,'0')}-${d.getFullYear()}`;
    }
    return String(raw).trim();
  }

  function cdDateObj(s) {
    const m = (s || '').match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
    if (!m) return null;
    const d = new Date(+m[3], +m[2] - 1, +m[1]);
    d.setHours(0, 0, 0, 0);
    return d;
  }

  function cdFmtDate(s) {
    const m = (s || '').match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
    if (!m) return s || '';
    const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return `${parseInt(m[1])} ${MON[parseInt(m[2]) - 1]} ${m[3]}`;
  }

  function cdParseTimeMins(t) {
    const m = String(t).match(/(\d+):(\d+)\s*([AP]M)?/i);
    if (!m) return 0;
    let h = parseInt(m[1]);
    const min = parseInt(m[2]);
    const ampm = (m[3] || '').toUpperCase();
    if (ampm === 'PM' && h < 12) h += 12;
    if (ampm === 'AM' && h === 12) h = 0;
    if (!ampm && h < 7) h += 12;
    return h * 60 + min;
  }

  function cdExamDateTime(exam) {
    const d = cdDateObj(exam.date);
    if (!d) return null;
    const mins = cdParseTimeMins(exam.time);
    d.setHours(Math.floor(mins / 60), mins % 60, 0, 0);
    return d;
  }

  /* ── Timer management ── */
  const _timers = {};

  function cdStartTick(examDt, ids, key) {
    if (_timers[key]) clearInterval(_timers[key]);
    const pad = n => String(n).padStart(2, '0');
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };

    function tick() {
      const diff = examDt.getTime() - Date.now();
      if (diff <= 0) {
        clearInterval(_timers[key]);
        delete _timers[key];
        ['days','hrs','min','sec'].forEach(k => set(ids[k], '00'));
        return;
      }
      set(ids.days, Math.floor(diff / 86400000));
      set(ids.hrs,  pad(Math.floor((diff % 86400000) / 3600000)));
      set(ids.min,  pad(Math.floor((diff % 3600000) / 60000)));
      set(ids.sec,  pad(Math.floor((diff % 60000) / 1000)));
    }
    tick();
    _timers[key] = setInterval(tick, 1000);
  }

  function cdStopTick(key) {
    if (_timers[key]) { clearInterval(_timers[key]); delete _timers[key]; }
  }

  /* ── Info-page countdown block (called from exam.js) ── */
  function cdBuildInfoBlock(exams, prefix) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const upcoming = exams.filter(e => { const d = cdDateObj(e.date); return d && d >= today; });
    if (!upcoming.length) return '';
    const next = upcoming[0];
    const dt = cdExamDateTime(next);
    if (!dt) return '';

    setTimeout(() => {
      cdStartTick(dt, {
        days: `${prefix}CdD`,
        hrs:  `${prefix}CdH`,
        min:  `${prefix}CdM`,
        sec:  `${prefix}CdS`,
      }, `info_${prefix}`);
    }, 30);

    return `<div class="exam-cd-wrap">
      <div class="exam-cd-left">
        <div class="exam-cd-lbl">Next Exam</div>
        <div class="exam-cd-crs">${next.course}</div>
        <div class="exam-cd-dt">${cdFmtDate(next.date)}&nbsp;&nbsp;·&nbsp;&nbsp;${next.time}</div>
      </div>
      <div class="exam-cd-timer">
        <div class="exam-cd-unit"><span id="${prefix}CdD">--</span><small>d</small></div>
        <span class="exam-cd-sep">:</span>
        <div class="exam-cd-unit"><span id="${prefix}CdH">--</span><small>h</small></div>
        <span class="exam-cd-sep">:</span>
        <div class="exam-cd-unit"><span id="${prefix}CdM">--</span><small>m</small></div>
        <span class="exam-cd-sep">:</span>
        <div class="exam-cd-unit"><span id="${prefix}CdS">--</span><small>s</small></div>
      </div>
    </div>`;
  }

  function cdStopInfo(prefix) {
    cdStopTick(`info_${prefix}`);
  }

  /* ── Sheet helper: ALL linked sheet IDs for a keyword (B = Link 1, C = …) ── */
  async function cdGetSheetIds(keyword) {
    const ids = [];
    try {
      const d = await window.fetchSheet('Routine');
      const rows = (d.table?.rows || []).map(r => (r.c || []).map(c => (c?.v != null ? String(c.v).trim() : '')));
      for (const row of rows) {
        if (!row[0]?.toLowerCase().includes(keyword)) continue;
        for (let i = 1; i < row.length; i++) {
          const m = (row[i] || '').match(/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
          if (m && !ids.includes(m[1])) ids.push(m[1]);
        }
        break;
      }
    } catch (_) {}
    return ids;
  }

  let _courseTitles = null;

  async function cdCourseTitles() {
    if (_courseTitles) return _courseTitles;
    const map = {};
    try {
      const d = await window.fetchSheet('CPG_Courses');
      const rows = (d.table?.rows || []).map(r => (r.c || []).map(c => (c?.v != null ? String(c.v).trim() : '')));
      rows.forEach(row => {
        if (row.length < 2) return;
        const title = (row[0] || '').trim();
        const code = (row[1] || '').trim().toUpperCase();
        if (!code || ['code','title','course'].includes((row[1] || '').trim().toLowerCase())) return;
        if (title) map[code] = title;
      });
    } catch (_) {}
    _courseTitles = map;
    return map;
  }

  function cdCourseDisplay(course, titles) {
    const code = String(course || '').trim();
    return titles[code.toUpperCase()] || code;
  }

  function cdEsc(value) {
    return String(value ?? '').replace(/[&<>"']/g, ch => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    }[ch]));
  }

  /* Merge several GVIZ tables (same format) into one. */
  function cdMergeTables(tables) {
    const valid = tables.filter(t => t?.table);
    if (!valid.length) return null;
    const base = valid.reduce((a, b) =>
      (b.table.cols?.length || 0) > (a.table.cols?.length || 0) ? b : a, valid[0]);
    const rows = [];
    valid.forEach(t => (t.table.rows || []).forEach(r => rows.push(r)));
    return { table: { cols: base.table.cols || [], rows } };
  }

  /* ── Mini exam parser (batch 62, section B) ── */
  function cdParseExams(data, targetBatch, targetSection) {
    const table = data?.table;
    if (!table) return [];

    const allRows = (table.rows || []).map(r =>
      (r.c || []).map(c => { if (!c || c.v == null) return ''; return normDate(c.v) || String(c.v).trim(); })
    );

    const colLabels = (table.cols || []).map(c => String(c.label || '').trim());
    if (colLabels.some(l => /day[\s\-]*\d+/i.test(l))) {
      const synRow = colLabels.map(l => { const m = l.match(/day[\s\-]*(\d+)/i); return m ? `Day-${m[1]}` : ''; });
      allRows.unshift(synRow);
    }

    const blockStarts = [];
    for (let r = 0; r < allRows.length; r++) {
      for (let c = 0; c < allRows[r].length; c++) {
        if (/^\s*day[\s\-]*\d+\s*$/i.test(allRows[r][c])) { blockStarts.push({ rowIdx: r }); break; }
      }
    }
    if (!blockStarts.length) return [];

    let batchCol = 0, sectionCol = 1;
    for (let r = 0; r < Math.min(allRows.length, 15); r++) {
      (allRows[r] || []).forEach((cell, i) => {
        if (/^\s*batch\s*$/i.test(cell)) batchCol = i;
        if (/^\s*section\s*$/i.test(cell)) sectionCol = i;
      });
    }

    const tbNum = String(targetBatch).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
    const tsStr = String(targetSection).trim().toUpperCase();
    const allExams = [];

    blockStarts.forEach((block, blockIdx) => {
      const dayHeaderIdx = block.rowIdx;
      const nextBlockRow = blockStarts[blockIdx + 1] ? blockStarts[blockIdx + 1].rowIdx : allRows.length;

      const rowBatches = {};
      let lastBatch = '';
      for (let r = dayHeaderIdx; r < nextBlockRow; r++) {
        const bc = String(allRows[r][batchCol] || '').trim();
        if (bc && /\d/.test(bc) && !/^(date|time|day|section)/i.test(bc)) lastBatch = bc;
        rowBatches[r] = lastBatch;
      }

      const dayRow = allRows[dayHeaderIdx] || [];
      const dayCols = dayRow.reduce((a, cell, i) => { if (/^\s*day[\s\-]*\d+\s*$/i.test(cell)) a.push(i); return a; }, []);

      let dateRowIdx = dayHeaderIdx + 1, timeRowIdx = dayHeaderIdx + 2;
      if (dayCols.length > 0) {
        const sc = dayCols[0];
        for (let i = 1; i <= 5; i++) {
          const rIdx = dayHeaderIdx + i;
          if (rIdx >= allRows.length || rIdx >= nextBlockRow) break;
          const cell = String(allRows[rIdx][sc]).trim();
          if (/Date\(/i.test(cell) || /\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/.test(cell)) dateRowIdx = rIdx;
          else if (/\d{1,2}:\d{2}/.test(cell) || /am|pm/i.test(cell)) timeRowIdx = rIdx;
        }
      }

      const dataStartRow = Math.max(dayHeaderIdx, dateRowIdx, timeRowIdx) + 1;
      const dateRow = allRows[dateRowIdx] || [];
      const timeRow = allRows[timeRowIdx] || [];
      const examDays = dayCols.map(col => ({ col, date: dateRow[col] || '', time: timeRow[col] || '' }));

      for (let r = dataStartRow; r < nextBlockRow; r++) {
        const row = allRows[r];
        if (!row) continue;
        const section = (row[sectionCol] || '').trim();
        if (!section || /^(section|day|date|time)$/i.test(section)) continue;
        const cbNum = String(rowBatches[r]).replace(/\.0+$/, '').replace(/[^0-9]/g, '');
        const csStr = section.toUpperCase();
        if (cbNum === tbNum && (csStr === tsStr || csStr.split(/[+&,]/).map(s => s.trim()).includes(tsStr))) {
          examDays.forEach(day => {
            const course = (row[day.col] || '').replace(/\s*\(\d+\)\s*/g, '').trim();
            if (course && course !== '--' && course !== '–') allExams.push({ date: day.date, time: day.time, course });
          });
        }
      }
    });

    return allExams.sort((a, b) => {
      const da = cdDateObj(a.date), db = cdDateObj(b.date);
      if (!da && !db) return 0; if (!da) return 1; if (!db) return -1;
      return da - db;
    });
  }

  /* ── Home page init ── */
  async function initHome() {
    await new Promise(r => { if (document.readyState !== 'loading') r(); else document.addEventListener('DOMContentLoaded', r); });

    const container = document.getElementById('examCdHomeWrap');
    if (!container) return;

    try {
      const raw = localStorage.getItem('lu62b_student') || sessionStorage.getItem('lu62b_student');
      if (!raw || !JSON.parse(raw)?.id) return;
    } catch { return; }

    let t = 0;
    while (typeof window.fetchSheet !== 'function' && t++ < 40) {
      await new Promise(r => setTimeout(r, 100));
    }
    if (typeof window.fetchSheet !== 'function') return;

    try {
      const [midIds, finalIds, titles] = await Promise.all([
        cdGetSheetIds('mid term'),
        cdGetSheetIds('final term'),
        cdCourseTitles(),
      ]);

      const today = new Date(); today.setHours(0, 0, 0, 0);
      const hits = [];

      for (const [type, ids, color] of [['Mid', midIds, '#4ade80'], ['Final', finalIds, '#f87171']]) {
        if (!ids.length) continue;
        /* raw=true → &headers=0 so a stacked per-batch header block isn't folded into column labels */
        const tables = await Promise.all(ids.map(id => window.fetchSheetById(id, '', true).catch(() => null)));
        const data = cdMergeTables(tables);
        if (!data) continue;
        const exams = cdParseExams(data, '62', 'B');
        const upcoming = exams.filter(e => { const d = cdDateObj(e.date); return d && d >= today; });
        if (!upcoming.length) continue;
        const next = upcoming[0];
        const diffDays = Math.ceil((cdDateObj(next.date) - today) / 86400000);
        if (diffDays <= 7) hits.push({
          type,
          exam: { ...next, courseName: cdCourseDisplay(next.course, titles) },
          color,
        });
      }

      if (!hits.length) return;

      container.style.display = '';
      container.innerHTML = `<div class="ehcd-wrap">
        <div class="ehcd-header">
          <i class="fa-solid fa-bell" style="color:#a78bfa;margin-right:6px;font-size:.8rem;"></i>
          Upcoming Exam${hits.length > 1 ? 's' : ''}
        </div>
        <div class="ehcd-cards">
          ${hits.map((r, i) => `
          <div class="ehcd-card">
            <div class="ehcd-info">
              <span class="ehcd-type" style="color:${r.color};">${cdEsc(r.type)} Term</span>
              <span class="ehcd-course">${cdEsc(r.exam.courseName || r.exam.course)}</span>
              <span class="ehcd-date">${cdEsc(cdFmtDate(r.exam.date))}&nbsp;·&nbsp;${cdEsc(r.exam.time)}</span>
            </div>
            <div class="ehcd-timer">
              <div class="ehcd-unit"><span id="ehcd${i}D">--</span><small>d</small></div>
              <span class="ehcd-sep">:</span>
              <div class="ehcd-unit"><span id="ehcd${i}H">--</span><small>h</small></div>
              <span class="ehcd-sep">:</span>
              <div class="ehcd-unit"><span id="ehcd${i}M">--</span><small>m</small></div>
              <span class="ehcd-sep">:</span>
              <div class="ehcd-unit"><span id="ehcd${i}S">--</span><small>s</small></div>
            </div>
          </div>`).join('')}
        </div>
      </div>`;

      hits.forEach((r, i) => {
        const dt = cdExamDateTime(r.exam);
        if (dt) cdStartTick(dt, { days: `ehcd${i}D`, hrs: `ehcd${i}H`, min: `ehcd${i}M`, sec: `ehcd${i}S` }, `home${i}`);
      });

    } catch (_) {}
  }

  /* ── Expose to exam.js ── */
  async function cdGetExamsToday(batch = '62', section = 'B') {
    const todayExams = [];
    try {
      const [midIds, finalIds] = await Promise.all([
        cdGetSheetIds('mid term'),
        cdGetSheetIds('final term'),
      ]);
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      for (const [type, ids] of [['Mid Term', midIds], ['Final Term', finalIds]]) {
        if (!ids.length) continue;
        const tables = await Promise.all(
          ids.map(id => window.fetchSheetById(id, '', true).catch(() => null))
        );
        const data = cdMergeTables(tables);
        if (!data) continue;
        const exams = cdParseExams(data, batch, section);
        exams.forEach(e => {
          const d = cdDateObj(e.date);
          if (d && d.getTime() === today.getTime()) todayExams.push({ ...e, type });
        });
      }
    } catch (_) {}
    return todayExams.sort((a, b) => cdParseTimeMins(a.time) - cdParseTimeMins(b.time));
  }

  async function cdHasExamToday(batch = '62', section = 'B') {
    return (await cdGetExamsToday(batch, section)).length > 0;
  }

  window._examCd = {
    cdBuildInfoBlock,
    cdStopInfo,
    hasExamToday: cdHasExamToday,
    getExamsToday: cdGetExamsToday,
  };

  initHome();
})();
