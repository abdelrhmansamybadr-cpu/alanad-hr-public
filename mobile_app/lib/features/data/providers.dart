import '../../core/push/push_service.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/models/json.dart';
import '../../core/models/models.dart';

/// Every screen reads server data through these providers. Mutations call `ref.invalidate(...)` afterwards.
Api _api(Ref ref) => ref.read(apiProvider);

List<T> _list<T>(dynamic data, T Function(dynamic) parse) => data is List ? data.map(parse).toList() : <T>[];

// ------------------------------------------------------------------ home / stats

final myStatsProvider = FutureProvider.autoDispose<MyStats>((ref) async => MyStats.fromJson(await _api(ref).get('/stats/me')));
final hrStatsProvider = FutureProvider.autoDispose<HrStats>((ref) async => HrStats.fromJson(await _api(ref).get('/stats')));

// -------------------------------------------------------------------- attendance

final todayProvider = FutureProvider.autoDispose<TodayInfo>((ref) async => TodayInfo.fromJson(await _api(ref).get('/attendance/today')));

/// Monthly summary for the signed-in employee. Key = first day of the month.
final attendanceSummaryProvider = FutureProvider.autoDispose.family<AttendanceSummary, DateTime>((ref, month) async {
  return AttendanceSummary.fromJson(await _api(ref).get('/attendance/summary', query: {'month': month.month, 'year': month.year}));
});

/// HR live board for a date ("yyyy-MM-dd").
final boardProvider = FutureProvider.autoDispose.family<({Map<String, int> counts, String? holiday, List<BoardRow> rows}), String>((ref, date) async {
  final m = asMap(await _api(ref).get('/attendance/board', query: {'date': date}));
  final counts = <String, int>{};
  asMap(m['counts']).forEach((k, v) => counts[k] = v is int ? v : int.tryParse('$v') ?? 0);
  return (counts: counts, holiday: jStrN(m, 'holiday'), rows: asMapList(m['employees']).map(BoardRow.fromJson).toList());
});

/// Attendance records for one employee (HR view) between two dates.
final employeeAttendanceProvider = FutureProvider.autoDispose.family<List<AttendanceRecord>, ({int employeeId, String from, String to})>((ref, q) async {
  return _list(await _api(ref).get('/attendance', query: {'employeeId': q.employeeId, 'from': q.from, 'to': q.to}), AttendanceRecord.fromJson);
});

// ------------------------------------------------------------------------ leave

final leaveTypesProvider = FutureProvider.autoDispose<List<LeaveType>>((ref) async => _list(await _api(ref).get('/leave-types'), LeaveType.fromJson));
final allLeaveTypesProvider = FutureProvider.autoDispose<List<LeaveType>>((ref) async => _list(await _api(ref).get('/leave-types', query: {'all': 1}), LeaveType.fromJson));

final leaveBalanceProvider = FutureProvider.autoDispose.family<List<LeaveBalance>, int>((ref, year) async {
  final m = asMap(await _api(ref).get('/leaves/balance', query: {'year': year}));
  return asMapList(m['balances']).map(LeaveBalance.fromJson).toList();
});

/// scope: `mine` (default), `team` (my direct reports), `all` (HR). [status] filters when non-empty.
final leavesProvider = FutureProvider.autoDispose.family<List<LeaveItem>, ({String scope, String status})>((ref, q) async {
  final query = <String, dynamic>{if (q.scope == 'team') 'scope': 'team', if (q.status.isNotEmpty) 'status': q.status};
  return _list(await _api(ref).get('/leaves', query: query), LeaveItem.fromJson);
});

final employeeLeavesProvider = FutureProvider.autoDispose.family<List<LeaveItem>, int>((ref, employeeId) async {
  return _list(await _api(ref).get('/leaves', query: {'employeeId': employeeId}), LeaveItem.fromJson);
});

final requestsProvider = FutureProvider.autoDispose.family<List<RequestItem>, ({String scope, String status})>((ref, q) async {
  final query = <String, dynamic>{if (q.scope == 'team') 'scope': 'team', if (q.status.isNotEmpty) 'status': q.status};
  return _list(await _api(ref).get('/requests', query: query), RequestItem.fromJson);
});

final holidaysProvider = FutureProvider.autoDispose.family<List<Holiday>, int>((ref, year) async => _list(await _api(ref).get('/holidays', query: {'year': year}), Holiday.fromJson));

// ------------------------------------------------------------------- pay / files

/// Payslips: the employee's own, or (HR) all — optionally filtered by month "YYYY-MM".
final payslipsProvider = FutureProvider.autoDispose.family<List<Payslip>, String>((ref, month) async {
  return _list(await _api(ref).get('/payroll', query: {if (month.isNotEmpty) 'month': month}), Payslip.fromJson);
});

