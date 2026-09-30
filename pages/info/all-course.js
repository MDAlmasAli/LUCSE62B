/* ─── All Batch Course Offer ─── */
/* Globals from info.html: fetchSheet, getSemesterLabel, escH */

const _AC_WORKER = 'https://lucse62b-api.sy164425.workers.dev';
const _AC_SUPA   = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const _AC_KEY    = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

/* ── Grade helpers: collapse a result set to the BEST grade per course, then
   bucket once — so a course later passed/improved stops showing as
   retake/improve, and codes like "GED 1262" / "GED-1262" all match. ── */
function _gradeRank(g) {
  return ['F','D','C','C+','B-','B','B+','A-','A','A+'].indexOf((g || '').trim());
}
function _normCourseCode(c) {
  const s = (c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const m = s.match(/^([A-Z]+)(\d.*)$/);
  return m ? `${m[1]}-${m[2]}` : s;
}
function _bucketBestGrade(data) {
  const IMPROVE = new Set(['B-', 'C+', 'C', 'D']);
  const best = {};   /* normCode → { grade, rank } */
  for (const yearSems of Object.values(data.results || {})) {
    const sems = Array.isArray(yearSems) ? yearSems : Object.values(yearSems);
    for (const sem of sems) {
      for (const c of (sem.courses || [])) {
        const code = _normCourseCode(c.course_code);
        const rank = _gradeRank(c.grade);
        if (!code || rank < 0) continue;
        if (!(code in best) || rank > best[code].rank) best[code] = { grade: (c.grade || '').trim(), rank };
      }
    }
  }
  const retake = [], improve = [], resolved = [];
  for (const [code, { grade, rank }] of Object.entries(best)) {
    if (grade === 'F')                retake.push(code);
    else if (IMPROVE.has(grade))      improve.push(code);
    else if (rank >= _gradeRank('B')) resolved.push(code);   /* B or better → done */
  }
  return { retake, improve, resolved };
}

function _acCachedCodes() {
  try {
    return {
      retake:  new Set(JSON.parse(localStorage.getItem('lu62b_retake_codes')  || '[]')),
      improve: new Set(JSON.parse(localStorage.getItem('lu62b_improve_codes') || '[]')),
      resolved: new Set(), live: false,
    };
  } catch(e) { return { retake: new Set(), improve: new Set(), resolved: new Set(), live: false }; }
}

async function _acFetchRetakeCodes() {
  try {
    const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
    if (!user?.id) return _acCachedCodes();
    const dob = localStorage.getItem(`lu62b_dob_${user.id}`);
    if (!dob) return _acCachedCodes();

    const doFetch = async () => {
      let text = null;
      for (const [url, opts] of [
        [_AC_WORKER + '/result', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ student_id: user.id, birth_date: dob }) }],
        [_AC_SUPA + '/functions/v1/get-result', { method:'POST', headers:{'Content-Type':'application/json','apikey':_AC_KEY}, body: JSON.stringify({ student_id: user.id, birth_date: dob }) }],
      ]) {
        try {
          const r = await fetch(url, opts);
          if (!r.ok) continue;
          const t = await r.text();
          if (!t.trimStart().startsWith('<')) { text = t; break; }
        } catch(e) {}
      }
      return text;
    };

    const timeout = new Promise(r => setTimeout(() => r(null), 6000));
    const text = await Promise.race([doFetch(), timeout]);
    if (!text) return _acCachedCodes();

    const data = JSON.parse(text);
    if (!data?.success) return _acCachedCodes();

    const { retake, improve, resolved } = _bucketBestGrade(data);
    try {
      localStorage.setItem('lu62b_retake_codes',  JSON.stringify(retake));
      localStorage.setItem('lu62b_improve_codes', JSON.stringify(improve));
    } catch(e) {}
    return { retake: new Set(retake), improve: new Set(improve), resolved: new Set(resolved), live: true };
  } catch(e) { return _acCachedCodes(); }
}

