// ui/metric_detail_sheet.dart — tap a muscle or row to open this. Shows the
// rank, the derived tier ladder (achieved/next/locked), log history, and an
// inline log form. Showcases the engine's derived thresholds.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/aesthetic_guides.dart';
import '../data/metrics.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log, strengthValue, isolationLifts;
import '../state/providers.dart';
import 'acuity_test.dart';
import 'hearing_test.dart';
import 'badge.dart';
import 'grooming_checklist.dart';
import 'photo_measure.dart';
import 'voice_measure.dart';

const List<String> _ladderTiers = [
  'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Titan'
];

// Cap the rendered history so a metric with hundreds of logs stays snappy.
const int _historyWindow = 8; // beyond this, history becomes a fixed-height scroll window

void openDetailSheet(BuildContext context, String metricId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0D1024),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _MetricDetailSheet(metricId: metricId),
  );
}

class _MetricDetailSheet extends ConsumerStatefulWidget {
  final String metricId;
  const _MetricDetailSheet({required this.metricId});
  @override
  ConsumerState<_MetricDetailSheet> createState() => _MetricDetailSheetState();
}

class _MetricDetailSheetState extends ConsumerState<_MetricDetailSheet> {
  final _weight = TextEditingController();
  final _reps = TextEditingController(text: '5');
  final _value = TextEditingController();
  final _bw = TextEditingController();

  @override
  void initState() {
    super.initState();
    final bw = ref.read(currentBodyweightProvider);
    if (bw != null) _bw.text = bw.toStringAsFixed(0);
  }

  void _save() {
    final m = metricById(widget.metricId);
    Log log;
    if (m.isStrength) {
      final w = double.tryParse(_weight.text);
      final reps = int.tryParse(_reps.text);
      final bw = double.tryParse(_bw.text);
      if (w == null || reps == null || bw == null) return;
      log = Log(m.id, strengthValue(m.id, w, reps),
          bodyweight: bw, ts: DateTime.now().toIso8601String());
    } else {
      final v = double.tryParse(_value.text);
      if (v == null) return;
      log = Log(m.id, v, ts: DateTime.now().toIso8601String());
    }
    ref.read(logsProvider.notifier).add(m.id, log);
    _weight.clear();
    _value.clear();
  }

  Future<void> _measureVoice() async {
    final avqi = await measureVoiceFlow(context, ref);
    if (avqi == null || !mounted) return;
    ref.read(logsProvider.notifier)
        .add('voice', Log('voice', avqi, ts: DateTime.now().toIso8601String()));
    setState(() {}); // refresh latest/history
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Voice logged: AVQI ${avqi.toStringAsFixed(1)}')));
  }

  Future<void> _measureAcuity() async {
    final logMar = await measureAcuityFlow(context, ref);
    if (logMar == null || !mounted) return;
    ref.read(logsProvider.notifier)
        .add('eye', Log('eye', logMar, ts: DateTime.now().toIso8601String()));
    setState(() {}); // refresh latest/history
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Acuity logged: ${snellen(logMar)} (${logMar.toStringAsFixed(2)} logMAR)')));
  }

  Future<void> _measureHearing() async {
    final score = await measureHearingFlow(context, ref);
    if (score == null || !mounted) return;
    ref.read(logsProvider.notifier)
        .add('ear', Log('ear', score, ts: DateTime.now().toIso8601String()));
    setState(() {}); // refresh latest/history
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Hearing logged: ${score.toStringAsFixed(0)} / 100')));
  }

  Future<void> _measureGrooming() async {
    final score = await measureGroomingFlow(context, ref);
    if (score == null || !mounted) return;
    ref.read(logsProvider.notifier)
        .add('grooming', Log('grooming', score, ts: DateTime.now().toIso8601String()));
    setState(() {}); // refresh latest/history
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Grooming logged: ${score.toStringAsFixed(0)}/100')));
  }

  // Photo-based aesthetics + their capture tip.
  static const Map<String, String> _photoTips = {
    'skin': 'Face the camera, fill the frame, no makeup or harsh shadows.',
    'oral': 'A clear, well-lit photo of your smile showing teeth and gums.',
    'hair': 'A macro-lens close-up of the scalp (part the hair). Set the lens field-of-view below.',
  };

  Future<void> _measurePhoto(String id, String label) async {
    final m = metricById(id);
    final score = await measurePhotoFlow(context, ref,
        metric: id, title: label, tip: _photoTips[id] ?? '');
    if (score == null || !mounted) return;
    ref.read(logsProvider.notifier)
        .add(id, Log(id, score, ts: DateTime.now().toIso8601String()));
    setState(() {}); // refresh latest/history
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label logged: ${score.toStringAsFixed(score < 10 ? 1 : 0)} ${m.unit}')));
  }

