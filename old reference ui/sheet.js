// ════════════════════════════════════════════════════════
// ui/sheet.js — Bottom sheet (detail + log for any metric)
// ════════════════════════════════════════════════════════

import { RANKS, MUSCLES, SUB, THRESH, TOP_PCT_ARR } from '../data/metrics.js';
import { rankOf, getSubrank, latestORM, getPrecisePercent, epley } from '../engine/rank.js';
import { getLogs, getSettings, addLog, deleteLog, setSheetMid, getSheetMid } from '../engine/state.js';
import { injectBadge } from './badge.js';
import { showToast, buildProgBar } from './toast.js';

// ── OPEN
export function openSheet(mid) {
  setSheetMid(mid);
  _renderSheet(mid);
  document.getElementById('detail-sheet').classList.add('open');
}

// ── CLOSE
export function closeSheet() {
  document.getElementById('detail-sheet').classList.remove('open');
  MUSCLES.forEach(m => [...(m.front || []), ...(m.back || []), ...(m.inner || [])].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.classList.remove('sel', 'dim');
  }));
  setSheetMid(null);
}

export function sheetBackdropClick(e) {
  if (e.target.classList.contains('sheet-backdrop') || e.target === e.currentTarget) closeSheet();
}

// ── INTERNAL RENDER (rebuilds sheet contents cleanly on every open)
function _renderSheet(mid) {
  const logs    = getLogs();
  const settings = getSettings();
  const m       = MUSCLES.find(x => x.id === mid);
  const orm     = latestORM(mid, logs);
  const ri      = rankOf(mid, orm);
  const r       = RANKS[ri];
  const sub     = getSubrank(mid, orm);

  // Badge + header
  injectBadge('sheet-badge-wrap', ri, 72, 72);
  const emb = document.getElementById('sheet-emblem');
  emb.textContent = SUB[sub];
  emb.style.color = r.c;
  emb.style.background = 'rgba(8,9,26,.85)';
  emb.style.borderColor = r.c + '44';

  document.getElementById('sheet-muscle').textContent = m.label;

  const rankEl = document.getElementById('sheet-rank');
  rankEl.textContent = `${r.name} ${SUB[sub]}`;
  rankEl.style.color = r.c;

  const topEl = document.getElementById('sheet-top');
  topEl.textContent = `Top ${getPrecisePercent(mid, orm)}% of lifters`;
  topEl.style.color = r.c;

  document.getElementById('sheet-ex').textContent = '📍 ' + m.ex;
  document.getElementById('sheet-1rm').textContent = orm > 0 ? `Best: ${orm.toFixed(1)} ${m.type === 'score' ? m.unit : settings.unit}` : 'No logs yet';
  const measureEl = document.getElementById('sheet-measure');
  if (measureEl) { measureEl.textContent = m.measure ? '📐 ' + m.measure : ''; measureEl.style.display = m.measure ? 'block' : 'none'; }
  document.getElementById('sheet-log-title').textContent = `Log ${m.ex}`;

  // Rank-tinted background
  const sheetBody = document.querySelector('.sheet-body');
  sheetBody.style.setProperty('--rank-tinge', r.c + '30');
  sheetBody.style.setProperty('--rank-tinge-border', r.c + '50');

  // Input mode toggle
  document.getElementById('sheet-input-weight').style.display = !m.type ? 'flex' : 'none';
  document.getElementById('sheet-input-score').style.display  = m.type === 'score' ? 'flex' : 'none';

  // Unit selector
  const unitSel = document.getElementById('sh-u');
  if (unitSel) unitSel.value = settings.unit;

  // Progress bar
  buildProgBar(mid, orm, 'sheet-prog', m.type === 'score' ? (m.unit || '') : settings.unit);

  // History
  const entries = logs[mid] || [];
  document.getElementById('sheet-hist-count').textContent = `${entries.length} log${entries.length !== 1 ? 's' : ''}`;
  document.getElementById('sheet-log-cards').innerHTML = _logCardsHTML(mid, logs, settings);

  // Milestone ledger — always replace, never append
  let ledgerEl = document.getElementById('sheet-ledger');
  if (!ledgerEl) {
    ledgerEl = document.createElement('div');
    ledgerEl.id = 'sheet-ledger';
    document.querySelector('.sheet-body').appendChild(ledgerEl);
  }
  ledgerEl.innerHTML = _milestoneLedgerHTML(mid, orm);

  // Bodygraph highlight
  MUSCLES.forEach(mx => [...(mx.front || []), ...(mx.back || []), ...(mx.inner || [])].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.classList.remove('sel', 'dim');
    el.classList.add(mx.id === mid ? 'sel' : 'dim');
  }));
}

