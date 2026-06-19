// ════════════════════════════════════════════════════════
// ui/habits.js — Habit Planner screen
// Changes:
//   • 'Why' and 'How to measure' fields — collapsed by default,
//     tap card to expand/collapse with smooth animation
//   • Haptic on add / save / delete
// ════════════════════════════════════════════════════════

import { getHabits, addHabit, updateHabit, deleteHabit } from '../engine/state.js';

// ── CATEGORY DEFINITIONS
const CATS = {
  fitness: { label: 'Fitness', icon: '💪', c: '#4ce0c3', bg: 'rgba(76,224,195,0.12)', border: 'rgba(76,224,195,0.3)' },
  sleep:   { label: 'Sleep',   icon: '😴', c: '#8e8eff', bg: 'rgba(142,142,255,0.12)', border: 'rgba(142,142,255,0.3)' },
  diet:    { label: 'Diet',    icon: '🥗', c: '#f6cf3e', bg: 'rgba(246,207,62,0.12)',  border: 'rgba(246,207,62,0.3)'  },
  other:   { label: 'Other',   icon: '⚙️', c: '#c28a67', bg: 'rgba(194,138,103,0.12)', border: 'rgba(194,138,103,0.3)' },
};

const DAYS_SHORT = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

// ── FORM STATE
let _editId      = null;
let _editSection = 'daily';

// ── HAPTIC
function _buzz(p = 10) { if (navigator.vibrate) navigator.vibrate(p); }

// ── MAIN RENDER
export function renderHabits() {
  const habits = getHabits();
  _renderSection('daily',   habits);
  _renderSection('weekly',  habits);
  _renderSection('monthly', habits);
  _renderAnalytics(habits);
  _renderDensityBar(habits);
}

// ── RENDER ONE SECTION
function _renderSection(section, habits) {
  const list   = habits[section] || [];
  const sorted = [...list].sort((a, b) => _timeToMins(a.time) - _timeToMins(b.time));
  const container = document.getElementById(`hab-list-${section}`);
  if (!container) return;

  if (!sorted.length) {
    container.innerHTML = `<div class="hab-empty">
      <span style="font-size:22px;opacity:.35">${section === 'daily' ? '☀️' : section === 'weekly' ? '📅' : '🗓️'}</span>
      <span>No ${section} habits yet</span>
    </div>`;
    return;
  }
  container.innerHTML = sorted.map(h => _habitCardHTML(h, section)).join('');
}

// ── SINGLE HABIT CARD HTML
function _habitCardHTML(h, section) {
  const cat  = CATS[h.cat] || CATS.other;
  const days = section === 'weekly' && h.days?.length
    ? `<div class="hab-days">${DAYS_SHORT.map(d =>
        `<span class="hab-day${h.days.includes(d) ? ' on' : ''}"
          style="${h.days.includes(d) ? `background:${cat.c}30;color:${cat.c};border-color:${cat.c}60` : ''}"
        >${d}</span>`).join('')}</div>`
    : '';
  const freq = section === 'weekly' && h.days?.length
    ? `<span class="hab-freq">${h.days.length}× / week</span>`
    : '';

  const costStr = h.cost > 0 ? `$${parseFloat(h.cost).toFixed(0)}/mo` : '';
  const hasDetail = h.why && h.why.trim();

  // Detail panel — only rendered if there's content
  const detailPanel = hasDetail ? `
    <div class="hab-detail" id="habdet-${h.id}" style="display:none">
      ${h.why?.trim() ? `<div class="hab-detail-row"><span class="hab-detail-lbl" style="color:${cat.c}">WHY</span><span class="hab-detail-val">${_esc(h.why)}</span></div>` : ''}
    </div>` : '';

  const expandIcon = hasDetail
    ? `<span class="hab-expand-icon" id="habexp-${h.id}">▾</span>`
    : '';

  return `<div class="hab-card" style="border-color:${cat.border};background:linear-gradient(135deg,${cat.bg} 0%,var(--bg4) 70%)"
    ${hasDetail ? `onclick="LR.toggleHabitDetail('${h.id}')"` : ''}>
    <div class="hab-cat-bar" style="background:${cat.c}"></div>
    <div class="hab-card-inner">
      <div class="hab-row1">
        <span class="hab-icon">${cat.icon}</span>
        <span class="hab-name">${_esc(h.name)}</span>
        ${freq}
        ${expandIcon}
        <div class="hab-actions" onclick="event.stopPropagation()">
          <button class="hab-btn-edit" onclick="LR.editHabit('${section}','${h.id}')">✎</button>
          <button class="hab-btn-del"  onclick="LR.deleteHabitUI('${section}','${h.id}')">×</button>
        </div>
      </div>
      <div class="hab-row2">
        ${h.time    ? `<span class="hab-pill" style="color:${cat.c};border-color:${cat.c}44;background:${cat.c}12">⏰ ${_fmt12(h.time)}</span>` : ''}
        ${h.duration ? `<span class="hab-pill">⏱ ${_fmtDur(h.duration)}</span>` : ''}
        ${costStr    ? `<span class="hab-pill" style="color:#f6cf3e;border-color:#f6cf3e44;background:#f6cf3e12">💰 ${costStr}</span>` : ''}
        <span class="hab-cat-chip" style="color:${cat.c};background:${cat.c}18;border-color:${cat.c}33">${cat.label}</span>
      </div>
      ${days}
      ${detailPanel}
    </div>
  </div>`;
}

