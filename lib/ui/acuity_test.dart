// ui/acuity_test.dart — in-app visual-acuity self-test (tumbling-E → logMAR).
//
// Honest method: (1) calibrate the screen's px/mm with a real credit card, (2) set
// the viewing distance, (3) show a tumbling "E" at the physical size that subtends the
// target logMAR at that distance. The smallest line the user resolves → logMAR, which
// the `eye` metric ranks. Pure helpers (optotypePx/snellen) are unit-tested.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accent = Color(0xFF4CE0C3);
const _muted = Color(0xFF8A90B0);

// Credit card (ISO/IEC 7810 ID-1) width in mm — the calibration reference.
const double _cardWidthMm = 85.6;
// Below this rendered size an optotype is sub-pixel/unreliable → stop (screen floor).
const double _minRenderPx = 4.0;
// logMAR levels, easiest (largest) → hardest (smallest): 20/200 … 20/10.
const List<double> _levels = [1.0, 0.7, 0.5, 0.3, 0.2, 0.1, 0.0, -0.1, -0.2, -0.3];

/// Screen size (logical px) of an optotype for a target logMAR. A letter subtends
/// 5×MAR; MAR(arcmin) = 10^logMAR; height = 2·d·tan(angle/2).
double optotypePx(double logMAR, double distanceMm, double pxPerMm) {
  final marArcmin = math.pow(10, logMAR).toDouble();
  final angleRad = 5 * marArcmin * (math.pi / 180.0 / 60.0);
  final heightMm = 2 * distanceMm * math.tan(angleRad / 2);
  return heightMm * pxPerMm;
}

/// Snellen (20/xx) equivalent of a logMAR value.
String snellen(double logMAR) => '20/${(20 * math.pow(10, logMAR)).round()}';

Future<double?> measureAcuityFlow(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AcuitySheet(),
  );
}

enum _Phase { calibrate, distance, test, result }

class _AcuitySheet extends ConsumerStatefulWidget {
  const _AcuitySheet();
  @override
  ConsumerState<_AcuitySheet> createState() => _AcuitySheetState();
}

class _AcuitySheetState extends ConsumerState<_AcuitySheet> {
  _Phase _phase = _Phase.calibrate;
  double _cardPx = 280; // calibration card width on screen (logical px)
  double _distanceCm = 40;
  int _level = 0, _trial = 0, _correct = 0;
  double _resultLogMar = 1.0;
  int _eDir = 0; // 0 right, 1 down, 2 left, 3 up
  final _rand = math.Random();

