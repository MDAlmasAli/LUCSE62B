/* ── Bus Schedule ── */

async function loadBus(body) {
  body.innerHTML = '<div class="info-loading-spin"><div class="spin-sm"></div> Loading Bus Schedule...</div>';

  try {
    const data = await fetchSheet('Bus');

    const rows = (data.table?.rows || []).map(r =>
      (r.c || []).map(c => {
        if (!c) return '';
        if (c.f != null && c.f !== '') return String(c.f).trim();
        if (c.v == null) return '';
        const s = String(c.v).trim();
        const dm = s.match(/^Date\((\d+),(\d+),(\d+),(\d+),(\d+)/);
        if (dm) {
          let h = parseInt(dm[4]), m = parseInt(dm[5]);
          const ap = h >= 12 ? 'PM' : 'AM';
          h = h % 12 || 12;
          return `${h}:${String(m).padStart(2, '0')} ${ap}`;
        }
        return s;
      })
    );

    if (!rows.length) {
      body.innerHTML = '<div class="info-placeholder"><i class="fa-solid fa-bus"></i><p>No bus schedule data found.</p></div>';
      return;
    }

    const firstVal = rows[0]?.[0]?.toLowerCase().trim() || '';
    const startIdx = firstVal === 'schedule' ? 1 : 0;

    const schedules = {};
    for (let i = startIdx; i < rows.length; i++) {
      const row = rows[i];
      if (!row || !row[0] || !row[3]) continue;
      const sched = row[0].trim(), dayGrp = row[1].trim(), dir = row[2].trim();
      const time = row[3].trim(), note = row[4] ? row[4].trim() : '';
      if (!sched || !time) continue;
      if (!schedules[sched]) schedules[sched] = {};
      if (!schedules[sched][dayGrp]) schedules[sched][dayGrp] = { 'To LU': [], 'From LU': [] };
      if (!schedules[sched][dayGrp][dir]) schedules[sched][dayGrp][dir] = [];
      schedules[sched][dayGrp][dir].push({ time, note });
    }

    const keys = Object.keys(schedules);
    const examKeys = keys.filter(k => k.startsWith('Exam:')).sort((a, b) => {
      const toMin = s => {
        const m = s.match(/(\d+):(\d+)\s*(AM|PM)/i);
        if (!m) return 0;
        let h = parseInt(m[1]), mn = parseInt(m[2]);
        if (m[3].toUpperCase() === 'PM' && h !== 12) h += 12;
        if (m[3].toUpperCase() === 'AM' && h === 12) h = 0;
        return h * 60 + mn;
      };
      return toMin(a) - toMin(b);
    });
    const hasReg  = keys.includes('Regular');
    const hasExam = examKeys.length > 0;
    const examDay = hasExam
      ? await (window._examCd?.hasExamToday?.('62', 'B') || Promise.resolve(false)).catch(() => false)
      : false;

    if (!hasReg && !hasExam) {
      body.innerHTML = '<div class="info-placeholder"><i class="fa-solid fa-bus"></i><p>No schedule data available.</p></div>';
      return;
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    function toMins(str) {
      const m = str.match(/(\d+):(\d+)\s*(AM|PM)/i);
      if (!m) return -1;
      let h = parseInt(m[1]), mn = parseInt(m[2]);
      if (m[3].toUpperCase() === 'PM' && h !== 12) h += 12;
      if (m[3].toUpperCase() === 'AM' && h === 12) h = 0;
      return h * 60 + mn;
    }

    function nowMins() {
      const n = new Date(); return n.getHours() * 60 + n.getMinutes();
    }

    function countdown(timeStr) {
      const diff = toMins(timeStr) - nowMins();
      if (diff <= 0) return null;
      if (diff < 60) return `${diff} min`;
      const h = Math.floor(diff / 60), m = diff % 60;
      return m > 0 ? `${h}h ${m}m` : `${h}h`;
    }

    function detectDayGroup(groups) {
      const day = new Date().getDay();
      const isFri = day === 5;
      const isSat = day === 6;
      for (const g of groups) {
        const gl = g.toLowerCase();
        if (isFri && gl.includes('fri')) return g;
        if (isSat && gl === 'saturday') return g;
        if (!isFri && !isSat && (gl.includes('sun') || gl.includes('mon') || gl.includes('sat–thu') || gl.includes('sat-thu'))) return g;
      }
      return groups[0];
    }

    // ── State ─────────────────────────────────────────────────────────────
    const regData     = schedules['Regular'] || {};
    const allDayGrps  = Object.keys(regData);
    const examDayGrps = examKeys.length ? Object.keys(schedules[examKeys[0]] || {}) : [];
    let activeTab     = examDay && hasExam ? 'exam' : (hasReg ? 'regular' : 'exam');
    let activeDayGrp  = detectDayGroup(allDayGrps);
    let activeExamDayGrp = detectDayGroup(examDayGrps);

    // ── Next Bus cards ────────────────────────────────────────────────────
    function renderNextBus(dayData) {
      const now = nowMins();

      const findNext = dir => (dayData?.[dir] || [])
        .filter(e => toMins(e.time) >= now)
        .sort((a, b) => toMins(a.time) - toMins(b.time))[0];

      const toLU   = findNext('To LU');
      const fromLU = findNext('From LU');

      const items = [
        toLU   ? { label: 'Next → To LU',   ...toLU,   color: '#34d399', icon: 'fa-right-to-bracket'   } : null,
        fromLU ? { label: 'Next ← From LU', ...fromLU, color: '#38bdf8', icon: 'fa-right-from-bracket' } : null,
      ].filter(Boolean);

      if (!items.length) return `
        <div style="background:rgba(255,255,255,0.03);border:1px solid var(--border);border-radius:16px;
          padding:16px 20px;margin-bottom:20px;display:flex;align-items:center;gap:10px;">
          <i class="fa-solid fa-moon" style="color:var(--muted);"></i>
          <span style="color:var(--muted);font-size:0.85rem;">No more buses today</span>
        </div>`;

      return `
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-bottom:22px;">
          ${items.map(c => `
            <div style="background:${c.color}0f;border:1px solid ${c.color}30;border-radius:16px;padding:18px 20px;">
              <div style="font-size:0.67rem;font-weight:800;color:${c.color};text-transform:uppercase;
                letter-spacing:0.08em;margin-bottom:8px;display:flex;align-items:center;gap:6px;">
                <i class="fa-solid ${c.icon}"></i>${c.label}
              </div>
              <div style="font-size:1.9rem;font-weight:900;color:var(--text);font-variant-numeric:tabular-nums;line-height:1;">
                ${escH(c.time)}
              </div>
              ${countdown(c.time) ? `<div style="font-size:0.72rem;color:${c.color};margin-top:6px;font-weight:600;">in ${countdown(c.time)}</div>` : ''}
              ${c.note ? `<div style="font-size:0.64rem;background:rgba(251,191,36,0.12);color:#fbbf24;padding:2px 8px;
                border-radius:5px;display:inline-block;margin-top:6px;font-weight:700;">${escH(c.note)}</div>` : ''}
            </div>`).join('')}
        </div>`;
    }

    // ── Timeline pills (green future, red past, no strikethrough) ─────────
    function renderTimeline(entries) {
      if (!entries.length) return `
        <div style="color:var(--muted);font-size:0.82rem;padding:10px 0;text-align:center;opacity:0.5;">
          No buses scheduled
        </div>`;

      const now  = nowMins();
      const next = entries.find(e => toMins(e.time) >= now);

      return `
        <div style="display:flex;flex-wrap:wrap;gap:8px;padding:4px 0;">
          ${entries.map(e => {
            const mins   = toMins(e.time);
            const isPast = mins !== -1 && mins < now;
            const isNext = next && e.time === next.time;
            let pillStyle;
            if (isPast) {
              pillStyle = 'background:rgba(248,113,113,0.12);color:#f87171;border:1px solid rgba(248,113,113,0.3);';
            } else if (isNext) {
              pillStyle = 'background:#34d399;color:#fff;box-shadow:0 0 14px #34d39966,0 0 4px #34d39999;border:1px solid #34d399;';
            } else {
              pillStyle = 'background:rgba(52,211,153,0.12);color:#34d399;border:1px solid rgba(52,211,153,0.3);';
            }
            return `
              <div style="display:inline-flex;flex-direction:column;align-items:center;gap:3px;">
                <div style="padding:8px 14px;border-radius:10px;font-size:0.88rem;font-weight:700;
                  font-variant-numeric:tabular-nums;white-space:nowrap;${pillStyle}">
                  ${escH(e.time)}${isNext ? ' <i class="fa-solid fa-bus" style="font-size:0.68rem;margin-left:3px;"></i>' : ''}
                </div>
                ${e.note ? `<span style="font-size:0.58rem;background:rgba(251,191,36,0.15);color:#fbbf24;
                  padding:1px 6px;border-radius:4px;font-weight:700;">${escH(e.note)}</span>` : ''}
              </div>`;
          }).join('')}
        </div>`;
    }

    // ── Side-by-side direction panel ──────────────────────────────────────
    function renderDirPanel(dayData) {
      const toLU   = dayData?.['To LU']   || [];
      const fromLU = dayData?.['From LU'] || [];
      return `
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;">
          <div style="background:rgba(255,255,255,0.02);border:1px solid var(--border);border-radius:14px;padding:16px 18px;">
            <div style="display:flex;align-items:center;gap:7px;margin-bottom:13px;">
              <div style="width:3px;height:16px;background:#34d399;border-radius:2px;flex-shrink:0;"></div>
              <i class="fa-solid fa-right-to-bracket" style="color:#34d399;font-size:0.72rem;"></i>
              <span style="font-size:0.7rem;font-weight:800;color:#34d399;text-transform:uppercase;letter-spacing:0.07em;">To LU</span>
            </div>
            ${renderTimeline(toLU)}
          </div>
          <div style="background:rgba(255,255,255,0.02);border:1px solid var(--border);border-radius:14px;padding:16px 18px;">
            <div style="display:flex;align-items:center;gap:7px;margin-bottom:13px;">
              <div style="width:3px;height:16px;background:#38bdf8;border-radius:2px;flex-shrink:0;"></div>
              <i class="fa-solid fa-right-from-bracket" style="color:#38bdf8;font-size:0.72rem;"></i>
              <span style="font-size:0.7rem;font-weight:800;color:#38bdf8;text-transform:uppercase;letter-spacing:0.07em;">From LU</span>
            </div>
            ${renderTimeline(fromLU)}
          </div>
        </div>`;
    }

    // ── Regular tab ───────────────────────────────────────────────────────
    function renderRegular() {
      const dayChips = allDayGrps.map(dg => {
        const isActive = dg === activeDayGrp;
        return `<button class="bus-day-chip" data-group="${escH(dg)}" style="
          padding:5px 13px;border-radius:8px;border:none;cursor:pointer;
          font-size:0.77rem;font-weight:700;font-family:'Inter',sans-serif;transition:all 0.15s;
          background:${isActive ? 'rgba(99,102,241,0.2)' : 'rgba(255,255,255,0.05)'};
          color:${isActive ? '#a5b4fc' : 'var(--muted)'};
          border:1px solid ${isActive ? 'rgba(99,102,241,0.4)' : 'transparent'};
        ">${escH(dg)}</button>`;
      }).join('');

      return `
        ${renderNextBus(regData[activeDayGrp])}
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:16px;flex-wrap:wrap;">
          <i class="fa-solid fa-calendar-days" style="color:var(--muted);font-size:0.78rem;"></i>
          <span style="font-size:0.72rem;color:var(--muted);font-weight:700;text-transform:uppercase;letter-spacing:0.06em;">Day Group</span>
          ${dayChips}
        </div>
        ${renderDirPanel(regData[activeDayGrp])}`;
    }

    // ── Exam tab ──────────────────────────────────────────────────────────
    function renderExam() {
      const dayChips = examDayGrps.map(dg => {
        const isActive = dg === activeExamDayGrp;
        return `<button class="bus-exam-day-chip" data-group="${escH(dg)}" style="
          padding:5px 13px;border-radius:8px;border:none;cursor:pointer;
          font-size:0.77rem;font-weight:700;font-family:'Inter',sans-serif;transition:all 0.15s;
          background:${isActive ? 'rgba(99,102,241,0.2)' : 'rgba(255,255,255,0.05)'};
          color:${isActive ? '#a5b4fc' : 'var(--muted)'};
          border:1px solid ${isActive ? 'rgba(99,102,241,0.4)' : 'transparent'};
        ">${escH(dg)}</button>`;
      }).join('');

      const dayBar = examDayGrps.length > 1 ? `
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:16px;flex-wrap:wrap;">
          <i class="fa-solid fa-calendar-days" style="color:var(--muted);font-size:0.78rem;"></i>
          <span style="font-size:0.72rem;color:var(--muted);font-weight:700;text-transform:uppercase;letter-spacing:0.06em;">Day Group</span>
          ${dayChips}
        </div>` : '';

      const combinedDay = { 'To LU': [], 'From LU': [] };
      examKeys.forEach(key => {
        const d = schedules[key]?.[activeExamDayGrp] || {};
        combinedDay['To LU'].push(...(d['To LU'] || []));
        combinedDay['From LU'].push(...(d['From LU'] || []));
      });
      combinedDay['To LU'].sort((a, b) => toMins(a.time) - toMins(b.time));
      combinedDay['From LU'].sort((a, b) => toMins(a.time) - toMins(b.time));

      const slots = examKeys.map(key => {
        const slotData  = schedules[key] || {};
        const examLabel = key.replace('Exam: ', '');
        return `
          <div style="background:rgba(248,113,113,0.05);border:1px solid rgba(248,113,113,0.22);
            border-radius:14px;overflow:hidden;margin-bottom:14px;">
            <div style="padding:10px 16px;border-bottom:1px solid rgba(248,113,113,0.15);
              background:rgba(248,113,113,0.08);display:flex;align-items:center;gap:8px;">
              <i class="fa-solid fa-clock" style="color:#f87171;font-size:0.78rem;"></i>
              <span style="font-size:0.84rem;font-weight:800;color:#f87171;">${escH(examLabel)} Exam</span>
            </div>
            <div style="padding:14px 16px;">
              ${renderDirPanel(slotData[activeExamDayGrp] || {})}
            </div>
          </div>`;
      }).join('');

      return (examDay ? renderNextBus(combinedDay) : '') + dayBar + slots;
    }

    function renderTab(id) {
      if (id === 'regular') return renderRegular();
      if (id === 'exam')    return renderExam();
      return '';
    }

    // ── Tab bar ───────────────────────────────────────────────────────────
    const tabs = [];
    if (hasReg)  tabs.push({ id: 'regular', label: 'Regular',   icon: 'fa-solid fa-bus',     color: '#34d399' });
    if (hasExam) tabs.push({ id: 'exam',    label: 'Exam Days', icon: 'fa-solid fa-file-pen', color: '#f87171' });

    function tabStyle(tab, isActive) {
      return `padding:8px 18px;border-radius:9px;border:none;cursor:pointer;font-size:0.82rem;font-weight:700;
        font-family:'Inter',sans-serif;display:inline-flex;align-items:center;gap:7px;transition:all 0.18s;
        background:${isActive ? `linear-gradient(135deg,${tab.color}cc,${tab.color}77)` : 'transparent'};
        color:${isActive ? '#fff' : 'var(--text-secondary)'};`;
    }

    const tabBtns = tabs.map(t => `
      <button class="bus-tab-btn" data-tabid="${t.id}" style="${tabStyle(t, t.id === activeTab)}">
        <i class="${t.icon}" style="font-size:0.75rem;"></i>${t.label}
      </button>`).join('');

    body.innerHTML = `
      <div style="display:flex;gap:6px;margin-bottom:22px;background:rgba(255,255,255,0.03);
        padding:4px;border-radius:12px;border:1px solid var(--border);width:fit-content;">
        ${tabBtns}
      </div>
      <div id="busTabContent">${renderTab(activeTab)}</div>
      <div style="font-size:0.67rem;color:var(--text-secondary);opacity:0.4;margin-top:14px;
        display:flex;align-items:center;gap:6px;">
        <i class="fa-solid fa-circle-info"></i>
        Schedule may change · Always check notice board for updates
      </div>`;

    // ── Event delegation ──────────────────────────────────────────────────
    body.addEventListener('click', e => {
      const tabBtn = e.target.closest('.bus-tab-btn');
      if (tabBtn) {
        activeTab = tabBtn.dataset.tabid;
        body.querySelectorAll('.bus-tab-btn').forEach(b => {
          const t = tabs.find(x => x.id === b.dataset.tabid);
          b.style.cssText = tabStyle(t, b.dataset.tabid === activeTab);
        });
        document.getElementById('busTabContent').innerHTML = renderTab(activeTab);
        return;
      }
      const dayChip = e.target.closest('.bus-day-chip');
      if (dayChip) {
        activeDayGrp = dayChip.dataset.group;
        document.getElementById('busTabContent').innerHTML = renderTab(activeTab);
        return;
      }
      const examDayChip = e.target.closest('.bus-exam-day-chip');
      if (examDayChip) {
        activeExamDayGrp = examDayChip.dataset.group;
        document.getElementById('busTabContent').innerHTML = renderTab(activeTab);
      }
    });

  } catch (err) {
    console.error('Bus Schedule Error:', err);
    body.innerHTML = '<div class="info-placeholder"><p>Error fetching bus schedule.</p></div>';
  }
}
