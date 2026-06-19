// ════════════════════════════════════════════════════════
// ui/progress.js — Progress screen
// Uses preciseRankValue from rank.js (same as overallScore) so
// charts are always consistent with the body/profile screens.
// ════════════════════════════════════════════════════════

import { RANKS, MUSCLES, SUB, THRESH } from '../data/metrics.js';
import { rankOf, getSubrank, latestORM, parseDate, preciseRankValue } from '../engine/rank.js';
import { getLogs, getRHSelected, getORMMid, setRHSelected, setORMMid } from '../engine/state.js';

let _rhChart  = null;
let _ormChart = null;
let _rhPeriod  = 'all';
let _ormPeriod = 'all';

const PALETTE = ['#4ce0c3', '#e67be6', '#f6cf3e', '#8e8eff', '#fa3737', '#7eb8f7', '#c28a67'];
const PERIODS  = [
  { id: '1m',  label: '1M',  months: 1  },
  { id: '3m',  label: '3M',  months: 3  },
  { id: '6m',  label: '6M',  months: 6  },
  { id: '1y',  label: '1Y',  months: 12 },
  { id: 'all', label: 'All', months: null },
];

function _buzz() { if (navigator.vibrate) navigator.vibrate(8); }

function _cutoff(pid) {
  const p = PERIODS.find(x => x.id === pid);
  if (!p?.months) return null;
  const d = new Date(); d.setMonth(d.getMonth() - p.months); return d;
}

function _filterByPeriod(data, pid) {
  const cut = _cutoff(pid);
  return cut ? data.filter(pt => pt.x >= cut) : data;
}

// ── PEARSON CORRELATION
// Computes r between two arrays of {x,y} by aligning on nearest dates.
function _pearson(dataA, dataB) {
  if (dataA.length < 3 || dataB.length < 3) return null;
  // Build a map of timestamp → value for B, then interpolate for each A point
  const pairs = [];
  dataA.forEach(ptA => {
    // find closest B point in time
    let best = null, bestDist = Infinity;
    dataB.forEach(ptB => {
      const dist = Math.abs(ptB.x - ptA.x);
      if (dist < bestDist) { bestDist = dist; best = ptB; }
    });
    // Only pair if within 30 days
    if (best && bestDist <= 30 * 86400000) pairs.push([ptA.y, best.y]);
  });
  if (pairs.length < 3) return null;
  const n  = pairs.length;
  const mA = pairs.reduce((s, p) => s + p[0], 0) / n;
  const mB = pairs.reduce((s, p) => s + p[1], 0) / n;
  let num = 0, dA = 0, dB = 0;
  pairs.forEach(([a, b]) => {
    num += (a - mA) * (b - mB);
    dA  += (a - mA) ** 2;
    dB  += (b - mB) ** 2;
  });
  const r = num / Math.sqrt(dA * dB);
  return isFinite(r) ? +r.toFixed(3) : null;
}

function _pearsonLabel(r) {
  if (r === null) return null;
  const abs = Math.abs(r);
  const dir = r >= 0 ? 'positive' : 'negative';
  const str = abs >= 0.7 ? 'strong' : abs >= 0.4 ? 'moderate' : abs >= 0.2 ? 'weak' : 'negligible';
  return { r, str, dir, label: `r = ${r.toFixed(2)} · ${str} ${dir} correlation` };
}

// ── MAIN RENDER
export function renderProgress() {
  const logs     = getLogs();
  const selected = getRHSelected();
  const ormMid   = getORMMid();
  _renderRHTabs(selected, logs);
  _renderPeriodBtns('rh-period-row',  _rhPeriod,  '__progress_rhPeriod');
  _renderRHChart(selected, logs);
  _renderORMTabs(ormMid);
  _renderPeriodBtns('orm-period-row', _ormPeriod, '__progress_ormPeriod');
  _renderORMChart(ormMid, logs);
}

function _renderPeriodBtns(id, active, handler) {
  const row = document.getElementById(id);
  if (!row) return;
  row.innerHTML = PERIODS.map(p =>
    `<button class="period-btn${active === p.id ? ' active' : ''}"
       onclick="window.${handler}('${p.id}')">${p.label}</button>`
  ).join('');
}

window.__progress_rhPeriod = id => {
  _buzz(); _rhPeriod = id;
  _renderPeriodBtns('rh-period-row', _rhPeriod, '__progress_rhPeriod');
  _renderRHChart(getRHSelected(), getLogs());
};
window.__progress_ormPeriod = id => {
  _buzz(); _ormPeriod = id;
  _renderPeriodBtns('orm-period-row', _ormPeriod, '__progress_ormPeriod');
  _renderORMChart(getORMMid(), getLogs());
};

