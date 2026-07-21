/* ═══════════════════════════════════════════════════════════════════
   CSE 62B · Cinematic engine
   Two modes, chosen automatically:

   STAGE mode (homepage — #cineWrap present)
     phase A (0 → .24)  energy core boots in the centre
     phase B (.24 → 1)  core parks up top, the real navigation grid
                        assembles card by card with the scrollbar

   INNER mode (every other page)
     · ambient amber/cyan dust drifting behind the content
     · reversible scroll-scrub entrances for card grids and section
       headers — driven by the scrollbar, backwards too

   Degrades safely: on reduced motion, missing canvas, or script
   failure every page renders as its normal static layout.
   ═══════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce) return;                        // static site, untouched

  function stp(x) { x = Math.max(0, Math.min(1, x)); return x * x * (3 - 2 * x); }
  function easeIO(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  var DPR = Math.min(2, window.devicePixelRatio || 1);

  /* ── shared: reversible scroll-scrub for a list of {el, dir, d} ── */
  function makeScrub(items) {
    function scrub() {
      var vh = innerHeight;
      for (var i = 0; i < items.length; i++) {
        var o = items[i];
        var r = o.el.getBoundingClientRect();
        var p = (vh * 0.96 - r.top) / (vh * 0.42);
        var e = stp((p - o.d) / (1 - o.d * 0.5));
        if (e >= 0.999) {
          /* hand the element back to the stylesheet (hover effects etc.) */
          if (o.on) { o.el.style.transform = ''; o.el.style.opacity = ''; o.on = false; }
        } else {
          o.on = true;
          var t;
          if (o.dir === 'left')      t = 'translateX(' + (1 - e) * -60 + 'px)';
          else if (o.dir === 'right') t = 'translateX(' + (1 - e) * 60 + 'px)';
          else                        t = 'translateY(' + (1 - e) * 46 + 'px) scale(' + (0.9 + e * 0.1) + ')';
          o.el.style.transform = t;
          o.el.style.opacity = e.toFixed(3);
        }
      }
    }
    var tick = false;
    addEventListener('scroll', function () {
      if (!tick) { tick = true; requestAnimationFrame(function () { scrub(); tick = false; }); }
    }, { passive: true });
    addEventListener('resize', scrub);
    scrub();
  }

  /* ═════════════════════ INNER MODE ═════════════════════ */
  function innerMode() {
    /* ambient dust behind the content (wrapper sits at z-index 1) */
    try {
      var dc = document.createElement('canvas');
      dc.id = 'cineDust';
      dc.style.cssText = 'position:fixed;inset:0;z-index:0;pointer-events:none;';
      document.body.insertBefore(dc, document.body.firstChild);
      var dctx = dc.getContext('2d');
      if (dctx) {
        var DW = 0, DH = 0, idle = 0;
        var drs = function () {
          DW = innerWidth; DH = innerHeight;
          dc.width = DW * DPR; dc.height = DH * DPR;
          dctx.setTransform(DPR, 0, 0, DPR, 0, 0);
        };
        addEventListener('resize', drs); drs();
        var dust = [];
        for (var j = 0; j < 40; j++) {
          dust.push({
            x: Math.random(), y: Math.random(), s: 0.6 + Math.random() * 1.6,
            v: 0.00014 + Math.random() * 0.00035, o: 0.04 + Math.random() * 0.12,
            c: Math.random() > 0.5, ph: Math.random() * 6.28
          });
        }
        (function ddraw() {
          if (!document.hidden) {
            idle += 0.01;
            dctx.clearRect(0, 0, DW, DH);
            for (var i = 0; i < dust.length; i++) {
              var d = dust[i];
              d.y -= d.v;
              if (d.y < -0.02) { d.y = 1.02; d.x = Math.random(); }
              var tw = 0.6 + 0.4 * Math.sin(idle * 2 + d.ph);
              dctx.beginPath();
              dctx.arc(d.x * DW, d.y * DH, d.s, 0, 7);
              dctx.fillStyle = (d.c ? 'rgba(63,224,224,' : 'rgba(255,182,72,') + d.o * tw + ')';
              dctx.fill();
            }
          }
          requestAnimationFrame(ddraw);
        })();
      }
    } catch (e) { /* ambience is optional */ }

    /* scroll-scrub entrances for static card grids + section headers.
       Sensitive zones are excluded: the cover-page form/preview (PDF
       capture), the homepage stage, and anything under [data-cine-off]. */
    try {
      var EXCLUDE = '#cineWrap, #coverPreview, .cg-panel, .cg-preview-outer, [data-cine-off]';
      var items = [], seen = [];
      var heads = document.querySelectorAll('.section-header');
      for (var h = 0; h < heads.length; h++) {
        if (heads[h].closest(EXCLUDE)) continue;
        items.push({ el: heads[h], dir: 'left', d: 0, on: false });
      }
      var grids = document.querySelectorAll('[class*="-grid"]');
      for (var g = 0; g < grids.length && items.length < 90; g++) {
        var grid = grids[g];
        if (grid.closest(EXCLUDE)) continue;
        if (seen.indexOf(grid) !== -1) continue;
        seen.push(grid);
        var kids = grid.children;
        var n = Math.min(kids.length, 24);
        if (n < 2) continue;
        for (var k = 0; k < n && items.length < 90; k++) {
          if (kids[k].nodeType !== 1) continue;
          items.push({ el: kids[k], dir: 'up', d: (k % 6) * 0.08, on: false });
        }
      }
      if (items.length) makeScrub(items);
    } catch (e) { /* entrances are optional */ }
  }

  /* ═════════════════════ STAGE MODE ═════════════════════ */
  function stageMode(wrap) {
    var cv = document.getElementById('cineCore');
    var ctx = cv && cv.getContext ? cv.getContext('2d') : null;
    if (!ctx) return;

    var stage    = wrap.querySelector('.cine-stage');
    var navZone  = document.getElementById('cineNavZone');
    var headline = document.getElementById('cineHeadline');
    var quote    = document.getElementById('cineQuote');
    var kick     = document.getElementById('cineKick');
    var boot     = document.getElementById('cineBoot');
    var bar      = document.getElementById('cineBar');
    var pct      = document.getElementById('cinePct');
    var cntEl    = document.getElementById('cineCnt');
    var brs = ['cineBkTL', 'cineBkTR', 'cineBkBL', 'cineBkBR'].map(function (id) {
      return document.getElementById(id);
    });

    /* only animate cards that are actually visible (attendance card is
       display:none for non-CR users) */
    var grid  = navZone ? navZone.querySelector('.folders-grid') : null;
    var cards = grid ? [].slice.call(grid.children).filter(function (el) {
      return el.nodeType === 1 && getComputedStyle(el).display !== 'none';
    }) : [];
    var N = cards.length;

    var W = 0, H = 0, prog = 0, target = 0, idle = 0;
    var A = 0.24;

    var particles = [];
    for (var i = 0; i < 80; i++) {
      particles.push({
        a: Math.random() * 6.28, r: 0.4 + Math.random() * 1.1,
        y: (Math.random() - 0.5) * 1.6, sp: 0.003 + Math.random() * 0.01,
        size: 0.5 + Math.random() * 1.8, tw: Math.random() * 6
      });
    }

    function resize() {
      var r = stage.getBoundingClientRect();
      W = r.width; H = r.height;
      cv.width = W * DPR; cv.height = H * DPR;
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    }
    addEventListener('resize', resize); resize();

    function onScroll() {
      var r = wrap.getBoundingClientRect();
      var span = wrap.offsetHeight - innerHeight;
      target = span > 0 ? Math.max(0, Math.min(1, -r.top / span)) : 0;
    }
    addEventListener('scroll', onScroll, { passive: true }); onScroll();

    function draw() {
      prog += (target - prog) * 0.1;
      idle += 0.01;
      var pa = stp(prog / A);
      var pb = Math.max(0, Math.min(1, (prog - A) / (1 - A)));
      ctx.clearRect(0, 0, W, H);
      var base = Math.min(W, H);

      var park   = stp(pb * 1.6);
      var grow   = lerp(0.25 + easeIO(pa) * 1.05, 0.42, park);
      var cy     = lerp(H * (0.62 - easeIO(pa) * 0.18), H * 0.15, park);
      var cx     = W / 2 + Math.sin(prog * Math.PI) * W * 0.05;
      var bright = lerp(0.25 + pa * 0.75, 0.5, park);
      var rot    = prog * Math.PI * 7 + idle * 0.3;
      var R      = base * 0.2 * grow;
      var bloom  = Math.sin(pa * Math.PI) * (1 - park * 0.8);

      var g = ctx.createRadialGradient(cx, cy, 0, cx, cy, base * 0.55 * grow);
      g.addColorStop(0, 'rgba(255,182,72,' + 0.18 * bright + ')');
      g.addColorStop(0.5, 'rgba(255,138,60,' + 0.06 * bright + ')');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

      for (var k = 0; k < 5; k++) {
        var ph = rot * (1 + k * 0.22) + k;
        var ry = Math.abs(Math.sin(ph)) * 0.9 + 0.08;
        ctx.save(); ctx.translate(cx, cy); ctx.rotate(k * 0.5 + rot * 0.15);
        ctx.beginPath();
        for (var t = 0; t <= 6.38; t += 0.16) {
          var x = Math.cos(t) * R * (1 + k * 0.15), y = Math.sin(t) * R * (1 + k * 0.15) * ry;
          if (t === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = (k % 2 ? 'rgba(63,224,224,' : 'rgba(255,182,72,') + (0.3 * bright + 0.08) + ')';
        ctx.lineWidth = 1.2; ctx.stroke(); ctx.restore();
      }

      for (var p2 = 0; p2 < particles.length; p2++) {
        var p = particles[p2];
        p.a += p.sp * (0.5 + prog * 1.4);
        var rr = R * (1 + p.r * (0.5 + bloom * 1.6));
        var depth = Math.cos(p.a + rot * 0.3);
        var px = cx + Math.cos(p.a) * rr;
        var py = cy + Math.sin(p.a) * rr * 0.44 + p.y * R * 0.5;
        var sc = (depth + 1.4) / 2.4;
        var tw = 0.6 + 0.4 * Math.sin(idle * 3 + p.tw);
        ctx.beginPath(); ctx.arc(px, py, p.size * sc * (0.6 + prog * 0.7), 0, 7);
        ctx.fillStyle = 'rgba(' + (depth > 0 ? '255,205,120' : '110,224,224') + ',' + (0.2 + sc * 0.7 * bright) * tw + ')';
        ctx.fill();
      }

      var cg = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * 0.62);
      cg.addColorStop(0, 'rgba(255,246,220,' + bright + ')');
      cg.addColorStop(0.4, 'rgba(255,182,72,' + 0.75 * bright + ')');
      cg.addColorStop(1, 'rgba(255,138,60,0)');
      ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(cx, cy, R * 0.62, 0, 7); ctx.fill();

      if (headline) {
        var hFade = 1 - stp(pb * 3);
        headline.style.opacity = (stp(pa * 2.2) * hFade).toFixed(3);
        headline.style.transform = 'translateY(' + ((1 - stp(pa * 2.2)) * 60 - stp(pb * 3) * 60) + 'px)';
      }
      if (quote) {
        var qShow = stp((pa - 0.25) * 3) * (1 - stp(pb * 3));
        quote.style.transform = 'translateX(' + (1 - qShow) * -40 + 'px)';
        quote.style.opacity = qShow.toFixed(3);
      }

      var done = 0;
      if (navZone && N) {
        navZone.style.opacity = stp(pb * 5).toFixed(3);
        navZone.style.pointerEvents = pb > 0.05 ? 'auto' : 'none';
        var win = 1.9 / N;
        for (var c = 0; c < N; c++) {
          var st = (c / N) * (1 - win);
          var e = stp((pb - st) / win);
          var el = cards[c];
          if (e >= 0.999) {
            el.style.transform = ''; el.style.opacity = '';
            done++;
          } else {
            el.style.transform = 'translateY(' + (1 - e) * 70 + 'px) scale(' + (0.82 + e * 0.18) + ')';
            el.style.opacity = e.toFixed(3);
            if (e > 0.5) done++;
          }
        }
      }
      if (cntEl) cntEl.textContent = Math.min(done, N) + '/' + N;

      if (bar) bar.style.width = prog * 100 + '%';
      if (boot) boot.textContent = pb <= 0 ? (pa < 1 ? 'CORE // BOOT' : 'CORE // READY')
                                          : (pb >= 0.97 ? 'CORE // ONLINE' : 'CORE // LOADING');
      if (kick) kick.textContent = pa < 1 ? '// booting' : '// systems online';
      var bo = easeIO(prog) * 10;
      var bt = [[-bo, -bo], [bo, -bo], [-bo, bo], [bo, bo]];
      for (var b = 0; b < 4; b++) {
        if (brs[b]) brs[b].style.transform = 'translate(' + bt[b][0] + 'px,' + bt[b][1] + 'px)';
      }
      if (pct) pct.textContent = pb <= 0
        ? 'BOOT ' + String(Math.round(pa * 100)).padStart(2, '0') + '%'
        : (pb >= 0.97 ? 'ONLINE' : 'MODULES ' + Math.min(done, N) + '/' + N);

      requestAnimationFrame(draw);
    }
    requestAnimationFrame(draw);

    /* scrub entrances for the homepage sections below the stage */
    try {
      var items = [];
      var below = document.querySelectorAll('.grad-strip, .hero, .qi-strip, .deadlines-wrap, .memories-section, .contact-panel');
      for (var s2 = 0; s2 < below.length; s2++) {
        items.push({ el: below[s2], dir: 'up', d: 0, on: false });
      }
      if (items.length) makeScrub(items);
    } catch (e) {}
  }

  var wrap = document.getElementById('cineWrap');
  if (wrap) stageMode(wrap); else innerMode();
})();
