/// Where a tapped notification leads. Used by the in-app inbox and by the system (Android) notifications.
/// [data] is the notification's own data (e.g. {meetingId: 12}). EVERY kind the server creates has a target, and an
/// unknown kind opens the inbox, so a tap never does "nothing".
String routeForNotification({required String type, Map? data, required bool hr}) {
  final d = data ?? const {};
  final meetingId = int.tryParse('${d['meetingId'] ?? d['meeting_id'] ?? ''}');

  if (type == 'meeting') return meetingId != null ? '/meeting/$meetingId' : '/meetings';
  if (type == 'decision') return '/decisions';
  final complaintId = int.tryParse('${d['complaintId'] ?? d['complaint_id'] ?? ''}');
  if (type == 'complaint') return complaintId != null ? '/complaint/$complaintId' : '/complaints';
  if (type == 'chain_head_approved') return hr ? '/approvals' : '/e/requests';
  if (type == 'field') return '/field';
  if (type == 'leave_request' || type == 'request') return '/approvals';
  if (type.startsWith('leave') || type.startsWith('request')) return hr ? '/approvals' : '/e/requests';
  switch (type) {
    case 'payslip':
    case 'loan':
      return '/payslips';
    case 'announcement':
      return '/announcements';
    case 'document':
      return hr ? '/h/people' : '/documents';
    case 'shift_assigned':
    case 'late_checkin':
      return hr ? '/h/attendance' : '/e/time';
    case 'left_zone':
    case 'security_flag':
      return hr ? '/h/attendance' : '/e/time';
    case 'reminder_checkin':
    case 'reminder_checkout':
      return hr ? '/h/home' : '/e/time';
    case 'onboarding':
      return '/onboarding';
    case 'birthday':
      return '/directory';
    case 'kudos':
      return '/kudos';
    case 'review':
      return hr ? '/h/reviews' : '/my-reviews';
    case 'employee_added':
      return '/h/people';
    case 'department_head':
      return hr ? '/h/departments' : '/team';
    case 'promotion':
      return '/career';
    case 'points':
    case 'reward':
    case 'level_up':
      return hr ? '/h/rewards' : '/rewards';
    default:
      return '/inbox';
  }
}
