import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';

/// Description of a newer release published on the server.
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? sha256;
  final String notes;
  final bool mandatory;

  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.sha256,
    this.notes = '',
    this.mandatory = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        versionCode: (j['versionCode'] as num).toInt(),
        versionName: j['versionName'] as String? ?? '',
        apkUrl: j['apkUrl'] as String,
        sha256: j['sha256'] as String?,
        notes: j['notes'] as String? ?? '',
        mandatory: j['mandatory'] as bool? ?? false,
      );
}

/// Where the release script publishes the latest version info.
String get updateManifestUrl => '${AppConfig.baseUrl}/app/alanad/version.json';

/// Returns the published release if it is newer than the installed app, else null.
/// Never throws: no network / no manifest simply means "no update".
Future<UpdateInfo?> fetchAvailableUpdate() async {
  if (!Platform.isAndroid) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final installed = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    // A changing query string makes the host's CDN fetch the current file instead of a cached older one.
    final request = await client.getUrl(Uri.parse('$updateManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final info = UpdateInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
    return info.versionCode > installed ? info : null;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Wraps the whole app: checks for a new release shortly after start-up and,
/// if there is one, shows an "Update available" card with download progress.
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  UpdateInfo? _update;
  bool _dismissed = false;
  bool _busy = false;
  int? _percent;
  String? _error;
  StreamSubscription<OtaEvent>? _sub;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), _check);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final info = await fetchAvailableUpdate();
    if (mounted && info != null) setState(() => _update = info);
  }

  void _install(bool ar) {
    final info = _update!;
    setState(() {
      _busy = true;
      _percent = 0;
      _error = null;
    });
    try {
      _sub = OtaUpdate()
          .execute(
        info.apkUrl,
        destinationFilename: 'hr-update-${info.versionCode}.apk',
        sha256checksum: info.sha256,
      )
          .listen((event) {
        if (!mounted) return;
        setState(() {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              _percent = int.tryParse(event.value ?? '') ?? _percent;
            case OtaStatus.INSTALLING:
              _percent = 100;
              _busy = false; // the system installer takes over
            case OtaStatus.CHECKSUM_ERROR:
              _busy = false;
              _error = ar ? 'الملف غير سليم، حاول مرة أخرى' : 'The downloaded file is invalid. Please try again.';
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _busy = false;
              _error = ar ? 'اسمح بتثبيت التطبيقات من هذا المصدر ثم حاول مرة أخرى' : 'Allow installing apps from this source, then try again.';
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.INSTALLATION_ERROR:
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.CANCELED:
              _busy = false;
              _error = ar ? 'تعذر التحديث، حاول مرة أخرى' : 'Update failed. Please try again.';
            default:
              break;
          }
        });
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = ar ? 'تعذر التحديث، حاول مرة أخرى' : 'Update failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _update;
    final show = info != null && (!_dismissed || info.mandatory);
    if (!show) return widget.child;

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final scheme = Theme.of(context).colorScheme;

    final card = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.system_update, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ar ? 'يتوفر تحديث جديد' : 'New update available',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${ar ? 'الإصدار' : 'Version'} ${info.versionName}'),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(info.notes),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: (_percent ?? 0) / 100),
              const SizedBox(height: 6),
              Text(ar ? 'جاري التحميل ${_percent ?? 0}%' : 'Downloading ${_percent ?? 0}%'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            // The app theme gives buttons an infinite minimum width, so each one must be Expanded
            // inside a Row (otherwise they collapse and the dialog shows no buttons at all).
            Row(
              children: [
                if (!info.mandatory && !_busy) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => setState(() => _dismissed = true),
                      child: Text(ar ? 'لاحقاً' : 'Later'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _busy ? null : () => _install(ar),
                    child: Text(ar ? 'تحديث الآن' : 'Update now'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: card),
            ),
          ),
        ),
      ],
    );
  }
}
