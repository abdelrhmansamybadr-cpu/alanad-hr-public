import 'json.dart';

// ------------------------------------------------------------------ company / user

class Company {
  final int id;
  final String name;
  final String slug;
  final String? logoUrl;
  final int primary;
  final int accent;
  final String timezone;
  final String currency;
  final List<String> weekendDays;
  final String language;
  final int lateGraceMinutes;
  final List<String>? modules; // null = every module enabled
  final Map<String, dynamic> attendancePolicy;
  final Map<String, dynamic> pointsConfig;
  final Map<String, dynamic> payrollPolicy;
  /// Premium features the owner switched on for this company (camelCase keys: localLaws, fairDecisions...). Missing = off.
  final Map<String, bool> features;

  const Company({
    required this.id,
    required this.name,
    this.slug = '',
    this.logoUrl,
    this.primary = 0xFF00617A,
    this.accent = 0xFFC88453,
    this.timezone = 'Africa/Cairo',
    this.currency = 'EGP',
    this.weekendDays = const ['fri', 'sat'],
    this.language = 'en',
    this.lateGraceMinutes = 15,
    this.modules,
    this.attendancePolicy = const {},
    this.pointsConfig = const {},
    this.payrollPolicy = const {},
    this.features = const {},
  });

  static int _color(String? hex, int fallback) {
    if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
    return int.parse('FF${hex.substring(1)}', radix: 16);
  }

  factory Company.fromJson(dynamic raw) {
    final m = asMap(raw);
    final mods = m['modules'];
    return Company(
      id: jInt(m, 'id'),
      name: jStr(m, 'name'),
      slug: jStr(m, 'slug'),
      logoUrl: jStrN(m, 'logoUrl'),
      primary: _color(jStrN(m, 'primaryColor'), 0xFF00617A),
      accent: _color(jStrN(m, 'accentColor'), 0xFFC88453),
      timezone: jStr(m, 'timezone', 'Africa/Cairo'),
      currency: jStr(m, 'currency', 'EGP'),
      weekendDays: jStr(m, 'weekendDays', 'fri,sat').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      language: jStr(m, 'language', 'en'),
      lateGraceMinutes: jInt(m, 'lateGraceMinutes', 15),
      modules: mods is List ? mods.map((e) => e.toString()).toList() : null,
      attendancePolicy: asMap(m['attendancePolicy']),
      pointsConfig: asMap(m['pointsConfig']),
      payrollPolicy: asMap(m['payrollPolicy']),
      features: {for (final e in asMap(m['features']).entries) e.key: e.value == true},
    );
  }

  bool hasModule(String key) => modules == null || modules!.contains(key);

  /// Is a premium feature on? (the server enforces it too: turning it off closes the API, this only hides the screens)
  bool hasFeature(String key) => features[key] == true;

  /// Reward points are on unless the admin switched them off.
  bool get pointsEnabled => pointsConfig['enabled'] != false;
  bool get leaderboardVisible => pointsConfig['showLeaderboard'] != false;
}

class AppUser {
  final int id;
  final String name;
  final String email;
  final String role; // hr_admin | hr_manager | employee
  final String? avatar;
  final String? title;
  final String? phone;
  final int? employeeId;
  final bool isTeamLead;
  final Map<String, bool> permissions;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar,
    this.title,
    this.phone,
    this.employeeId,
    this.isTeamLead = false,
    this.permissions = const {},
  });

  factory AppUser.fromJson(dynamic raw) {
    final m = asMap(raw);
    final perms = <String, bool>{};
    for (final p in asMapList(m['permissions'])) {
      perms[jStr(p, 'module')] = jBool(p, 'enabled', true);
    }
    return AppUser(
      id: jInt(m, 'id'),
      name: jStr(m, 'name'),
      email: jStr(m, 'email'),
      role: jStr(m, 'role', 'employee'),
      avatar: jStrN(m, 'avatar'),
      title: jStrN(m, 'title'),
      phone: jStrN(m, 'phone'),
      employeeId: jIntN(m, 'employeeId'),
      isTeamLead: jBool(m, 'isTeamLead'),
      permissions: perms,
    );
  }

  bool get isAdmin => role == 'hr_admin';
  bool get isHr => role == 'hr_admin' || role == 'hr_manager';
  bool get isEmployee => role == 'employee';

  /// HR managers may have single modules switched off by the admin.
  bool canUse(String module) => isAdmin || (isHr && (permissions[module] ?? true));

  String get firstName => name.trim().split(' ').first;
}

// ---------------------------------------------------------------------- people

class Employee {
  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String position;
  final int? departmentId;
  final String? departmentName;
  final int? shiftId;
  final String? shiftName;
  final int? managerId;
  final String? managerName;
  final String status;
  final DateTime? startDate;
  final double? salary;
  final String? avatar;
  final DateTime? birthDate;
  final String? gender;
  final String? address;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? inviteCode; // present only right after creating an employee
  final DateTime? terminationDate;
  final String? terminationReason;

  const Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email = '',
    this.phone,
    this.position = '',
    this.departmentId,
    this.departmentName,
    this.shiftId,
    this.shiftName,
    this.managerId,
    this.managerName,
    this.status = 'active',
    this.startDate,
    this.salary,
    this.avatar,
    this.birthDate,
    this.gender,
    this.address,
    this.emergencyName,
    this.emergencyPhone,
    this.inviteCode,
    this.terminationDate,
    this.terminationReason,
  });

  factory Employee.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Employee(
      id: jInt(m, 'id'),
      firstName: jStr(m, 'firstName'),
      lastName: jStr(m, 'lastName'),
      email: jStr(m, 'email'),
      phone: jStrN(m, 'phone'),
      position: jStr(m, 'position'),
      departmentId: jIntN(m, 'departmentId'),
      departmentName: jStrN(m, 'departmentName'),
      shiftId: jIntN(m, 'shiftId'),
      shiftName: jStrN(m, 'shiftName'),
      managerId: jIntN(m, 'managerId'),
      managerName: jStrN(m, 'managerName'),
      status: jStr(m, 'status', 'active'),
      startDate: jDate(m, 'startDate'),
      salary: jDoubleN(m, 'salary'),
      avatar: jStrN(m, 'avatar'),
      birthDate: jDate(m, 'birthDate'),
      gender: jStrN(m, 'gender'),
      address: jStrN(m, 'address'),
      emergencyName: jStrN(m, 'emergencyName'),
      emergencyPhone: jStrN(m, 'emergencyPhone'),
      inviteCode: jStrN(m, 'inviteCode'),
      terminationDate: jDate(m, 'terminationDate'),
      terminationReason: jStrN(m, 'terminationReason'),
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}

