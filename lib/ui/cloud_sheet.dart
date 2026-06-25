// ui/cloud_sheet.dart — in-app cloud controls. Sign in with Google (which also
// links your Google Health), then sync — all buttons, no terminal. Opened from
// the app-bar ☁ icon.
import 'package:flutter/material.dart';
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
      if (mounted) setState(() { _signedIn = email != null; _email = email; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _msg = "Couldn't reach the backend."; });
    }
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
        // A successful sign-in also refreshes the Google Health token.
        if (mounted) {
          setState(() {
          _signedIn = true; _email = email; _needsReconnect = false; _msg = 'Signed in ✓';
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

  Future<void> _signOut() async {
    await ref.read(apiClientProvider).signOut();
    if (mounted) setState(() { _signedIn = false; _email = null; _msg = 'Signed out'; });
  }

  Future<void> _sync() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final r = await cloudSync(ref);
      if (mounted) {
        setState(() {
          _needsReconnect = r.needsReconnect;
          _msg = r.pulled > 0
              ? 'Pulled ${r.pulled} new readings · ${r.note}'
              : 'Up to date · ${r.note}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't reach the backend.");
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
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _signOut, child: const Text('Sign out')),
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
