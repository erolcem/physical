// ui/photo_measure.dart — capture a photo, send it to the backend CV analyzer, and
// return a 0–100 aesthetic score. Reused by Skin / Oral / Hair. Honest framing: these
// are screening estimates (lighting/framing-sensitive), not clinical instruments.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_client.dart' show ApiException;
import '../data/sync.dart' show apiClientProvider;

const _accent = Color(0xFF4CE0C3);
const _muted = Color(0xFF8A90B0);

/// Capture + analyze a photo for [metric] (skin|oral|hair). Returns the 0–100 score,
/// or null if cancelled / failed.
Future<double?> measurePhotoFlow(BuildContext context, WidgetRef ref,
    {required String metric, required String title, required String tip}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0D1024),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PhotoSheet(metric: metric, title: title, tip: tip),
  );
}

enum _Phase { idle, analyzing, result, error }

class _PhotoSheet extends ConsumerStatefulWidget {
  final String metric, title, tip;
  const _PhotoSheet({required this.metric, required this.title, required this.tip});
  @override
  ConsumerState<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends ConsumerState<_PhotoSheet> {
  _Phase _phase = _Phase.idle;
  String _error = '';
  Map<String, dynamic>? _result;
  double _fovMm = 20; // hair only: the macro lens' field-of-view width (for hairs/cm²)

  bool get _isHair => widget.metric == 'hair';

  @override
  void initState() {
    super.initState();
    if (_isHair) {
      SharedPreferences.getInstance().then((p) {
        final v = p.getDouble('hair_fov_mm');
        if (v != null && mounted) setState(() => _fovMm = v);
      });
    }
  }

  Future<void> _capture(ImageSource source) async {
    try {
      // Higher res for hair so thin strands stay separable in the count.
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: _isHair ? 2000 : 1280, imageQuality: 92);
      if (x == null) return; // user cancelled the picker
      setState(() => _phase = _Phase.analyzing);
      if (_isHair) {
        (await SharedPreferences.getInstance()).setDouble('hair_fov_mm', _fovMm);
      }
      final api = ref.read(apiClientProvider);
      await api.loadPersistedToken();
      _result = await api.measurePhoto(widget.metric, x.path,
          fovMm: _isHair ? _fovMm : null);
      setState(() => _phase = _Phase.result);
    } on ApiException catch (e) {
      setState(() { _phase = _Phase.error; _error = e.message; });
    } catch (e) {
      setState(() { _phase = _Phase.error; _error = '$e'; });
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
          const SizedBox(height: 16),
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(widget.tip, style: const TextStyle(fontSize: 13, color: _muted, height: 1.35)),
          const SizedBox(height: 4),
          const Text('Screening estimate — bright, even lighting gives the most consistent result.',
              style: TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 20),
          ..._body(),
        ]),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.idle:
        return [
          if (_isHair) ...[
            Row(children: [
              const Expanded(child: Text('Macro lens field-of-view',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Text('${_fovMm.round()} mm', style: const TextStyle(color: _accent, fontWeight: FontWeight.w700)),
            ]),
            const Text('The real width your lens captures — needed for hairs/cm². Set once.',
                style: TextStyle(fontSize: 11, color: _muted)),
            Slider(value: _fovMm, min: 5, max: 40, divisions: 35, activeColor: _accent,
                onChanged: (v) => setState(() => _fovMm = v)),
            const SizedBox(height: 4),
          ],
          _btn('📷  Take photo', _accent, () => _capture(ImageSource.camera)),
          const SizedBox(height: 8),
          _btn('🖼  Choose from library', const Color(0xFF232741), () => _capture(ImageSource.gallery)),
        ];
      case _Phase.analyzing:
        return const [
          Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(color: _accent))),
          SizedBox(height: 12),
          Center(child: Text('Analysing…', style: TextStyle(color: _muted))),
        ];
      case _Phase.result:
        return _resultBody();
      case _Phase.error:
        return [
          Text(_error, style: const TextStyle(color: Color(0xFFF8A55B), fontSize: 13)),
          const SizedBox(height: 16),
          _btn('Try again', _accent, () => setState(() => _phase = _Phase.idle)),
        ];
    }
  }

  List<Widget> _resultBody() {
    final r = _result!;
    final score = (r['score'] as num).toDouble();
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        );
    final List<Widget> detail;
    final String unitLabel;
    if (_isHair) {
      unitLabel = 'HAIRS / CM²';
      detail = [
        row('Strands counted', (r['count'] as num?)?.toStringAsFixed(0) ?? '–'),
        row('Field of view', '${(r['fov_mm'] as num?)?.toStringAsFixed(0) ?? '–'} mm'),
        row('Area', '${(r['area_cm2'] as num?)?.toStringAsFixed(2) ?? '–'} cm²'),
      ];
    } else {
      unitLabel = '${widget.title.toUpperCase()} / 100';
      final comp = (r['components'] as Map?) ?? const {};
      detail = [
        for (final e in comp.entries)
          row('${e.key[0].toUpperCase()}${e.key.substring(1)}'.replaceAll('_', ' '),
              '${(e.value as num).toStringAsFixed(0)}/100'),
      ];
    }
    return [
      Center(child: Text(score.toStringAsFixed(0),
          style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _accent, height: 1))),
      Center(child: Text(unitLabel,
          style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted, fontWeight: FontWeight.w700))),
      const SizedBox(height: 14),
      ...detail,
      const SizedBox(height: 18),
      _btn('Use this result', _accent, () => Navigator.of(context).pop(score)),
      const SizedBox(height: 8),
      _btn('Retake', const Color(0xFF232741), () => setState(() => _phase = _Phase.idle)),
    ];
  }

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
