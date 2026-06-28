// ui/hearing_test.dart — in-app pure-tone hearing screening for the Ear metric.
// For each test frequency we play a tone that ramps from very quiet to full; the user
// taps the moment they hear it → that level is their threshold. Quieter detection =
// better hearing. HONEST SCOPE: uncalibrated (level is app dBFS, not clinical dB HL),
// so it's a relative screening — use headphones in a quiet room. Provisional.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

const _accent = Color(0xFF4CE0C3);
const _muted = Color(0xFF8A90B0);

// Test frequencies (Hz). High frequencies degrade first with age/noise damage.
const List<(double, String)> _freqs = [(1000, '1 kHz'), (4000, '4 kHz'), (8000, '8 kHz')];
const double _minDb = -55, _maxDb = 0, _rampSecs = 6.0;

/// Build a mono 16-bit PCM WAV of a sine [freq] for [secs] seconds.
Uint8List _toneWav(double freq, {double secs = _rampSecs, int sr = 44100}) {
  final n = (secs * sr).round();
  final dataSize = n * 2;
  final b = BytesBuilder();
  void s(String x) => b.add(x.codeUnits);
  void u32(int v) => b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  s('RIFF'); u32(36 + dataSize); s('WAVE');
  s('fmt '); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16);
  s('data'); u32(dataSize);
  for (var i = 0; i < n; i++) {
    var v = (math.sin(2 * math.pi * freq * i / sr) * 32767 * 0.95).round();
    v = v.clamp(-32768, 32767);
    b.add([v & 0xff, (v >> 8) & 0xff]);
  }
  return b.toBytes();
}

/// 0–100 hearing score from per-frequency detection levels (dBFS). Quieter (more
/// negative) detection → higher score; averaged across frequencies.
double hearingScore(List<double> detectedDb) {
  if (detectedDb.isEmpty) return 0;
  final per = [for (final db in detectedDb) (((-db) / -_minDb) * 100).clamp(0.0, 100.0)];
  return per.reduce((a, b) => a + b) / per.length;
}

Future<double?> measureHearingFlow(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12152E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _HearingSheet(),
  );
}

enum _Phase { intro, testing, result }

class _HearingSheet extends ConsumerStatefulWidget {
  const _HearingSheet();
  @override
  ConsumerState<_HearingSheet> createState() => _HearingSheetState();
}

class _HearingSheetState extends ConsumerState<_HearingSheet> {
  final _player = AudioPlayer();
  _Phase _phase = _Phase.intro;
  int _freqIdx = 0;
  double _db = _minDb;
  Timer? _ramp;
  final List<double> _detected = [];
  String _error = '';

  @override
  void dispose() {
    _ramp?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startFreq() async {
    _ramp?.cancel();
    setState(() => _db = _minDb);
    try {
      final dir = Directory.systemTemp.createTempSync('ear');
      final f = File('${dir.path}/tone_${_freqs[_freqIdx].$1.round()}.wav');
      f.writeAsBytesSync(_toneWav(_freqs[_freqIdx].$1));
      await _player.setAudioSource(AudioSource.file(f.path));
      await _player.setVolume(_dbToVol(_minDb));
      await _player.play();
    } catch (e) {
      setState(() { _phase = _Phase.result; _error = 'Audio unavailable on this device: $e'; });
      return;
    }
    _ramp = Timer.periodic(const Duration(milliseconds: 60), (t) {
      final next = _db + (_maxDb - _minDb) / (_rampSecs * 1000 / 60);
      if (next >= _maxDb) {
        _heard(_maxDb); // reached full volume without a tap → worst threshold
      } else {
        setState(() => _db = next);
        _player.setVolume(_dbToVol(next));
      }
    });
  }

  double _dbToVol(double db) => math.pow(10, db / 20).toDouble();

  Future<void> _heard(double db) async {
    _ramp?.cancel();
    await _player.stop();
    _detected.add(db);
    if (_freqIdx + 1 < _freqs.length) {
      setState(() => _freqIdx++);
      _startFreq();
    } else {
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
          const SizedBox(height: 16),
          const Text('Hearing test', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Put on headphones in a quiet room. A tone fades in — tap the moment '
              'you first hear it. Three frequencies. (Screening, not clinical.)',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.35)),
          const SizedBox(height: 20),
          ..._body(),
        ]),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.intro:
        return [_btn('Start', _accent, () { setState(() => _phase = _Phase.testing); _startFreq(); })];
      case _Phase.testing:
        return [
          Center(child: Text('Tone ${_freqIdx + 1} of ${_freqs.length} · ${_freqs[_freqIdx].$2}',
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: ((_db - _minDb) / (_maxDb - _minDb)).clamp(0.0, 1.0),
                minHeight: 6, color: _accent, backgroundColor: _accent.withValues(alpha: 0.15)),
          ),
          const SizedBox(height: 20),
          _btn('🔊  I hear it', _accent, () => _heard(_db)),
        ];
      case _Phase.result:
        if (_error.isNotEmpty) {
          return [
            Text(_error, style: const TextStyle(color: Color(0xFFF8A55B), fontSize: 13)),
          ];
        }
        final score = hearingScore(_detected);
        return [
          Center(child: Text(score.toStringAsFixed(0),
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _accent, height: 1))),
          const Center(child: Text('HEARING / 100',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted, fontWeight: FontWeight.w700))),
          const SizedBox(height: 14),
          for (var i = 0; i < _detected.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_freqs[i].$2, style: const TextStyle(color: _muted, fontSize: 12.5)),
                Text('${_detected[i].round()} dBFS',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          const SizedBox(height: 18),
          _btn('Use this result', _accent, () => Navigator.of(context).pop(score)),
        ];
    }
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