class Department {
  final int id;
  final String name;
  final String? description;
  final int? headId;
  final String? headName;
  final String? headAvatar;
  final String? headPosition;
  final int employeeCount;
  final List<Employee> members;
  const Department({required this.id, required this.name, this.description, this.headId, this.headName, this.headAvatar, this.headPosition, this.employeeCount = 0, this.members = const []});

  String? get managerName => headName;

  factory Department.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Department(
      id: jInt(m, 'id'),
      name: jStr(m, 'name'),
      description: jStrN(m, 'description'),
      headId: jIntN(m, 'headEmployeeId'),
      headName: jStrN(m, 'headName'),
      headAvatar: jStrN(m, 'headAvatar'),
      headPosition: jStrN(m, 'headPosition'),
      employeeCount: jInt(m, 'employeeCount'),
      members: asMapList(m['members']).map(Employee.fromJson).toList(),
    );
  }
}

class Shift {
  final int id;
  final String name;
  final String startTime; // HH:mm
  final String endTime;
  final String color;
  final String days;
  final int assigned;
  const Shift({required this.id, required this.name, required this.startTime, required this.endTime, this.color = '#00617A', this.days = '', this.assigned = 0});

  factory Shift.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Shift(
      id: jInt(m, 'id'),
      name: jStr(m, 'name'),
      startTime: jStr(m, 'startTime'),
      endTime: jStr(m, 'endTime'),
      color: jStr(m, 'color', '#00617A'),
      days: jStr(m, 'days'),
      assigned: jInt(m, 'assignedEmployees'),
    );
  }
}

// ------------------------------------------------------------------- attendance

class AttendanceRecord {
  final int id;
  final int employeeId;
  final String employeeName;
  final String? employeeAvatar;
  final DateTime date;
  final String? checkIn; // HH:mm
  final String? checkOut;
  final String status;
  final double hoursWorked;
  final int lateMinutes;
  final String? note;
  final String source;
  final int earlyLeaveMinutes;
  final int outZoneMinutes;
  final int overtimeMinutes;
  final List<String> flags;
  final List<String> securityFlags;
  final bool closed;
  final bool? insideNow;
  final PointReward? reward;

  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    this.employeeName = '',
    this.employeeAvatar,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.status = 'present',
    this.hoursWorked = 0,
    this.lateMinutes = 0,
    this.note,
    this.source = 'manual',
    this.earlyLeaveMinutes = 0,
    this.outZoneMinutes = 0,
    this.overtimeMinutes = 0,
    this.flags = const [], this.securityFlags = const [],
    this.closed = false,
    this.insideNow,
    this.reward,
  });

  bool get missedCheckout => flags.contains('missed_checkout');

  factory AttendanceRecord.fromJson(dynamic raw) {
    final m = asMap(raw);
    return AttendanceRecord(
      id: jInt(m, 'id'),
      employeeId: jInt(m, 'employeeId'),
      employeeName: jStr(m, 'employeeName'),
      employeeAvatar: jStrN(m, 'employeeAvatar'),
      date: jDate(m, 'date') ?? DateTime.now(),
      checkIn: jStrN(m, 'checkIn'),
      checkOut: jStrN(m, 'checkOut'),
      status: jStr(m, 'status', 'present'),
      hoursWorked: jDouble(m, 'hoursWorked'),
      lateMinutes: jInt(m, 'lateMinutes'),
      note: jStrN(m, 'note'),
      source: jStr(m, 'source', 'manual'),
      earlyLeaveMinutes: jInt(m, 'earlyLeaveMinutes'),
      outZoneMinutes: jInt(m, 'outZoneMinutes'),
      overtimeMinutes: jInt(m, 'overtimeMinutes'),
      flags: jStr(m, 'flags').split(',').where((e) => e.isNotEmpty).toList(),
      securityFlags: jStr(m, 'securityFlags').split(',').where((e) => e.isNotEmpty).toList(),
      closed: jBool(m, 'closed'),
      insideNow: m['lastPingInside'] == null ? null : jBool(m, 'lastPingInside'),
      reward: m['reward'] is Map ? PointReward.fromJson(m['reward']) : null,
    );
  }
}

class PointReward {
  final String color; // green | red | black | none
  final String reason;
  const PointReward(this.color, this.reason);
  factory PointReward.fromJson(dynamic raw) {
    final m = asMap(raw);
    return PointReward(jStr(m, 'color', 'none'), jStr(m, 'reason'));
  }
}

class TodayInfo {
  final String date;
  final DateTime serverTime;
  final String state; // ready | checked_in | checked_out
  final AttendanceRecord? record;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final bool locationRequired;
  final bool wifiRequired;
  final String? wifiSsid;
  final double? radiusM;
  final String? holiday;
  final String? onLeave;
  final bool isWeekend;
  final bool isWorkday;
  final bool shiftIsDefault;
  final String matchMode;
  final bool trackLocation;
  final int pingIntervalMinutes;
  final int outZoneHalfDayMinutes;
  final int lateGraceMinutes;
  final int halfDayLateMinutes;

