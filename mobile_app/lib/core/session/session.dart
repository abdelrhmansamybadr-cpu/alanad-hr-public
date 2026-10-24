import '../config.dart';
import '../push/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/theme.dart';
import '../../features/group/group_models.dart';
import '../api/api.dart';
import '../models/models.dart';

enum SessionStatus { loading, signedOut, signedIn, offline }

class SessionState {
  final SessionStatus status;
  final AppUser? user;
  final Company? company;
  /// The holding this company belongs to and the companies the person may enter (null outside a group).
  final GroupInfo? group;
  final String? notice; // e.g. "session expired" shown on the welcome screen

  const SessionState({this.status = SessionStatus.loading, this.user, this.company, this.group, this.notice});

  bool get isSignedIn => status == SessionStatus.signedIn && user != null && company != null;

  SessionState copyWith({SessionStatus? status, AppUser? user, Company? company, GroupInfo? group, String? notice}) =>
      SessionState(status: status ?? this.status, user: user ?? this.user, company: company ?? this.company, group: group ?? this.group, notice: notice);
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this._ref) : super(const SessionState()) {
    // The API client tells us when the server rejected our token.
    _ref.listen<int>(unauthorizedSignalProvider, (_, __) {
      if (state.status == SessionStatus.signedIn) signOut(expired: true);
    });
    restore();
  }

  final Ref _ref;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'session_token_v2';

  Api get _api => _ref.read(apiProvider);

  /// Called at start-up: reuse the saved token if it is still valid.
  Future<void> restore() async {
    state = const SessionState(status: SessionStatus.loading);
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }
    _api.token = token;
    try {
      final data = await _api.get('/auth/me');
      _applyMe(data);
    } on ApiException catch (e) {
      if (e.isNetwork || (e.status ?? 0) >= 500) {
        state = const SessionState(status: SessionStatus.offline);
      } else {
        await _clear();
        state = const SessionState(status: SessionStatus.signedOut);
      }
    }
  }

  bool _pushOn = false;

  void _applyMe(dynamic data) {
    final m = data is Map ? data : const {};
    if (!_pushOn) {
      _pushOn = true;
      PushService.enable();
    }
    state = SessionState(
      status: SessionStatus.signedIn,
      user: AppUser.fromJson(m['user'] ?? m),
      company: Company.fromJson(m['company']),
      group: GroupInfo.fromJsonN(m['group']),
    );
  }

  /// Work inside another company of the group. The server checks every switch; the answer is the new /auth/me.
  Future<void> switchCompany(int companyId) async {
    _applyMe(await _api.post('/group/switch', {'companyId': companyId}));
  }

  /// Store the result of a successful login / activation / company sign-up.
  Future<void> signIn(dynamic data) async {
    final m = data is Map ? data : const {};
    final token = m['token']?.toString();
    if (token == null) throw const ApiException('Sign-in failed. Please try again.');
    await _storage.write(key: _tokenKey, value: token);
    _api.token = token;
    _applyMe(m);
  }

  /// Reload the user + company (after editing the profile or the company settings).
  Future<void> refresh() async {
    try {
      _applyMe(await _api.get('/auth/me'));
    } on ApiException {
      // keep the current state; the next call will surface real problems
    }
  }

  Future<void> signOut({bool expired = false}) async {
    if (!expired) {
      try {
        await _api.post('/auth/logout');
      } on ApiException {
        // signing out locally is enough
      }
    }
    await _clear();
    state = SessionState(status: SessionStatus.signedOut, notice: expired ? 'expired' : null);
  }

  Future<void> _clear() async {
    _pushOn = false;
    PushService.disable();
    await _storage.delete(key: _tokenKey);
    _api.token = null;
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) => SessionNotifier(ref));

/// The company's colours (or the product defaults before sign-in).
final brandProvider = Provider<Brand>((ref) {
  final c = ref.watch(sessionProvider).company;
  // Al Anad edition: the app always uses the Al Anad brand colours, whatever the company record says.
  if (AppConfig.lockBrand) return Brand.fallback;
  return c == null ? Brand.fallback : Brand(Color(c.primary), Color(c.accent));
});