// ── LOG SUBMISSION
export function sheetLog() {
  const mid = getSheetMid();
  if (!mid) return;

  const m        = MUSCLES.find(x => x.id === mid);
  const settings = getSettings();
  const date     = new Date().toLocaleDateString('en-AU', { day: '2-digit', month: 'short', year: '2-digit' });
  let w, reps, u, orm;

  if (!m.type) {
    w    = parseFloat(document.getElementById('sh-w').value);
    reps = parseInt(document.getElementById('sh-r').value);
    u    = document.getElementById('sh-u').value;
    if (!w || !reps) { showToast('Enter weight and reps', '#f0622a'); return; }
    const wKg = u === 'lb' ? w * 0.4536 : w;
    orm = epley(wKg, reps);
  } else if (m.type === 'score') {
    w    = parseFloat(document.getElementById('sh-score').value);
    reps = 1;
    u    = m.unit;
    if (!w && w !== 0) { showToast('Enter score', '#f0622a'); return; }
    orm = w;
  }

  if (navigator.vibrate) navigator.vibrate(15);
  const saved = addLog(mid, { date, w, u, reps, oneRM: orm });
  if (!saved) { showToast('⚠️ Storage full — export your data!', '#f0622a'); return; }

  // Clear inputs
  const wEl = document.getElementById('sh-w');
  const sEl = document.getElementById('sh-score');
  if (wEl) wEl.value = '';
  if (sEl) sEl.value = '';

  const ri  = rankOf(mid, orm);
  const sub = getSubrank(mid, orm);
  showToast(`✓ Logged! Best ≈ ${orm.toFixed(1)} · ${RANKS[ri].name} ${SUB[sub]}`, RANKS[ri].c);

  // Re-render sheet in place
  _renderSheet(mid);
}

// ── INTERNAL HELPERS

function _logCardsHTML(mid, logs, settings) {
  const m       = MUSCLES.find(x => x.id === mid);
  const entries = logs[mid] || [];
  if (!entries.length) {
    return '<div class="empty-state" style="padding:1rem"><div class="empty-icon" style="font-size:24px">📋</div><div class="empty-text">No logs yet</div></div>';
  }
  return [...entries].reverse().map((e, revIdx) => {
    const realIdx  = entries.length - 1 - revIdx;
    const ri       = rankOf(mid, e.oneRM);
    const r        = RANKS[ri];
    const sub      = getSubrank(mid, e.oneRM);
    const isLatest = revIdx === 0;

    let mainStr = `${e.w}${e.u} × ${e.reps}`;
    if (m && m.type === 'score') mainStr = `${e.w} ${m.unit}`;

    return `<div class="lc" style="${isLatest ? 'border-color:' + r.c + '55' : ''}">
      <div class="lc-dot" style="background:${r.c}"></div>
      <div>
        <div class="lc-main">${mainStr}</div>
        <div class="lc-sub">${m.ex} · Best ≈ ${e.oneRM.toFixed(1)}</div>
      </div>
      <div style="text-align:right">
        <div class="lc-date">${e.date}</div>
        <span class="lc-chip" style="background:${r.c}1e;color:${r.c};border-color:${r.c}40">${r.name} ${SUB[sub]}</span>
      </div>
      <button class="lc-del" onclick="LR.deleteLogFromSheet('${mid}',${realIdx})">×</button>
      ${isLatest ? '<div class="lc-new">LATEST</div>' : ''}
    </div>`;
  }).join('');
}

function _milestoneLedgerHTML(mid, orm) {
  let html = `
    <div style="margin-top:1.2rem;border-top:1px solid var(--border);padding-top:.8rem;">
      <div style="font-size:9px;letter-spacing:2px;color:var(--muted);text-transform:uppercase;font-weight:700;margin-bottom:.6rem;">Rank Milestones</div>
      <div style="display:flex;flex-direction:column;gap:5px;">`;

  THRESH[mid].forEach((w, i) => {
    const r          = RANKS[i + 1];
    const targetPct  = TOP_PCT_ARR[i + 1];
    const isAchieved = orm >= w;
    const isNext     = !isAchieved && (orm >= (i > 0 ? THRESH[mid][i - 1] : 0));
    const bg         = isAchieved ? r.c + '1a' : 'var(--surface)';
    const col        = isAchieved ? r.c : 'var(--muted)';
    const border     = isNext ? `border:1px solid ${r.c};box-shadow:0 0 10px ${r.c}40;` : 'border:1px solid transparent;';
    const dot        = isNext ? '🎯' : (isAchieved ? '✓' : '🔒');

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

// ── DELETE LOG (callable from log card buttons via LR global)
export function deleteLogFromSheet(mid, idx) {
  deleteLog(mid, idx);
  _renderSheet(mid);
}