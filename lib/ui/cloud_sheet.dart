// ui/cloud_sheet.dart — in-app cloud controls. Sign in with Google (which also
// links your Google Health), then sync — all buttons, no terminal. Opened from
// the app-bar ☁ icon.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/api_client.dart';
import '../data/sync.dart';

const _accent = Color(0xFF5B6AF8);
const _teal = Color(0xFF4CE0C3);
const _bg = Color(0xFF12152E);

void openCloudSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _CloudSheet(),
  );
}

class _CloudSheet extends ConsumerStatefulWidget {
  const _CloudSheet();
  @override
  ConsumerState<_CloudSheet> createState() => _CloudSheetState();
}

class _CloudSheetState extends ConsumerState<_CloudSheet> {
  bool _loading = true, _signedIn = false, _busy = false, _needsReconnect = false;
  bool? _calendarConnected; // null until status is known
  String? _email, _msg;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      await api.loadPersistedToken();
      // Signed-in == the backend confirms our identity. If a stored token can't be
      // confirmed (e.g. we switched to the hosted server), just prompt sign-in.
      final email = api.isSignedIn ? await api.whoAmI() : null;
      // Diagnose the stored health token: missing health scopes, or POISONED
      // (it carries calendar.events, which makes the Health API 403 everything —
      // a health-only reconnect fixes it). Also whether Calendar is linked.
      var missingScopes = false, poisoned = false;
      bool? calendarConnected;
      if (email != null) {
        final gs = await api.googleStatus();
        missingScopes = ((gs['missing_scopes'] as List?) ?? const []).isNotEmpty;
        poisoned = gs['health_token_poisoned'] == true;
        calendarConnected = gs['calendar_connected'] as bool?;
      }
      if (mounted) {
        setState(() {
          _signedIn = email != null;
          _email = email;
          _calendarConnected = calendarConnected;
          _loading = false;
          if (poisoned) {
            _needsReconnect = true;
            _msg = 'Google Health rejected the old permission (it bundled Calendar) — '
                'tap Reconnect to grant a fresh health-only permission.';
          } else if (missingScopes) {
            _needsReconnect = true;
            _msg = 'Google needs new permissions — reconnect below.';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _msg = "Couldn't reach the backend."; });
    }
  }

  // Short friendly names for the app's Google scopes (for the "not granted" message).
  static String _scopeName(String s) {
    if (s.contains('calendar')) return 'Calendar';
    if (s.contains('nutrition')) return 'Nutrition';
    if (s.contains('sleep')) return 'Sleep';
    if (s.contains('activity')) return 'Activity';
    if (s.contains('health_metrics')) return 'Health metrics';
    if (s.contains('googlehealth.profile')) return 'Health profile';
    return s.split('/').last;
  }

