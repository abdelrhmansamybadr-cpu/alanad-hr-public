import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/i18n/strings.dart';
import '../../core/ui/widgets.dart';

/// Two-step approvals (team head first, then HR): where is this request now?
/// [headStatus] null = no head step.
class ChainBanner extends StatelessWidget {
  final String? headStatus;
  final String status;
  const ChainBanner({super.key, required this.headStatus, required this.status});

  @override
  Widget build(BuildContext context) {
    final hs = headStatus;
    if (hs == null) return const SizedBox.shrink();
    late final IconData icon;
    late final Color color;
    late final String text;
    if (hs == 'pending' && status == 'pending') {
      icon = Icons.hourglass_top_rounded; color = context.colors.warning; text = context.t('chain.waiting_head');
    } else if (hs == 'approved' && status == 'pending') {
      icon = Icons.how_to_reg_rounded; color = context.colors.info; text = context.t('chain.waiting_hr');
    } else if (hs == 'approved') {
      icon = Icons.verified_rounded; color = context.colors.success; text = context.t('chain.head_ok');
    } else if (hs == 'rejected') {
      icon = Icons.block_rounded; color = context.colors.danger; text = context.t('chain.head_no');
    } else {
      icon = Icons.fast_forward_rounded; color = context.colors.subtext; text = context.t('chain.skipped');
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .35))),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
  }
}

/// Status chip for lists: shows the stage while a two-step request is still pending.
Widget chainStatusChip(BuildContext context, String status, String? headStatus) {
  if (status == 'pending' && headStatus == 'pending') return StatusChip('pending', label: context.t('chain.tile_head'));
  if (status == 'pending' && headStatus == 'approved') return StatusChip('pending', label: context.t('chain.tile_hr'));
  return StatusChip(status);
}
