import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/config.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

/// Which ways of sending work on this server: e-mail (SMTP or the host's basic mail) and SMS (only with a provider).
final messagingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/company/messaging')));

final inviteStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => asMap(await ref.read(apiProvider).get('/employees/invite-status')));

/// What is still missing on an employee's record, in words.
String missingLabel(BuildContext c, String key) => c.t('miss.${key == 'startDate' ? 'start_date' : key}');

String missingText(BuildContext c, List<String> keys) => keys.map((k) => missingLabel(c, k)).join(c.isAr ? '، ' : ', ');

/// Invite one person. Nothing is sent until the button is pressed; [result] is the answer of the server when the invitation was
/// already created together with the employee (the sheet then goes straight to the result).
Future<void> showInviteSheet(BuildContext context, WidgetRef ref, Employee e, {Map<String, dynamic>? result}) async {
  var via = e.hasEmail ? 'email' : (e.hasPhone ? 'sms' : 'none');
  var busy = false;
  Map<String, dynamic>? res = result;
  var requested = result == null ? '' : jStr(result, 'channel');
  final msg = ref.read(messagingProvider).valueOrNull;
  final smsOff = msg != null && asMap(msg['sms'])['configured'] != true;
  final mailBasic = msg != null && asMap(msg['email'])['smtp'] != true;

  await showAppSheet<void>(
    context,
    title: e.hasAccount ? context.t('invite.reset_title') : context.t('invite.title'),
    child: StatefulBuilder(builder: (ctx, set) {
      Widget option(String id, IconData icon, String title, String sub, {bool disabled = false}) => Opacity(
            opacity: disabled ? 0.5 : 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: disabled ? null : () => set(() => via = id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: via == id ? ctx.scheme.primary : ctx.colors.border, width: via == id ? 2 : 1), borderRadius: BorderRadius.circular(14), color: via == id ? ctx.scheme.primary.withValues(alpha: 0.06) : null),
                child: Row(children: [
                  Icon(via == id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: via == id ? ctx.scheme.primary : ctx.colors.subtext),
                  const SizedBox(width: 10),
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(sub, style: TextStyle(color: ctx.colors.subtext, fontSize: 12.5, height: 1.3))])),
                ]),
              ),
            ),
          );

      if (res != null) {
        final r = res!;
        final sent = r['sent'];
        final code = jStr(r, 'code');
        final ch = jStr(r, 'channel');
        final text = ctx.t('invite.message', {'name': e.firstName, 'email': jStr(r, 'username'), 'code': code, 'link': '${AppConfig.baseUrl}/app/alanad/AlAnad-HR.apk'});
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (requested != 'none' && ch.isNotEmpty)
            Pill(sent == true ? (ch == 'sms' ? ctx.t('invite.sms_sent', {'to': jStr(r, 'phone')}) : ctx.t('invite.emailed', {'email': jStr(r, 'email')})) : '${ctx.t('invite.not_sent')}: ${jStr(r, 'error')}',
                color: sent == true ? ctx.colors.success : ctx.colors.warning, icon: sent == true ? Icons.mark_email_read_outlined : Icons.warning_amber_rounded),
          const SizedBox(height: 14),
          Text('${ctx.t('invite.username')}: ${jStr(r, 'username')}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(color: ctx.colors.brandSoft, borderRadius: BorderRadius.circular(20)),
            child: Center(child: Text(code.split('').join(' '), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4, color: ctx.scheme.primary))),
          ),
          const SizedBox(height: 10),
          Center(child: Text(ctx.t('invite.once', {'n': jInt(r, 'expiresInDays', 7)}), style: TextStyle(color: ctx.colors.subtext, fontSize: 12))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: code)); toast(ctx, ctx.t('common.copied')); }, icon: const Icon(Icons.copy_rounded), label: Text(ctx.t('common.copy')))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(onPressed: () => Share.share(text), icon: const Icon(Icons.share_rounded), label: Text(ctx.t('common.share')))),
          ]),
        ]);
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(e.hasAccount ? ctx.t('invite.reset_hint', {'name': e.firstName}) : ctx.t('invite.hint2', {'name': e.firstName}), style: TextStyle(color: ctx.colors.subtext, height: 1.4)),
        const SizedBox(height: 14),
        option('email', Icons.mail_outline_rounded, ctx.t('invite.by_email'), e.hasEmail ? e.email : ctx.t('invite.no_email'), disabled: !e.hasEmail),
        option('sms', Icons.sms_outlined, ctx.t('invite.by_sms'), e.hasPhone ? '${e.phone}${smsOff ? ' — ${ctx.t('invite.sms_off')}' : ''}' : ctx.t('invite.no_phone'), disabled: !e.hasPhone || smsOff),
        option('none', Icons.vpn_key_outlined, ctx.t('invite.no_send'), ctx.t('invite.no_send_hint')),
        if (mailBasic && via == 'email') Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(ctx.t('invite.mail_basic'), style: TextStyle(color: ctx.colors.warning, fontSize: 12, height: 1.4))),
        const SizedBox(height: 10),
        LoadingButton(
          label: via == 'none' ? ctx.t('invite.make_code') : ctx.t('invite.send_now'),
          icon: Icons.send_rounded,
          loading: busy,
          onPressed: () async {
            set(() => busy = true);
            try {
              final r = asMap(await ref.read(apiProvider).post('/employees/${e.id}/invite', {'sendVia': via}));
              ref.invalidate(employeesProvider);
              set(() {
                res = r;
                requested = via;
                busy = false;
              });
            } on ApiException catch (err) {
              if (ctx.mounted) toast(ctx, err.message, error: true);
              set(() => busy = false);
            }
          },
        ),
      ]);
    }),
  );
}

