// ui/guide_sheet.dart — the in-app help guide, opened from the top-left "?" button.
//
// ▶▶ TO EDIT THE GUIDE: just rewrite the `guideText` string below. It's plain text —
// blank lines separate paragraphs; a line in ALL CAPS (or ending with ':') renders as a
// section heading. Nothing else to touch.
import 'package:flutter/material.dart';

const _bg = Color(0xFF04050C);
const _card = Color(0xFF0D1024);
const _accent = Color(0xFF5B6AF8);
const _muted = Color(0xFF8A90B0);

/// The guide content. EDIT THIS — write whatever you like; headings = ALL-CAPS lines or
/// lines ending in ":". Keep it as one big string.
const String guideText = '''
WELCOME TO PHYSICAL
Physical is a quest; to get your body to the highest rank possible. 
Ranks are based on all the relevant aspects of your body.
They are grounded against the general young-male population.
Will you achieve the highest rank your body can be?

HOME
Here is where you will see your ranks,
At the top is the overall rank.
Click on it to view the four category ranks (Strength, Performance, Recovery, Aesthetics).
Below that are body figures coloured by rank to show individual metrics. 
At the bottom is an individual box layout separated by categories too.
Tap any metric or muscle to open its detail. 
You can log, see the tiers, and read how each metric is measured.
Some metrics are measured automatically.
However for the rest, it will be up to you to log what you do everyday.

PROGRESS
To help on your quest, presented here is everything data related.
Every metric, graphable over time. 
This includes metrics that aren't ranked.
You can plot, compare and also see diet, sleep and exercises here too.
You will also need to log exercise sets here for context for the next part.

HABITS
Helping you stay accountable too, are the habits section.
It is here to build a daily/weekly checklist. 
Auto-verified habits tick themselves from your real data.
But there are some manual habits you tick yourself. 
habits are pushed to your Google Calendar
With also reminders + an AI nudge keep you accountable.

COACH
To aid you even further, is an AI to iterate on your data and habits.
It continuously takes initiative to improve your habits for your quest.
Your AI coach sees your ranks, full history, trends, correlations, workout sets and habits. 
Ask anything, and it can propose habit changes you apply in one tap.
It will also allow context to be saved and pinned for specialisation.

SYNC
This step 1 connected your account and your smart watch data. 
Sign in with Google to back up everything and make sure to pull your Google Health / Fitbit data.
Your data stays local-first; sync just keeps your devices in step. Reconnect here if Google asks.
Exercise, diet and sleep data, and a lot of recovery data automatically and exclusively comes from google health.

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
              child: const Text('Never give up',
                  style: TextStyle(fontSize: 11, color: _muted)),
            ),
          ]),
        ),
      ),
    );
  }
}
