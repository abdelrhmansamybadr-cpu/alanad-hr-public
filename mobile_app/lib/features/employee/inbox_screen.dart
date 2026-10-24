import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../../core/push/notification_route.dart';
import '../data/providers.dart';

IconData notificationIcon(String type) {
  if (type.startsWith('leave')) return Icons.beach_access_rounded;
  if (type.startsWith('request')) return Icons.assignment_rounded;
  switch (type) {
    case 'payslip':
      return Icons.receipt_long_rounded;
    case 'announcement':
      return Icons.campaign_rounded;
    case 'document':
      return Icons.folder_rounded;
    case 'shift_assigned':
      return Icons.schedule_rounded;
    case 'late_checkin':
      return Icons.timer_outlined;
    case 'reminder_checkin':
      return Icons.login_rounded;
    case 'reminder_checkout':
      return Icons.logout_rounded;
    case 'onboarding':
      return Icons.checklist_rounded;
    case 'birthday':
      return Icons.cake_rounded;
    case 'kudos':
      return Icons.favorite_rounded;
    case 'review':
      return Icons.star_rounded;
    case 'employee_added':
      return Icons.person_add_alt_1_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

Color notificationColor(BuildContext c, String type) {
  if (type.endsWith('approved') || type == 'payslip') return c.colors.success;
  if (type.endsWith('rejected') || type == 'late_checkin') return c.colors.danger;
  if (type == 'announcement' || type.startsWith('reminder')) return c.colors.warning;
  return c.scheme.primary;
}

class InboxScreen extends ConsumerWidget {
  /// When shown as a pushed page (HR) there is a back button; as a tab there is not.
  final bool showBack;
  const InboxScreen({super.key, this.showBack = false});

  void _open(BuildContext context, WidgetRef ref, NotificationItem n) {
    final hr = ref.read(sessionProvider).user!.isHr;
    final to = routeForNotification(type: n.type, data: n.data, hr: hr);
    // The shell tabs ("/e/..", "/h/..") are switched to; everything else is pushed on top
    (to.startsWith('/e/') || to.startsWith('/h/')) ? context.go(to) : context.push(to);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(notificationsProvider);

    Future<void> markAll() async {
      try {
        await ref.read(apiProvider).post('/notifications/read', {'all': true});
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadCountProvider);
      } on ApiException catch (e) {
        if (context.mounted) toast(context, e.message, error: true);
      }
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text(context.t('inbox.title')),
        actions: [
          if ((data.valueOrNull?.unread ?? 0) > 0) TextButton(onPressed: markAll, child: Text(context.t('inbox.mark_all'))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future).catchError((_) => const NotificationsData(0, []));
        },
        child: AsyncBody<NotificationsData>(
          value: data,
          onRetry: () => ref.invalidate(notificationsProvider),
          builder: (d) => d.items.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.notifications_off_outlined, title: context.t('inbox.empty'), subtitle: context.t('inbox.empty_hint')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: d.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = d.items[i];
                    final color = notificationColor(context, n.type);
                    return Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: AlignmentDirectional.centerEnd,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: BoxDecoration(color: context.colors.danger, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        try {
                          await ref.read(apiProvider).delete('/notifications/${n.id}');
                        } on ApiException {
                          // will reappear on refresh
                        }
                        ref.invalidate(unreadCountProvider);
                      },
                      child: AppCard(
                        color: n.read ? null : context.colors.brandSoft,
                        padding: const EdgeInsets.all(14),
                        onTap: () async {
                          if (!n.read) {
                            try {
                              await ref.read(apiProvider).post('/notifications/read', {'ids': [n.id]});
                            } on ApiException {
                              // non-critical
                            }
                            ref.invalidate(notificationsProvider);
                            ref.invalidate(unreadCountProvider);
                          }
                          if (context.mounted) _open(context, ref, n);
                        },
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          IconBadge(notificationIcon(n.type), color: color),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(notifTitle(context, n), style: TextStyle(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800))),
                                if (!n.read) Container(width: 9, height: 9, decoration: BoxDecoration(color: context.scheme.primary, shape: BoxShape.circle)),
                              ]),
                              if (n.body.isNotEmpty) ...[const SizedBox(height: 3), Text(notifBody(context, n), style: TextStyle(color: context.colors.subtext, fontSize: 13, height: 1.35))],
                              const SizedBox(height: 6),
                              Text(timeAgo(context, n.createdAt), style: TextStyle(color: context.colors.subtext, fontSize: 11)),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}


/// Server notifications are written in English; show known kinds in the user's language.
String notifTitle(BuildContext context, NotificationItem n) {
  if (!context.isAr) return n.title;
  const m = {
    'department_head': 'أصبحت رئيس قسم',
    'document': 'مستند جديد',
    'employee_added': 'موظف جديد',
    'leave_approved': 'تم تسجيل الإجازة',
    'leave_request': 'طلب إجازة جديد',
    'left_zone': 'ابتعاد عن مكان العمل',
    'level_up': 'ارتقيت لمستوى جديد!',
    'payslip': 'قسيمة راتبك جاهزة',
    'request': 'طلب جديد',
    'review': 'تقييم أداء جديد',
    'shift_assigned': 'وردية جديدة',
    'promotion': 'تغيير وظيفي',
    'points': 'تحديث النقاط',
    'late_checkin': 'حضور متأخر',
    'request_approved': 'تمت الموافقة على طلبك',
    'request_rejected': 'تم رفض طلبك',
    'reminder_checkin': 'لا تنسَ تسجيل الحضور',
    'reminder_checkout': 'لا تنسَ تسجيل الانصراف',
    'onboarding': 'التهيئة الوظيفية',
    'birthday': 'عيد ميلاد اليوم',
    'kudos': 'وصلتك كلمة شكر',
  };
  return m[n.type] ?? n.title;
}

String notifBody(BuildContext context, NotificationItem n) {
  if (!context.isAr) return n.body;
  final mins = RegExp(r'(\d+)\s*minutes').firstMatch(n.body)?.group(1);
  switch (n.type) {
    case 'left_zone':
      return mins != null ? 'ابتعدت عن مكان العمل $mins دقيقة، لذلك يُحتسب اليوم نصف يوم.' : n.body;
    case 'level_up':
      return 'وصلت إلى مستوى جديد بعد سلسلة من الأيام الخضراء المتتالية. استمر!';
    case 'payslip':
      return 'تم دفع راتبك. يمكنك مراجعة القسيمة.';
    case 'department_head':
      return 'تم تعيينك رئيساً لقسم. يمكنك الموافقة على طلبات فريقك.';
    case 'promotion':
      return 'تم تحديث بياناتك الوظيفية. راجع مسيرتك المهنية.';
    case 'shift_assigned':
      return 'تم تعيين وردية جديدة لك.';
    case 'birthday':
      final who = RegExp(r"Today is (.+?)'s birthday").firstMatch(n.body)?.group(1);
      return who != null ? 'اليوم عيد ميلاد $who. أرسل تهنئتك!' : n.body;
    case 'reminder_checkin':
      return 'بدأت ورديتك. افتح التطبيق وسجّل حضورك ليُحتسب يومك.';
    case 'reminder_checkout':
      return 'انتهت ورديتك. سجّل انصرافك قبل المغادرة.';
  }
  return n.body;
}
