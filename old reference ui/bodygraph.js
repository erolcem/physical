// ════════════════════════════════════════════════════════
// ui/bodygraph.js — Body screen renderer
// Layout (top→bottom):
//   1. Overall rank card
//   2. Aesthetics & Armor icon strip  ← NEW position
//   3. Three bodygraphs (Front | Inner | Back)
//   4. Strength Metrics text grid
//   5. Performance & Recovery text grid ← NEW
// ════════════════════════════════════════════════════════

import { RANKS, MUSCLES, SUB } from '../data/metrics.js';
import { rankOf, getSubrank, latestORM, overallScore, getPrecisePercentOverall } from '../engine/rank.js';
import { getLogs } from '../engine/state.js';
import { injectBadge } from './badge.js';
import { openSheet } from './sheet.js';

// ── APPLY RANK COLOURS TO ALL THREE SVG FIGURES
export function applyColors(logs) {
  MUSCLES.forEach(m => {
    const ri       = rankOf(m.id, latestORM(m.id, logs));
    const col      = RANKS[ri].c;
    const isRanked = ri > 0;
    [...(m.front || []), ...(m.back || []), ...(m.inner || [])].forEach(id => {
      const g = document.getElementById(id);
      if (!g) return;
      g.querySelectorAll('path,rect,ellipse,polygon,circle').forEach(s => {
        const f = s.getAttribute('fill') || '';
        if (f === 'none' || f.startsWith('rgba(255,255,255') || f.startsWith('rgba(0,0,0') || f.startsWith('url(')) return;
        if (f === '#c8cee0' || f === '#c8a830') return;
        s.setAttribute('fill', col);
        s.setAttribute('opacity', isRanked ? '0.88' : '0.15');
        s.style.filter = isRanked ? `drop-shadow(0 0 7px ${col}90)` : 'none';
      });
    });
  });
}

// ── INNER BODYGRAPH SVG
function _innerSVG() {
  return `<svg width="148" viewBox="0 0 148 420" xmlns="http://www.w3.org/2000/svg">
    <polygon points="64,15 84,15 90,45 130,65 140,190 120,200 130,110 100,100 100,170 120,265 110,360 85,360 74,200 63,360 38,360 28,265 48,170 48,100 18,110 28,200 8,190 18,65 58,45" fill="#1c1e3a"/>
    <polygon points="66,15 82,15 86,35 62,35" fill="#3a3f58"/>
    <g class="mr" id="I-brain" data-m="sleep" onclick="LR.openSheet('sleep')">
      <ellipse cx="74" cy="22" rx="12" ry="9" fill="#777"/>
      <path d="M64 21 Q68 17 72 21 Q76 17 80 21 Q84 17 84 23" fill="none" stroke="rgba(0,0,0,.3)" stroke-width="1.2"/>
    </g>
    <g class="mr" id="I-heart" data-m="restHeart" onclick="LR.openSheet('restHeart')">
      <path d="M62 63 Q58 57 62 53 Q66 49 70 55 Q74 49 78 53 Q82 57 78 63 L70 73 Z" fill="#777"/>
    </g>
    <g class="mr" id="I-lung-l" data-m="vo2max" onclick="LR.openSheet('vo2max')">
      <path d="M52 57 Q46 61 46 76 Q46 91 54 96 Q60 99 64 91 L64 59 Q58 55 52 57Z" fill="#777"/>
    </g>
    <g class="mr" id="I-lung-r" data-m="vo2max" onclick="LR.openSheet('vo2max')">
      <path d="M96 57 Q102 61 102 76 Q102 91 94 96 Q88 99 84 91 L84 59 Q90 55 96 57Z" fill="#777"/>
    </g>
    <g class="mr" id="I-core" data-m="plank" onclick="LR.openSheet('plank')">
      <rect x="55" y="104" width="38" height="58" rx="6" fill="#777"/>
    </g>
    <g class="mr" id="I-hand-l" data-m="hrv" onclick="LR.openSheet('hrv')">
      <rect x="4" y="190" width="15" height="10" rx="3" fill="#777"/>
      <rect x="4"  y="181" width="3" height="11" rx="2" fill="#777"/>
      <rect x="8"  y="178" width="3" height="13" rx="2" fill="#777"/>
      <rect x="12" y="179" width="3" height="12" rx="2" fill="#777"/>
      <rect x="16" y="182" width="3" height="9"  rx="2" fill="#777"/>
    </g>
    <g class="mr" id="I-hand-r" data-m="hrv" onclick="LR.openSheet('hrv')">
      <rect x="129" y="190" width="15" height="10" rx="3" fill="#777"/>
      <rect x="141" y="181" width="3" height="11" rx="2" fill="#777"/>
      <rect x="137" y="178" width="3" height="13" rx="2" fill="#777"/>
      <rect x="133" y="179" width="3" height="12" rx="2" fill="#777"/>
      <rect x="129" y="182" width="3" height="9"  rx="2" fill="#777"/>
    </g>
    <g class="mr" id="I-thigh-l" data-m="mobility" onclick="LR.openSheet('mobility')">
      <path d="M63 173 Q55 178 53 212 Q53 242 59 258 L67 256 Q67 234 67 212 Q67 185 67 173Z" fill="#777"/>
    </g>
    <g class="mr" id="I-thigh-r" data-m="mobility" onclick="LR.openSheet('mobility')">
      <path d="M85 173 Q93 178 95 212 Q95 242 89 258 L81 256 Q81 234 81 212 Q81 185 81 173Z" fill="#777"/>
    </g>
    <g class="mr" id="I-tibia-l" data-m="run5k" onclick="LR.openSheet('run5k')">
      <rect x="41" y="270" width="16" height="78" rx="5" fill="#777"/>
    </g>
    <g class="mr" id="I-tibia-r" data-m="run5k" onclick="LR.openSheet('run5k')">
      <rect x="91" y="270" width="16" height="78" rx="5" fill="#777"/>
    </g>
    <g class="mr" id="I-foot-l" data-m="vert" onclick="LR.openSheet('vert')">
      <path d="M34 356 Q34 366 38 369 Q50 373 58 369 Q62 365 58 358 L50 356Z" fill="#777"/>
    </g>
    <g class="mr" id="I-foot-r" data-m="vert" onclick="LR.openSheet('vert')">
      <path d="M114 356 Q114 366 110 369 Q98 373 90 369 Q86 365 90 358 L98 356Z" fill="#777"/>
    </g>
    <g class="mr" id="I-platform" data-m="mass" onclick="LR.openSheet('mass')">
      <rect x="22" y="376" width="104" height="9" rx="4" fill="#777"/>
    </g>
  </svg>`;
}