  const TodayInfo({
    required this.date,
    required this.serverTime,
    required this.state,
    this.record,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    this.locationRequired = false,
    this.wifiRequired = false,
    this.wifiSsid,
    this.radiusM,
    this.holiday,
    this.onLeave,
    this.isWeekend = false,
    this.isWorkday = true,
    this.shiftIsDefault = false,
    this.matchMode = 'any',
    this.trackLocation = true,
    this.pingIntervalMinutes = 5,
    this.outZoneHalfDayMinutes = 0,
    this.lateGraceMinutes = 15,
    this.halfDayLateMinutes = 120,
  });

  bool get hasZoneRule => locationRequired || wifiRequired;

  factory TodayInfo.fromJson(dynamic raw) {
    final m = asMap(raw);
    final shift = m['shift'] is Map ? asMap(m['shift']) : null;
    final rule = m['rule'] is Map ? asMap(m['rule']) : null;
    final leave = m['onLeave'] is Map ? asMap(m['onLeave']) : null;
    final policy = asMap(m['policy']);
    return TodayInfo(
      date: jStr(m, 'date'),
      // keep the company's wall-clock digits: drop the UTC offset ("...+03:00") before parsing
      serverTime: DateTime.tryParse(jStr(m, 'serverTime').split(RegExp(r'[+Z]')).first) ?? DateTime.now(),
      state: jStr(m, 'state', 'ready'),
      record: m['record'] is Map ? AttendanceRecord.fromJson(m['record']) : null,
      shiftName: shift == null ? null : jStrN(shift, 'name'),
      shiftStart: shift == null ? null : jStrN(shift, 'startTime'),
      shiftEnd: shift == null ? null : jStrN(shift, 'endTime'),
      locationRequired: rule != null && jBool(rule, 'locationEnabled'),
      wifiRequired: rule != null && jBool(rule, 'wifiEnabled'),
      wifiSsid: rule == null ? null : jStrN(rule, 'wifiSsid'),
      radiusM: rule == null ? null : jDoubleN(rule, 'radiusM'),
      holiday: jStrN(m, 'holiday'),
      onLeave: leave == null ? null : (jStrN(leave, 'typeName') ?? jStr(leave, 'type')),
      isWeekend: jBool(m, 'isWeekend'),
      isWorkday: jBool(m, 'isWorkday', true),
      shiftIsDefault: shift != null && jBool(shift, 'isDefault'),
      matchMode: rule == null ? 'any' : jStr(rule, 'matchMode', 'any'),
      trackLocation: jBool(policy, 'trackLocation', true),
      pingIntervalMinutes: jInt(policy, 'pingIntervalMinutes', 5),
      outZoneHalfDayMinutes: jInt(policy, 'outZoneHalfDayMinutes'),
      lateGraceMinutes: jInt(policy, 'lateGraceMinutes', 15),
      halfDayLateMinutes: jInt(policy, 'halfDayLateMinutes', 120),
    );
  }
}

class AttendanceSummary {
  final int month;
  final int year;
  final int present;
  final int late;
  final int half;
  final int absent;
  final int leave;
  final double hours;
  final int lateMinutes;
  final int earlyLeaveDays;
  final int overtimeMinutes;
  final int outZoneMinutes;
  final Map<String, String> days; // yyyy-MM-dd -> status (present | late | half_day | absent | on_leave | holiday | off)
  final List<AttendanceRecord> records;
  const AttendanceSummary({required this.month, required this.year, this.present = 0, this.late = 0, this.half = 0, this.absent = 0, this.leave = 0, this.hours = 0, this.lateMinutes = 0, this.earlyLeaveDays = 0, this.overtimeMinutes = 0, this.outZoneMinutes = 0, this.days = const {}, this.records = const []});

  factory AttendanceSummary.fromJson(dynamic raw) {
    final m = asMap(raw);
    return AttendanceSummary(
      month: jInt(m, 'month'),
      year: jInt(m, 'year'),
      present: jInt(m, 'presentDays'),
      late: jInt(m, 'lateDays'),
      half: jInt(m, 'halfDays'),
      absent: jInt(m, 'absentDays'),
      leave: jInt(m, 'leaveDays'),
      hours: jDouble(m, 'totalHours'),
      lateMinutes: jInt(m, 'lateMinutes'),
      earlyLeaveDays: jInt(m, 'earlyLeaveDays'),
      overtimeMinutes: jInt(m, 'overtimeMinutes'),
      outZoneMinutes: jInt(m, 'outZoneMinutes'),
      days: asMap(m['days']).map((k, v) => MapEntry(k, v.toString())),
      records: asMapList(m['records']).map(AttendanceRecord.fromJson).toList(),
    );
  }
}

class BoardRow {
  final int? attendanceId;
  final int employeeId;
  final String name;
  final String? avatar;
  final String position;
  final String? department;
  final String status; // present | late | half_day | absent | on_leave
  final String? checkIn;
  final String? checkOut;
  final int lateMinutes;
  final String? leaveType;
  final List<String> flags;
  final List<String> securityFlags;
  final bool outsideNow;
  final int outZoneMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  const BoardRow({this.attendanceId, required this.employeeId, required this.name, this.avatar, this.position = '', this.department, required this.status, this.checkIn, this.checkOut, this.lateMinutes = 0, this.leaveType, this.flags = const [], this.securityFlags = const [], this.outsideNow = false, this.outZoneMinutes = 0, this.earlyLeaveMinutes = 0, this.overtimeMinutes = 0});