  double get _pxPerMm => _cardPx / _cardWidthMm;
  double _sizeFor(int level) => optotypePx(_levels[level], _distanceCm * 10, _pxPerMm);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final px = p.getDouble('acuity_cardpx');
    final d = p.getDouble('acuity_distcm');
    if (!mounted) return;
    setState(() {
      if (px != null) _cardPx = px;
      if (d != null) _distanceCm = d;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('acuity_cardpx', _cardPx);
    await p.setDouble('acuity_distcm', _distanceCm);
  }

  void _startTest() {
    _save();
    setState(() {
      _phase = _Phase.test;
      _level = 0;
      _trial = 0;
      _correct = 0;
      _eDir = _rand.nextInt(4);
    });
  }

  void _answer(int dir) {
    if (dir == _eDir) _correct++;
    _trial++;
    if (_trial < 3) {
      setState(() => _eDir = _rand.nextInt(4));
      return;
    }
    final passed = _correct >= 2; // ≥2 of 3 clears the line
    if (passed) _resultLogMar = _levels[_level];
    final nextLevel = _level + 1;
    final canGoSmaller = passed &&
        nextLevel < _levels.length &&
        _sizeFor(nextLevel) >= _minRenderPx; // stop at the screen's renderable floor
    if (canGoSmaller) {
      setState(() {
        _level = nextLevel;
        _trial = 0;
        _correct = 0;
        _eDir = _rand.nextInt(4);
      });
    } else {
      if (!passed && _level == 0) _resultLogMar = _levels[0] + 0.3; // worse than 20/200
      setState(() => _phase = _Phase.result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 44, height: 5,
              decoration: BoxDecoration(color: const Color(0x21FFFFFF), borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 14),
          ..._body(),
        ]),
      ),
    );
  }

  List<Widget> _body() => switch (_phase) {
        _Phase.calibrate => _calibrate(),
        _Phase.distance => _distance(),
        _Phase.test => _test(),
        _Phase.result => _result(),
      };

  List<Widget> _calibrate() => [
        const Text('Step 1 · Calibrate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Hold a real bank/credit card against the screen and adjust the box until it matches exactly.',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.35)),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: _cardPx, height: _cardPx * 53.98 / 85.6, // ID-1 aspect
            decoration: BoxDecoration(
              border: Border.all(color: _accent, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: _accent.withValues(alpha: 0.06),
            ),
            child: const Center(child: Text('💳', style: TextStyle(fontSize: 22))),
          ),
        ),
        const SizedBox(height: 8),
        Slider(value: _cardPx, min: 160, max: 460, activeColor: _accent,
            onChanged: (v) => setState(() => _cardPx = v)),
        Center(child: Text('${_pxPerMm.toStringAsFixed(1)} px/mm',
            style: const TextStyle(color: _muted, fontSize: 12))),
        const SizedBox(height: 12),
        _btn('Next', _accent, () => setState(() => _phase = _Phase.distance)),
      ];

  List<Widget> _distance() => [
        const Text('Step 2 · Distance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Prop the phone and sit back this far. Further = finer acuity can be measured; cover one eye and test each separately.',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.35)),
        const SizedBox(height: 18),
        Center(child: Text('${_distanceCm.round()} cm',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _accent))),
        Slider(value: _distanceCm, min: 30, max: 300, divisions: 27, activeColor: _accent,
            onChanged: (v) => setState(() => _distanceCm = v)),
        Center(child: Text('Smallest measurable here ≈ ${_smallestMeasurable()}',
            style: const TextStyle(color: _muted, fontSize: 12))),
        const SizedBox(height: 12),
        _btn('Start test', _accent, _startTest),
        const SizedBox(height: 8),
        _btn('Back', const Color(0xFF232741), () => setState(() => _phase = _Phase.calibrate)),
      ];

  String _smallestMeasurable() {
    for (final l in _levels) {
      if (optotypePx(l, _distanceCm * 10, _pxPerMm) >= _minRenderPx) return snellen(l);
    }
    return snellen(_levels.first);
  }

  List<Widget> _test() {
    final size = _sizeFor(_level);
    return [
      const Center(child: Text('Which way do the prongs point?',
          style: TextStyle(fontSize: 13, color: _muted))),
      const SizedBox(height: 4),
      Center(child: Text(snellen(_levels[_level]),
          style: const TextStyle(fontSize: 11, color: _muted, letterSpacing: 1))),
      const SizedBox(height: 16),
      SizedBox(
        height: 150,
        child: Center(
          child: SizedBox(
            width: size, height: size,
            child: Transform.rotate(
              angle: _eDir * math.pi / 2,
              child: CustomPaint(painter: _EPainter()),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _dirBtn(Icons.arrow_upward, 3),
        _dirBtn(Icons.arrow_back, 2),
        _dirBtn(Icons.arrow_forward, 0),
        _dirBtn(Icons.arrow_downward, 1),
      ]),
      const SizedBox(height: 8),
      Center(child: Text('Line ${_level + 1} of ${_levels.length}',
          style: const TextStyle(color: _muted, fontSize: 11))),
    ];
  }

  List<Widget> _result() {
    final r = _resultLogMar;
    return [
      Center(child: Text(snellen(r),
          style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: _accent, height: 1))),
      Center(child: Text('${r.toStringAsFixed(2)} logMAR',
          style: const TextStyle(fontSize: 12, color: _muted, letterSpacing: 1))),
      const SizedBox(height: 18),
      _btn('Use this result', _accent, () => Navigator.of(context).pop(r)),
      const SizedBox(height: 8),
      _btn('Retry', const Color(0xFF232741), () => setState(() => _phase = _Phase.distance)),
    ];
  }

  Widget _dirBtn(IconData icon, int dir) => Material(
        color: const Color(0xFF232741),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _answer(dir),
          child: Padding(padding: const EdgeInsets.all(14), child: Icon(icon, color: Colors.white)),
        ),
      );

  Widget _btn(String label, Color c, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: Material(
          color: c,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(child: Text(label,
                  style: TextStyle(
                      color: c.computeLuminance() > 0.4 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
        ),
      );
}

/// Tumbling-E optotype on a 5×5 grid (spine + 3 prongs pointing right at rotation 0).
class _EPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 5;
    final p = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, u, size.height), p); // spine (left column)
    for (final row in [0, 2, 4]) {
      canvas.drawRect(Rect.fromLTWH(0, row * u, size.width, u), p); // 3 prongs
    }
  }

  @override
  bool shouldRepaint(covariant _EPainter oldDelegate) => false;
}