// ── OVERALL RANK CARD
function _renderOverallCard(logs) {
  const score = overallScore(logs);
  const ri    = Math.min(7, Math.floor(score));
  const r     = RANKS[ri];
  const frac  = score % 1;
  const sub   = frac < 0.333 ? 0 : frac < 0.666 ? 1 : 2;

  const ovCard = document.getElementById('ov-card');
  if (ri > 0) {
    ovCard.classList.add('flair-active');
    ovCard.style.setProperty('--flair-bg', r.c + '15');
    ovCard.style.setProperty('--flair-border', r.c + '80');
  } else {
    ovCard.classList.remove('flair-active');
  }

  injectBadge('ov-badge-wrap', ri, 64, 64);

  const emb = document.getElementById('ov-emblem');
  emb.textContent = SUB[sub];
  emb.style.color = r.c;
  emb.style.background = r.c + '44';
  emb.style.borderColor = r.c + '44';

  document.getElementById('ov-name').textContent = r.name + ' ' + SUB[sub];
  document.getElementById('ov-name').style.color = r.c;
  document.getElementById('ov-top').textContent = `Top ${getPrecisePercentOverall(score)}% of athletes`;
  document.getElementById('ov-top').style.color = r.c;

  const outer = document.getElementById('ov-prog-outer');
  outer.querySelectorAll('.prog-tick').forEach(e => e.remove());
  document.getElementById('ov-prog-fill').style.cssText =
    `width:${(frac * 100).toFixed(1)}%;background:linear-gradient(90deg,${r.c}cc,${r.c})`;
  [33.3, 66.6].forEach((pos, i) => {
    const t = document.createElement('div');
    t.className = 'prog-tick';
    t.style.left = pos + '%';
    t.innerHTML = `<div class="prog-tick-lbl"><b style="color:${r.c}">${SUB[i + 1]}</b></div>`;
    outer.appendChild(t);
  });
  document.getElementById('ov-prog-l').textContent = ri > 0 ? RANKS[ri - 1].name : 'Start';
  document.getElementById('ov-prog-r').textContent = ri < 7 ? RANKS[ri].name : 'Max';

  const allRanks   = MUSCLES.map(m => rankOf(m.id, latestORM(m.id, logs)));
  const weakestIdx = allRanks.indexOf(Math.min(...allRanks));
  document.getElementById('ov-sub').textContent =
    `Avg ${score.toFixed(2)}/7 · Weakest: ${MUSCLES[weakestIdx].label}`;
}

