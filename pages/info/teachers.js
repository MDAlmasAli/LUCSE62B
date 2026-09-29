/* ── Website/pages/info/teachers.js ── */
/* Source of truth: Class Routine (62B slots) for teacher→course assignments.
   CPG_Teachers supplies contact info; CPG_Courses supplies course titles only. */


const _tcEmpty = v => !v || String(v).trim() === '' || String(v).trim() === '-' || String(v).trim().toLowerCase() === 'n/a';

function _tcPhoneHtml(phone) {
    if (_tcEmpty(phone)) return '<span style="color:#64748b;font-size:0.82rem;">N/A</span>';
    let norm = String(phone).replace(/[\s\-\(\)\.]/g, '').replace(/^\+/, '');
    if      (norm.startsWith('880') && norm.length === 13) norm = '0' + norm.slice(3);
    else if (norm.startsWith('88')  && norm.length === 12) norm = '0' + norm.slice(2);
    else if (norm.startsWith('1')   && norm.length === 10) norm = '0' + norm;
    const display = `<span style="font-size:0.85rem;font-weight:600;">${escH(norm)}</span>`;
    if (!/^01\d{9}$/.test(norm)) return display;
    return `${display}
            <a href="https://wa.me/88${norm}" target="_blank"
                style="margin-left:6px;color:#25D366;font-size:1rem;" title="WhatsApp">
                <i class="fa-brands fa-whatsapp"></i></a>`;
}

