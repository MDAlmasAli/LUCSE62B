/* ─── My Retake/Improve Routine ─── */
/* Globals: fetchDayTab, getRoutineSheetId, getSemesterLabel, fetchSheet,
   ROUTINE_DAY_NAMES, parseClassCell, timeToMin, courseColor, escH,
   DAY_DISPLAY, sheetRows */

const _RR_SUPA = 'https://ftvtlqxpalwvyserujuh.supabase.co';
const _RR_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ0dnRscXhwYWx3dnlzZXJ1anVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5MDA1MDgsImV4cCI6MjA5MzQ3NjUwOH0.kdmxzcqmOlCpMmjnvZPaOLIdfdLomrbMZBo4Nd5YecM';

async function _rrFetchEnrollments(userId) {
  try {
    const r = await fetch(
      `${_RR_SUPA}/rest/v1/student_retake_enrollments?student_id=eq.${encodeURIComponent(userId)}&select=*`,
      { headers: { 'apikey': _RR_KEY, 'Authorization': `Bearer ${_RR_KEY}` } }
    );
    if (!r.ok) return [];
    return await r.json();
  } catch(e) { return []; }
}

function _rrBuild62BSchedule(dayResults) {
  const schedule = {};

  ROUTINE_DAY_NAMES.forEach((dayName, idx) => {
    const data = dayResults[idx];
    if (!data?.table) return;
    const rows = data.table.rows || [];
    const cols = data.table.cols || [];

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

    for (let r = dataStart; r < rows.length; r++) {
      const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
      const rowBatch   = (cells[1] || '').replace(/\.0+$/, '');
      const rowSection = (cells[2] || '').trim().toUpperCase();
      if (rowBatch !== '62' || rowSection !== 'B') continue;

      cells.slice(3).forEach((cell, i) => {
        if (!cell || cell.toUpperCase() === 'BREAK') return;
        const parsed = parseClassCell(cell);
        if (!parsed?.code) return;
        const time = timeSlots[i] || '';
        if (!time || !/\d+:\d+/.test(time)) return;
        const codeUp = parsed.code.toUpperCase();

        if (!schedule[dayName]) schedule[dayName] = [];
        const dup = schedule[dayName].some(s => s.code === codeUp && s.time === time);
        if (!dup) {
          schedule[dayName].push({
            code: codeUp, time,
            initials: parsed.initials || '',
            room: parsed.room || '',
          });
        }
      });
    }
  });

  return schedule;
}