  factory BoardRow.fromJson(dynamic raw) {
    final m = asMap(raw);
    return BoardRow(
      attendanceId: jIntN(m, 'attendanceId'),
      employeeId: jInt(m, 'employeeId'),
      name: jStr(m, 'employeeName'),
      avatar: jStrN(m, 'employeeAvatar'),
      position: jStr(m, 'position'),
      department: jStrN(m, 'departmentName'),
      status: jStr(m, 'boardStatus', 'absent'),
      checkIn: jStrN(m, 'checkIn'),
      checkOut: jStrN(m, 'checkOut'),
      lateMinutes: jInt(m, 'lateMinutes'),
      leaveType: jStrN(m, 'leaveType'),
      flags: jStr(m, 'flags').split(',').where((e) => e.isNotEmpty).toList(),
      securityFlags: jStr(m, 'securityFlags').split(',').where((e) => e.isNotEmpty).toList(),
      outsideNow: jBool(m, 'outsideNow'),
      outZoneMinutes: jInt(m, 'outZoneMinutes'),
      earlyLeaveMinutes: jInt(m, 'earlyLeaveMinutes'),
      overtimeMinutes: jInt(m, 'overtimeMinutes'),
    );
  }
}

// ------------------------------------------------------------------------ leave

class LeaveType {
  final int id;
  final String code;
  final String name;
  final int daysPerYear; // 0 = unlimited
  final bool paid;
  final String color;
  final bool active;
  const LeaveType({required this.id, required this.code, required this.name, this.daysPerYear = 0, this.paid = true, this.color = '#00617A', this.active = true});

  factory LeaveType.fromJson(dynamic raw) {
    final m = asMap(raw);
    return LeaveType(
      id: jInt(m, 'id'),
      code: jStr(m, 'code'),
      name: jStr(m, 'name'),
      daysPerYear: jInt(m, 'daysPerYear'),
      paid: jBool(m, 'paid', true),
      color: jStr(m, 'color', '#00617A'),
      active: jBool(m, 'isActive', true),
    );
  }
}

class LeaveBalance {
  final String code;
  final String name;
  final String color;
  final bool paid;
  final int total; // 0 = unlimited
  final int used;
  final int pending;
  final int? remaining;
  const LeaveBalance({required this.code, required this.name, this.color = '#00617A', this.paid = true, this.total = 0, this.used = 0, this.pending = 0, this.remaining});

  factory LeaveBalance.fromJson(dynamic raw) {
    final m = asMap(raw);
    return LeaveBalance(
      code: jStr(m, 'code'),
      name: jStr(m, 'name'),
      color: jStr(m, 'color', '#00617A'),
      paid: jBool(m, 'paid', true),
      total: jInt(m, 'total'),
      used: jInt(m, 'used'),
      pending: jInt(m, 'pending'),
      remaining: jIntN(m, 'remaining'),
    );
  }

  bool get unlimited => total == 0;
}

class LeaveItem {
  final int id;
  final int employeeId;
  final String employeeName;
  final String? employeeAvatar;
  final String? departmentName;
  final String type;
  final String typeName;
  final String typeColor;
  final DateTime start;
  final DateTime end;
  final int days;
  final String? reason;
  final String status;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? createdAt;
  /// Two-step approvals: null = no head step, pending / approved / rejected / skipped.
  final String? headStatus;

  const LeaveItem({
    required this.id,
    required this.employeeId,
    this.employeeName = '',
    this.employeeAvatar,
    this.departmentName,
    required this.type,
    required this.typeName,
    this.typeColor = '#00617A',
    required this.start,
    required this.end,
    this.days = 1,
    this.reason,
    this.status = 'pending',
    this.reviewNote,
    this.reviewedBy,
    this.createdAt,
    this.headStatus,
  });

  factory LeaveItem.fromJson(dynamic raw) {
    final m = asMap(raw);
    final type = jStr(m, 'type');
    return LeaveItem(
      id: jInt(m, 'id'),
      employeeId: jInt(m, 'employeeId'),
      employeeName: jStr(m, 'employeeName'),
      employeeAvatar: jStrN(m, 'employeeAvatar'),
      departmentName: jStrN(m, 'departmentName'),
      type: type,
      typeName: jStr(m, 'typeName', type),
      typeColor: jStr(m, 'typeColor', '#00617A'),
      start: jDate(m, 'startDate') ?? DateTime.now(),
      end: jDate(m, 'endDate') ?? DateTime.now(),
      days: jInt(m, 'days', 1),
      reason: jStrN(m, 'reason'),
      status: jStr(m, 'status', 'pending'),
      reviewNote: jStrN(m, 'reviewNote'),
      reviewedBy: jStrN(m, 'reviewedByName'),
      createdAt: jDate(m, 'createdAt'),
      headStatus: jStrN(m, 'headStatus'),
    );
  }
}

class RequestItem {
  final int id;
  final int employeeId;
  final String employeeName;
  final String? employeeAvatar;
  final String type;
  final String title;
  final String? description;
  final double? amount;
  final String status;
  final String? reviewNote;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;
  final String? headStatus;
  const RequestItem({required this.id, required this.employeeId, this.employeeName = '', this.employeeAvatar, required this.type, required this.title, this.description, this.amount, this.status = 'pending', this.reviewNote, this.createdAt, this.payload = const {}, this.headStatus});

  factory RequestItem.fromJson(dynamic raw) {
    final m = asMap(raw);
    return RequestItem(
      id: jInt(m, 'id'),
      employeeId: jInt(m, 'employeeId'),
      employeeName: jStr(m, 'employeeName'),
      employeeAvatar: jStrN(m, 'employeeAvatar'),
      type: jStr(m, 'type', 'other'),
      title: jStr(m, 'title'),
      description: jStrN(m, 'description'),
      amount: jDoubleN(m, 'amount'),
      status: jStr(m, 'status', 'pending'),
      reviewNote: jStrN(m, 'reviewNote'),
      createdAt: jDate(m, 'createdAt'),
      payload: asMap(m['payload']),
      headStatus: jStrN(m, 'headStatus'),
    );
  }
}

// ------------------------------------------------------------- pay / documents