// ── AESTHETICS ICON STRIP (above bodygraph)
function _renderAesStrip(logs) {
  const container = document.getElementById('aes-strip');
  if (!container) return;
  const aesMetrics = MUSCLES.filter(m => m.cat === 'aes');
  container.innerHTML = aesMetrics.map(m => {
    const ri = rankOf(m.id, latestORM(m.id, logs));
    const r  = RANKS[ri];
    const styleStr = ri === 0
      ? `opacity:0.3;filter:grayscale(100%);background:var(--bg4);border-color:var(--border);`
      : `border-color:${r.c}90;background:radial-gradient(ellipse at 50% 30%,${r.c}45 0%,${r.c}18 40%,var(--bg4) 75%);box-shadow:0 0 20px ${r.c}35,0 0 8px ${r.c}20,inset 0 0 16px ${r.c}20;text-shadow:0 0 12px ${r.c};`;
    return `<div class="aes-icon" onclick="LR.openSheet('${m.id}')" style="${styleStr}" title="${m.label}">
      <span class="aes-emoji">${m.icon}</span>
      <span class="aes-label">${m.label}</span>
      <span class="aes-rank" style="color:${ri > 0 ? r.c : 'var(--muted)'}">${r.name}</span>
    </div>`;
  }).join('');
}

// ── STRENGTH MUSCLE GRID (front/back muscles) with rank colour gradient
function _renderMuscleGrid(logs) {
  const grid = document.getElementById('muscle-grid');
  grid.innerHTML = '';
  MUSCLES.filter(m => m.front?.length || m.back?.length).forEach(m => {
    const ri     = rankOf(m.id, latestORM(m.id, logs));
    const r      = RANKS[ri];
    const orm    = latestORM(m.id, logs);
    const sub    = getSubrank(m.id, orm);
    const ranked = ri > 0;
    const div    = document.createElement('div');
    div.className = 'mg-row';
    div.id = 'mg-' + m.id;
    if (ranked) {
      div.style.cssText = `border-color:${r.c}40;background:linear-gradient(135deg,${r.c}12 0%,var(--bg4) 60%,var(--surface) 100%);`;
    }
    div.innerHTML = `
      <div class="mg-dot" style="background:${r.c};box-shadow:0 0 6px ${r.glow}"></div>
      <span class="mg-name">${m.label}</span>
      <span class="mg-rank" style="color:${r.c}">${r.name}</span>
      <span class="mg-sub" style="color:${r.c}">${SUB[sub]}</span>`;
    div.onclick = () => openSheet(m.id);
    grid.appendChild(div);
  });
}

// ── PERFORMANCE & RECOVERY TEXT GRID — same visual style as strength grid
function _renderInnerGrid(logs) {
  const grid = document.getElementById('inner-grid');
  if (!grid) return;
  grid.innerHTML = '';

  MUSCLES.filter(m => m.inner?.length).forEach(m => {
    const ri  = rankOf(m.id, latestORM(m.id, logs));
    const r   = RANKS[ri];
    const orm = latestORM(m.id, logs);
    const sub = getSubrank(m.id, orm);
    const hasData = orm > 0 && ri > 0;

    const div = document.createElement('div');
    // Same classes as mg-row so it gets identical base styles
    div.className = 'mg-row ig-row';
    if (hasData) {
      div.style.cssText = `border-color:${r.c}40;background:linear-gradient(135deg,${r.c}12 0%,var(--bg4) 60%,var(--surface) 100%);`;
    }

    div.innerHTML = `
      <div class="mg-dot" style="background:${r.c};box-shadow:0 0 6px ${r.glow}"></div>
      <span class="mg-name">${m.icon} ${m.label}</span>
      <span class="mg-rank" style="color:${r.c}">${r.name}</span>
      <span class="mg-sub" style="color:${r.c}">${SUB[sub]}</span>
      ${hasData ? `<div class="ig-glow" style="background:${r.c}"></div>` : ''}`;

    div.onclick = () => openSheet(m.id);
    grid.appendChild(div);
  });
}

// ── INJECT INNER FIGURE INTO DOM (runs once)
function _ensureInnerFigure() {
  if (document.getElementById('bodygraph-inner')) return;
  const row = document.getElementById('bodygraph-row');
  if (!row) return;
  const fig = document.createElement('div');
  fig.className = 'body-fig';
  fig.id = 'bodygraph-inner';
  fig.innerHTML = _innerSVG() + '<div class="fig-label">Inner</div>';
  if (row.children.length >= 2) {
    row.insertBefore(fig, row.children[1]);
  } else {
    row.appendChild(fig);
  }
}

// ── MAIN RENDER ENTRY POINT
export function renderBody() {
  const logs = getLogs();
  _ensureInnerFigure();
  applyColors(logs);
  _renderOverallCard(logs);
  _renderAesStrip(logs);
  _renderMuscleGrid(logs);
  _renderInnerGrid(logs);
}
