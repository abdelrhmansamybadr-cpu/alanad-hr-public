import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/session/session.dart';
import '../premium/arabic_tools.dart';

class _Msg {
  final bool mine;
  final String text;
  final List<({String label, String route})> actions;
  const _Msg(this.mine, this.text, [this.actions = const []]);
}

/// "Ask Al Anad HR": type a question, get an answer worked out from your own records.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  List<String> _suggestions = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final d = await ref.read(apiProvider).get('/assistant/suggestions');
      if (mounted && d is List) setState(() => _suggestions = d.map((e) => '$e').toList());
    } on ApiException {/* chips are optional */}
  }

  Future<void> _ask(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg(true, q));
      _busy = true;
    });
    _toEnd();
    try {
      final m = asMap(await ref.read(apiProvider).post('/assistant', {'question': q}));
      final acts = [for (final a in asMapList(m['actions'])) (label: jStr(a, 'label'), route: jStr(a, 'route'))];
      final sug = m['suggestions'];
      if (mounted) {
        setState(() {
          _msgs.add(_Msg(false, jStr(m, 'answer'), acts));
          if (sug is List) _suggestions = sug.map((e) => '$e').toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _msgs.add(_Msg(false, e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void _open(String route) {
    if (route.startsWith('/e/') || route.startsWith('/h/') && route.split('/').length == 3 && const ['/h/people', '/h/attendance', '/h/approvals', '/h/more'].contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('assistant.title')), actions: [
        if (ref.watch(sessionProvider).company?.hasFeature('arabicPack') ?? false) IconButton(tooltip: context.t('ar.voice'), icon: const Icon(Icons.mic_rounded), onPressed: () => showVoiceSheet(context)),
      ]),
      body: Column(children: [
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), children: [
            _Bubble(mine: false, child: Text(context.t('assistant.hello'), style: const TextStyle(height: 1.4))),
            for (final m in _msgs)
              _Bubble(
                mine: m.mine,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.text, style: TextStyle(height: 1.4, color: m.mine ? Colors.white : null)),
                  if (m.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [for (final a in m.actions) ActionChip(label: Text(a.label), avatar: const Icon(Icons.arrow_outward_rounded, size: 16), onPressed: () => _open(a.route))]),
                  ],
                ]),
              ),
            if (_busy) const _Bubble(mine: false, child: SizedBox(width: 28, height: 14, child: LinearProgressIndicator(minHeight: 3))),
          ]),
        ),
        if (_suggestions.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final s in _suggestions) Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: ActionChip(label: Text(s), onPressed: () => _ask(s))),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  maxLength: 300,
                  decoration: InputDecoration(hintText: context.t('assistant.hint'), counterText: '', prefixIcon: const Icon(Icons.auto_awesome_rounded)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _busy ? null : () => _ask(_input.text), icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final Widget child;
  const _Bubble({required this.mine, required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: mine ? context.scheme.primary : context.colors.surfaceAlt,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: child,
        ),
      );
}