class Payslip {
  final int id;
  final int employeeId;
  final String employeeName;
  final String month; // YYYY-MM
  final double base;
  final double bonus;
  final double deductions;
  final double net;
  final String status;
  final DateTime? paidAt;
  final String? position;
  final String? department;
  final List<PayLine> lines;
  final Map<String, dynamic> stats;
  const Payslip({required this.id, required this.employeeId, this.employeeName = '', required this.month, this.base = 0, this.bonus = 0, this.deductions = 0, this.net = 0, this.status = 'pending', this.paidAt, this.position, this.department, this.lines = const [], this.stats = const {}});

  factory Payslip.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Payslip(
      id: jInt(m, 'id'),
      employeeId: jInt(m, 'employeeId'),
      employeeName: jStr(m, 'employeeName'),
      month: jStr(m, 'month'),
      base: jDouble(m, 'baseSalary'),
      bonus: jDouble(m, 'bonus'),
      deductions: jDouble(m, 'deductions'),
      net: jDouble(m, 'netPay'),
      status: jStr(m, 'status', 'pending'),
      paidAt: jDate(m, 'paidAt'),
      position: jStrN(m, 'position'),
      department: jStrN(m, 'departmentName'),
      lines: asMapList(asMap(m['breakdown'])['lines']).map(PayLine.fromJson).toList(),
      stats: asMap(asMap(m['breakdown'])['stats']),
    );
  }
}

class PayLine {
  final String key;
  final String label;
  final double qty;
  final double amount; // negative = deduction
  const PayLine({required this.key, required this.label, this.qty = 0, this.amount = 0});
  factory PayLine.fromJson(dynamic raw) {
    final m = asMap(raw);
    return PayLine(key: jStr(m, 'key'), label: jStr(m, 'label'), qty: jDouble(m, 'qty'), amount: jDouble(m, 'amount'));
  }
}

class DocType {
  final int id;
  final String label;
  const DocType({required this.id, required this.label});
  factory DocType.fromJson(dynamic raw) {
    final m = asMap(raw);
    return DocType(id: jInt(m, 'id'), label: jStr(m, 'label', jStr(m, 'name')));
  }
}

class DocFile {
  final int id;
  final String fileName;
  final String typeLabel;
  final int typeId;
  final String mime;
  final DateTime? uploadedAt;
  final String downloadUrl;
  const DocFile({required this.id, required this.fileName, this.typeLabel = '', this.typeId = 0, this.mime = '', this.uploadedAt, required this.downloadUrl});
  factory DocFile.fromJson(dynamic raw) {
    final m = asMap(raw);
    return DocFile(
      id: jInt(m, 'id'),
      fileName: jStr(m, 'fileName'),
      typeLabel: jStr(m, 'typeLabel'),
      typeId: jInt(m, 'typeId'),
      mime: jStr(m, 'mimeType'),
      uploadedAt: jDate(m, 'uploadedAt'),
      downloadUrl: jStr(m, 'downloadUrl'),
    );
  }
}

// ---------------------------------------------------------------- communication

class Announcement {
  final int id;
  final String title;
  final String content;
  final String author;
  final String priority;
  final DateTime? createdAt;
  const Announcement({required this.id, required this.title, this.content = '', this.author = '', this.priority = 'medium', this.createdAt});
  factory Announcement.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Announcement(id: jInt(m, 'id'), title: jStr(m, 'title'), content: jStr(m, 'content'), author: jStr(m, 'authorName'), priority: jStr(m, 'priority', 'medium'), createdAt: jDate(m, 'createdAt'));
  }
}

class Holiday {
  final int id;
  final String name;
  final DateTime date;
  const Holiday({required this.id, required this.name, required this.date});
  factory Holiday.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Holiday(id: jInt(m, 'id'), name: jStr(m, 'name'), date: jDate(m, 'date') ?? DateTime.now());
  }
}

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime? createdAt;
  const NotificationItem({required this.id, required this.type, required this.title, this.body = '', this.data = const {}, this.read = false, this.createdAt});
  factory NotificationItem.fromJson(dynamic raw) {
    final m = asMap(raw);
    return NotificationItem(id: jInt(m, 'id'), type: jStr(m, 'type'), title: jStr(m, 'title'), body: jStr(m, 'body'), data: asMap(m['data']), read: m['readAt'] != null, createdAt: jDate(m, 'createdAt'));
  }
}

// --------------------------------------------------------------------- dashboards

class WhoIsOut {
  final int id;
  final String name;
  final String? avatar;
  final DateTime? until;
  const WhoIsOut({required this.id, required this.name, this.avatar, this.until});
  factory WhoIsOut.fromJson(dynamic raw) {
    final m = asMap(raw);
    return WhoIsOut(id: jInt(m, 'id'), name: jStr(m, 'name'), avatar: jStrN(m, 'avatar'), until: jDate(m, 'endDate'));
  }
}

class MyStats {
  final int unread;
  final Holiday? nextHoliday;
  final List<WhoIsOut> onLeaveToday;
  final List<Announcement> announcements;
  final int monthPresent;
  final int monthLate;
  final double monthHours;
  final List<LeaveBalance> balances;
  final int pendingApprovals;
  final bool isTeamLead;
  final PointsBrief? points;
  const MyStats({this.unread = 0, this.nextHoliday, this.onLeaveToday = const [], this.announcements = const [], this.monthPresent = 0, this.monthLate = 0, this.monthHours = 0, this.balances = const [], this.pendingApprovals = 0, this.isTeamLead = false, this.points});

