// ════════════════════════════════════════════════════════
// ui/log.js — Log screen (muscle picker + form + history)
// ════════════════════════════════════════════════════════

import { RANKS, MUSCLES, SUB } from '../data/metrics.js';
import { rankOf, getSubrank, latestORM, epley, getPrecisePercent } from '../engine/rank.js';
import { getLogs, getSettings, addLog, deleteLog, setLogMid, getLogMid, setUnit } from '../engine/state.js';
import { injectBadge } from './badge.js';
import { showToast, buildProgBar } from './toast.js';

// ── RENDER MUSCLE PICKER LIST
export function renderLog() {
  const logs    = getLogs();
  const logMid  = getLogMid();
  const list    = document.getElementById('mp-list');
  list.innerHTML = '';

  MUSCLES.forEach(m => {
    const orm = latestORM(m.id, logs);
    const ri  = rankOf(m.id, orm);
    const r   = RANKS[ri];
    const sub = getSubrank(m.id, orm);
    const div = document.createElement('div');
    div.className = 'mp-row' + (m.id === logMid ? ' active' : '');
    div.id = 'mp-' + m.id;
    div.innerHTML = `
      <div class="mp-dot" style="background:${r.c};box-shadow:0 0 5px ${r.glow}"></div>
      <span class="mp-name">${m.label}</span>
      <div class="mp-badge">
        <span class="mp-rank" style="color:${r.c}">${r.name}</span>
        <span class="mp-sub">${SUB[sub]}</span>
      </div>
      <span class="mp-1rm">${orm > 0 ? orm.toFixed(1) + (m.type === 'score' ? ' ' + m.unit : ' kg') : '—'}</span>`;
    div.onclick = () => selectLogMuscle(m.id);
    list.appendChild(div);
  });

  if (logMid) updateLogPanel();
}

// ── SELECT A MUSCLE IN THE PICKER
export function selectLogMuscle(mid) {
  setLogMid(mid);
  document.querySelectorAll('.mp-row').forEach(r => r.classList.remove('active'));
  document.getElementById('mp-' + mid)?.classList.add('active');
  updateLogPanel();
}

// ── UPDATE THE LOG FORM PANEL (right side)
export function updateLogPanel() {
  const logMid  = getLogMid();
  if (!logMid) return;

  const logs     = getLogs();
  const settings = getSettings();
  const m        = MUSCLES.find(x => x.id === logMid);
  const orm      = latestORM(logMid, logs);
  const ri       = rankOf(logMid, orm);
  const r        = RANKS[ri];
  const sub      = getSubrank(logMid, orm);

  document.getElementById('log-empty').style.display    = 'none';
  document.getElementById('log-form-inner').style.display = 'block';
  document.getElementById('history-card').style.display   = 'block';

  // Badge preview
  injectBadge('lfbp-badge', ri, 54, 54);
  const rankNameEl = document.getElementById('lfbp-rank');
  rankNameEl.textContent = r.name;
  rankNameEl.style.color = r.c;

  const chip = document.getElementById('lfbp-chip');
  chip.textContent = `${r.name} ${SUB[sub]}`;
  chip.style.background  = r.c + '22';
  chip.style.color       = r.c;
  chip.style.borderColor = r.c + '44';

  const topEl = document.getElementById('lfbp-top');
  topEl.textContent = `Top ${getPrecisePercent(logMid, orm)}% of lifters`;
  topEl.style.color = r.c;

  document.getElementById('lfbp-1rm').textContent = orm > 0 ? `Latest: ${orm.toFixed(1)} ${m.type === 'score' ? m.unit : settings.unit}` : 'No logs yet';
  document.getElementById('lfm-name').textContent = m.label;
  document.getElementById('lfm-ex').textContent   = '📍 ' + m.ex;

  buildProgBar(logMid, orm, 'lfm-prog', m.type === 'score' ? (m.unit || '') : settings.unit);

  // Unit toggle
  ['kg', 'lb'].forEach(u => {
    document.querySelector(`.unit-opt[data-unit="${u}"]`)?.classList.toggle('active', u === settings.unit);
  });

  // History
  const entries = logs[logMid] || [];
  document.getElementById('hist-count').textContent = `${entries.length} log${entries.length !== 1 ? 's' : ''}`;
  document.getElementById('log-cards-main').innerHTML = _logCardsHTML(logMid, logs, settings);
}

// ── SUBMIT LOG
export function submitLog() {
  const logMid  = getLogMid();
  if (!logMid) return;

  const m        = MUSCLES.find(x => x.id === logMid);
  const settings = getSettings();
  const date     = new Date().toLocaleDateString('en-AU', { day: '2-digit', month: 'short', year: '2-digit' });
  let w, reps, u, orm;

  if (!m.type) {
    w    = parseFloat(document.getElementById('log-w').value);
    reps = parseInt(document.getElementById('log-r').value);
    u    = settings.unit;
    if (!w || !reps) { showToast('Enter weight and reps', '#f0622a'); return; }
    const wKg = u === 'lb' ? w * 0.4536 : w;
    orm = epley(wKg, reps);
  } else if (m.type === 'score') {
    w    = parseFloat(document.getElementById('log-score-val').value);
    reps = 1;
    u    = m.unit;
    if (!w && w !== 0) { showToast('Enter score', '#f0622a'); return; }
    orm = w;
  }

  if (navigator.vibrate) navigator.vibrate(15);
  const saved = addLog(logMid, { date, w, u, reps, oneRM: orm });
  if (!saved) { showToast('⚠️ Storage full — export your data!', '#f0622a'); return; }

  const ri  = rankOf(logMid, orm);
  const sub = getSubrank(logMid, orm);
  showToast(`✓ Logged! Best ≈ ${orm.toFixed(1)} · ${RANKS[ri].name} ${SUB[sub]}`, RANKS[ri].c);

  document.getElementById('log-w').value = '';
  const sEl = document.getElementById('log-score-val');
  if (sEl) sEl.value = '';

  updateLogPanel();
}

// ── UNIT TOGGLE (log screen)
export function setLogUnit(u) {
  setUnit(u);
  updateLogPanel();
}

// ── DELETE LOG FROM LOG SCREEN
export function deleteLogFromLog(mid, idx) {
  deleteLog(mid, idx);
  updateLogPanel();
}

// ── PRIVATE: log card HTML
function _logCardsHTML(mid, logs, settings) {
  const m       = MUSCLES.find(x => x.id === mid);
  const entries = logs[mid] || [];
  if (!entries.length) {
    return '<div class="empty-state"><div class="empty-icon">📋</div><div class="empty-text">No logs yet</div></div>';
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
      <button class="lc-del" onclick="LR.deleteLogFromLog('${mid}',${realIdx})">×</button>
      ${isLatest ? '<div class="lc-new">LATEST</div>' : ''}
    </div>`;
  }).join('');
}
