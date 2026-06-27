// ui/voice_measure.dart — record a short sustained-vowel clip, send it to the
// backend for Praat acoustic analysis, and return a 0–100 voice-quality score.
// Used by the Voice metric in the detail sheet (the "Measure with mic" button).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../data/api_client.dart' show ApiException;
import '../data/sync.dart' show apiClientProvider;

const _accent = Color(0xFF4CE0C3);
const _muted = Color(0xFF8A90B0);

/// Opens the voice-measure sheet. Returns the chosen 0–100 score, or null if the
/// user cancelled / it failed.
Future<double?> measureVoiceFlow(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12152E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _VoiceMeasureSheet(),
  );
}

enum _Phase { idle, recording, analyzing, result, error }

class _VoiceMeasureSheet extends ConsumerStatefulWidget {
  const _VoiceMeasureSheet();
  @override
  ConsumerState<_VoiceMeasureSheet> createState() => _VoiceMeasureSheetState();
}

class _VoiceMeasureSheetState extends ConsumerState<_VoiceMeasureSheet> {
  final _rec = AudioRecorder();
  _Phase _phase = _Phase.idle;
  String _error = '';
  Map<String, dynamic>? _result;
  String? _path;

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() { _phase = _Phase.error; _error = 'Microphone access is needed to measure your voice.'; });
        return;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
        path: _path!,
      );
      setState(() => _phase = _Phase.recording);
    } catch (e) {
      setState(() { _phase = _Phase.error; _error = 'Could not start recording: $e'; });
    }
  }

  Future<void> _stopAndAnalyze() async {
    setState(() => _phase = _Phase.analyzing);
    try {
      final path = await _rec.stop() ?? _path;
      if (path == null) throw 'No recording was captured.';
      final api = ref.read(apiClientProvider);
      await api.loadPersistedToken();
      _result = await api.measureVoice(path);
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
          const Text('Measure Voice Quality',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
              'In a quiet room, hold the phone ~20 cm away and sustain a steady "aaah" '
              'for about 3 seconds. We analyse pitch stability, jitter, shimmer and clarity.',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.35)),
          const SizedBox(height: 20),
          ..._body(),
        ]),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.idle:
        return [_btn('🎙  Start recording', _accent, _start)];
      case _Phase.recording:
        return [
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.fiber_manual_record, color: Color(0xFFFA3737), size: 14),
            SizedBox(width: 8),
            Text('Recording… sustain "aaah"', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          _btn('Stop & analyse', _accent, _stopAndAnalyze),
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
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        );
    return [
      Center(child: Text(score.toStringAsFixed(0),
          style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _accent, height: 1))),
      const Center(child: Text('VOICE QUALITY / 100',
          style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted, fontWeight: FontWeight.w700))),
      const SizedBox(height: 16),
      if (r['pitch_hz'] != null) row('Pitch', '${(r['pitch_hz'] as num).toStringAsFixed(0)} Hz'),
      row('Jitter', '${(r['jitter_pct'] as num).toStringAsFixed(2)} %  (${(comp['jitter'] as num?)?.toStringAsFixed(0) ?? '–'}/100)'),
      row('Shimmer', '${(r['shimmer_pct'] as num).toStringAsFixed(2)} %  (${(comp['shimmer'] as num?)?.toStringAsFixed(0) ?? '–'}/100)'),
      row('Clarity (HNR)', '${(r['hnr_db'] as num).toStringAsFixed(1)} dB  (${(comp['hnr'] as num?)?.toStringAsFixed(0) ?? '–'}/100)'),
      const SizedBox(height: 18),
      _btn('Use this score', _accent, () => Navigator.of(context).pop(score)),
      const SizedBox(height: 8),
      _btn('Re-record', const Color(0xFF2A2F4A), () => setState(() => _phase = _Phase.idle)),
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