  factory MyStats.fromJson(dynamic raw) {
    final m = asMap(raw);
    final month = asMap(m['month']);
    final nh = m['nextHoliday'];
    return MyStats(
      unread: jInt(m, 'unreadNotifications'),
      nextHoliday: nh is Map ? Holiday.fromJson({'id': 0, ...Map<String, dynamic>.from(nh)}) : null,
      onLeaveToday: asMapList(m['onLeaveToday']).map(WhoIsOut.fromJson).toList(),
      announcements: asMapList(m['announcements']).map(Announcement.fromJson).toList(),
      monthPresent: jInt(month, 'present'),
      monthLate: jInt(month, 'late'),
      monthHours: jDouble(month, 'hours'),
      balances: asMapList(m['leaveBalances']).map(LeaveBalance.fromJson).toList(),
      pendingApprovals: jInt(m, 'pendingApprovals'),
      isTeamLead: jBool(m, 'isTeamLead'),
      points: m['points'] is Map ? PointsBrief.fromJson(m['points']) : null,
    );
  }
}

class PointsBrief {
  final int green;
  final int red;
  final int black;
  final int level;
  final String levelName;
  final int streak;
  final int streakTarget;
  const PointsBrief({this.green = 0, this.red = 0, this.black = 0, this.level = 0, this.levelName = '', this.streak = 0, this.streakTarget = 30});
  factory PointsBrief.fromJson(dynamic raw) {
    final m = asMap(raw);
    return PointsBrief(green: jInt(m, 'green'), red: jInt(m, 'red'), black: jInt(m, 'black'), level: jInt(m, 'level'), levelName: jStr(m, 'levelName'), streak: jInt(m, 'streak'), streakTarget: jInt(m, 'streakTarget', 30));
  }
}

class DayCount {
  final DateTime date;
  final int present;
  final int late;
  const DayCount(this.date, this.present, this.late);
}

class UpcomingEvent {
  final String type; // birthday | anniversary
  final int employeeId;
  final String name;
  final String? avatar;
  final DateTime date;
  final int inDays;
  final int? years;
  const UpcomingEvent({required this.type, required this.employeeId, required this.name, this.avatar, required this.date, required this.inDays, this.years});
  factory UpcomingEvent.fromJson(dynamic raw) {
    final m = asMap(raw);
    return UpcomingEvent(type: jStr(m, 'type'), employeeId: jInt(m, 'employeeId'), name: jStr(m, 'name'), avatar: jStrN(m, 'avatar'), date: jDate(m, 'date') ?? DateTime.now(), inDays: jInt(m, 'inDays'), years: jIntN(m, 'years'));
  }
}

class HrStats {
  final int total;
  final int active;
  final int onLeave;
  final int present;
  final int late;
  final int absent;
  final int pendingLeaves;
  final int pendingRequests;
  final int openPositions;
  final int newApplications;
  final int newHires;
  final double payroll;
  final double attendanceRate;
  final List<MapEntry<String, int>> departments;
  final List<DayCount> trend;
  final List<UpcomingEvent> events;
  final int notIn;
  final int halfDay;
  final int outsideNow;
  final int pendingCorrections;
  final List<LeaderboardItem> topPerformers;
  const HrStats({this.notIn = 0, this.halfDay = 0, this.outsideNow = 0, this.pendingCorrections = 0, this.topPerformers = const [], this.total = 0, this.active = 0, this.onLeave = 0, this.present = 0, this.late = 0, this.absent = 0, this.pendingLeaves = 0, this.pendingRequests = 0, this.openPositions = 0, this.newApplications = 0, this.newHires = 0, this.payroll = 0, this.attendanceRate = 0, this.departments = const [], this.trend = const [], this.events = const []});

  factory HrStats.fromJson(dynamic raw) {
    final m = asMap(raw);
    return HrStats(
      total: jInt(m, 'totalEmployees'),
      active: jInt(m, 'activeEmployees'),
      onLeave: jInt(m, 'onLeave'),
      present: jInt(m, 'presentToday'),
      late: jInt(m, 'lateToday'),
      absent: jInt(m, 'absentToday'),
      pendingLeaves: jInt(m, 'pendingLeaves'),
      pendingRequests: jInt(m, 'pendingRequests'),
      openPositions: jInt(m, 'openPositions'),
      newApplications: jInt(m, 'newApplications'),
      newHires: jInt(m, 'newHires'),
      payroll: jDouble(m, 'totalPayroll'),
      attendanceRate: jDouble(m, 'attendanceRate'),
      departments: asMapList(m['deptBreakdown']).map((e) => MapEntry(jStr(e, 'name'), jInt(e, 'count'))).toList(),
      trend: asMapList(m['attendanceTrend']).map((e) => DayCount(jDate(e, 'date') ?? DateTime.now(), jInt(e, 'present'), jInt(e, 'late'))).toList(),
      events: asMapList(m['upcomingEvents']).map(UpcomingEvent.fromJson).toList(),
      notIn: jInt(m, 'notInYet'),
      halfDay: jInt(m, 'halfDayToday'),
      outsideNow: jInt(m, 'outsideNow'),
      pendingCorrections: jInt(m, 'pendingCorrections'),
      topPerformers: asMapList(m['topPerformers']).map(LeaderboardItem.fromJson).toList(),
    );
  }

  int get pendingApprovals => pendingLeaves + pendingRequests;
}

// ------------------------------------------------------------ recruitment / staff

class Job {
  final int id;
  final String title;
  final int? departmentId;
  final String? departmentName;
  final String location;
  final String type;
  final String description;
  final String? requirements;
  final String? salary;
  final String status;
  final int applicants;
  final DateTime? postedAt;
  const Job({required this.id, required this.title, this.departmentId, this.departmentName, this.location = '', this.type = '', this.description = '', this.requirements, this.salary, this.status = 'open', this.applicants = 0, this.postedAt});
  factory Job.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Job(id: jInt(m, 'id'), title: jStr(m, 'title'), departmentId: jIntN(m, 'departmentId'), departmentName: jStrN(m, 'departmentName'), location: jStr(m, 'location'), type: jStr(m, 'type'), description: jStr(m, 'description'), requirements: jStrN(m, 'requirements'), salary: jStrN(m, 'salary'), status: jStr(m, 'status', 'open'), applicants: jInt(m, 'applicantCount'), postedAt: jDate(m, 'postedAt'));
  }
}