// ── TOGGLE DETAIL PANEL
export function toggleHabitDetail(id) {
  _buzz(6);
  const panel = document.getElementById(`habdet-${id}`);
  const icon  = document.getElementById(`habexp-${id}`);
  if (!panel) return;
  const open = panel.style.display === 'none' || panel.style.display === '';
  panel.style.display  = open ? 'block' : 'none';
  if (icon) icon.textContent = open ? '▴' : '▾';
}

// ── ANALYTICS PANEL
function _renderAnalytics(habits) {
  const el = document.getElementById('hab-analytics');
  if (!el) return;

  const daily   = habits.daily   || [];
  const weekly  = habits.weekly  || [];
  const monthly = habits.monthly || [];

  const dMins = daily.reduce((s, h) => s + (+h.duration || 0), 0);
  const dCost = daily.reduce((s, h) => s + (+h.cost || 0), 0);
  const wMins = weekly.reduce((s, h) => s + (+h.duration || 0) * (h.days?.length || 1), 0);
  const wCost = weekly.reduce((s, h) => s + (+h.cost || 0), 0);
  const mMins = monthly.reduce((s, h) => s + (+h.duration || 0), 0);
  const mCost = monthly.reduce((s, h) => s + (+h.cost || 0), 0);

  const dWeeklyMins        = dMins * 7;
  const combinedWeeklyMins = dWeeklyMins + wMins;
  const dMonthlyMins       = dMins * 30;
  const wMonthlyMins       = wMins * 4.3;
  const grandMins          = dMonthlyMins + wMonthlyMins + mMins;
  const grandCost          = dCost + wCost + mCost;

  el.innerHTML = `
    <div class="ana-group">
      <div class="ana-group-title">Daily</div>
      <div class="ana-row">
        <span class="ana-lbl">Per day</span>
        <span class="ana-val">${_fmtDur(dMins)}</span>
        <span class="ana-cost">${dCost > 0 ? '$' + dCost.toFixed(0) + '/mo' : '—'}</span>
      </div>
      <div class="ana-row ana-sub">
        <span class="ana-lbl">× 7 (weekly rollup)</span>
        <span class="ana-val">${_fmtDur(dWeeklyMins)}</span>
        <span class="ana-cost" style="color:var(--muted2)">—</span>
      </div>
    </div>

    <div class="ana-group">
      <div class="ana-group-title">Weekly</div>
      <div class="ana-row">
        <span class="ana-lbl">Scheduled this week</span>
        <span class="ana-val">${_fmtDur(wMins)}</span>
        <span class="ana-cost">${wCost > 0 ? '$' + wCost.toFixed(0) + '/mo' : '—'}</span>
      </div>
      <div class="ana-row ana-sub ana-combined">
        <span class="ana-lbl">Daily + weekly / wk</span>
        <span class="ana-val" style="color:#4ce0c3">${_fmtDur(combinedWeeklyMins)}</span>
        <span class="ana-cost" style="color:var(--muted2)">—</span>
      </div>
    </div>

    <div class="ana-group">
      <div class="ana-group-title">Monthly</div>
      <div class="ana-row">
        <span class="ana-lbl">Monthly-only habits</span>
        <span class="ana-val">${_fmtDur(mMins)}</span>
        <span class="ana-cost">${mCost > 0 ? '$' + mCost.toFixed(0) + '/mo' : '—'}</span>
      </div>
    </div>

    <div class="ana-grand">
      <div class="ana-grand-title">Grand Total / Month</div>
      <div class="ana-grand-row">
        <div class="ana-grand-block">
          <div class="ana-grand-val">${_fmtDur(grandMins)}</div>
          <div class="ana-grand-lbl">Time invested</div>
        </div>
        <div class="ana-grand-sep"></div>
        <div class="ana-grand-block">
          <div class="ana-grand-val" style="color:#f6cf3e">$${grandCost.toFixed(0)}</div>
          <div class="ana-grand-lbl">Monthly spend</div>
        </div>
        <div class="ana-grand-sep"></div>
        <div class="ana-grand-block">
          <div class="ana-grand-val" style="color:#e67be6">${(grandMins / 60 / (24 * 30) * 100).toFixed(1)}%</div>
          <div class="ana-grand-lbl">of waking month</div>
        </div>
      </div>
      <div class="ana-breakdown">
        ${_breakdownBar(dMonthlyMins, wMonthlyMins, mMins)}
      </div>
    </div>`;
}