  Future<void> _signIn() async {
    final api = ref.read(apiClientProvider);
    setState(() { _busy = true; _msg = null; });
    try {
      final url = await api.googleSignInUrl();
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {/* fall back to the copyable link in the dialog */}
      if (!mounted) return;
      final code = await _askForCode(url);
      if (code != null && code.isNotEmpty) {
        final email = await api.googleSignInComplete(code);
        // Google can "succeed" while silently dropping scopes (unticked consent
        // checkboxes; restricted health scopes when the OAuth consent screen isn't
        // in Testing mode). Say exactly what was NOT granted — otherwise the only
        // symptom is 403 on every sync and reconnecting looks broken.
        final missing = api.lastSignInMissingScopes;
        bool? calendarConnected;
        try {
          calendarConnected =
              (await api.googleStatus())['calendar_connected'] as bool?;
        } catch (_) {/* status is a nice-to-have here */}
        if (mounted) {
          setState(() {
            _signedIn = true;
            _email = email;
            _calendarConnected = calendarConnected;
            _needsReconnect = missing.isNotEmpty;
            _msg = missing.isEmpty
                ? 'Signed in ✓ — health access granted'
                    '${calendarConnected == false ? '. Connect Google Calendar below to auto-add habits.' : ''}'
                : 'Signed in, but Google did NOT grant: '
                  '${missing.map(_scopeName).join(', ')}.\n'
                  'Reconnect and TICK EVERY CHECKBOX on Google\'s consent page. '
                  'If they were ticked, check in Google Cloud Console that the '
                  'OAuth consent screen is in Testing mode, your email is under '
                  'Test users, and the Google Health API is enabled.';
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _msg = 'Sign-in failed: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't start sign-in.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Fetch the raw Google Health data and show it copyable — so the exact field
  // shapes can be pasted to the developer to wire the remaining auto-metrics.
  Future<void> _inspect() async {
    setState(() => _busy = true);
    final api = ref.read(apiClientProvider);
    try {
      final raw = await api.googleDebug();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bg,
          title: const Text('Google data', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(raw,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white70, height: 1.3)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: raw));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Copied — paste it to Claude'), duration: Duration(seconds: 2)));
              },
              child: const Text('Copy'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't fetch Google data.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(apiClientProvider).signOut();
    if (mounted) setState(() { _signedIn = false; _email = null; _msg = 'Signed out'; });
  }

  // The separate Calendar grant (auto-add habits). Health and Calendar can't share
  // a token — the Health API rejects tokens carrying calendar.events — so this is
  // its own consent, same code-paste flow as sign-in.
  Future<void> _connectCalendar() async {
    final api = ref.read(apiClientProvider);
    setState(() { _busy = true; _msg = null; });
    try {
      final url = await api.googleCalendarAuthorizeUrl();
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {/* fall back to the copyable link in the dialog */}
      if (!mounted) return;
      final code = await _askForCode(url);
      if (code != null && code.isNotEmpty) {
        await api.googleCalendarExchange(code);
        if (mounted) {
          setState(() {
            _calendarConnected = true;
            _msg = 'Google Calendar connected ✓ — habits will auto-add from now on.';
          });
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _msg = 'Calendar connect failed: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't start the calendar connect.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final r = await cloudSync(ref);
      if (mounted) {
        setState(() {
          _needsReconnect = r.needsReconnect;
          if (r.calendarNeedsReconnect) _calendarConnected = false;
          final base = r.pulled > 0
              ? 'Pulled ${r.pulled} new readings · ${r.note}'
              : 'Up to date · ${r.note}';
          _msg = r.calendarNeedsReconnect
              ? '$base\nConnect Google Calendar below to auto-add habits.'
              : base;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't reach the backend.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12152E),
        title: const Text('Restore from cloud?'),
        content: const Text('This replaces ALL data on this device with your last cloud '
            'backup (logs, food, workouts, habits…). Use it on a new device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _msg = null; });
    try {
      final restored = await restoreFromCloud(ref);
      if (mounted) setState(() => _msg = restored ? 'Restored from cloud ✓' : 'No cloud backup found yet');
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't restore — check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Rebuild the rank + readiness history purely from the data that exists now —
  // deleting logs used to leave the old category-rank climb behind.
  Future<void> _recomputeHistory() async {
    setState(() { _busy = true; _msg = null; });
    final n = recomputeDerivedHistory(ref);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = 'Rank & readiness history rebuilt from current data ($n day-points).';
      });
    }
  }

  // Wipe the CLOUD copy of the samples (server store) — the fix for deleted data
  // living on in the server-side ranks/coach fallback. Local data stays.
  Future<void> _resetCloud() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        title: const Text('Delete cloud data?'),
        content: const Text('This deletes ALL samples stored in the cloud for your account '
            '(manual + Google-synced). Data on this device stays; the next "Sync now" '
            're-uploads your current local logs so the cloud matches what you see.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFA3737)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _busy = true; _msg = null; });
    try {
      final n = await ref.read(apiClientProvider).deleteCloudSamples();
      // Push the current local truth straight back up so cloud == device.
      final synced = await syncNow(ref);
      if (mounted) {
        setState(() =>
            _msg = 'Cloud reset: $n samples deleted, ${synced.ingested} re-uploaded from this device.');
      }
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't reset the cloud data — check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForCode(String url) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        title: const Text('Sign in with Google'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Approve in the page that just opened (if it didn’t, copy this link):',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(url, style: const TextStyle(fontSize: 11, color: _teal)),
            const SizedBox(height: 12),
            const Text('2. It lands on a google.com page — paste that whole address (or just the code) here:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(controller: ctrl, autofocus: true,
                decoration: const InputDecoration(hintText: 'paste here', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, _extractCode(ctrl.text)), child: const Text('Sign in')),
        ],
      ),
    );
  }

  // Accept either a pasted code or the full redirect URL (?code=...).
  String _extractCode(String input) {
    final t = input.trim();
    return Uri.tryParse(t)?.queryParameters['code'] ?? t;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Cloud Sync', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Sign in with Google to pull your Fitbit / Google Health data into your ranks. '
              'Your Google account is your account and your data source.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (!_signedIn) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(46)),
            ),
          ] else ...[
            Row(children: [
              const Icon(Icons.check_circle, color: _teal, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_email == null ? 'Signed in' : 'Signed in as $_email',
                  style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 16),
            if (_needsReconnect) ...[
              // Google's 7-day testing token expired — one tap refreshes it.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF3A2E12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Color(0xFFE0B44C), size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Google sign-in expired — tap to reconnect Health.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFE0B44C)))),
                ]),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect Google Health'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0B44C),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(46)),
              ),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _sync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
                style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(46)),
              ),
            if (_calendarConnected == false) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _connectCalendar,
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Connect Google Calendar (auto-add habits)'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _accent, minimumSize: const Size.fromHeight(46)),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('Restore all data from cloud'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _teal, minimumSize: const Size.fromHeight(46)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _recomputeHistory,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Rebuild rank history', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _resetCloud,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Reset cloud data', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFA3737)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton.icon(
                onPressed: _busy ? null : _inspect,
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: const Text('Inspect Google data'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
              TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
            ]),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
          if (_msg != null)
            Padding(padding: const EdgeInsets.only(top: 16),
                child: Text(_msg!, style: const TextStyle(color: _teal, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
