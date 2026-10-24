import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';
import '../employee/requests_screen.dart';

/// Pending leave + other requests to review. HR sees the whole company; a team lead sees their reports.
class ApprovalsScreen extends ConsumerStatefulWidget {
  /// Shown as a tab (no back button) inside the HR shell.
  final bool asTab;
  const ApprovalsScreen({super.key, this.asTab = false});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  int _kind = 0; // 0 leaves, 1 requests
  int _filter = 0; // 0 pending, 1 approved, 2 rejected

  static const _filters = ['pending', 'approved', 'rejected'];

  @override
  Widget build(BuildContext context) {
    final isHr = ref.watch(sessionProvider).user!.isHr;
    final scope = isHr ? 'all' : 'team';
    final q = (scope: scope, status: _filters[_filter]);
    final leaves = ref.watch(leavesProvider(q));
    final requests = ref.watch(requestsProvider(q));
    final pendingLeaves = ref.watch(leavesProvider((scope: scope, status: 'pending'))).valueOrNull?.length ?? 0;
    final pendingReqs = ref.watch(requestsProvider((scope: scope, status: 'pending'))).valueOrNull?.length ?? 0;

    Future<void> refresh() async {
      ref.invalidate(leavesProvider);
      ref.invalidate(requestsProvider);
      await Future.wait([ref.read(leavesProvider(q).future).catchError((_) => <LeaveItem>[]), ref.read(requestsProvider(q).future).catchError((_) => <RequestItem>[])]);
    }

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !widget.asTab, title: Text(context.t('nav.approvals'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SegmentBar(
            labels: [context.t('req.tab_leave') + (pendingLeaves > 0 ? ' ($pendingLeaves)' : ''), context.t('req.tab_other') + (pendingReqs > 0 ? ' ($pendingReqs)' : '')],
            index: _kind,
            onChanged: (i) => setState(() => _kind = i),
          ),
        ),
        FilterChips(labels: [context.t('status.pending'), context.t('status.approved'), context.t('status.rejected')], index: _filter, onChanged: (i) => setState(() => _filter = i)),
        const SizedBox(height: 10),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: _kind == 0
                ? AsyncBody<List<LeaveItem>>(
                    value: leaves,
                    onRetry: () => ref.invalidate(leavesProvider(q)),
                    builder: (items) => items.isEmpty
                        ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.task_alt_rounded, title: context.t('approvals.empty'), subtitle: context.t('approvals.empty_hint')))])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => LeaveTile(leave: items[i], showEmployee: true, onTap: () => showLeaveDetail(context, ref, items[i], canReview: true)),
                          ),
                  )
                : AsyncBody<List<RequestItem>>(
                    value: requests,
                    onRetry: () => ref.invalidate(requestsProvider(q)),
                    builder: (items) => items.isEmpty
                        ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.task_alt_rounded, title: context.t('approvals.empty'), subtitle: context.t('approvals.empty_hint')))])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => RequestTile(item: items[i], showEmployee: true, onTap: () => showRequestDetail(context, ref, items[i], canReview: true)),
                          ),
                  ),
          ),
        ),
      ]),
    );
  }
}