// ── RANK HISTORY TABS
function _renderRHTabs(selected, logs) {
  const tabs = document.getElementById('rh-tabs');
  tabs.innerHTML = '';
  [{ id: 'overall', label: 'Overall' }, ...MUSCLES.map(m => ({ id: m.id, label: m.label }))].forEach(t => {
    const btn = document.createElement('button');
    btn.className = 'rh-tab' + (selected.includes(t.id) ? ' active' : '');
    btn.textContent = t.label;
    btn.onclick = () => {
      _buzz();
      let next;
      if (t.id === 'overall') {
        next = ['overall'];
      } else {
        next = selected.filter(id => id !== 'overall');
        if (next.includes(t.id)) {
          next = next.filter(id => id !== t.id);
          if (!next.length) next = ['overall'];
        } else {
          next = [...next, t.id];
        }
      }
      setRHSelected(next);
      renderProgress();
    };
    tabs.appendChild(btn);
  });
}

// ── RANK HISTORY CHART
function _renderRHChart(selected, logs) {
  const yLabels = ['Wood', 'Bronze', 'Silver', 'Gold', 'Plat', 'Diamond', 'Champ', 'Titan'];
  const datasets = [];
  const seriesData = [];   // collected for Pearson

  selected.forEach((id, index) => {
    let data;

    if (id === 'overall') {
      const allDates = new Set();
      MUSCLES.forEach(m => (logs[m.id] || []).forEach(e => allDates.add(e.date)));
      const sorted = [...allDates].sort((a, b) => parseDate(a) - parseDate(b));
      if (!sorted.length) return;
      const running = {};
      MUSCLES.forEach(m => running[m.id] = 0);

      data = sorted.map(date => {
        const targetDateObj = parseDate(date);
        MUSCLES.forEach(m => {
          (logs[m.id] || []).forEach(e => {
            if (parseDate(e.date) <= targetDateObj) running[m.id] = e.oneRM;
          });
        });
        // Use same preciseRankValue so this matches the body/profile overall score
        const scores = MUSCLES.map(m => preciseRankValue(m.id, running[m.id]));
        return { x: targetDateObj, y: +(scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(4) };
      });

      data = _filterByPeriod(data, _rhPeriod);
      if (!data.length) return;

      datasets.push({
        label: 'Overall Rank', data,
        borderColor: '#7eb8f7', backgroundColor: '#7eb8f71a',
        borderWidth: 2.5, pointRadius: 4, fill: true, tension: 0.3,
      });

    } else {
      const entries = logs[id] || [];
      if (!entries.length) return;
      const col = selected.length > 1
        ? PALETTE[index % PALETTE.length]
        : RANKS[rankOf(id, latestORM(id, logs))].c;

      data = entries.map(e => ({
        x: parseDate(e.date),
        y: preciseRankValue(id, e.oneRM),   // ← canonical function
      }));
      data = _filterByPeriod(data, _rhPeriod);
      if (!data.length) return;

      datasets.push({
        label: MUSCLES.find(m => m.id === id)?.label || id, data,
        borderColor: col,
        backgroundColor: selected.length === 1 ? col + '1a' : col,
        borderWidth: 2.5,
        pointRadius: data.length === 1 ? 6 : 4,
        fill: selected.length === 1,
        tension: 0.3,
      });
    }

    seriesData.push(data);
  });

  // ── Pearson annotation (only when exactly 2 metrics selected)
  const corrEl = document.getElementById('rh-corr');
  if (corrEl) {
    if (seriesData.length === 2) {
      const corr = _pearsonLabel(_pearson(seriesData[0], seriesData[1]));
      if (corr) {
        const col = Math.abs(corr.r) >= 0.7 ? '#4ce0c3' : Math.abs(corr.r) >= 0.4 ? '#f6cf3e' : 'var(--muted2)';
        corrEl.innerHTML = `<span style="color:${col};font-weight:700">${corr.label}</span>`;
        corrEl.style.display = 'block';
      } else {
        corrEl.innerHTML = '<span style="color:var(--muted2)">Not enough overlapping data for correlation</span>';
        corrEl.style.display = 'block';
      }
    } else {
      corrEl.style.display = 'none';
    }
  }

  if (_rhChart) _rhChart.destroy();
  if (!datasets.length) {
    _rhChart = new Chart(document.getElementById('rh-chart'), { type: 'line', data: { datasets: [] } });
    return;
  }

  _rhChart = new Chart(document.getElementById('rh-chart'), {
    type: 'line',
    data: { datasets },
    options: {
      responsive: true, maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: {
          display: selected.length > 1,
          labels: { color: '#7880a8', font: { size: 10, family: 'Barlow' }, boxWidth: 12 },
        },
        tooltip: {
          callbacks: {
            label: ctx => {
              const v    = ctx.parsed.y;
              const ri   = Math.min(7, Math.floor(v));
              const frac = v % 1;
              // Derive subrank label from fraction (same logic as getSubrank)
              const subIdx = frac < 0.333 ? 0 : frac < 0.666 ? 1 : 2;
              return `${ctx.dataset.label}: ${RANKS[ri].name} ${SUB[subIdx]} (${v.toFixed(3)})`;
            },
          },
        },
      },
      scales: {
        x: {
          type: 'time',
          time: { unit: 'day', displayFormats: { day: 'd MMM', month: 'MMM yy' } },
          ticks: { color: '#525878', font: { size: 9 }, maxTicksLimit: 8 },
          grid: { color: '#ffffff06' },
        },
        y: {
          min: 0, max: 7.5,
          ticks: {
            color: '#525878', font: { size: 9 }, stepSize: 1,
            callback: v => yLabels[Math.floor(v)] || '',
          },
          grid: { color: '#ffffff08' },
        },
      },
    },
  });
}