  @override
  Widget build(BuildContext context) {
    final m = metricById(widget.metricId);
    final logs = ref.watch(logsProvider)[m.id] ?? const [];
    // Newest by timestamp (logs may be stored out of order after a sync), not last-inserted.
    final latest = logs.isEmpty
        ? null
        : logs.reduce((a, b) => b.ts.compareTo(a.ts) > 0 ? b : a);
    final ranked = latest != null && eng.standards.containsKey(m.id);
    final r = ranked ? eng.scoreLog(latest) : null;
    final c = r != null ? tierColor(r.tier) : const Color(0xFF5A6072);
    final bw = m.bodyweightScaled ? ref.watch(currentBodyweightProvider) : null;
    final curIdx = r != null ? r.rankValue.floor() : 0;

    // Newest first by timestamp — logs can be stored out of order (e.g. after a
    // Google sync), so sort by ts rather than insertion order. Keep the original
    // index so delete still targets the right entry.
    final ordered = [for (var i = 0; i < logs.length; i++) (i, logs[i])]
      ..sort((a, b) => b.$2.ts.compareTo(a.$2.ts));

    // How far to the next rank, in the metric's own units (sign = direction).
    String? nextHint;
    if (r != null && latest != null) {
      if (curIdx + 1 < eng.tiers.length) {
        final nt = eng.tiers[curIdx + 1];
        try {
          final thr = eng.threshold(m.id, nt, bw);
          if (thr.isFinite) {
            final gap = (thr - latest.value).abs();
            final gapStr = gap < 10 ? gap.toStringAsFixed(1) : gap.toStringAsFixed(0);
            nextHint = '${thr >= latest.value ? '▲' : '▼'} $gapStr ${m.unit} to $nt';
          }
        } catch (_) {/* threshold unavailable (e.g. no bodyweight) */}
      } else {
        nextHint = 'Top rank reached 🏆';
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        // Leave a tappable strip of scrim at the top for reliable dismissal.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
              left: 18, right: 18, top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.only(bottom: 12, top: 2),
                child: Center(child: SizedBox(
                  width: 44, height: 5,
                  child: DecoratedBox(decoration: BoxDecoration(
                      color: Color(0x21FFFFFF), borderRadius: BorderRadius.all(Radius.circular(3)))),
                )),
              ),
            ),
            // ── Header ──
            Row(children: [
              if (r != null)
                RankBadge(tier: r.tier, sub: r.sub, size: 128)
              else
                // Tracked / unranked metric — no tier, so no medallion.
                Container(
                  width: 102, height: 102,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4CE0C3).withValues(alpha: 0.12),
                    border: Border.all(color: const Color(0xFF4CE0C3).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.insights, color: Color(0xFF4CE0C3), size: 38),
                ),
              const SizedBox(width: 12),
              Expanded(child: Text(m.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              if (r != null)
                Text('${r.tier} ${r.sub}',
                    style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 2),
            Text('📍 ${m.exercise}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            // How to log it — the exact protocol, so numbers are comparable
            // session to session (and to the population standard).
            if (m.howTo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D1D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('📝 ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Text(m.howTo,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8A90B0), height: 1.35)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            if (r != null) ...[
              Text('Top ${r.topPct.toStringAsFixed(1)}% of young men',
                  style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              if (m.provisional) ...[
                const SizedBox(height: 4),
                Text(
                    isolationLifts.contains(m.id)
                        ? '⚠ Ranked by estimated 1RM from your working set (reps capped at 12) — a provisional standard for isolation lifts.'
                        : '⚠ Provisional standard — this rank is an estimate.',
                    style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                    value: r.rankValue - curIdx, minHeight: 8,
                    color: c, backgroundColor: c.withValues(alpha: 0.15)),
              ),
              if (nextHint != null) ...[
                const SizedBox(height: 6),
                Text(nextHint, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ],
            ] else if (latest != null)
              // Tracked (unranked) metric with data — show the value, no tier.
              Text('Latest: ${latest.value.toStringAsFixed(1)} ${m.unit}  ·  tracked, not ranked',
                  style: const TextStyle(color: Color(0xFF4CE0C3), fontWeight: FontWeight.w600))
            else
              const Text('No logs yet — add one below.',
                  style: TextStyle(color: Colors.grey)),

            // ── Measurement guide (aesthetics — what/how/scale + readiness) ──
            if (aestheticGuides[m.id] != null) _guideCard(aestheticGuides[m.id]!),

            // ── Milestone ladder (derived thresholds) ──
            if (ranked) ...[
              const SizedBox(height: 18),
              const Text('TIER LADDER',
                  style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
              const SizedBox(height: 6),
              for (var i = 0; i < _ladderTiers.length; i++)
                _ladderRow(m, _ladderTiers[i], i + 1, curIdx, bw),
            ],

            // Auto-synced metrics come from Google Health — no manual logging.
            if (m.autoSync) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D1D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: const Row(children: [
                  Icon(Icons.cloud_done_outlined, size: 18, color: Color(0xFF4CE0C3)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Synced automatically from Google Health — '
                      'logged on each ☁ sync, no manual entry.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A90B0)))),
                ]),
              ),
            ] else ...[
            // ── Log form (above the history, so logging is the first thing) ──
            const SizedBox(height: 18),
            Text('LOG ${m.exercise.isEmpty ? m.label : m.exercise}'.toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 8),
            if (m.isStrength) ...[
              Row(children: [
                Expanded(child: _field(_weight,
                    m.id == 'pullup' ? 'Total weight (kg)' : 'Weight (kg)')),
                const SizedBox(width: 8),
                Expanded(child: _field(_reps, 'Reps')),
              ]),
              // The pullup standard expects TOTAL system weight — typing only
              // the added plate would rank a real pullup as Wood.
              if (m.id == 'pullup')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Total = bodyweight + added load (bodyweight-only pullup → enter your bodyweight)',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              _field(_bw, 'Bodyweight now (kg) — snapshotted'),
            ] else ...[
              // Voice quality can be measured directly from the mic (Praat analysis).
              if (m.id == 'voice') ...[
                _grandButton('🎙  Measure with mic', const Color(0xFF4CE0C3), _measureVoice),
                const SizedBox(height: 8),
                const Text('— or enter a score manually —',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
              if (m.id == 'eye') ...[
                _grandButton('👁  Measure acuity', const Color(0xFF4CE0C3), _measureAcuity),
                const SizedBox(height: 8),
                const Text('— or enter logMAR manually —',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
              if (m.id == 'grooming') ...[
                _grandButton('✂  Grooming check', const Color(0xFF4CE0C3), _measureGrooming),
                const SizedBox(height: 8),
                const Text('— or enter a score manually —',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
              if (m.id == 'ear') ...[
                _grandButton('👂  Measure hearing', const Color(0xFF4CE0C3), _measureHearing),
                const SizedBox(height: 8),
                const Text('— or enter a score manually —',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
              if (_photoTips[m.id] != null) ...[
                _grandButton('📷  Measure from photo', const Color(0xFF4CE0C3),
                    () => _measurePhoto(m.id, m.label)),
                const SizedBox(height: 8),
                const Text('— or enter a score manually —',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
              ],
              _field(_value, '${m.label} (${m.unit})'),
            ],
            const SizedBox(height: 12),
            _grandButton('Save', ranked ? c : const Color(0xFF5B6AF8), _save),
            ],

            // ── History (newest first by date) ──
            if (logs.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('HISTORY · ${logs.length}',
                  style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
              const SizedBox(height: 6),
              // Short histories render inline; long ones become a fixed-height scroll
              // window so the sheet never grows without bound (scales to thousands).
              if (ordered.length <= _historyWindow)
                for (final (idx, log) in ordered) _historyRow(m, log, idx)
              else
                SizedBox(
                  height: 360,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: ordered.length,
                    itemBuilder: (_, i) => _historyRow(m, ordered[i].$2, ordered[i].$1),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _guideCard(AestheticGuide g) {
    final (label, color) = switch (g.status) {
      MeasureStatus.ready => ('● Measurable in-app', const Color(0xFF4CE0C3)),
      MeasureStatus.manual => ('● Manual entry', const Color(0xFFF6CF3E)),
      MeasureStatus.planned => ('● Coming soon', const Color(0xFFF8A55B)),
    };
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('HOW IT’S MEASURED',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, textAlign: TextAlign.end,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 8),
        _guideRow('What', g.what),
        _guideRow('How', g.how),
        _guideRow('Scale', g.anchor),
      ]),
    );
  }

  Widget _guideRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 42,
              child: Text(k, style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w700))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, height: 1.3))),
        ]),
      );

  Widget _ladderRow(MetricDef m, String tier, int tierIdx, int curIdx, double? bw) {
    final thr = eng.threshold(m.id, tier, bw);
    final achieved = curIdx >= tierIdx;
    final isNext = curIdx == tierIdx - 1;
    final col = tierColor(tier);
    final icon = achieved ? '✓' : (isNext ? '🎯' : '🔒');
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: achieved ? col.withValues(alpha: 0.12) : const Color(0xFF0A0D1D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isNext ? col : Colors.transparent, width: 1),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
        Expanded(child: Text(tier,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: achieved ? col : Colors.grey))),
        Text('${thr.toStringAsFixed(1)} ${m.unit}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: achieved ? col : Colors.grey)),
        const SizedBox(width: 8),
        Text('top ${eng.tierTopPct[tier]!.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  Widget _historyRow(MetricDef m, Log log, int index) {
    final r = eng.standards.containsKey(m.id) ? eng.scoreLog(log) : null;
    final c = r != null ? tierColor(r.tier) : Colors.grey;
    final date = DateTime.tryParse(log.ts);
    final dateStr = date != null
        ? '${date.day}/${date.month}/${date.year % 100}'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${log.value.toStringAsFixed(1)} ${m.unit}'
            '${m.bodyweightScaled && log.bodyweight != null ? ' @ ${log.bodyweight!.toStringAsFixed(0)} kg' : ''}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (r != null)
          Text('${r.tier} ${r.sub}',
              style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          color: Colors.grey,
          onPressed: () => ref.read(logsProvider.notifier).remove(m.id, index),
        ),
      ]),
    );
  }

  // A grand gradient action button with a coloured glow.
  Widget _grandButton(String label, Color c, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, 0.28)!]),
            boxShadow: [
              BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -2, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Center(child: Text(label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
              ),
            ),
          ),
        ),
      );

  Widget _field(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}
