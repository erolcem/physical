// ui/guide_sheet.dart — the in-app help guide, opened from the top-left "?" button.
//
// ▶▶ TO EDIT THE GUIDE: just rewrite the `guideText` string below. It's plain text —
// blank lines separate paragraphs; a line in ALL CAPS (or ending with ':') renders as a
// section heading. Nothing else to touch.
import 'package:flutter/material.dart';

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _accent = Color(0xFF5B6AF8);
const _muted = Color(0xFF8A90B0);

/// The guide content. EDIT THIS — write whatever you like; headings = ALL-CAPS lines or
/// lines ending in ":". Keep it as one big string.
const String guideText = '''
WELCOME TO PHYSICAL
Physical measures every trainable dimension of your body and ranks it honestly against
the general young-male population — Wood → Bronze → Silver → Gold → Platinum → Diamond →
Champion → Titan → Glory. A rank only ever reflects real, logged or synced data.

Your goal, is to get your body to the highest rank possible, and this app is here to help you.

HOME
Your overall rank and the four category ranks (Strength, Performance, Recovery,
Aesthetics) sit at the top, with the body figures coloured by tier. Tap any metric or
muscle to open its detail — log a value, see the tier ladder, and read how it's measured.
Tap the overall rank to open the full breakdown + your Trophy Room.

PROGRESS
Every metric, graphable over time. Each section also plots its category rank, and the
Compare tab overlays any two metrics. Exercise and Diet live here too.

HABITS
Build a daily/weekly checklist. Auto-verified habits (sleep, training, diet, steps…) tick
themselves from your real data — you can't just tap them done. Manual habits (skincare,
journaling…) you tick yourself. The timeline shows your day; "Calendar" pushes habits to
your Google Calendar; reminders + an AI nudge keep you accountable.

COACH
Your AI coach sees your ranks, full history, trends, correlations, workout sets and
habits — and never your identity. Ask anything, or use a function (sleep review, find
correlations, weekly review…). It can propose habit changes you apply in one tap.

SYNC (top-right ☁)
Sign in with Google to back up everything and pull your Google Health / Fitbit data
(sleep, HRV, steps, weight, nutrition). Your data stays local-first; sync just keeps your
devices in step. Reconnect here if Google asks.
''';

void openGuideSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _GuideSheet(),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  bool _isHeading(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    return t.endsWith(':') || (t == t.toUpperCase() && t.length <= 40);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = guideText.trim().split('\n\n');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(width: 44, height: 5,
                  decoration: BoxDecoration(color: const Color(0x21FFFFFF), borderRadius: BorderRadius.circular(3))),
            ),
            const SizedBox(height: 16),
            const Row(children: [
              Icon(Icons.help_outline, color: _accent, size: 22),
              SizedBox(width: 8),
              Text('Guide', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            for (final block in blocks) ...[
              if (_isHeading(block.split('\n').first))
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(block.split('\n').first.trim(),
                      style: const TextStyle(fontSize: 12, letterSpacing: 1.5,
                          fontWeight: FontWeight.w800, color: _accent)),
                ),
              Text(
                _isHeading(block.split('\n').first)
                    ? block.split('\n').skip(1).join('\n').trim()
                    : block.trim(),
                style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFFD6D9E6)),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
              child: const Text('Tip: edit this guide in lib/ui/guide_sheet.dart (guideText).',
                  style: TextStyle(fontSize: 11, color: _muted)),
            ),
          ]),
        ),
      ),
    );
  }
}
