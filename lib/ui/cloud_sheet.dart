// ui/cloud_sheet.dart — in-app cloud controls so connecting Google Health and
// syncing are buttons, not terminal curls. Opened from the app-bar ☁ icon.
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
  bool _loading = true, _connected = false, _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    try {
      if (!api.isSignedIn) await api.devSignIn();
      final c = await api.googleConnected();
      if (mounted) setState(() { _connected = c; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _msg = "Couldn't reach the backend."; });
    }
  }

  Future<void> _connect() async {
    final api = ref.read(apiClientProvider);
    setState(() { _busy = true; _msg = null; });
    try {
      if (!api.isSignedIn) await api.devSignIn();
      final url = await api.googleAuthorizeUrl();
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {/* fall back to the copyable link in the dialog */}
      if (!mounted) return;
      final code = await _askForCode(url);
      if (code != null && code.isNotEmpty) {
        await api.googleExchange(code);
        await _refresh();
        if (mounted) setState(() => _msg = 'Connected to Google Health ✓');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _msg = 'Connect failed: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't start the connection.");
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
        title: const Text('Connect Google Health'),
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
          FilledButton(onPressed: () => Navigator.pop(ctx, _extractCode(ctrl.text)), child: const Text('Connect')),
        ],
      ),
    );
  }

  // Accept either a pasted code or the full redirect URL (?code=...).
  String _extractCode(String input) {
    final t = input.trim();
    final code = Uri.tryParse(t)?.queryParameters['code'];
    return code ?? t;
  }

  Future<void> _sync() async {
    setState(() { _busy = true; _msg = null; });
    try {
      final r = await cloudSync(ref);
      if (mounted) {
        setState(() => _msg = r.pulled > 0
            ? 'Pulled ${r.pulled} new readings · ${r.note}'
            : 'Up to date · ${r.note}');
      }
    } catch (_) {
      if (mounted) setState(() => _msg = "Couldn't reach the backend.");
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
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
          const Text('Connect Google Health (Fitbit) to pull your wearable data into your ranks.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else ...[
            Row(children: [
              Icon(_connected ? Icons.check_circle : Icons.cloud_off,
                  color: _connected ? _teal : Colors.grey, size: 20),
              const SizedBox(width: 8),
              Text(_connected ? 'Google Health connected' : 'Not connected',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : (_connected ? _sync : _connect),
              icon: Icon(_connected ? Icons.sync : Icons.link),
              label: Text(_connected ? 'Sync now' : 'Connect Google Health'),
              style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(46)),
            ),
            if (_connected) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : _connect, child: const Text('Reconnect')),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
            if (_msg != null)
              Padding(padding: const EdgeInsets.only(top: 16),
                  child: Text(_msg!, style: const TextStyle(color: _teal, fontWeight: FontWeight.w600))),
          ],
        ]),
      ),
    );
  }
}
