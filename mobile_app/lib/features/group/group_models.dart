import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/models/json.dart';

/// Parts of a company that can be handed out in a "chosen parts" access (same names as the server).
const groupModules = ['dashboard', 'employees', 'departments', 'leaves', 'attendance', 'shifts', 'payroll', 'recruitment', 'talent_pool', 'reviews', 'announcements', 'documents', 'hr_staff', 'requests'];

/// One company of the group, with what the signed-in person may do inside it.
class GroupCompany {
  final int id;
  final String name;
  final String status;
  final bool isHome;
  final String? ceoName;
  final String? ceoEmail;
  final String level; // home | super | full | custom
  final bool readOnly;
  final int employeeCount;
  final int departmentCount;
  /// The owner keeps it for himself: a Super Admin sees it only when the owner gave him access.
  final bool ownerManaged;
  /// Names of the HR managers who run this company (its own HR accounts + people given access).
  final List<String> managerNames;

  const GroupCompany({required this.id, required this.name, required this.status, required this.isHome, this.ceoName, this.ceoEmail, required this.level, required this.readOnly, this.employeeCount = 0, this.departmentCount = 0, this.ownerManaged = false, this.managerNames = const []});

  bool get active => status == 'active';

  factory GroupCompany.fromJson(Map<String, dynamic> m) {
    final access = asMap(m['access']);
    final ceo = asMap(m['ceo']);
    return GroupCompany(
      id: jInt(m, 'id'),
      name: jStr(m, 'name'),
      status: jStr(m, 'status', 'active'),
      isHome: jBool(m, 'isHome'),
      ceoName: jStrN(ceo, 'name'),
      ceoEmail: jStrN(ceo, 'email'),
      level: jStr(access, 'level', 'home'),
      readOnly: jBool(access, 'readOnly'),
      employeeCount: jInt(m, 'employeeCount'),
      departmentCount: jInt(m, 'departmentCount'),
      ownerManaged: jBool(m, 'ownerManaged'),
      managerNames: [for (final x in asMapList(m['managers'])) jStr(x, 'name')],
    );
  }
}

/// The holding company and the companies the signed-in person can enter.
class GroupInfo {
  final int id;
  final String name;
  final bool isSuperAdmin;
  /// The platform owner: creates companies and decides which HR managers run each one.
  final bool isOwner;
  final int homeCompanyId;
  final int activeCompanyId;
  final List<GroupCompany> companies;

  const GroupInfo({required this.id, required this.name, required this.isSuperAdmin, this.isOwner = false, required this.homeCompanyId, required this.activeCompanyId, required this.companies});

  /// More than one company to choose from -> show the switcher.
  bool get canSwitch => companies.length > 1;

  GroupCompany? get active {
    for (final c in companies) {
      if (c.id == activeCompanyId) return c;
    }
    return null;
  }

  static GroupInfo? fromJsonN(dynamic v) => v is Map ? GroupInfo.fromJson(asMap(v)) : null;

  /// Accepts both shapes the server sends: the flat block of the sign-in answer and the `/group/companies` answer.
  factory GroupInfo.fromJson(Map<String, dynamic> m) {
    final g = m['group'] is Map ? asMap(m['group']) : m;
    return GroupInfo(
      id: jInt(g, 'id'),
      name: jStr(g, 'name'),
      isSuperAdmin: jBool(m, 'isSuperAdmin'),
      isOwner: jBool(m, 'isOwner'),
      homeCompanyId: jInt(m, 'homeCompanyId'),
      activeCompanyId: jInt(m, 'activeCompanyId'),
      companies: asMapList(m['companies']).map(GroupCompany.fromJson).toList(),
    );
  }
}

/// An HR account of the group (to pick who receives access).
class GroupPerson {
  final int id;
  final String name;
  final String email;
  final String role;
  final int companyId;
  final String companyName;
  final bool isSuperAdmin;
  const GroupPerson({required this.id, required this.name, required this.email, required this.role, required this.companyId, required this.companyName, this.isSuperAdmin = false});

  factory GroupPerson.fromJson(Map<String, dynamic> m) => GroupPerson(
        id: jInt(m, 'id'), name: jStr(m, 'name'), email: jStr(m, 'email'), role: jStr(m, 'role'), companyId: jInt(m, 'companyId'), companyName: jStr(m, 'companyName'), isSuperAdmin: jInt(m, 'isSuperAdmin') > 0);
}

/// One extra-access grant: [userName] may work inside [companyName].
class AccessGrant {
  final int id;
  final int userId;
  final String userName;
  final String userEmail;
  final String homeCompanyName;
  final int companyId;
  final String companyName;
  final String level; // full | custom
  final List<String> modules;
  final bool readOnly;
  const AccessGrant({required this.id, required this.userId, required this.userName, required this.userEmail, required this.homeCompanyName, required this.companyId, required this.companyName, required this.level, required this.modules, required this.readOnly});

  factory AccessGrant.fromJson(Map<String, dynamic> m) => AccessGrant(
        id: jInt(m, 'id'),
        userId: jInt(m, 'userId'),
        userName: jStr(m, 'userName'),
        userEmail: jStr(m, 'userEmail'),
        homeCompanyName: jStr(m, 'homeCompanyName'),
        companyId: jInt(m, 'companyId'),
        companyName: jStr(m, 'companyName'),
        level: jStr(m, 'level', 'full'),
        modules: m['modules'] is List ? (m['modules'] as List).map((e) => '$e').toList() : const [],
        readOnly: jBool(m, 'readOnly'),
      );
}

/// One HR admin / HR manager account of the group, as the owner sees it (any status).
class HrAccount {
  final int id;
  final String name;
  final String email;
  final String role; // hr_admin | hr_manager
  final String status; // active | suspended | disabled
  final String companyName;
  final bool isSuperAdmin;
  final bool isOwner;
  final int extraCompanies;
  final DateTime? lastLoginAt;
  const HrAccount({required this.id, required this.name, required this.email, required this.role, required this.status, required this.companyName, required this.isSuperAdmin, required this.isOwner, required this.extraCompanies, this.lastLoginAt});

  bool get isActive => status == 'active';

  factory HrAccount.fromJson(Map<String, dynamic> m) => HrAccount(
        id: jInt(m, 'id'),
        name: jStr(m, 'name'),
        email: jStr(m, 'email'),
        role: jStr(m, 'role'),
        status: jStr(m, 'status', 'active'),
        companyName: jStr(m, 'companyName'),
        isSuperAdmin: jBool(m, 'isSuperAdmin'),
        isOwner: jBool(m, 'isOwner'),
        extraCompanies: jInt(m, 'extraCompanies'),
        lastLoginAt: jDate(m, 'lastLoginAt'),
      );
}

List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) parse) => data is List ? data.whereType<Map>().map((e) => parse(asMap(e))).toList() : <T>[];

/// Super admin: every company of the group with employee and department counts.
final groupCompaniesProvider = FutureProvider.autoDispose<GroupInfo>((ref) async => GroupInfo.fromJson(asMap(await ref.read(apiProvider).get('/group/companies'))));
final groupPeopleProvider = FutureProvider.autoDispose<List<GroupPerson>>((ref) async => _list(await ref.read(apiProvider).get('/group/people'), GroupPerson.fromJson));
final hrAccountsProvider = FutureProvider.autoDispose<List<HrAccount>>((ref) async => _list(await ref.read(apiProvider).get('/group/hr-accounts'), HrAccount.fromJson));
final groupAccessProvider = FutureProvider.autoDispose<List<AccessGrant>>((ref) async => _list(await ref.read(apiProvider).get('/group/access'), AccessGrant.fromJson));
