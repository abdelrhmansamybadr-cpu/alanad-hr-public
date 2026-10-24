import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';

/// Printable Arabic letters (employment, salary, experience). The server makes a signed 10-minute link; it opens in the browser.
void showLettersSheet(BuildContext context) => showAppSheet(context, title: context.t('ar.letters'), child: const _LettersSheet());

class _LettersSheet extends ConsumerStatefulWidget {
  const _LettersSheet();
  @override
  ConsumerState<_LettersSheet> createState() => _LettersSheetState();
}

class _LettersSheetState extends ConsumerState<_LettersSheet> {
  bool _arDigits = false;
  String? _busy;

  Future<void> _open(String type) async {
    setState(() => _busy = type);
    try {
      final r = asMap(await ref.read(apiProvider).get('/arabic/letter-link', query: {'type': type, if (_arDigits) 'digits': 'ar'}));
      final ok = await launchUrl(Uri.parse(jStr(r, 'url')), mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, context.t('ar.cannot_open'), error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('ar.letters_hint'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
        const SizedBox(height: 12),
        for (final t in const [('employment', Icons.badge_rounded), ('salary', Icons.payments_rounded), ('experience', Icons.workspace_premium_rounded)])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RowTile(
              leading: IconBadge(t.$2, color: context.scheme.primary, size: 42),
              title: context.t('ar.letter_${t.$1}'),
              trailing: _busy == t.$1 ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.open_in_new_rounded, size: 20),
              onTap: _busy == null ? () => _open(t.$1) : null,
            ),
          ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('ar.arabic_digits')), subtitle: const Text('١٢٣٤٥٦'), value: _arDigits, onChanged: (v) => setState(() => _arDigits = v)),
      ]);
}

// ------------------------------------------------------------------------------------------ voice

/// Where a spoken screen name goes, for this kind of account.
String? routeForVoiceTarget(String target, {required bool isHr}) {
  const both = {
    'meetings': '/meetings', 'payslips': '/payslips', 'rewards': '/rewards', 'announcements': '/announcements', 'holidays': '/holidays',
    'documents': '/documents', 'career': '/career-path', 'decisions': '/decisions', 'field': '/field', 'coach': '/coach', 'team': '/team',
  };
  if (both.containsKey(target)) return both[target];
  switch (target) {
    case 'attendance':
      return isHr ? '/h/attendance' : '/e/time';
    case 'requests':
      return isHr ? '/h/approvals' : '/e/requests';
    case 'approvals':
      return isHr ? '/h/approvals' : '/approvals';
    case 'inbox':
      return isHr ? '/inbox' : '/e/inbox';
    case 'people':
      return isHr ? '/h/people' : '/directory';
    case 'payroll':
      return isHr ? '/h/payroll' : '/payslips';
    case 'home':
      return isHr ? '/h/home' : '/e/home';
  }
  return null;
}

/// "Talk to the app" in Arabic. The phone turns speech into text; the server understands the sentence. Nothing is
/// changed by voice alone: check-in / check-out only open the attendance screen after a tap.
void showVoiceSheet(BuildContext context) => showAppSheet(context, title: context.t('ar.voice'), child: const _VoiceSheet());

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();
  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet> {
  final _stt = SpeechToText();
  bool _ready = false;
  bool _listening = false;
  String _heard = '';
  Map<String, dynamic>? _reply;
  String? _problem;
  bool _asking = false;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final noArabic = context.t('ar.no_arabic_voice');
    final noMic = context.t('ar.no_mic');
    try {
      _ready = await _stt.initialize(onError: (e) { if (mounted) setState(() { _listening = false; _problem = e.errorMsg; }); }, onStatus: (s) { if (s == 'done' || s == 'notListening') { if (mounted) setState(() => _listening = false); } });
      if (_ready) {
        final locales = await _stt.locales();
        final ids = locales.map((l) => l.localeId).toList();
        _locale = ids.firstWhere((i) => i == 'ar_EG', orElse: () => ids.firstWhere((i) => i.startsWith('ar'), orElse: () => ''));
        if (_locale!.isEmpty) _problem = noArabic;
      } else {
        _problem = noMic;
      }
    } catch (_) {
      _problem = noMic;
    }
    if (mounted) setState(() {});
  }

  Future<void> _listen() async {
    if (!_ready || (_locale ?? '').isEmpty) return;
    setState(() { _heard = ''; _reply = null; _listening = true; _problem = null; });
    await _stt.listen(
      listenOptions: SpeechListenOptions(localeId: _locale, listenFor: const Duration(seconds: 12), pauseFor: const Duration(seconds: 3)),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) _ask(r.recognizedWords);
      },
    );
  }

  Future<void> _ask(String text) async {
    if (_asking) return;
    setState(() { _asking = true; _listening = false; });
    try {
      final r = asMap(await ref.read(apiProvider).post('/arabic/voice', {'text': text}));
      if (mounted) setState(() => _reply = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  void _go(String route) {
    Navigator.pop(context);
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final isHr = (ref.watch(sessionProvider).user?.role ?? 'employee') != 'employee';
    final r = _reply;
    final target = r == null ? null : jStrN(r, 'target');
    final route = target == null ? null : routeForVoiceTarget(target, isHr: isHr);
    final intent = r == null ? '' : jStr(r, 'intent');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.t('ar.voice_hint'), style: TextStyle(color: context.colors.subtext, height: 1.45)),
      const SizedBox(height: 16),
      Center(
        child: GestureDetector(
          onTap: _listening ? () => _stt.stop() : _listen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _listening ? 96 : 84,
            height: _listening ? 96 : 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _listening ? context.colors.danger : context.scheme.primary, boxShadow: [BoxShadow(color: (_listening ? context.colors.danger : context.scheme.primary).withValues(alpha: 0.35), blurRadius: _listening ? 26 : 12)]),
            child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 40),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(child: Text(_listening ? context.t('ar.listening') : (_asking ? context.t('ar.thinking') : context.t('ar.tap_to_speak')), style: TextStyle(color: context.colors.subtext))),
      if (_heard.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppCard(color: context.colors.surfaceAlt, child: Text('“$_heard”', textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 17, height: 1.5))),
      ],
      if (_problem != null) ...[const SizedBox(height: 12), Text(_problem!, style: TextStyle(color: context.colors.danger, height: 1.4))],
      if (r != null) ...[
        const SizedBox(height: 14),
        AppCard(
          color: context.colors.brandSoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(jStr(r, 'answer'), textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 16.5, height: 1.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 10),
        if (r['confirm'] == true) FilledButton.icon(onPressed: () => _go(isHr ? '/h/attendance' : '/e/time'), icon: const Icon(Icons.check_rounded), label: Text(context.t(intent == 'check_in' ? 'ar.confirm_in' : 'ar.confirm_out'))),
        if (route != null) FilledButton.icon(onPressed: () => _go(route), icon: const Icon(Icons.open_in_new_rounded), label: Text(context.t('ar.open_screen'))),
        for (final a in asMapList(r['actions']))
          if (jStrN(a, 'route') != null) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: () => _go(jStr(a, 'route')), child: Text(jStr(a, 'label')))),
        const SizedBox(height: 4),
        Text(context.t('ar.voice_safe'), style: TextStyle(color: context.colors.subtext, fontSize: 12, height: 1.4)),
      ],
      const SizedBox(height: 10),
      Text(context.t('ar.examples'), style: TextStyle(color: context.colors.subtext, fontSize: 12.5, height: 1.5)),
    ]);
  }
}