final docTypesProvider = FutureProvider.autoDispose<List<DocType>>((ref) async => _list(await _api(ref).get('/documents/types'), DocType.fromJson));
final employeeDocsProvider = FutureProvider.autoDispose.family<List<DocFile>, int>((ref, employeeId) async {
  return _list(await _api(ref).get('/documents/employee/$employeeId'), DocFile.fromJson);
});

// ---------------------------------------------------------------- communication

final announcementsProvider = FutureProvider.autoDispose<List<Announcement>>((ref) async => _list(await _api(ref).get('/announcements'), Announcement.fromJson));

class NotificationsData {
  final int unread;
  final List<NotificationItem> items;
  const NotificationsData(this.unread, this.items);
}

final notificationsProvider = FutureProvider.autoDispose<NotificationsData>((ref) async {
  final m = asMap(await _api(ref).get('/notifications'));
  return NotificationsData(jInt(m, 'unreadCount'), asMapList(m['items']).map(NotificationItem.fromJson).toList());
});

/// Unread badge, refreshed every minute while the app is open.
final unreadCountProvider = StreamProvider.autoDispose<int>((ref) async* {
  final api = _api(ref);
  Future<int> load() async {
    try {
      PushService.check().catchError((_) => 0);     // show new items in the system shade too
      return jInt(asMap(await api.get('/notifications/count')), 'unreadCount');
    } on ApiException {
      return 0;
    }
  }

  yield await load();
  yield* Stream.periodic(const Duration(seconds: 60)).asyncMap((_) => load());
});

// ----------------------------------------------------------------------- people

final directoryProvider = FutureProvider.autoDispose.family<List<Employee>, String>((ref, q) async {
  return _list(await _api(ref).get('/directory', query: {if (q.isNotEmpty) 'q': q}), Employee.fromJson);
});

final employeesProvider = FutureProvider.autoDispose.family<List<Employee>, String>((ref, q) async {
  return _list(await _api(ref).get('/employees', query: {if (q.isNotEmpty) 'q': q}), Employee.fromJson);
});

final employeeProvider = FutureProvider.autoDispose.family<Employee, int>((ref, id) async => Employee.fromJson(await _api(ref).get('/employees/$id')));

final departmentsProvider = FutureProvider.autoDispose<List<Department>>((ref) async => _list(await _api(ref).get('/departments'), Department.fromJson));
final shiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) async => _list(await _api(ref).get('/shifts'), Shift.fromJson));

/// Direct reports of the signed-in team lead, with today's status.
final teamProvider = FutureProvider.autoDispose<List<BoardRow>>((ref) async {
  final rows = asMapList(await _api(ref).get('/team'));
  return rows.map((r) => BoardRow.fromJson({...r, 'employeeId': r['id'], 'employeeName': '${r['firstName']} ${r['lastName']}', 'employeeAvatar': r['avatar'], 'boardStatus': r['today']})).toList();
});

// ----------------------------------------------------------------------- HR data

final jobsProvider = FutureProvider.autoDispose<List<Job>>((ref) async => _list(await _api(ref).get('/jobs'), Job.fromJson));
final applicationsProvider = FutureProvider.autoDispose.family<List<Application>, int?>((ref, jobId) async {
  return _list(await _api(ref).get('/applications', query: {if (jobId != null) 'jobId': jobId}), Application.fromJson);
});
final talentBankProvider = FutureProvider.autoDispose<List<Candidate>>((ref) async => _list(await _api(ref).get('/talent-pool/talent-bank/candidates'), Candidate.fromJson));
final reviewsProvider = FutureProvider.autoDispose<List<Review>>((ref) async => _list(await _api(ref).get('/reviews'), Review.fromJson));
final staffProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async => _list(await _api(ref).get('/hr-staff'), StaffMember.fromJson));

// ------------------------------------------------------------------ rewards / career / org

final myPointsProvider = FutureProvider.autoDispose<PointsSummary>((ref) async => PointsSummary.fromJson(await _api(ref).get('/points/me')));
final employeePointsProvider = FutureProvider.autoDispose.family<PointsSummary, int>((ref, id) async => PointsSummary.fromJson(await _api(ref).get('/points/employee/$id')));
final leaderboardProvider = FutureProvider.autoDispose<List<LeaderboardItem>>((ref) async {
  final m = asMap(await _api(ref).get('/points/leaderboard'));
  return asMapList(m['items']).map(LeaderboardItem.fromJson).toList();
});
final promotionsProvider = FutureProvider.autoDispose.family<List<Promotion>, int>((ref, id) async => _list(await _api(ref).get('/employees/$id/promotions'), Promotion.fromJson));
final orgProvider = FutureProvider.autoDispose<OrgData>((ref) async => OrgData.fromJson(await _api(ref).get('/org')));
final departmentProvider = FutureProvider.autoDispose.family<Department, int>((ref, id) async => Department.fromJson(await _api(ref).get('/departments/$id')));
final auditProvider = FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, entity) async {
  return _list(await _api(ref).get('/audit', query: {'limit': 150, if (entity.isNotEmpty) 'entity': entity}), AuditEntry.fromJson);
});
