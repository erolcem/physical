// ════════════════════════════════════════════════════════
// ui/profile.js — Profile screen
// ════════════════════════════════════════════════════════

import { RANKS, MUSCLES, SUB } from '../data/metrics.js';
import { rankOf, getSubrank, latestORM, overallScore, getPrecisePercentOverall, parseDate, preciseRankValue } from '../engine/rank.js';
import { getLogs, getSettings, getHabits, setUnit, clearLogs, importLogs, importHabitsData } from '../engine/state.js';
import { exportData, parseImport, storageUsage } from '../engine/storage.js';
import { injectBadge, badge } from './badge.js';
import { showToast } from './toast.js';

export function renderProfile() {
  const logs     = getLogs();
  const settings = getSettings();
  const score    = overallScore(logs);
  const ri       = Math.min(7, Math.floor(score));
  const r        = RANKS[ri];
  const frac     = score % 1;
  const sub      = frac < 0.333 ? 0 : frac < 0.666 ? 1 : 2;

  // ── Hero badge
  injectBadge('profile-badge-wrap', ri, 96, 96);
  const emb = document.getElementById('profile-emblem');
  emb.textContent = SUB[sub];
  emb.style.color = r.c;
  emb.style.background = r.c + '44';
  emb.style.borderColor = r.c + '44';

  document.getElementById('profile-rank-name').textContent = r.name + ' ' + SUB[sub];
  document.getElementById('profile-rank-name').style.color = r.c;
  document.getElementById('profile-top').textContent = `Top ${getPrecisePercentOverall(score)}% of all athletes`;
  document.getElementById('profile-top').style.color = r.c;
  document.getElementById('profile-avg').textContent = `Combined rank score: ${score.toFixed(2)} / 7.0`;

  // ── Core stats
  const allEntries    = Object.values(logs).flat();
  const totalSets     = allEntries.length;
  const loggedMuscles = Object.keys(logs).filter(k => logs[k]?.length).length;
  const allDates      = new Set(allEntries.map(e => e.date));
  const totalMetrics  = MUSCLES.length;

  // Best single rank achieved
  const topRankIdx  = Math.max(0, ...MUSCLES.map(m => rankOf(m.id, latestORM(m.id, logs))));
  const topRankName = RANKS[topRankIdx].name;

  document.getElementById('stats-grid').innerHTML = `
    <div class="stat-card">
      <div class="stat-val" style="color:${r.c}">${totalSets}</div>
      <div class="stat-lbl">Total Logs</div>
    </div>
    <div class="stat-card">
      <div class="stat-val" style="color:${r.c}">${loggedMuscles}<span style="font-size:13px;color:var(--muted2)">/${totalMetrics}</span></div>
      <div class="stat-lbl">Metrics Active</div>
    </div>
    <div class="stat-card">
      <div class="stat-val" style="color:${r.c}">${allDates.size}</div>
      <div class="stat-lbl">Session Days</div>
    </div>`;

  // ── Category breakdown with full rank progress bars + mini badges
  const strengthIds = MUSCLES.filter(m => m.front?.length || m.back?.length).map(m => m.id);
  const innerIds    = MUSCLES.filter(m => m.inner?.length).map(m => m.id);
  const aesIds      = MUSCLES.filter(m => m.cat === 'aes').map(m => m.id);

  const avgOf = ids => {
    const scores = ids.map(id => preciseRankValue(id, latestORM(id, logs)));
    return scores.length ? (scores.reduce((a, b) => a + b, 0) / scores.length) : 0;
  };

  const categoryBreakdown = [
    { label: 'Strength',    ids: strengthIds,                                                                            icon: '💪' },
    { label: 'Performance', ids: innerIds.filter(id => ['run5k','vert','plank','mobility','restHeart'].includes(id)),    icon: '⚡' },
    { label: 'Recovery',    ids: innerIds.filter(id => ['sleep','hrv','vo2max','mass'].includes(id)),                    icon: '❤️' },
    { label: 'Aesthetics',  ids: aesIds,                                                                                 icon: '✨' },
  ];

  const breakEl = document.getElementById('profile-breakdown');
  if (breakEl) {
    breakEl.innerHTML = categoryBreakdown.map(cat => {
      const avg      = avgOf(cat.ids);
      const catRi    = Math.min(7, Math.floor(avg));
      const catR     = RANKS[catRi];
      const catFrac  = avg % 1;
      const catSub   = catFrac < 0.333 ? 0 : catFrac < 0.666 ? 1 : 2;
      const catPct   = (catFrac * 100).toFixed(1);
      const prevName = catRi > 0 ? RANKS[catRi - 1].name : 'Start';
      const nextName = catRi < 7 ? RANKS[catRi].name : 'Max';
      const badgeSVG = badge(catRi, 36, 36);
      return `
        <div class="cat-break-block">
          <div class="cat-break-head">
            <div class="cat-break-badge" style="filter:drop-shadow(0 0 8px ${catR.c}80)">${badgeSVG}</div>
            <div class="cat-break-info">
              <div class="cat-break-title">
                <span class="cat-break-icon">${cat.icon}</span>
                <span class="cat-break-label">${cat.label}</span>
                <span class="cat-break-rank" style="color:${catR.c}">${catR.name} ${SUB[catSub]}</span>
              </div>
              <div class="cat-break-sub">Avg ${avg.toFixed(2)}/7.0 · Top ${getPrecisePercentOverall(avg)}%</div>
            </div>
          </div>
          <div class="prog-outer" style="margin-bottom:14px">
            <div class="prog-fill" style="width:${catPct}%;background:linear-gradient(90deg,${catR.c}cc,${catR.c})"></div>
            <div class="prog-tick" style="left:33.3%"><div class="prog-tick-lbl"><b style="color:${catR.c}">II</b></div></div>
            <div class="prog-tick" style="left:66.6%"><div class="prog-tick-lbl"><b style="color:${catR.c}">III</b></div></div>
          </div>
          <div class="prog-ends" style="margin-top:-10px">${prevName}<span style="color:${catR.c}">${nextName}</span></div>
        </div>`;
    }).join('');
  }

  // ── Badge showcase
  const showcase = document.getElementById('badges-showcase');
  showcase.innerHTML = '';
  RANKS.forEach((rk, i) => {
    const cnt  = MUSCLES.filter(m => rankOf(m.id, latestORM(m.id, logs)) === i).length;
    const tile = document.createElement('div');
    tile.className = 'badge-tile';
    if (cnt === 0) {
      tile.innerHTML = `<div style="opacity:.2;filter:grayscale(100%)">${badge(i, 40, 40)}</div>
        <div class="badge-tile-name" style="color:var(--muted)">${rk.name}</div>
        <div class="badge-tile-count" style="color:var(--muted2)">0</div>`;
    } else {
      const blur      = 4 + cnt * 3;
      const bgOpacity = Math.min(40, 5 + cnt * 4).toString(16).padStart(2, '0');
      const scale     = 1 + cnt * 0.012;
      tile.innerHTML = `<div>${badge(i, 40, 40)}</div>
        <div class="badge-tile-name" style="color:${rk.c}">${rk.name}</div>
        <div class="badge-tile-count" style="color:#fff;font-weight:900">${cnt}</div>`;
      tile.querySelector('svg').style.filter = `drop-shadow(0 0 ${blur}px ${rk.c})`;
      tile.style.borderColor = `${rk.c}50`;
      tile.style.background  = `radial-gradient(circle at top,${rk.c}${bgOpacity} 0%,var(--surface) 100%)`;
      tile.style.transform   = `scale(${scale})`;
    }
    showcase.appendChild(tile);
  });

  // ── Per-metric leaderboard (top 5 by rank)
  const rankEl = document.getElementById('profile-metric-ranks');
  if (rankEl) {
    const sorted = [...MUSCLES]
      .map(m => ({ m, orm: latestORM(m.id, logs), ri: rankOf(m.id, latestORM(m.id, logs)), prv: preciseRankValue(m.id, latestORM(m.id, logs)) }))
      .filter(x => x.orm > 0)
      .sort((a, b) => b.prv - a.prv)
      .slice(0, 6);
    rankEl.innerHTML = sorted.length ? sorted.map((x, idx) => {
      const rk  = RANKS[x.ri];
      const sub = getSubrank(x.m.id, x.orm);
      return `<div class="metric-rank-row">
        <span class="metric-rank-pos" style="color:${idx < 3 ? rk.c : 'var(--muted)'}">${idx + 1}</span>
        <span class="metric-rank-icon">${x.m.icon || '💪'}</span>
        <span class="metric-rank-name">${x.m.label}</span>
        <span class="metric-rank-badge" style="background:${rk.c}22;color:${rk.c};border-color:${rk.c}44">${rk.name} ${SUB[sub]}</span>
        <span class="metric-rank-val" style="color:var(--muted2)">${x.orm.toFixed(1)} ${x.m.type === 'score' ? x.m.unit : 'kg'}</span>
      </div>`;
    }).join('') : '<div style="color:var(--muted);font-size:12px;padding:.5rem 0">No data yet — start logging!</div>';
  }

  // ── Activity streaks
  const dateObjs = [...allDates].map(d => parseDate(d)).sort((a, b) => a - b);
  let longest = 0, cur = 0;
  for (let i = 0; i < dateObjs.length; i++) {
    if (i === 0 || (dateObjs[i] - dateObjs[i - 1]) <= 86400000 * 1.5) cur++;
    else cur = 1;
    longest = Math.max(longest, cur);
  }
  let topM = '—', topCount = 0;
  MUSCLES.forEach(m => {
    const c = (logs[m.id] || []).length;
    if (c > topCount) { topCount = c; topM = m.label; }
  });

  // Most improved (biggest rank jump — requires ≥2 logs)
  let mostImproved = '—', bestJump = 0;
  MUSCLES.forEach(m => {
    const entries = logs[m.id] || [];
    if (entries.length < 2) return;
    const first = preciseRankValue(m.id, entries[0].oneRM);
    const last  = preciseRankValue(m.id, entries[entries.length - 1].oneRM);
    const jump  = last - first;
    if (jump > bestJump) { bestJump = jump; mostImproved = m.label; }
  });

  document.getElementById('streak-rows').innerHTML = `
    <div class="streak-row">
      <div class="streak-icon">🔥</div>
      <div class="streak-info">
        <div class="streak-val" style="color:#f0622a">${allDates.size}</div>
        <div class="streak-lbl">Total session days</div>
      </div>
    </div>
    <div class="streak-row">
      <div class="streak-icon">⚡</div>
      <div class="streak-info">
        <div class="streak-val" style="color:${r.c}">${longest}</div>
        <div class="streak-lbl">Longest streak</div>
      </div>
    </div>
    <div class="streak-row">
      <div class="streak-icon">🏆</div>
      <div class="streak-info">
        <div class="streak-val" style="color:${r.c};font-size:14px">${topM}</div>
        <div class="streak-lbl">Most logged · ${topCount} sessions</div>
      </div>
    </div>
    <div class="streak-row">
      <div class="streak-icon">📈</div>
      <div class="streak-info">
        <div class="streak-val" style="color:#4ce0c3;font-size:14px">${mostImproved}</div>
        <div class="streak-lbl">Most improved${bestJump > 0 ? ' · +'+ bestJump.toFixed(1) +' tiers' : ''}</div>
      </div>
    </div>`;

  // ── Unit toggle + storage
  ['kg', 'lb'].forEach(u => {
    document.getElementById('unit-' + u)?.classList.toggle('active', u === settings.unit);
  });
  const usageEl = document.getElementById('storage-usage');
  if (usageEl) usageEl.textContent = storageUsage();
}

export function setUnitFromProfile(u) { setUnit(u); renderProfile(); }

export function exportDataFromProfile() {
  exportData(getLogs(), getSettings(), getHabits());
  showToast('✓ Backup downloaded', '#3dd6c0');
}

export function clearDataFromProfile() {
  if (!confirm('Delete ALL your log data? This cannot be undone.')) return;
  clearLogs();
  renderProfile();
  showToast('All data cleared', '#f0622a');
}

export function handleImportFile(event) {
  const file = event.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = e => {
    try {
      const { logs: newLogs, settings: newSettings, habits: newHabits } = parseImport(e.target.result);
      if (confirm('This will overwrite your current logs. Are you sure?')) {
        importLogs(newLogs, newSettings);
        if (newHabits) importHabitsData(newHabits);
        renderProfile();
        showToast('✓ Data imported successfully!', '#3dd6c0');
      }
    } catch {
      showToast('Invalid backup file format.', '#f0622a');
    }
    event.target.value = '';
  };
  reader.readAsText(file);
}