// ui/photo_measure.dart — capture a photo, send it to the backend CV analyzer, and
// return a 0–100 aesthetic score. Reused by Skin / Oral / Hair. Honest framing: these
// are screening estimates (lighting/framing-sensitive), not clinical instruments.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
    backgroundColor: const Color(0xFF12152E),
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

  Future<void> _capture(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1280, imageQuality: 90);
      if (x == null) return; // user cancelled the picker
      setState(() => _phase = _Phase.analyzing);
      final api = ref.read(apiClientProvider);
      await api.loadPersistedToken();
      _result = await api.measurePhoto(widget.metric, x.path);
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
          _btn('📷  Take photo', _accent, () => _capture(ImageSource.camera)),
          const SizedBox(height: 8),
          _btn('🖼  Choose from library', const Color(0xFF2A2F4A), () => _capture(ImageSource.gallery)),
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
    final comp = (r['components'] as Map?) ?? const {};
    return [
      Center(child: Text(score.toStringAsFixed(0),
          style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _accent, height: 1))),
      Center(child: Text('${widget.title.toUpperCase()} / 100',
          style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted, fontWeight: FontWeight.w700))),
      const SizedBox(height: 14),
      for (final e in comp.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${e.key[0].toUpperCase()}${e.key.substring(1)}'.replaceAll('_', ' '),
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            Text('${(e.value as num).toStringAsFixed(0)}/100',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
      const SizedBox(height: 18),
      _btn('Use this score', _accent, () => Navigator.of(context).pop(score)),
      const SizedBox(height: 8),
      _btn('Retake', const Color(0xFF2A2F4A), () => setState(() => _phase = _Phase.idle)),
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
