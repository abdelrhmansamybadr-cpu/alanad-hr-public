import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';

/// An error from the server (or the network) with a message that is safe to show to the user.
class ApiException implements Exception {
  final String message;
  final int? status;
  const ApiException(this.message, {this.status});

  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Thin JSON client over Dio. Every call returns decoded JSON (Map / List) or throws [ApiException].
class Api {
  Api(this._onUnauthorized) {
    _dio = Dio(BaseOptions(
      baseUrl: '${AppConfig.baseUrl}/api',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json', if (AppConfig.appId.isNotEmpty) 'X-App-Id': AppConfig.appId},
      validateStatus: (_) => true, // we map status codes ourselves
    ));
  }

  late final Dio _dio;
  final void Function() _onUnauthorized;
  /// Bearer token of the signed-in user (owned by the session notifier).
  String? token;

  Options get _opts => Options(headers: {if (token != null) 'Authorization': 'Bearer $token'});

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(() => _dio.get(path, queryParameters: query, options: _opts));
  Future<dynamic> post(String path, [Object? body]) => _send(() => _dio.post(path, data: body, options: _opts));
  Future<dynamic> put(String path, [Object? body]) => _send(() => _dio.put(path, data: body, options: _opts));
  Future<dynamic> delete(String path) => _send(() => _dio.delete(path, options: _opts));

  /// Multipart upload (`file` field) — used for avatars, logos and documents.
  Future<dynamic> upload(String path, String filePath, {String field = 'file', String? filename}) async {
    final form = FormData.fromMap({field: await MultipartFile.fromFile(filePath, filename: filename)});
    return _send(() => _dio.post(path, data: form, options: _opts));
  }

  /// Downloads a protected file (e.g. an employee document) to [savePath].
  Future<void> download(String path, String savePath) async {
    try {
      final r = await _dio.download(path.startsWith('/api') ? '${AppConfig.baseUrl}$path' : path, savePath, options: _opts);
      if ((r.statusCode ?? 500) >= 400) throw const ApiException('Could not download the file');
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<dynamic> _send(Future<Response> Function() call) async {
    try {
      final res = await call();
      final code = res.statusCode ?? 0;
      final data = res.data is String && (res.data as String).isNotEmpty ? _tryDecode(res.data as String) : res.data;
      if (code >= 200 && code < 300) return data;
      if (code == 401) _onUnauthorized();
      throw ApiException(_messageFrom(data, code), status: code);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static dynamic _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static String _messageFrom(dynamic data, int code) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    switch (code) {
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do this.';
      case 404:
        return 'Not found.';
      case 429:
        return 'Too many attempts. Please try again in a few minutes.';
      default:
        return code >= 500 ? 'The server had a problem. Please try again.' : 'Something went wrong ($code).';
    }
  }

  static ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException('The connection timed out. Check your internet and try again.');
      case DioExceptionType.connectionError:
        return const ApiException('Cannot reach the server. Check your internet connection.');
      default:
        return ApiException(e.message ?? 'Something went wrong. Please try again.');
    }
  }
}

/// The single API client. The session notifier owns its token; a 401 signs the user out.
final apiProvider = Provider<Api>((ref) {
  final api = Api(() => ref.read(unauthorizedSignalProvider.notifier).state++);
  return api;
});

/// Incremented when the server answers 401 — the session notifier listens and signs out.
final unauthorizedSignalProvider = StateProvider<int>((ref) => 0);