// ── 24H DENSITY BAR
// Shows which hours of the day are "occupied" by habits, coloured by category.
function _renderDensityBar(habits) {
  const el = document.getElementById('hab-density-bar');
  if (!el) return;

  const allHabits = [
    ...(habits.daily   || []),
    ...(habits.weekly  || []),
    ...(habits.monthly || []),
  ].filter(h => h.time && h.duration > 0);

  if (!allHabits.length) {
    el.innerHTML = '<div style="color:var(--muted);font-size:10px;text-align:center;padding:.5rem 0">Add habits with a time and duration to see your day</div>';
    return;
  }

  // Build 48 × 30-min slots
  const SLOTS = 48;
  const slots = Array.from({ length: SLOTS }, () => ({ cat: null, overlap: 0 }));

  allHabits.forEach(h => {
    const cat  = CATS[h.cat] || CATS.other;
    const [hh, mm] = h.time.split(':').map(Number);
    const startSlot = Math.floor((hh * 60 + mm) / 30);
    const durSlots  = Math.ceil((+h.duration) / 30);
    for (let i = 0; i < durSlots; i++) {
      const s = (startSlot + i) % SLOTS;
      slots[s].overlap++;
      // Last category written wins for colour — earliest stays if only one
      if (!slots[s].cat || slots[s].overlap === 1) slots[s].cat = cat;
    }
  });

  const hourLabels = ['12am','3am','6am','9am','12pm','3pm','6pm','9pm'];
  const labelHtml = `<div class="den-labels">${hourLabels.map(l => `<span>${l}</span>`).join('')}</div>`;

  const slotHtml = slots.map((s, i) => {
    if (!s.cat) return `<div class="den-slot"></div>`;
    const opacity = Math.min(0.9, 0.35 + s.overlap * 0.2);
    return `<div class="den-slot den-slot-on" style="background:${s.cat.c};opacity:${opacity}" title="${s.cat.label}"></div>`;
  }).join('');

  el.innerHTML = `
    <div class="den-track">${slotHtml}</div>
    ${labelHtml}`;
}

function _breakdownBar(d, w, m) {
  const total = d + w + m || 1;
  const dp = (d / total * 100).toFixed(1);
  const wp = (w / total * 100).toFixed(1);
  const mp = (m / total * 100).toFixed(1);
  return `<div style="display:flex;gap:3px;margin-top:.6rem">
    <div style="height:6px;border-radius:3px 0 0 3px;background:#4ce0c3;width:${dp}%;min-width:${d>0?'4px':'0'};transition:width .4s"></div>
    <div style="height:6px;background:#8e8eff;width:${wp}%;min-width:${w>0?'4px':'0'};transition:width .4s"></div>
    <div style="height:6px;border-radius:0 3px 3px 0;background:#f6cf3e;width:${mp}%;min-width:${m>0?'4px':'0'};transition:width .4s"></div>
  </div>
  <div style="display:flex;gap:1rem;margin-top:.3rem">
    <span style="font-size:8px;color:#4ce0c3">■ Daily ${dp}%</span>
    <span style="font-size:8px;color:#8e8eff">■ Weekly ${wp}%</span>
    <span style="font-size:8px;color:#f6cf3e">■ Monthly ${mp}%</span>
  </div>`;
}

