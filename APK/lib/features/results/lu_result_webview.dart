import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_colors.dart';
import '../../core/worker_api.dart';
import 'result_import.dart';

/// Leading University's own result page, opened inside the app.
///
/// LU retired the JSON endpoint the portal used to call; results now come only
/// from this form, which sits behind a Cloudflare Turnstile check. We do not
/// touch that check — the student ticks it, exactly as they would in a browser.
/// All this screen saves them is the select-all / copy / paste dance: the two
/// fields the app already knows are filled in, and once LU renders the result
/// the page is read straight out of the DOM and imported.
///
/// Pops `true` when a result was imported.
class LuResultWebView extends StatefulWidget {
  final String studentId;
  final String birthDate; // YYYY-MM-DD — the format LU's field asks for.

  const LuResultWebView({
    super.key,
    required this.studentId,
    required this.birthDate,
  });

  @override
  State<LuResultWebView> createState() => _LuResultWebViewState();
}

class _LuResultWebViewState extends State<LuResultWebView> {
  static const _url = 'https://lus.ac.bd/result/';

  late final WebViewController _controller;
  bool _loading = true;
  bool _importing = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('LuBridge', onMessageReceived: _onPageHtml)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            await _injectHelpers();
          },
          onWebResourceError: (e) {
            if (!mounted || e.isForMainFrame != true) return;
            setState(() => _error = 'Could not open the LU page (${e.description}).');
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  /// Fill in what we already know and start watching for the result tables.
  /// Re-running this is harmless; the watcher guards against duplicates.
  Future<void> _injectHelpers() async {
    final id = jsonEncode(widget.studentId);
    final dob = jsonEncode(widget.birthDate);
    try {
      await _controller.runJavaScript('''
(function () {
  function fill(sel, value) {
    var el = document.querySelector(sel);
    if (!el || el.value) return;
    el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  fill('#student_id', $id);
  fill('#birth_date', $dob);

  if (window.__luPortalWatch) return;
  window.__luPortalWatch = true;

  // Submit for the student once Cloudflare's widget has issued its token. The
  // token is produced by Turnstile itself - we never solve or fake it, we only
  // save a tap once it is already there.
  var submitted = false;
  var submitTimer = setInterval(function () {
    if (submitted || document.querySelector('table.result-table')) {
      clearInterval(submitTimer);
      return;
    }
    var token = document.querySelector('[name="cf-turnstile-response"]');
    var form = document.getElementById('lu-results-form');
    var id = document.querySelector('#student_id');
    var dob = document.querySelector('#birth_date');
    if (!token || !token.value || !form || !id || !id.value || !dob || !dob.value) return;
    submitted = true;
    clearInterval(submitTimer);
    var button = form.querySelector('button[type="submit"]');
    if (button) button.click(); else form.submit();
  }, 600);

  var ticks = 0;
  var timer = setInterval(function () {
    ticks++;
    if (document.querySelector('table.result-table')) {
      clearInterval(timer);
      var body = document.body.cloneNode(true);
      body.querySelectorAll('script,style,noscript,iframe,svg').forEach(function (n) {
        n.remove();
      });
      LuBridge.postMessage(body.innerHTML);
    } else if (ticks > 600) {
      clearInterval(timer);   // give up quietly after ~5 minutes
    }
  }, 500);
})();
''');
    } catch (_) {
      // A navigation can tear the page down mid-injection; the next
      // onPageFinished re-runs this.
    }
  }

  Future<void> _onPageHtml(JavaScriptMessage message) async {
    if (_importing || _done) return;
    setState(() {
      _importing = true;
      _error = null;
    });

    final parsed = importParse(message.message);
    if (parsed['success'] != true) {
      setState(() {
        _importing = false;
        _error = 'Your result is on screen but could not be read. '
            'Scroll through it once, or use the manual paste option.';
      });
      return;
    }

    final saved = await WorkerApi.instance.resultImport(
      widget.studentId,
      widget.birthDate,
      parsed,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _importing = false;
        _error = 'Read your result, but saving it failed. Check your connection '
            'and tap View Result again.';
      });
      return;
    }
    setState(() {
      _importing = false;
      _done = true;
    });
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Get result from LU'),
        backgroundColor: AppColors.bg,
      ),
      body: Column(
        children: [
          _banner(),
          if (_loading || _importing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }

  Widget _banner() {
    final problem = _error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: problem != null
          ? AppColors.red.withValues(alpha: 0.10)
          : AppColors.accent.withValues(alpha: 0.10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            problem != null
                ? Icons.error_outline_rounded
                : Icons.verified_user_outlined,
            size: 18,
            color: problem != null ? AppColors.red : AppColors.accentBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              problem ??
                  (_importing
                      ? 'Reading your result…'
                      : 'Everything is filled in for you. If Cloudflare shows a '
                            '"Verify you are human" box, tick it — the result is '
                            'then fetched and saved automatically.'),
              style: TextStyle(
                color: problem != null ? AppColors.red : AppColors.text,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