async function loadTeachers(body) {
    body.innerHTML = '<div class="info-loading-spin"><div class="spin-sm"></div> Loading Teachers & Courses...</div>';
    try {
        /* Reuse already-fetched routine data if the Routine tab was visited first */
        const routinePromise = (typeof _allDayResults !== 'undefined' && _allDayResults)
            ? Promise.resolve(_allDayResults)
            : (typeof fetchAllRoutineDays === 'function' ? fetchAllRoutineDays().catch(() => null) : Promise.resolve(null));

        const [cpgTeacherData, dayResults, cpgCoursesData] = await Promise.all([
            fetchSheet('CPG_Teachers').catch(() => null),
            routinePromise,
            fetchSheet('CPG_Courses').catch(() => null),
        ]);

        /* ── Build full teacher directory from CPG_Teachers ── */
        const directory   = {}; /* lowercase name → teacher info */
        const initialsMap = {}; /* uppercase initials → lowercase name */
        if (cpgTeacherData?.table) {
            const tRows  = cpgTeacherData.table.rows || [];
            const hCells = (cpgTeacherData.table.cols || [])
                .map(c => (c?.label != null ? String(c.label).trim().toLowerCase() : ''));

            let initCol = hCells.findIndex(h => /initial|abbr|short|code|acronym/.test(h));
            let nameCol = hCells.findIndex(h => /^name$|teacher/.test(h));
            let deCol   = hCells.findIndex(h => /designation/.test(h));
            let dpCol   = hCells.findIndex(h => /department/.test(h));
            let phCol   = hCells.findIndex(h => /phone|cell/.test(h));
            let emCol   = hCells.findIndex(h => /email/.test(h));

            /* Fallback column layout: A=Acronym B=Name C=Designation D=Department E=Cell F=Email */
            if (initCol < 0) initCol = 0;
            if (nameCol < 0) nameCol = 1;
            if (deCol   < 0) deCol   = 2;
            if (dpCol   < 0) dpCol   = 3;
            if (phCol   < 0) phCol   = 4;
            if (emCol   < 0) emCol   = 5;

            tRows.forEach(row => {
                const cells = (row.c || []).map(c => {
                    if (!c) return '';
                    const fv = c.f != null ? String(c.f).trim() : '';
                    const vv = c.v != null ? String(c.v).trim() : '';
                    return fv || vv;
                });
                const init = cells[initCol]?.toUpperCase().trim();
                const name = cells[nameCol];
                if (!init || !name) return;

                /* Resolve phone/email by CONTENT, not fixed column. Cross-department
                   / guest teachers carry an extra "institution" cell (" LU", " SUST", …)
                   that shifts the Cell & Email columns one or two places right, so the
                   header position alone is unreliable. Take the cell that actually holds
                   an "@" as the email and the one that reads as a phone number; fall back
                   to the header column when nothing better is found. */
                const looksEmail = v => /\S+@\S+\.\S+/.test(v);
                const looksPhone = v => /^\+?\d{7,}$/.test(String(v).replace(/[\s\-()+.]/g, ''));
                let phone = cells[phCol] || '';
                let email = cells[emCol] || '';
                if (!looksEmail(email)) {
                    email = cells.find((v, i) => i > nameCol && looksEmail(v)) || '';
                }
                if (!looksPhone(phone)) {
                    const p = cells.find((v, i) => i > nameCol && v !== email && looksPhone(v));
                    if (p) phone = p;
                }

                const key  = name.toLowerCase().trim();
                const prev = directory[key] || {};
                const pick = (existing, incoming) => _tcEmpty(existing) ? (incoming || '') : existing;
                directory[key] = {
                    name,
                    designation: pick(prev.designation, cells[deCol]),
                    department:  pick(prev.department,  cells[dpCol]),
                    phone:       pick(prev.phone,       phone),
                    email:       pick(prev.email,       email),
                };
                initialsMap[init] = key;
            });
        }

        /* ── Build course title lookup from CPG_Courses (code → title) ── */
        const courseTitles = {};
        if (cpgCoursesData) {
            const rows = sheetRows(cpgCoursesData);
            const headerRow = rows[0] || [];
            const isHeader  = headerRow.some(h => /title|code|course/i.test(h));
            const dataStart = isHeader ? 1 : 0;
            /* CPG_Courses: A=Title, B=Code (or derive from column headers) */
            let titleIdx = 0, codeIdx = 1;
            if (isHeader) {
                const lo = headerRow.map(h => (h||'').toLowerCase());
                const ti = lo.findIndex(h => h.includes('title'));
                const ci = lo.findIndex(h => h.includes('code'));
                if (ti >= 0) titleIdx = ti;
                if (ci >= 0) codeIdx  = ci;
            }
            rows.slice(dataStart).forEach(r => {
                const code = (r[codeIdx] || '').trim().toUpperCase();
                const title = (r[titleIdx] || '').trim();
                if (code && title) courseTitles[code] = title;
            });
        }

        /* ── Build teacher→course map from Class Routine (Batch 62, Section B) ── */
        const teacherMap = new Map(); /* uppercase initials → teacher entry */

        if (dayResults) {
            ROUTINE_DAY_NAMES.forEach((dayName, idx) => {
                const data = dayResults[idx];
                if (!data?.table) return;
                const rows = data.table.rows || [];
                const cols = data.table.cols || [];
                if (!rows.length) return;

                /* Find data start row (time header may be in col labels or first rows) */
                let dataStart = 0;
                const colTimes = cols.slice(3).map(c => (c.label||'').trim());
                if (!colTimes.some(t => /\d+:\d+/.test(t))) {
                    for (let r = 0; r < Math.min(rows.length, 3); r++) {
                        const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
                        if (cells.slice(3).some(c => /\d+:\d+/.test(c))) { dataStart = r + 1; break; }
                    }
                }

                for (let r = dataStart; r < rows.length; r++) {
                    const cells = (rows[r].c || []).map(c => c?.v != null ? String(c.v).trim() : '');
                    /* Only process rows for Batch 62, Section B */
                    const rowBatch = String(cells[1]?.trim() || '').replace(/\.0+$/, '');
                    if (rowBatch !== '62' || cells[2]?.trim().toUpperCase() !== 'B') continue;

                    cells.slice(3).forEach(cell => {
                        const parsed = typeof parseClassCell === 'function' ? parseClassCell(cell) : null;
                        if (!parsed?.code) return;
                        const initials = (parsed.initials || '').toUpperCase().trim();
                        if (!initials || initials === 'BREAK') return;

                        const code    = parsed.code.trim().toUpperCase();
                        const dirKey  = initialsMap[initials];
                        const dir     = dirKey ? directory[dirKey] : null;

                        if (!teacherMap.has(initials)) {
                            teacherMap.set(initials, {
                                name:        dir?.name        || initials,
                                designation: dir?.designation || '',
                                department:  dir?.department  || '',
                                phone:       dir?.phone       || '',
                                email:       dir?.email       || '',
                                courses:     [],
                                _initials:   initials,
                            });
                        }

                        const teacher = teacherMap.get(initials);
                        /* Upgrade contact info if directory has it and teacher entry doesn't yet */
                        if (dir) {
                            if (teacher.name === initials && dir.name) teacher.name = dir.name;
                            if (_tcEmpty(teacher.phone) && dir.phone) teacher.phone = dir.phone;
                            if (_tcEmpty(teacher.email) && dir.email) teacher.email = dir.email;
                            if (!teacher.designation && dir.designation) teacher.designation = dir.designation;
                            if (!teacher.department  && dir.department)  teacher.department  = dir.department;
                        }

                        /* Add course if not already listed */
                        if (code && !teacher.courses.some(c => c.code === code)) {
                            teacher.courses.push({ code, title: courseTitles[code] || '' });
                        }
                    });
                }
            });
        }

        /* ── Merge enrolled retake/improve teachers ── */
        const user = JSON.parse(
            localStorage.getItem('lu62b_student') ||
            sessionStorage.getItem('lu62b_student') ||
            'null'
        );
        if (user?.id) {
            try {
                {
                    // fetchEnrollments() resolves to [] when it cannot reach
                    // the Worker, so there is nothing left to guard on.
                    const enrollments = await window.fetchEnrollments(user.id);
                    enrollments.forEach(enr => {
                        if (!enr.teacher) return;
                        const init   = enr.teacher.toUpperCase();
                        const dirKey = initialsMap[init];
                        const info   = dirKey ? directory[dirKey] : null;
                        const key    = init; /* use initials as map key (same as above) */

                        const enrolledCourse = {
                            title:    enr.course_name || courseTitles[enr.course_code?.toUpperCase()] || enr.course_code || '',
                            code:     enr.course_code || '',
                            enrolled: enr.type,
                        };

                        if (teacherMap.has(key)) {
                            const existing   = teacherMap.get(key);
                            const alreadyHas = existing.courses.some(c => c.code === enr.course_code);
                            if (!alreadyHas && enrolledCourse.code) existing.courses.push(enrolledCourse);
                            if (info?.phone && _tcEmpty(existing.phone)) existing.phone = info.phone;
                            if (info?.email && _tcEmpty(existing.email)) existing.email = info.email;
                        } else {
                            teacherMap.set(key, {
                                name:           info?.name || enr.teacher,
                                designation:    info?.designation || '',
                                department:     info?.department  || '',
                                phone:          info?.phone || '',
                                email:          info?.email || '',
                                courses:        enrolledCourse.code ? [enrolledCourse] : [],
                                isEnrolledOnly: true,
                                _initials:      init,
                            });
                        }
                    });
                }
            } catch(e) { /* silently skip */ }
        }

        const teachers  = Array.from(teacherMap.values());
        const dirCount  = Object.keys(directory).length;

        if (!teachers.length && !dirCount) {
            body.innerHTML = '<div class="info-placeholder"><p>No teacher data found.</p></div>';
            return;
        }

        /* ── Render cards ── */
        let cardsHtml = '';
        teachers.forEach(t => {
            const tKey       = (t._initials || t.name).toLowerCase().trim();
            const searchText = [t.name, t.designation, t.department, ...t.courses.map(c => c.code + ' ' + c.title)]
                .join(' ').toLowerCase();

            const coursesHtml = t.courses.map(c => {
                let badge = '';
                if (c.enrolled === 'retake') {
                    badge = `<span style="margin-left:6px;font-size:0.58rem;font-weight:800;padding:1px 6px;
                        border-radius:4px;background:rgba(244,63,94,.18);color:#f43f5e;
                        border:1px solid rgba(244,63,94,.3);letter-spacing:0.04em;
                        vertical-align:middle;">RETAKE</span>`;
                } else if (c.enrolled === 'improve') {
                    badge = `<span style="margin-left:6px;font-size:0.58rem;font-weight:800;padding:1px 6px;
                        border-radius:4px;background:rgba(251,146,60,.18);color:#fb923c;
                        border:1px solid rgba(251,146,60,.3);letter-spacing:0.04em;
                        vertical-align:middle;">IMPROVE</span>`;
                }
                return `<div style="font-size:0.72rem;background:rgba(124,58,237,0.1);
                    border:1px solid rgba(124,58,237,0.2);padding:4px 8px;border-radius:6px;
                    color:var(--text);margin-bottom:4px;">
                    <strong style="color:var(--accent-bright);">${escH(c.code)}:</strong>
                    ${escH(c.title)}${badge}</div>`;
            }).join('');

            cardsHtml += `
                <div class="info-item-card tc-card" data-search="${escH(searchText)}" data-name="${escH(tKey)}" style="display:flex;flex-direction:column;">
                    <div style="margin-bottom:12px;">
                        <div style="font-size:1.05rem;font-weight:700;color:var(--text);">${escH(t.name)}</div>
                        ${t.designation ? `<div style="font-size:0.78rem;color:var(--accent-bright);font-weight:600;margin-bottom:2px;">${escH(t.designation)}</div>` : ''}
                        ${t.department  ? `<div style="font-size:0.7rem;color:var(--text-secondary);opacity:0.8;">${escH(t.department)}</div>` : ''}
                    </div>
                    ${coursesHtml ? `
                    <div style="margin-bottom:12px;">
                        <div style="font-size:0.65rem;text-transform:uppercase;letter-spacing:0.05em;
                            color:var(--text-secondary);margin-bottom:6px;font-weight:700;">Assigned Courses</div>
                        ${coursesHtml}
                    </div>` : ''}
                    <div style="margin-top:auto;padding-top:10px;border-top:1px solid rgba(255,255,255,0.05);">
                        <div style="font-size:0.8rem;margin-bottom:5px;">
                            <i class="fa-solid fa-phone" style="width:18px;opacity:0.5;"></i> ${_tcPhoneHtml(t.phone)}
                        </div>
                        <div style="font-size:0.8rem;word-break:break-all;">
                            <i class="fa-solid fa-envelope" style="width:18px;opacity:0.5;"></i>
                            ${!_tcEmpty(t.email)
                                ? `<a href="mailto:${t.email}" style="color:var(--accent-bright);text-decoration:none;">${escH(t.email)}</a>`
                                : '<span style="color:#64748b;">N/A</span>'}
                        </div>
                    </div>
                </div>`;
        });

        /* ── Autocomplete suggestions from ALL CPG_Teachers ── */
        const tcSuggestions = Object.values(directory).map(t => ({
            label: t.name,
            sub:   t.designation || '',
            key:   t.name.toLowerCase().trim(),
        }));

        body.innerHTML = `
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:16px;flex-wrap:wrap;">
                <span id="tcCountLabel" style="flex:1;font-size:0.78rem;color:var(--text-secondary);">
                    ${teachers.length
                        ? `${teachers.length} teacher${teachers.length !== 1 ? 's' : ''}`
                        : `<i class="fa-solid fa-magnifying-glass" style="margin-right:5px;opacity:0.5;"></i>Search any of ${dirCount} teachers`}
                </span>
                <div style="position:relative;" id="tcSearchWrap">
                    <i class="fa-solid fa-magnifying-glass" style="position:absolute;left:10px;top:50%;
                        transform:translateY(-50%);opacity:0.4;font-size:0.78rem;pointer-events:none;z-index:1;"></i>
                    <input id="tcSearchInput" type="text" placeholder="Search teachers or courses…"
                        autocomplete="off"
                        style="background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.12);
                        border-radius:8px;padding:7px 12px 7px 30px;color:var(--text);font-size:0.82rem;
                        outline:none;width:230px;transition:border-color .2s;"
                        onfocus="this.style.borderColor='var(--accent-bright)'"
                        onblur="this.style.borderColor='var(--border)'" />
                    <div id="tcDropdown" style="display:none;position:absolute;top:calc(100% + 5px);right:0;
                        min-width:260px;max-height:260px;overflow-y:auto;
                        background:var(--surface);border:1px solid rgba(124,58,237,0.35);
                        border-radius:10px;box-shadow:0 8px 32px rgba(0,0,0,0.5);z-index:9999;"></div>
                </div>
            </div>
            <!-- directory lookup result (shown when searched teacher not in current list) -->
            <div id="tcDirResult" style="display:none;margin-bottom:16px;
                border:1px solid rgba(124,58,237,0.3);border-radius:12px;
                background:rgba(124,58,237,0.07);padding:16px 20px;">
                <div style="font-size:0.65rem;text-transform:uppercase;letter-spacing:0.06em;
                    color:var(--accent-bright);font-weight:700;margin-bottom:10px;">
                    <i class="fa-solid fa-address-card" style="margin-right:6px;"></i>Teacher Directory Result
                </div>
                <div id="tcDirContent"></div>
            </div>
            <div class="info-card-grid" id="tcGrid">${cardsHtml}</div>
            ${!teachers.length ? `
            <div id="tcEmptyHint" style="padding:40px 20px;text-align:center;color:var(--text-secondary);font-size:0.85rem;">
                <i class="fa-solid fa-chalkboard-user" style="opacity:0.25;font-size:2rem;display:block;margin-bottom:12px;"></i>
                No course teachers found in the class routine.<br>
                <span style="font-size:0.78rem;opacity:0.8;">Type a name above to look up any teacher's contact.</span>
            </div>` : ''}
            <div id="tcNoResult" style="display:none;padding:40px;text-align:center;
                color:var(--text-secondary);font-size:0.9rem;">No teachers found.</div>`;

        const searchInput = body.querySelector('#tcSearchInput');
        const countLabel  = body.querySelector('#tcCountLabel');
        const grid        = body.querySelector('#tcGrid');
        const noResult    = body.querySelector('#tcNoResult');
        const dropdown    = body.querySelector('#tcDropdown');
        const dirResult   = body.querySelector('#tcDirResult');
        const dirContent  = body.querySelector('#tcDirContent');
        const cards       = grid.querySelectorAll('.tc-card');
        let acFocused = -1;

        const emptyHint = body.querySelector('#tcEmptyHint');

        function tcDirCardInner(t) {
            return `
                <div style="font-size:1.05rem;font-weight:700;color:var(--text);margin-bottom:4px;">${escH(t.name)}</div>
                ${t.designation ? `<div style="font-size:0.78rem;color:var(--accent-bright);font-weight:600;margin-bottom:2px;">${escH(t.designation)}</div>` : ''}
                ${t.department  ? `<div style="font-size:0.7rem;color:var(--text-secondary);opacity:0.8;margin-bottom:10px;">${escH(t.department)}</div>` : ''}
                <div style="font-size:0.8rem;margin-bottom:5px;">
                    <i class="fa-solid fa-phone" style="width:18px;opacity:0.5;"></i> ${_tcPhoneHtml(t.phone)}
                </div>
                <div style="font-size:0.8rem;word-break:break-all;">
                    <i class="fa-solid fa-envelope" style="width:18px;opacity:0.5;"></i>
                    ${!_tcEmpty(t.email)
                        ? `<a href="mailto:${t.email}" style="color:var(--accent-bright);text-decoration:none;">${escH(t.email)}</a>`
                        : '<span style="color:#64748b;">N/A</span>'}
                </div>`;
        }

        function tcApplyFilter(q) {
            const lq = q.toLowerCase().trim();
            let visible = 0;
            const inGrid = new Set();
            cards.forEach(card => {
                const match = !lq || card.dataset.search.includes(lq);
                card.style.display = match ? '' : 'none';
                if (match) { visible++; inGrid.add(card.dataset.name); }
            });

            let dirMatches = [];
            if (lq.length >= 2) {
                dirMatches = Object.entries(directory)
                    .filter(([key, t]) => !inGrid.has(key)
                        && `${t.name} ${t.designation} ${t.department}`.toLowerCase().includes(lq))
                    .map(([, t]) => t)
                    .sort((a, b) => a.name.localeCompare(b.name))
                    .slice(0, 12);
            }
            if (dirMatches.length) {
                dirContent.innerHTML = `<div style="display:flex;flex-direction:column;gap:10px;">${
                    dirMatches.map(t => `
                    <div style="border:1px solid rgba(124,58,237,0.18);border-radius:10px;
                        background:rgba(255,255,255,0.02);padding:12px 14px;">${tcDirCardInner(t)}</div>`).join('')
                }</div>`;
                dirResult.style.display = '';
            } else {
                dirContent.innerHTML = '';
                dirResult.style.display = 'none';
            }

            if (emptyHint) emptyHint.style.display = (lq || dirMatches.length) ? 'none' : '';

            countLabel.innerHTML = lq
                ? `${visible + dirMatches.length} match${(visible + dirMatches.length) !== 1 ? 'es' : ''}`
                : (teachers.length
                    ? `${teachers.length} teacher${teachers.length !== 1 ? 's' : ''}`
                    : `<i class="fa-solid fa-magnifying-glass" style="margin-right:5px;opacity:0.5;"></i>Search any of ${dirCount} teachers`);

            noResult.style.display = (visible === 0 && dirMatches.length === 0 && lq) ? '' : 'none';
            grid.style.display     = visible === 0 ? 'none' : '';
        }

        function tcCloseDrop() {
            dropdown.style.display = 'none';
            dropdown.innerHTML = '';
            acFocused = -1;
        }

        function tcShowDrop(q) {
            if (!q || q.length < 1) { tcCloseDrop(); return; }
            const lq   = q.toLowerCase();
            const hits = tcSuggestions.filter(s =>
                s.label.toLowerCase().includes(lq) || s.sub.toLowerCase().includes(lq)
            ).slice(0, 8);
            if (!hits.length) { tcCloseDrop(); return; }

            dropdown.innerHTML = hits.map((s, i) => `
                <div class="tc-ac-item" data-idx="${i}" data-key="${escH(s.key)}" data-label="${escH(s.label)}"
                    style="padding:8px 12px;cursor:pointer;display:flex;flex-direction:column;gap:1px;
                    border-bottom:1px solid rgba(255,255,255,0.05);transition:background .15s;">
                    <span style="font-size:0.83rem;font-weight:600;color:var(--text);">${escH(s.label)}</span>
                    ${s.sub ? `<span style="font-size:0.7rem;color:var(--text-secondary);opacity:0.75;">${escH(s.sub)}</span>` : ''}
                </div>`).join('');
            dropdown.style.display = 'block';
            acFocused = -1;

            dropdown.querySelectorAll('.tc-ac-item').forEach(item => {
                item.addEventListener('mouseenter', () => {
                    dropdown.querySelectorAll('.tc-ac-item').forEach(el => el.style.background = '');
                    item.style.background = 'rgba(124,58,237,0.18)';
                });
                item.addEventListener('mouseleave', () => { item.style.background = ''; });
                item.addEventListener('mousedown', e => {
                    e.preventDefault();
                    const label = item.dataset.label;
                    searchInput.value = label;
                    tcApplyFilter(label);
                    tcCloseDrop();
                });
            });
        }

        searchInput.addEventListener('input', () => {
            const q = searchInput.value;
            tcApplyFilter(q);
            tcShowDrop(q.trim());
        });

        searchInput.addEventListener('keydown', e => {
            const items = dropdown.querySelectorAll('.tc-ac-item');
            if (!items.length) return;
            if (e.key === 'ArrowDown') {
                e.preventDefault();
                acFocused = Math.min(acFocused + 1, items.length - 1);
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                acFocused = Math.max(acFocused - 1, 0);
            } else if (e.key === 'Enter' && acFocused >= 0) {
                e.preventDefault();
                items[acFocused].dispatchEvent(new MouseEvent('mousedown'));
                return;
            } else if (e.key === 'Escape') {
                tcCloseDrop(); return;
            } else { return; }
            items.forEach((el, i) => {
                el.style.background = i === acFocused ? 'rgba(124,58,237,0.18)' : '';
            });
        });

        searchInput.addEventListener('blur', () => setTimeout(tcCloseDrop, 150));
        document.addEventListener('click', e => {
            if (!body.querySelector('#tcSearchWrap')?.contains(e.target)) tcCloseDrop();
        }, { capture: true });

    } catch (err) {
        console.error(err);
        body.innerHTML = '<div class="info-placeholder"><p>Error loading teacher data.</p></div>';
    }
}