/// "Send everyone their invitation": shows what would happen, and sends only after the person confirms.
Future<void> showInviteAllSheet(BuildContext context, WidgetRef ref) async {
  var via = 'auto';
  var again = false;
  var sure = false;
  var busy = false;
  Map<String, dynamic>? res;
  ref.invalidate(inviteStatusProvider);

  await showAppSheet<void>(
    context,
    title: context.t('invite.all_title'),
    child: Consumer(builder: (ctx, r, _) {
      final status = r.watch(inviteStatusProvider);
      return StatefulBuilder(builder: (ctx, set) {
        return status.when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(errorText(ctx, e)),
          data: (d) {
            final c = asMap(d['summary']);
            final ch = asMap(d['channels']);
            Widget stat(String l, int n) => Expanded(child: Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: ctx.colors.border), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), Text(l, style: TextStyle(color: ctx.colors.subtext, fontSize: 11.5))])));
            if (res != null) {
              final x = res!;
              final failed = asMapList(x['failed']);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.check_circle_rounded, color: ctx.colors.success), const SizedBox(width: 8), Expanded(child: Text(ctx.t('invite.all_done', {'n': jInt(x, 'sent')}), style: const TextStyle(fontWeight: FontWeight.w800)))]),
                const SizedBox(height: 10),
                if (jInt(x, 'skippedNoContact') > 0) Text('• ${ctx.t('invite.all_no_contact', {'n': jInt(x, 'skippedNoContact')})}'),
                if (jInt(x, 'skippedAlreadyInvited') > 0) Text('• ${ctx.t('invite.all_already', {'n': jInt(x, 'skippedAlreadyInvited')})}'),
                if (jInt(x, 'skippedHasAccount') > 0) Text('• ${ctx.t('invite.all_has_account', {'n': jInt(x, 'skippedHasAccount')})}'),
                if (failed.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(ctx.t('invite.all_failed'), style: TextStyle(color: ctx.colors.warning, fontWeight: FontWeight.w700)),
                  for (final f in failed) Text('• ${jStr(f, 'name')} — ${jStr(f, 'error')}', style: const TextStyle(fontSize: 12.5)),
                ],
              ]);
            }
            final ready = jInt(c, 'ready');
            final toSend = again ? ready : ready - jInt(c, 'alreadyInvited');
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [stat(ctx.t('invite.s_pending'), jInt(c, 'pending')), stat(ctx.t('invite.s_ready'), ready)]),
              Row(children: [stat(ctx.t('invite.s_email'), jInt(c, 'byEmail')), stat(ctx.t('invite.s_sms'), jInt(c, 'bySmsOnly'))]),
              Row(children: [stat(ctx.t('invite.s_nocontact'), jInt(c, 'noContact')), stat(ctx.t('invite.s_invited'), jInt(c, 'alreadyInvited'))]),
              if (jInt(c, 'noContact') > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ctx.t('invite.all_skip_hint', {'n': jInt(c, 'noContact')}), style: TextStyle(color: ctx.colors.warning, fontSize: 12.5, height: 1.4))),
              const SizedBox(height: 10),
              RadioGroup<String>(
                groupValue: via,
                onChanged: (v) => set(() => via = v ?? 'auto'),
                child: Column(children: [
                  for (final o in [('auto', 'invite.v_auto'), ('email', 'invite.v_email'), ('sms', 'invite.v_sms')])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: o.$1,
                      enabled: !(o.$1 == 'sms' && ch['sms'] != true),
                      title: Text('${ctx.t(o.$2)}${o.$1 == 'sms' && ch['sms'] != true ? ' — ${ctx.t('invite.sms_off')}' : ''}'),
                    ),
                ]),
              ),
              if (ch['smtp'] != true) Text(ctx.t('invite.mail_basic'), style: TextStyle(color: ctx.colors.warning, fontSize: 12, height: 1.4)),
              if (jInt(c, 'alreadyInvited') > 0) CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: again, onChanged: (v) => set(() => again = v ?? false), title: Text(ctx.t('invite.again'), style: const TextStyle(fontSize: 13))),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: ctx.colors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: sure, onChanged: (v) => set(() => sure = v ?? false), title: Text(ctx.t('invite.all_sure', {'n': toSend < 0 ? 0 : toSend}), style: TextStyle(color: ctx.colors.danger, fontSize: 13, fontWeight: FontWeight.w600))),
              ),
              const SizedBox(height: 14),
              LoadingButton(
                label: ctx.t('invite.all_send'),
                icon: Icons.send_rounded,
                loading: busy,
                onPressed: !sure || ready == 0
                    ? null
                    : () async {
                        set(() => busy = true);
                        try {
                          final x = asMap(await ref.read(apiProvider).post('/employees/invite-all', {'confirm': true, 'sendVia': via, 'includeInvited': again}));
                          ref.invalidate(employeesProvider);
                          set(() {
                            res = x;
                            busy = false;
                          });
                        } on ApiException catch (err) {
                          if (ctx.mounted) toast(ctx, err.message, error: true);
                          set(() => busy = false);
                        }
                      },
              ),
            ]);
          },
        );
      });
    }),
  );
}

/// Residence status: valid / under a month / expired, with the days left (nothing when the employee has no residence date).
class IqamaChip extends StatelessWidget {
  final DateTime? expiry;
  const IqamaChip(this.expiry, {super.key});

  static int? daysLeft(DateTime? d) {
    if (d == null) return null;
    final t = DateTime.now();
    return DateTime(d.year, d.month, d.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final n = daysLeft(expiry);
    if (n == null) return const SizedBox.shrink();
    final c = n < 0 ? context.colors.danger : (n <= 30 ? context.colors.warning : context.colors.success);
    final label = n < 0 ? context.t('iqama.expired') : (n <= 30 ? context.t('iqama.soon') : context.t('iqama.valid'));
    final days = n < 0 ? context.t('iqama.ago', {'n': -n}) : context.t('iqama.days', {'n': n});
    return Pill('$label · $days', color: c, icon: Icons.badge_outlined);
  }
}