async function loadAllCourse(body) {
  body.innerHTML = '<div class="info-loading-spin"><div class="spin-sm"></div> Loading course offer...</div>';

  let batches = {};
  let batchOrder = [];

  try {
    const [data, sem, myCodes] = await Promise.all([fetchSheet('LU_Course_Offer'), getSemesterLabel(), _acFetchRetakeCodes()]);

    const rows = (data.table?.rows || []).map(r =>
      (r.c || []).map(c => {
        if (!c) return '';
        if (c.f != null && c.f !== '') return String(c.f).trim();
        if (c.v == null) return '';
        return String(c.v).trim();
      })
    );

    if (!rows.length) {
      body.innerHTML = '<div class="info-placeholder"><i class="fa-solid fa-layer-group"></i><p>No course data found.</p></div>';
      return;
    }

    // Skip header if present
    const firstVal = rows[0] && rows[0][0] ? rows[0][0].toLowerCase().trim() : '';
    const startIdx = (firstVal === 'batch' || firstVal === 'semester') ? 1 : 0;
    for (let i = startIdx; i < rows.length; i++) {
      const r = rows[i];
      if (!r[0] || !r[1]) continue;
      const batch = r[0].trim();
      const course = {
        code:  r[1]?.trim() || '',
        title: r[2]?.trim() || '',
        credit: r[3]?.trim() || '',
        section: r[4]?.trim() || '',
        prereq: r[5]?.trim() || '',
      };
      if (!batches[batch]) { batches[batch] = []; batchOrder.push(batch); }
      batches[batch].push(course);
    }

    if (!batchOrder.length) {
      body.innerHTML = '<div class="info-placeholder"><i class="fa-solid fa-layer-group"></i><p>No course data found.</p></div>';
      return;
    }

    // Open on the viewer's own batch, which is 62 for the class itself.
    const homeBatch = window.lu62bBatch ? window.lu62bBatch() : '62';
    const defaultBatch = batchOrder.includes(homeBatch) ? homeBatch : batchOrder[0];
    let activeBatch = defaultBatch;
    let activeCodes = myCodes;

    const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
    const needsDob = user?.id && !localStorage.getItem(`lu62b_dob_${user.id}`);

    const dobCard = needsDob ? `
      <div class="ac-dob-card" id="ac-dob-card">
        <div class="ac-dob-icon"><i class="fa-solid fa-calendar-check"></i></div>
        <div class="ac-dob-text">
          <strong>See your retake &amp; improve courses</strong>
          <span>Enter your date of birth to highlight courses you need to retake or improve.</span>
        </div>
        <div class="ac-dob-row">
          <input type="date" id="ac-dob-input" max="${new Date().toISOString().split('T')[0]}">
          <button onclick="_acDobSubmit()">Show <i class="fa-solid fa-arrow-right"></i></button>
        </div>
      </div>` : '';

    body.innerHTML = `
      <div class="rt-sync">
        <div class="rt-sync-dot"></div>
        <span>All Batch Course Offer &nbsp;·&nbsp; ${escH(sem)}</span>
      </div>
      ${dobCard}
      <div id="ac-chip-bar" class="ac-chip-bar"></div>
      <div id="ac-table-wrap"></div>`;

    window._acDobSubmit = async function() {
      const input = document.getElementById('ac-dob-input');
      const dob   = input?.value;
      if (!dob) { input && (input.style.borderColor = '#f43f5e'); return; }
      const btn = input.nextElementSibling;
      btn.disabled = true; btn.textContent = 'Loading…';
      localStorage.setItem(`lu62b_dob_${user.id}`, dob);
      // Save to Supabase so other devices/sessions sync automatically
      try {
        await fetch(`${_AC_SUPA}/rest/v1/rpc/set_student_dob`, {
          method: 'POST',
          headers: { 'apikey': _AC_KEY, 'Authorization': `Bearer ${_AC_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_student_id: user.id, p_dob: dob }),
        });
        sessionStorage.setItem(`lu62b_dob_synced_${user.id}`, '1');
      } catch(e) { /* non-fatal */ }
      activeCodes = await _acFetchRetakeCodes();
      document.getElementById('ac-dob-card')?.remove();
      renderBatchTable(activeBatch, activeCodes);
    };

    // Render batch chips
    const chipBar = document.getElementById('ac-chip-bar');
    batchOrder.forEach(batch => {
      const chip = document.createElement('button');
      chip.className = 'ac-chip' + (batch === defaultBatch ? ' ac-chip-active' : '');
      chip.textContent = 'Batch ' + batch;
      chip.onclick = () => {
        document.querySelectorAll('.ac-chip').forEach(c => c.classList.remove('ac-chip-active'));
        chip.classList.add('ac-chip-active');
        activeBatch = batch;
        renderBatchTable(batch, activeCodes);
      };
      chipBar.appendChild(chip);
    });

    renderBatchTable(defaultBatch, activeCodes);

  } catch (err) {
    body.innerHTML = `<div class="info-placeholder">
      <i class="fa-solid fa-triangle-exclamation" style="color:#f87171;opacity:0.4;"></i>
      <p style="color:#f87171;font-weight:600;">Could not load course offer.</p>
      <p style="font-size:0.78rem;margin-top:6px;">${err.message}</p>
    </div>`;
  }

  function renderBatchTable(batch, myCodes) {
    const wrap = document.getElementById('ac-table-wrap');
    if (!wrap) return;
    const courses = batches[batch] || [];
    const totalCredits = courses.reduce((s, c) => s + (parseFloat(c.credit) || 0), 0);

    const { retake: retakeCodes, improve: improveCodes } = myCodes || _acCachedCodes();

    const myRetakeCount  = courses.filter(c => retakeCodes.has((c.code||'').trim().toUpperCase())).length;
    const myImproveCount = courses.filter(c => improveCodes.has((c.code||'').trim().toUpperCase())).length;
    const myBadges = [
      myRetakeCount  ? `<span class="ac-retake-tag retake"><i class="fa-solid fa-xmark-circle"></i> ${myRetakeCount} Retake</span>`   : '',
      myImproveCount ? `<span class="ac-retake-tag improve"><i class="fa-solid fa-arrow-up"></i> ${myImproveCount} Improve</span>` : '',
    ].filter(Boolean).join(' ');

    let html = `
      <div class="ac-summary-bar">
        <span><i class="fa-solid fa-layer-group" style="color:var(--accent-bright);margin-right:6px;"></i>Batch <strong>${escH(batch)}</strong></span>
        <span><strong>${courses.length}</strong> courses &nbsp;·&nbsp; <strong>${totalCredits}</strong> total credits${myBadges ? ' &nbsp;·&nbsp; ' + myBadges : ''}</span>
      </div>
      <div class="ac-table-scroll">
      <table class="ac-table">
        <thead><tr>
          <th>#</th>
          <th>Code</th>
          <th>Course Title</th>
          <th>Cr.</th>
          <th>Sec</th>
          <th>Prerequisite</th>
        </tr></thead>
        <tbody>`;

    courses.forEach((c, idx) => {
      const codeUp  = (c.code || '').trim().toUpperCase();
      const isRetake  = retakeCodes.has(codeUp);
      const isImprove = improveCodes.has(codeUp);
      const rowClass  = isRetake ? 'ac-row-retake' : isImprove ? 'ac-row-improve' : '';
      const badge     = isRetake
        ? `<span class="ac-retake-tag retake">Retake</span>`
        : isImprove
          ? `<span class="ac-retake-tag improve">Improve</span>`
          : '';
      html += `<tr${rowClass ? ` class="${rowClass}"` : ''}>
        <td class="ac-td-num">${idx + 1}</td>
        <td><span class="ac-code">${escH(c.code)}</span>${badge}</td>
        <td class="ac-td-title">${escH(c.title)}</td>
        <td class="ac-td-cr">${escH(c.credit)}</td>
        <td class="ac-td-sec">${escH(c.section)}</td>
        <td class="ac-td-pre">${c.prereq ? escH(c.prereq) : '<span style="opacity:0.3;">—</span>'}</td>
      </tr>`;
    });

    html += `</tbody></table></div>`;
    wrap.innerHTML = html;
  }
}