class Application {
  final int id;
  final int? jobId;
  final String jobTitle;
  final String name;
  final String email;
  final String? phone;
  final String? coverLetter;
  final String? resumeUrl;
  final String status;
  final DateTime? appliedAt;
  const Application({required this.id, this.jobId, this.jobTitle = '', required this.name, this.email = '', this.phone, this.coverLetter, this.resumeUrl, this.status = 'new', this.appliedAt});
  factory Application.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Application(id: jInt(m, 'id'), jobId: jIntN(m, 'jobId'), jobTitle: jStr(m, 'jobTitle'), name: jStr(m, 'applicantName', jStr(m, 'name')), email: jStr(m, 'email'), phone: jStrN(m, 'phone'), coverLetter: jStrN(m, 'coverLetter'), resumeUrl: jStrN(m, 'resumeUrl'), status: jStr(m, 'status', 'new'), appliedAt: jDate(m, 'appliedAt'));
  }
}

class Review {
  final int id;
  final int employeeId;
  final String employeeName;
  final String reviewerName;
  final String period;
  final int rating;
  final String? goals;
  final String? achievements;
  final String? feedback;
  final String status;
  const Review({required this.id, required this.employeeId, this.employeeName = '', this.reviewerName = '', this.period = '', this.rating = 0, this.goals, this.achievements, this.feedback, this.status = 'draft'});
  factory Review.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Review(id: jInt(m, 'id'), employeeId: jInt(m, 'employeeId'), employeeName: jStr(m, 'employeeName'), reviewerName: jStr(m, 'reviewerName'), period: jStr(m, 'period'), rating: jInt(m, 'rating'), goals: jStrN(m, 'goals'), achievements: jStrN(m, 'achievements'), feedback: jStrN(m, 'feedback'), status: jStr(m, 'status', 'draft'));
  }
}

class StaffMember {
  final int id;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? title;
  final Map<String, bool> permissions;
  const StaffMember({required this.id, required this.name, required this.email, required this.role, this.status = 'active', this.title, this.permissions = const {}});
  factory StaffMember.fromJson(dynamic raw) {
    final m = asMap(raw);
    final perms = <String, bool>{};
    for (final p in asMapList(m['permissions'])) {
      perms[jStr(p, 'module')] = jBool(p, 'enabled', true);
    }
    return StaffMember(id: jInt(m, 'id'), name: jStr(m, 'name'), email: jStr(m, 'email'), role: jStr(m, 'role'), status: jStr(m, 'status', 'active'), title: jStrN(m, 'title'), permissions: perms);
  }
}

class Candidate {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? jobTitle;
  final int? departmentId;
  final String? departmentName;
  final String? notes;
  const Candidate({required this.id, required this.name, this.email = '', this.phone, this.jobTitle, this.departmentId, this.departmentName, this.notes});
  factory Candidate.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Candidate(id: jInt(m, 'id'), name: jStr(m, 'name'), email: jStr(m, 'email'), phone: jStrN(m, 'phone'), jobTitle: jStrN(m, 'jobTitle'), departmentId: jIntN(m, 'departmentId'), departmentName: jStrN(m, 'departmentName'), notes: jStrN(m, 'notes'));
  }
}


// ------------------------------------------------------------------ rewards / career / org

class PointEntry {
  final int id;
  final DateTime date;
  final String color; // green | red | black | none
  final String reason;
  final String source; // auto | manual
  final String? note;
  final bool voided;
  const PointEntry({required this.id, required this.date, required this.color, this.reason = '', this.source = 'auto', this.note, this.voided = false});
  factory PointEntry.fromJson(dynamic raw) {
    final m = asMap(raw);
    return PointEntry(id: jInt(m, 'id'), date: jDate(m, 'date') ?? DateTime.now(), color: jStr(m, 'color', 'none'), reason: jStr(m, 'reason'), source: jStr(m, 'source', 'auto'), note: jStrN(m, 'note'), voided: jBool(m, 'voided'));
  }
}

class PointsSummary {
  final bool enabled;
  final int rawGreen;
  final int rawRed;
  final int rawBlack;
  final int netGreen;
  final int netRed;
  final int netBlack;
  final int cancelledRed;
  final int cancelledBlack;
  final int greenSpent;
  final int streak;
  final int bestStreak;
  final int streakTarget;
  final int level;
  final String levelName;
  final String nextLevelName;
  final Map<String, int> thisMonth;
  final List<PointEntry> history;
  final int redCost;
  final int blackCost;
  final List<String> levels;
  const PointsSummary({
    this.enabled = true,
    this.rawGreen = 0,
    this.rawRed = 0,
    this.rawBlack = 0,
    this.netGreen = 0,
    this.netRed = 0,
    this.netBlack = 0,
    this.cancelledRed = 0,
    this.cancelledBlack = 0,
    this.greenSpent = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.streakTarget = 30,
    this.level = 0,
    this.levelName = '',
    this.nextLevelName = '',
    this.thisMonth = const {},
    this.history = const [],
    this.redCost = 2,
    this.blackCost = 5,
    this.levels = const [],
  });

