// ════════════════════════════════════════════════════════
// ui/toast.js — Toast notifications + shared UI helpers
// ════════════════════════════════════════════════════════

import { RANKS, SUB } from '../data/metrics.js';
import { rankOf, getSubrank, getProgress } from '../engine/rank.js';

// ── TOAST
let _toastTimer = null;

export function showToast(msg, col = 'var(--text)') {
  const t = document.getElementById('toast');
  if (!t) return;
  if (_toastTimer) clearTimeout(_toastTimer);
  t.textContent = msg;
  t.style.color = col;
  t.classList.add('show');
  _toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
}

// ── PROGRESS BAR (renders into a container by ID)
export function buildProgBar(mid, orm, containerId, unit = 'kg') {
  const p   = getProgress(mid, orm);
  const ri  = rankOf(mid, orm);
  const col = RANKS[ri].c;
  const el  = document.getElementById(containerId);
  if (!el) return;

  const unitLabel = unit;

  el.innerHTML = `
    <div class="prog-outer">
      <div class="prog-fill" style="width:${p.pct.toFixed(1)}%;background:linear-gradient(90deg,${col}cc,${col})"></div>
      <div class="prog-tick" style="left:33.3%">
        <div class="prog-tick-lbl">${p.m1}${unitLabel}<br><b style="color:${col}">II</b></div>
      </div>
      <div class="prog-tick" style="left:66.6%">
        <div class="prog-tick-lbl">${p.m2}${unitLabel}<br><b style="color:${col}">III</b></div>
      </div>
    </div>
    <div class="prog-ends">
      <span>${ri > 0 ? RANKS[ri-1].name + ' ≥' + p.cur + unitLabel : 'Start'}</span>
      <span style="color:${col}">${ri < 7 ? RANKS[ri].name + ' ≥' + p.nxt + unitLabel + ' (+' + Math.max(0, p.nxt - p.orm).toFixed(1) + unitLabel + ')' : '🏆 Max'}</span>
    </div>`;
}

// ── LOG CARD HTML BUILDER (shared between Log screen and Sheet)
export function logCardsHTML(mid, logs, settings, deleteFn) {
  const { MUSCLES } = window.__LR__;           // accessed via app globals
  const m       = MUSCLES.find(x => x.id === mid);
  const entries = logs[mid] || [];
  if (!entries.length) {
    return '<div class="empty-state" style="padding:1rem"><div class="empty-icon" style="font-size:24px">📋</div><div class="empty-text">No logs yet</div></div>';
  }
  return [...entries].reverse().map((e, revIdx) => {
    const realIdx = entries.length - 1 - revIdx;
    const ri      = rankOf(mid, e.oneRM);
    const r       = RANKS[ri];
    const sub     = getSubrank(mid, e.oneRM);
    const isLatest = revIdx === 0;

    let mainStr = `${e.w}${e.u} × ${e.reps}`;
    if (m && (m.type === 'cardio' || m.type === 'time')) mainStr = `${e.w}m ${e.reps}s`;
    if (m && m.type === 'distance') mainStr = `${e.w} cm`;
    if (m && m.type === 'score') mainStr = `${e.w} ${m.unit}`;

    return `<div class="lc" style="${isLatest ? 'border-color:' + r.c + '55' : ''}">
      <div class="lc-dot" style="background:${r.c}"></div>
      <div>
        <div class="lc-main">${mainStr}</div>
        <div class="lc-sub">${m ? m.ex : ''} · Best ≈ ${e.oneRM.toFixed(1)}</div>
      </div>
      <div style="text-align:right">
        <div class="lc-date">${e.date}</div>
        <span class="lc-chip" style="background:${r.c}1e;color:${r.c};border-color:${r.c}40">${r.name} ${SUB[sub]}</span>
      </div>
      <button class="lc-del" onclick="${deleteFn}('${mid}',${realIdx})">×</button>
      ${isLatest ? '<div class="lc-new">LATEST</div>' : ''}
    </div>`;
  }).join('');
}

// ── MILESTONE LEDGER HTML BUILDER
export function milestoneLedgerHTML(mid, orm) {
  const { THRESH, RANKS, TOP_PCT_ARR } = window.__LR__;
  let html = `
    <div style="margin-top:1.2rem;border-top:1px solid var(--border);padding-top:.8rem;">
      <div style="font-size:9px;letter-spacing:2px;color:var(--muted);text-transform:uppercase;font-weight:700;margin-bottom:.6rem;">Rank Milestones</div>
      <div style="display:flex;flex-direction:column;gap:5px;">`;

  THRESH[mid].forEach((w, i) => {
    const r           = RANKS[i + 1];
    const targetPct   = TOP_PCT_ARR[i + 1];
    const isAchieved  = orm >= w;
    const isNext      = !isAchieved && (orm >= (i > 0 ? THRESH[mid][i - 1] : 0));
    const bg          = isAchieved ? r.c + '1a' : 'var(--surface)';
    const col         = isAchieved ? r.c : 'var(--muted)';
    const border      = isNext ? `border:1px solid ${r.c};box-shadow:0 0 10px ${r.c}40;` : 'border:1px solid transparent;';
    const dot         = isNext ? '🎯' : (isAchieved ? '✓' : '🔒');

    html += `
      <div style="display:flex;justify-content:space-between;align-items:center;padding:7px 10px;background:${bg};border-radius:10px;${border}">
        <div style="display:flex;align-items:center;gap:8px;">
          <div style="font-size:10px;opacity:.8">${dot}</div>
          <span style="font-size:12px;font-weight:700;color:${col}">${r.name}</span>
        </div>
        <div style="text-align:right;line-height:1.1">
          <div style="font-size:12px;font-weight:700;color:${col}">${w}</div>
          <div style="font-size:9px;color:var(--muted2)">Top ${targetPct}%</div>
        </div>
      </div>`;
  });

  html += `</div></div>`;
  return html;
}
