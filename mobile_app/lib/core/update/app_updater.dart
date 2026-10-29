import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
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
        apkUrl: (j['apkUrl'] ?? j['installerUrl']) as String,
        sha256: j['sha256'] as String?,
        notes: j['notes'] as String? ?? '',
        mandatory: j['mandatory'] as bool? ?? false,
      );
}

/// Where the release script publishes the latest version info.
String get updateManifestUrl => '${AppConfig.baseUrl}/app/alanad/version.json';

/// The laptop (Windows) app has its own manifest next to the phone one: it points at the Setup installer.
String get windowsManifestUrl => updateManifestUrl.replaceFirst('version.json', 'windows.json');

/// The update the app should offer right now (set by the start-up check and by "Check for updates" in Settings).
final ValueNotifier<UpdateInfo?> availableUpdate = ValueNotifier<UpdateInfo?>(null);

/// Looks for a newer release and, when there is one, makes the "Update available" card appear. Returns it (or null).
Future<UpdateInfo?> checkForUpdate() async {
  final info = await fetchAvailableUpdate();
  availableUpdate.value = null; // a fresh value always re-opens the card, even for the same version
  availableUpdate.value = info;
  return info;
}

/// Returns the published release if it is newer than the installed app, else null.
/// Never throws: no network / no manifest simply means "no update".
Future<UpdateInfo?> fetchAvailableUpdate() async {
  if (!Platform.isAndroid && !Platform.isWindows) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final installed = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    // A changing query string makes the host's CDN fetch the current file instead of a cached older one.
    final request = await client.getUrl(Uri.parse('${Platform.isWindows ? windowsManifestUrl : updateManifestUrl}?t=${DateTime.now().millisecondsSinceEpoch}'));
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
    availableUpdate.addListener(_onUpdate);
    Future<void>.delayed(const Duration(seconds: 2), checkForUpdate);
  }

  @override
  void dispose() {
    availableUpdate.removeListener(_onUpdate);
    _sub?.cancel();
    super.dispose();
  }

  void _onUpdate() {
    final info = availableUpdate.value;
    if (mounted && info != null) {
      setState(() {
        _update = info;
        _dismissed = false;
        _error = null;
      });
    }
  }

  /// Laptop: download the Setup installer, check it, run it silently (it closes this app, upgrades it and starts it again).
  Future<void> _installWindows(UpdateInfo info, bool ar) async {
    setState(() {
      _busy = true;
      _percent = 0;
      _error = null;
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}AlAnadHR-update-${info.versionCode}.exe');
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('status ${response.statusCode}');
      final total = response.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && mounted) setState(() => _percent = (got * 100 ~/ total).clamp(0, 100));
      }
      await sink.flush();
      await sink.close();
      final want = info.sha256;
      if (want != null && want.isNotEmpty) {
        final have = (await crypto.sha256.bind(file.openRead()).first).toString();
        if (have.toLowerCase() != want.toLowerCase()) {
          await file.delete().catchError((_) => file);
          if (mounted) {
            setState(() {
              _busy = false;
              _error = ar ? 'الملف غير سليم، حاول مرة أخرى' : 'The downloaded file is invalid. Please try again.';
            });
          }
          return;
        }
      }
      await Process.start(file.path, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'], mode: ProcessStartMode.detached);
      exit(0);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ar ? 'تعذر التحديث، حاول مرة أخرى' : 'Update failed. Please try again.';
        });
      }
    } finally {
      client.close();
    }
  }

  void _install(bool ar) {
    final info = _update!;
    if (Platform.isWindows) {
      _installWindows(info, ar);
      return;
    }
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