  factory PointsSummary.fromJson(dynamic raw) {
    final m = asMap(raw);
    final raws = asMap(m['raw']);
    final net = asMap(m['net']);
    final can = asMap(m['cancelled']);
    final rules = asMap(m['rules']);
    return PointsSummary(
      enabled: jBool(m, 'enabled', true),
      rawGreen: jInt(raws, 'green'),
      rawRed: jInt(raws, 'red'),
      rawBlack: jInt(raws, 'black'),
      netGreen: jInt(net, 'green'),
      netRed: jInt(net, 'red'),
      netBlack: jInt(net, 'black'),
      cancelledRed: jInt(can, 'red'),
      cancelledBlack: jInt(can, 'black'),
      greenSpent: jInt(m, 'greenSpent'),
      streak: jInt(m, 'streak'),
      bestStreak: jInt(m, 'bestStreak'),
      streakTarget: jInt(m, 'streakTarget', 30),
      level: jInt(m, 'level'),
      levelName: jStr(m, 'levelName'),
      nextLevelName: jStr(m, 'nextLevelName'),
      thisMonth: asMap(m['thisMonth']).map((k, v) => MapEntry(k, v is num ? v.toInt() : int.tryParse('$v') ?? 0)),
      history: asMapList(m['history']).map(PointEntry.fromJson).toList(),
      redCost: jInt(rules, 'redCost', 2),
      blackCost: jInt(rules, 'blackCost', 5),
      levels: (rules['levels'] is List) ? (rules['levels'] as List).map((e) => e.toString()).toList() : const [],
    );
  }
}

class LeaderboardItem {
  final int rank;
  final int employeeId;
  final String name;
  final String? avatar;
  final String? position;
  final String? department;
  final int level;
  final String levelName;
  final int streak;
  final int green;
  final int red;
  final int black;
  final int score;
  const LeaderboardItem({this.rank = 0, required this.employeeId, required this.name, this.avatar, this.position, this.department, this.level = 0, this.levelName = '', this.streak = 0, this.green = 0, this.red = 0, this.black = 0, this.score = 0});
  factory LeaderboardItem.fromJson(dynamic raw) {
    final m = asMap(raw);
    return LeaderboardItem(rank: jInt(m, 'rank'), employeeId: jInt(m, 'employeeId'), name: jStr(m, 'name'), avatar: jStrN(m, 'avatar'), position: jStrN(m, 'position'), department: jStrN(m, 'departmentName'), level: jInt(m, 'level'), levelName: jStr(m, 'levelName'), streak: jInt(m, 'streak'), green: jInt(m, 'green'), red: jInt(m, 'red'), black: jInt(m, 'black'), score: jInt(m, 'score'));
  }
}

class Promotion {
  final int id;
  final String type; // promotion | raise | transfer | demotion
  final String? fromPosition;
  final String? toPosition;
  final double? fromSalary;
  final double? toSalary;
  final String? fromDepartment;
  final String? toDepartment;
  final DateTime date;
  final bool applied;
  final String? note;
  final String? by;
  const Promotion({required this.id, required this.type, this.fromPosition, this.toPosition, this.fromSalary, this.toSalary, this.fromDepartment, this.toDepartment, required this.date, this.applied = true, this.note, this.by});
  factory Promotion.fromJson(dynamic raw) {
    final m = asMap(raw);
    return Promotion(
      id: jInt(m, 'id'),
      type: jStr(m, 'type', 'promotion'),
      fromPosition: jStrN(m, 'fromPosition'),
      toPosition: jStrN(m, 'toPosition'),
      fromSalary: jDoubleN(m, 'fromSalary'),
      toSalary: jDoubleN(m, 'toSalary'),
      fromDepartment: jStrN(m, 'fromDepartmentName'),
      toDepartment: jStrN(m, 'toDepartmentName'),
      date: jDate(m, 'effectiveDate') ?? DateTime.now(),
      applied: jBool(m, 'applied', true),
      note: jStrN(m, 'note'),
      by: jStrN(m, 'createdByName'),
    );
  }
}

class OrgPerson {
  final int id;
  final String name;
  final String position;
  final String? avatar;
  final List<OrgPerson> reports;
  const OrgPerson({required this.id, required this.name, this.position = '', this.avatar, this.reports = const []});
  factory OrgPerson.fromJson(dynamic raw) {
    final m = asMap(raw);
    return OrgPerson(
      id: jInt(m, 'id'),
      name: '${jStr(m, 'firstName')} ${jStr(m, 'lastName')}'.trim(),
      position: jStr(m, 'position'),
      avatar: jStrN(m, 'avatar'),
      reports: asMapList(m['reports']).map(OrgPerson.fromJson).toList(),
    );
  }
}

class OrgDepartment {
  final int id;
  final String name;
  final OrgPerson? head;
  final List<OrgPerson> members;
  const OrgDepartment({required this.id, required this.name, this.head, this.members = const []});
  factory OrgDepartment.fromJson(dynamic raw) {
    final m = asMap(raw);
    return OrgDepartment(id: jInt(m, 'id'), name: jStr(m, 'name'), head: m['head'] is Map ? OrgPerson.fromJson(m['head']) : null, members: asMapList(m['members']).map(OrgPerson.fromJson).toList());
  }
}

class OrgData {
  final List<OrgDepartment> departments;
  final List<OrgPerson> unassigned;
  final List<OrgPerson> tree;
  const OrgData({this.departments = const [], this.unassigned = const [], this.tree = const []});
  factory OrgData.fromJson(dynamic raw) {
    final m = asMap(raw);
    return OrgData(
      departments: asMapList(m['departments']).map(OrgDepartment.fromJson).toList(),
      unassigned: asMapList(m['unassigned']).map(OrgPerson.fromJson).toList(),
      tree: asMapList(m['tree']).map(OrgPerson.fromJson).toList(),
    );
  }
}

class AuditEntry {
  final int id;
  final String user;
  final String action;
  final String entity;
  final int? entityId;
  final String details;
  final DateTime? at;
  const AuditEntry({required this.id, this.user = '', required this.action, required this.entity, this.entityId, this.details = '', this.at});
  factory AuditEntry.fromJson(dynamic raw) {
    final m = asMap(raw);
    final d = m['details'];
    return AuditEntry(id: jInt(m, 'id'), user: jStr(m, 'userName'), action: jStr(m, 'action'), entity: jStr(m, 'entity'), entityId: jIntN(m, 'entityId'), details: d == null ? '' : (d is String ? d : d.toString()), at: jDate(m, 'createdAt'));
  }
}