// ── OPEN ADD FORM
export function openAddHabit(section) {
  _buzz(10);
  _editId = null;
  _editSection = section;
  _populateForm(section, null);
  _openModal();
}

// ── OPEN EDIT FORM
export function editHabit(section, id) {
  _buzz(10);
  const habits = getHabits();
  const h = (habits[section] || []).find(x => x.id === id);
  if (!h) return;
  _editId = id;
  _editSection = section;
  _populateForm(section, h);
  _openModal();
}

function _populateForm(section, h) {
  document.getElementById('hab-form-title').textContent = h ? 'Edit Habit' : `Add ${_cap(section)} Habit`;
  document.getElementById('hab-f-name').value    = h?.name    || '';
  document.getElementById('hab-f-time').value    = h?.time    || '';
  document.getElementById('hab-f-dur').value     = h?.duration || '';
  document.getElementById('hab-f-cost').value    = h?.cost    || '';
  document.getElementById('hab-f-cat').value     = h?.cat     || 'fitness';
  document.getElementById('hab-f-why').value     = h?.why     || '';
  document.getElementById('hab-f-section').value = section;

  const daysWrap = document.getElementById('hab-days-wrap');
  daysWrap.style.display = section === 'weekly' ? 'block' : 'none';
  document.querySelectorAll('.hfd-day').forEach(btn => {
    const on = !!h?.days?.includes(btn.dataset.day);
    btn.classList.toggle('on', on);
    _styleDay(btn, on);
  });
}

function _styleDay(btn, on) {
  btn.style.background  = on ? 'rgba(76,224,195,0.2)' : 'var(--bg4)';
  btn.style.color       = on ? '#4ce0c3' : 'var(--muted)';
  btn.style.borderColor = on ? 'rgba(76,224,195,0.5)' : 'var(--border)';
}

function _openModal() {
  document.getElementById('hab-modal').classList.add('open');
  setTimeout(() => document.getElementById('hab-f-name').focus(), 120);
}

export function closeHabitModal() {
  document.getElementById('hab-modal').classList.remove('open');
}

// ── SAVE HABIT
export function saveHabitForm() {
  const name    = document.getElementById('hab-f-name').value.trim();
  const time    = document.getElementById('hab-f-time').value;
  const dur     = parseFloat(document.getElementById('hab-f-dur').value) || 0;
  const cost    = parseFloat(document.getElementById('hab-f-cost').value) || 0;
  const cat     = document.getElementById('hab-f-cat').value;
  const why     = document.getElementById('hab-f-why').value.trim();
  const section = document.getElementById('hab-f-section').value;

  if (!name) {
    document.getElementById('hab-f-name').focus();
    document.getElementById('hab-f-name').style.borderColor = '#f06060';
    return;
  }
  document.getElementById('hab-f-name').style.borderColor = '';

  const days = section === 'weekly'
    ? [...document.querySelectorAll('.hfd-day.on')].map(b => b.dataset.day)
    : [];

  _buzz([15, 30, 15]);
  const habit = { name, time, duration: dur, cost, cat, why, days };

  if (_editId) {
    updateHabit(section, _editId, habit);
  } else {
    addHabit(section, habit);
  }

  closeHabitModal();
  renderHabits();
}

// ── DELETE
export function deleteHabitUI(section, id) {
  _buzz(15);
  deleteHabit(section, id);
  renderHabits();
}

// ── TOGGLE DAY BUTTON
export function toggleDay(btn) {
  btn.classList.toggle('on');
  _styleDay(btn, btn.classList.contains('on'));
}

// ── PRIVATE HELPERS
function _timeToMins(t) {
  if (!t) return 9999;
  const [h, m] = t.split(':').map(Number);
  return h * 60 + (m || 0);
}

function _fmt12(t) {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  return `${h % 12 || 12}:${String(m).padStart(2,'0')} ${h >= 12 ? 'PM' : 'AM'}`;
}

function _fmtDur(mins) {
  if (!mins) return '—';
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

function _cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

function _esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}