async function loadRetakeRoutine(body) {
  body.innerHTML = '<div class="info-loading-spin"><div class="spin-sm"></div> Loading My Routine…</div>';

  const user = JSON.parse(localStorage.getItem('lu62b_student') || 'null');
  if (!user?.id) {
    body.innerHTML = `<div class="info-placeholder" style="padding:48px 20px;">
      <i class="fa-solid fa-lock" style="opacity:0.25;font-size:2.2rem;display:block;margin-bottom:14px;"></i>
      <p style="font-weight:700;">Login required</p>
      <p style="font-size:0.78rem;margin-top:6px;">Please log in to view your personalised routine.</p>
    </div>`;
    return;
  }

  try {
    const [savedEnrollments, sem, cpgData, dayResults] = await Promise.all([
      _rrFetchEnrollments(user.id),
      getSemesterLabel(),
      fetchSheet('CPG_Courses').catch(() => null),
      fetchAllRoutineDays(),   /* merges Link 1 + extra Routine Link N */
    ]);

    /* The schedule saved on an enrollment is from the semester it was made in —
       use the live routine's slots, and skip sections it no longer offers. */
    const liveSlots   = buildSectionCourseSlots(dayResults);
    const enrollments = savedEnrollments
      .map(e => ({ ...e, schedule: liveEnrollmentSlots(e, liveSlots) }))
      .filter(e => e.schedule.length);

    /* Course name map */
    const courseNameMap = {};
    if (cpgData) {
      sheetRows(cpgData).forEach(r => {
        const code = (r[1] || '').trim().toUpperCase();
        if (code) courseNameMap[code] = r[0]?.trim() || '';
      });
    }
    enrollments.forEach(e => {
      if (e.course_code && e.course_name) courseNameMap[e.course_code] = e.course_name;
    });

    /* 62B regular schedule */
    const schedule62B = _rrBuild62BSchedule(dayResults);

    /* Combine */
    const combined = {};

    ROUTINE_DAY_NAMES.forEach(day => {
      (schedule62B[day] || []).forEach(s => {
        if (!combined[day]) combined[day] = [];
        combined[day].push({ ...s, name: courseNameMap[s.code] || '', type: '62b' });
      });
    });

    enrollments.forEach(e => {
      (e.schedule || []).forEach(s => {
        const day = s.day;
        if (!day) return;
        if (!combined[day]) combined[day] = [];
        const dup = combined[day].some(x => x.code === e.course_code && x.time === s.time);
        if (!dup) {
          combined[day].push({
            code: e.course_code,
            name: e.course_name || courseNameMap[e.course_code] || '',
            time: s.time,
            initials: s.initials || e.teacher || '',
            room: s.room || '',
            type: e.type,
          });
        }
      });
    });

    /* Sort by start time */
    ROUTINE_DAY_NAMES.forEach(day => {
      if (combined[day]) combined[day].sort((a, b) => timeToMin(a.time) - timeToMin(b.time));
    });

    const activeDays = ROUTINE_DAY_NAMES.filter(d => combined[d]?.length);
    const totalEnrolled = enrollments.length;

    if (!activeDays.length) {
      body.innerHTML = `<div class="info-placeholder" style="padding:48px 20px;">
        <i class="fa-solid fa-calendar-plus" style="opacity:0.25;font-size:2.2rem;display:block;margin-bottom:14px;"></i>
        <p style="font-weight:700;">No classes yet</p>
        <p style="font-size:0.78rem;margin-top:6px;max-width:300px;margin-left:auto;margin-right:auto;">
          Go to <strong>Retake &amp; Improve</strong> and click <strong>Enroll</strong> on a section to see it here.
        </p>
      </div>`;
      return;
    }

    body.innerHTML = `
      <div class="rt-sync" style="margin-bottom:20px;">
        <div class="rt-sync-dot"></div>
        <span>${escH(sem)} &nbsp;·&nbsp;
          62B Regular + ${totalEnrolled} enrolled ${totalEnrolled === 1 ? 'course' : 'courses'}
        </span>
      </div>
      <div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:20px;">
        <div style="display:flex;align-items:center;gap:6px;font-size:0.72rem;color:var(--text-secondary);">
          <span style="width:10px;height:10px;border-radius:3px;background:#6366f1;display:inline-block;"></span>
          62B Regular
        </div>
        <div style="display:flex;align-items:center;gap:6px;font-size:0.72rem;color:var(--text-secondary);">
          <span style="width:10px;height:10px;border-radius:3px;background:#f43f5e;display:inline-block;"></span>
          Retake
        </div>
        <div style="display:flex;align-items:center;gap:6px;font-size:0.72rem;color:var(--text-secondary);">
          <span style="width:10px;height:10px;border-radius:3px;background:#fb923c;display:inline-block;"></span>
          Improve
        </div>
      </div>
      ${activeDays.map(day => {
        const dayClasses = combined[day];
        const cards = dayClasses.map(cls => {
          const timeParts = cls.time.split(/\s*[-–]\s*/);
          const timeDisplay = timeParts.length >= 2
            ? `${escH(timeParts[0].trim())} <span style="opacity:0.45;">–</span> ${escH(timeParts[1].trim())}`
            : escH(cls.time);

          let badge, accentColor, bgColor;
          if (cls.type === '62b') {
            badge       = `<span style="font-size:0.58rem;font-weight:800;padding:2px 7px;border-radius:5px;background:rgba(99,102,241,.2);color:#818cf8;letter-spacing:0.05em;">62B</span>`;
            accentColor = '#6366f1';
            bgColor     = 'rgba(99,102,241,.05)';
          } else if (cls.type === 'retake') {
            badge       = `<span style="font-size:0.58rem;font-weight:800;padding:2px 7px;border-radius:5px;background:rgba(244,63,94,.18);color:#f43f5e;letter-spacing:0.05em;">RETAKE</span>`;
            accentColor = '#f43f5e';
            bgColor     = 'rgba(244,63,94,.04)';
          } else {
            badge       = `<span style="font-size:0.58rem;font-weight:800;padding:2px 7px;border-radius:5px;background:rgba(251,146,60,.18);color:#fb923c;letter-spacing:0.05em;">IMPROVE</span>`;
            accentColor = '#fb923c';
            bgColor     = 'rgba(251,146,60,.04)';
          }

          const codeColor = courseColor(cls.code);

          return `
            <div style="display:flex;align-items:stretch;border-radius:11px;overflow:hidden;
              border:1px solid var(--border);background:${bgColor};margin-bottom:8px;">
              <div style="width:4px;background:${accentColor};flex-shrink:0;"></div>
              <div style="padding:12px 14px;flex:1;min-width:0;">
                <div style="display:flex;align-items:center;gap:7px;flex-wrap:wrap;margin-bottom:5px;">
                  <span style="font-size:0.7rem;font-family:monospace;font-weight:800;color:${codeColor};
                    padding:2px 7px;background:${codeColor}1a;border-radius:5px;">${escH(cls.code)}</span>
                  ${badge}
                  ${cls.name ? `<span style="font-size:0.83rem;font-weight:700;color:var(--text);">${escH(cls.name)}</span>` : ''}
                </div>
                <div style="display:flex;align-items:center;gap:14px;flex-wrap:wrap;">
                  <span style="font-size:0.74rem;color:var(--text-secondary);font-weight:600;">${timeDisplay}</span>
                  ${cls.initials ? `<span style="font-size:0.7rem;font-family:monospace;font-weight:700;
                    color:#c4b5fd;background:rgba(196,181,253,.12);padding:1px 7px;border-radius:5px;">
                    ${escH(cls.initials)}</span>` : ''}
                  ${cls.room ? `<span style="font-size:0.7rem;color:var(--text-secondary);opacity:0.6;">
                    <i class="fa-solid fa-location-dot" style="font-size:0.6rem;"></i> ${escH(cls.room)}</span>` : ''}
                </div>
              </div>
            </div>`;
        }).join('');

        return `
          <div style="margin-bottom:22px;">
            <div style="font-size:0.7rem;font-weight:800;text-transform:uppercase;letter-spacing:0.1em;
              color:var(--accent-bright);margin-bottom:10px;display:flex;align-items:center;gap:8px;">
              <i class="fa-solid fa-calendar-day" style="font-size:0.62rem;opacity:0.6;"></i>
              ${escH(DAY_DISPLAY[day] || day)}
              <span style="font-size:0.6rem;font-weight:600;color:var(--text-secondary);
                background:rgba(255,255,255,.06);padding:1px 7px;border-radius:10px;letter-spacing:0;">
                ${dayClasses.length} class${dayClasses.length !== 1 ? 'es' : ''}
              </span>
            </div>
            ${cards}
          </div>`;
      }).join('')}`;

  } catch(err) {
    console.error(err);
    body.innerHTML = `<div class="info-placeholder">
      <i class="fa-solid fa-triangle-exclamation" style="color:#f87171;opacity:0.4;"></i>
      <p style="color:#f87171;font-weight:600;">Could not load routine.</p>
      <p style="font-size:0.78rem;margin-top:6px;">${escH(err.message)}</p>
    </div>`;
  }
}