// ── ORM TABS
function _renderORMTabs(ormMid) {
  const tabs = document.getElementById('orm-tabs');
  tabs.innerHTML = '';
  MUSCLES.forEach(m => {
    const btn = document.createElement('button');
    btn.className = 'rh-tab' + (m.id === ormMid ? ' active' : '');
    btn.textContent = m.label;
    btn.onclick = () => { _buzz(); setORMMid(m.id); renderProgress(); };
    tabs.appendChild(btn);
  });
}

// ── ORM HISTORY CHART
function _renderORMChart(ormMid, logs) {
  const entries = logs[ormMid] || [];
  if (_ormChart) _ormChart.destroy();
  if (!entries.length) return;

  const col  = RANKS[rankOf(ormMid, latestORM(ormMid, logs))].c;
  const m    = MUSCLES.find(x => x.id === ormMid);
  const unit = m?.type === 'score' ? m.unit : 'kg';

  let data = entries.map(e => ({ x: parseDate(e.date), y: +e.oneRM.toFixed(2) }));
  data = _filterByPeriod(data, _ormPeriod);
  if (!data.length) return;

  const bestVal = Math.max(...data.map(d => d.y));

  _ormChart = new Chart(document.getElementById('orm-chart'), {
    type: 'line',
    data: {
      datasets: [
        {
          label: m ? m.label : ormMid, data,
          borderColor: col, backgroundColor: col + '1a',
          borderWidth: 2.5, pointRadius: 5, pointBackgroundColor: col,
          fill: true, tension: 0.35, order: 1,
        },
        {
          label: `Best`,
          data: data.length >= 2
            ? [{ x: data[0].x, y: bestVal }, { x: data[data.length - 1].x, y: bestVal }]
            : [],
          borderColor: col + '55', backgroundColor: 'transparent',
          borderWidth: 1.5, borderDash: [6, 4],
          pointRadius: 0, fill: false, tension: 0, order: 2,
        },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          filter: item => item.datasetIndex === 0,
          callbacks: {
            label: ctx => {
              const val  = ctx.parsed.y;
              const prv  = preciseRankValue(ormMid, val);
              const ri   = Math.min(7, Math.floor(prv));
              const frac = prv % 1;
              const subIdx = frac < 0.333 ? 0 : frac < 0.666 ? 1 : 2;
              return `${val} ${unit} · ${RANKS[ri].name} ${SUB[subIdx]} (${prv.toFixed(3)})`;
            },
          },
        },
      },
      scales: {
        x: {
          type: 'time',
          time: { unit: 'day', displayFormats: { day: 'd MMM', month: 'MMM yy' } },
          ticks: { color: '#525878', font: { size: 9 }, maxTicksLimit: 8 },
          grid: { color: '#ffffff06' },
        },
        y: {
          ticks: { color: '#525878', font: { size: 9 } },
          grid: { color: '#ffffff06' },
          beginAtZero: false,
        },
      },
    },
  });
}