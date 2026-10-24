import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import 'onboarding.dart';

/// Sits above the whole app. While the employee is off doing an onboarding step (uploading a document, checking in,
/// looking at their team...) it asks the server every few seconds whether the step REALLY happened. The moment the
/// server has ticked it (the system ticks it, never the employee) the employee is brought back to "Getting started".
class ObFlowWatcher extends ConsumerStatefulWidget {
  final Widget child;
  const ObFlowWatcher({super.key, required this.child});

  @override
  ConsumerState<ObFlowWatcher> createState() => _ObFlowWatcherState();
}

class _ObFlowWatcherState extends ConsumerState<ObFlowWatcher> {
  Timer? _timer;
  DateTime _since = DateTime.now();
  bool _teamSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start(String? key) {
    _timer?.cancel();
    if (key == null) return;
    _since = DateTime.now();
    _teamSent = false;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick(key));
  }

  Future<void> _tick(String key) async {
    if (_busy || !mounted) return;
    final elapsed = DateTime.now().difference(_since);
    if (elapsed > const Duration(minutes: 15)) {
      ref.read(obFlowProvider.notifier).state = null;
      return;
    }
    _busy = true;
    try {
      final api = ref.read(apiProvider);
      // "meet your team" = the team page stayed open for a few seconds
      if (key == 'team' && !_teamSent && elapsed >= const Duration(seconds: 5)) {
        _teamSent = true;
        await api.post('/onboarding/event', {'key': 'team'});
      }
      final v = ObView.fromJson(await api.get('/onboarding/me'));
      final t = v.tasks.where((x) => x.autoKey == key).toList();
      if (t.isNotEmpty && t.first.done && mounted && ref.read(obFlowProvider) == key) {
        ref.read(obFlowProvider.notifier).state = null;
        ref.invalidate(onboardingProvider(0));
        final router = ref.read(routerProvider);
        router.go('/e/home');
        router.push('/onboarding');
        Future.delayed(const Duration(milliseconds: 500), () {
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted) toast(ctx, ctx.t('ob.flow_done'));
        });
      }
    } on ApiException {
      // offline for a moment: try again on the next tick
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(obFlowProvider, (_, key) => _start(key));
    return widget.child;
  }
}

/// Contract / personal details / policies: the employee reads, then confirms. The confirmation is recorded by the
/// server as an event, and the server (not the employee) ticks the step.
class ObStepScreen extends ConsumerStatefulWidget {
  final String stepKey; // contract | details | policies
  const ObStepScreen({super.key, required this.stepKey});

  @override
  ConsumerState<ObStepScreen> createState() => _ObStepScreenState();
}

class _ObStepScreenState extends ConsumerState<ObStepScreen> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/onboarding/event', {'key': widget.stepKey});
      ref.invalidate(onboardingProvider(0));
      if (!mounted) return;
      final nav = Navigator.of(context);
      final msg = context.t('ob.flow_done');
      toast(context, msg);
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.stepKey;
    final user = ref.watch(sessionProvider).user;
    final title = context.t('ob.${k}_title');
    final body = context.t('ob.${k}_body');
    final agree = switch (k) {
      'details' => context.t('ob.details_ok'),
      'policies' => context.t('ob.policies_agree'),
      _ => context.t('ob.agree'),
    };
    final icon = switch (k) {
      'details' => Icons.badge_outlined,
      'policies' => Icons.policy_outlined,
      _ => Icons.description_outlined,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: context.scheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            ]),
            const SizedBox(height: 12),
            Text(body, style: TextStyle(color: context.colors.subtext, height: 1.5)),
            if (k == 'details' && user != null) ...[
              const SizedBox(height: 14),
              _line(context, Icons.person_outline_rounded, user.name),
              _line(context, Icons.mail_outline_rounded, user.email),
              if ((user.phone ?? '').isNotEmpty) _line(context, Icons.phone_outlined, user.phone!),
              if ((user.title ?? '').isNotEmpty) _line(context, Icons.work_outline_rounded, user.title!),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        LoadingButton(label: agree, loading: _busy, onPressed: _confirm),
        if (k == 'details') ...[
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.push('/e/requests'), child: Text(context.t('ob.details_wrong'))),
        ],
      ]),
    );
  }

  Widget _line(BuildContext context, IconData i, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Icon(i, size: 18, color: context.colors.subtext), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)))]),
      );
}
