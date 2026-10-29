import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/api/api.dart';
import 'cert_model.dart';

// ---------------------------------------------------------------- pictures (protected: fetched with the login token)

final _assetCache = <int, Future<ui.Image>>{};

Future<ui.Image> loadCertAsset(Api api, int id) => _assetCache.putIfAbsent(id, () async {
      try {
        final bytes = await api.getBytes('/certificates/assets/$id');
        final codec = await ui.instantiateImageCodec(bytes);
        return (await codec.getNextFrame()).image;
      } catch (_) {
        _assetCache.remove(id);       // try again next time
        rethrow;
      }
    });

/// Every picture a design uses (background + picture blocks). A missing picture is simply not drawn.
Future<Map<int, ui.Image>> loadCertImages(Api api, CertTemplate t) async {
  final ids = <int>{if (t.bgAssetId != null) t.bgAssetId!, for (final b in t.blocks) if (b.isImage && b.asset > 0) b.asset};
  final out = <int, ui.Image>{};
  await Future.wait(ids.map((id) async {
    try {
      out[id] = await loadCertAsset(api, id);
    } catch (_) {/* not drawn */}
  }));
  return out;
}

// ---------------------------------------------------------------- layout

final _rtlChars = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');

class LaidBlock {
  final CertBlock block;
  final Rect rect; // in design pixels
  final List<(TextPainter, Offset)> lines;
  LaidBlock(this.block, this.rect, this.lines);
}

String _fill(String text, Map<String, String> v) => text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => v[m[1]] ?? '');

TextStyle _style(CertBlock b, double px) => TextStyle(
      fontSize: px,
      height: b.lh,
      color: b.color,
      fontWeight: b.bold ? FontWeight.w800 : FontWeight.w400,
      fontStyle: b.italic ? FontStyle.italic : FontStyle.normal,
      fontFamily: b.font == 'serif' ? 'Georgia' : (b.font == 'mono' ? 'Courier New' : null),
      fontFamilyFallback: b.font == 'serif' ? const ['Times New Roman', 'Noto Serif', 'serif'] : (b.font == 'mono' ? const ['Roboto Mono', 'monospace'] : const ['Segoe UI', 'Noto Sans Arabic', 'Roboto']),
    );

/// Lay every block out (wrapping, alignment, Arabic direction). Used both to draw and to place the drag handles.
List<LaidBlock> layoutCert(CertTemplate t, Map<String, String> values, Map<int, ui.Image> images) {
  final out = <LaidBlock>[];
  for (final b in t.blocks) {
    final bx = b.x / 100 * t.width, by = b.y / 100 * t.height, bw = b.w / 100 * t.width;
    if (b.isImage) {
      out.add(LaidBlock(b, Rect.fromLTWH(bx, by, bw, b.h / 100 * t.height), const []));
      continue;
    }
    final px = b.size / 100 * t.height;
    final align = switch (b.align) { 'left' => TextAlign.left, 'right' => TextAlign.right, _ => TextAlign.center };
    var y = by;
    final lines = <(TextPainter, Offset)>[];
    for (final para in _fill(b.text, values).split('\n')) {
      final tp = TextPainter(
        text: TextSpan(text: para.isEmpty ? ' ' : para, style: _style(b, px)),
        textDirection: _rtlChars.hasMatch(para) ? TextDirection.rtl : TextDirection.ltr,
        textAlign: align,
      )..layout(minWidth: bw, maxWidth: bw);
      lines.add((tp, Offset(bx, y)));
      y += tp.height;
    }
    out.add(LaidBlock(b, Rect.fromLTWH(bx, by, bw, (y - by) < px ? px * b.lh : (y - by)), lines));
  }
  return out;
}

void paintCert(Canvas canvas, CertTemplate t, List<LaidBlock> laid, Map<int, ui.Image> images) {
  final W = t.width, H = t.height;
  canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = t.bgColor);
  final bg = t.bgAssetId == null ? null : images[t.bgAssetId!];
  if (bg != null) {
    canvas.drawImageRect(bg, Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()), Rect.fromLTWH(0, 0, W, H), Paint()..filterQuality = FilterQuality.high);
  }
  final f = t.frame;
  if (f.style != 'none') {
    final p = Paint()..style = PaintingStyle.stroke..color = f.color..strokeWidth = f.width;
    canvas.drawRect(Rect.fromLTWH(f.inset, f.inset, W - 2 * f.inset, H - 2 * f.inset), p);
    if (f.style == 'double') {
      final g = f.inset + f.width * 2.4;
      p.strokeWidth = (f.width / 3).clamp(1, 100).toDouble();
      canvas.drawRect(Rect.fromLTWH(g, g, W - 2 * g, H - 2 * g), p);
    }
  }
  for (final l in laid) {
    if (l.block.isImage) {
      final img = l.block.asset > 0 ? images[l.block.asset] : null;
      if (img == null) {
        canvas.drawRect(l.rect, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF9CA3AF)..strokeWidth = 1);
      } else {
        final r = (l.rect.width / img.width) < (l.rect.height / img.height) ? l.rect.width / img.width : l.rect.height / img.height;
        final dw = img.width * r, dh = img.height * r;
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(l.rect.left + (l.rect.width - dw) / 2, l.rect.top + (l.rect.height - dh) / 2, dw, dh), Paint()..filterQuality = FilterQuality.high);
      }
      continue;
    }
    for (final (tp, off) in l.lines) {
      tp.paint(canvas, off);
    }
  }
}

class CertPainter extends CustomPainter {
  final CertTemplate template;
  final List<LaidBlock> laid;
  final Map<int, ui.Image> images;
  CertPainter(this.template, this.laid, this.images);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / template.width, size.height / template.height);
    paintCert(canvas, template, laid, images);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CertPainter old) => true;
}

/// The finished certificate as PNG bytes (the server turns it into a JPG + PDF).
Future<Uint8List> renderCertPng(CertTemplate t, Map<String, String> values, Map<int, ui.Image> images, {double scale = 1.5}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(scale);
  paintCert(canvas, t, layoutCert(t, values, images), images);
  final img = await rec.endRecording().toImage((t.width * scale).round(), (t.height * scale).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ---------------------------------------------------------------- values for the placeholders

const _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String certDate(DateTime? d, String lang) => d == null ? '' : '${d.day} ${(lang == 'ar' ? _arMonths : _enMonths)[d.month - 1]} ${d.year}';

String _arCount(int n, String one, String two, String few, String many) => n == 1 ? one : (n == 2 ? two : (n >= 3 && n <= 10 ? '$n $few' : '$n $many'));

/// "2 years and 3 months" / "سنتان و3 أشهر" between two dates, both days counted.
String certDuration(DateTime? a, DateTime? b, String lang) {
  if (a == null || b == null || b.isBefore(a)) return '';
  var y = b.year - a.year, m = b.month - a.month, d = b.day - a.day + 1;
  if (d < 0) {
    m -= 1;
    d += DateTime(b.year, b.month, 0).day;
  }
  if (m < 0) {
    y -= 1;
    m += 12;
  }
  final parts = <String>[];
  if (lang == 'ar') {
    if (y > 0) parts.add(_arCount(y, 'سنة', 'سنتان', 'سنوات', 'سنة'));
    if (m > 0) parts.add(_arCount(m, 'شهر', 'شهران', 'أشهر', 'شهرًا'));
    if (y == 0 && m == 0) parts.add(_arCount(d < 1 ? 1 : d, 'يوم', 'يومان', 'أيام', 'يومًا'));
    return parts.join(' و');
  }
  if (y > 0) parts.add('$y year${y == 1 ? '' : 's'}');
  if (m > 0) parts.add('$m month${m == 1 ? '' : 's'}');
  if (y == 0 && m == 0) parts.add('${d < 1 ? 1 : d} day${d == 1 ? '' : 's'}');
  return parts.join(' and ');
}

/// Keeps a code such as CERT-2026-0001 in its own left-to-right run inside Arabic text (otherwise the parts swap places).
String _ltr(String v, String lang) => lang == 'ar' ? '\u2066$v\u2069' : v;

Map<String, String> buildCertValues({
  required String firstName,
  required String lastName,
  String position = '',
  String department = '',
  required String company,
  required String serial,
  required DateTime issueDate,
  DateTime? startDate,
  DateTime? endDate,
  required String lang,
  String note = '',
}) =>
    {
      'name': '$firstName $lastName'.trim(),
      'first_name': firstName,
      'last_name': lastName,
      'position': position,
      'department': department,
      'company': company,
      'start_date': certDate(startDate, lang),
      'end_date': certDate(endDate, lang),
      'issue_date': certDate(issueDate, lang),
      'duration': certDuration(startDate, endDate, lang),
      'serial': _ltr(serial, lang),
      'note': note,
    };

Map<String, String> sampleCertValues(String lang) => buildCertValues(
      firstName: lang == 'ar' ? 'محمد أحمد' : 'Mohamed Ahmed',
      lastName: lang == 'ar' ? 'علي' : 'Ali',
      position: lang == 'ar' ? 'محاسب أول' : 'Senior Accountant',
      department: lang == 'ar' ? 'المالية' : 'Finance',
      company: lang == 'ar' ? 'اسم الشركة' : 'Company name',
      serial: 'CERT-2026-0001',
      issueDate: DateTime(2026, 3, 5),
      startDate: DateTime(2022, 3, 1),
      endDate: DateTime(2026, 3, 1),
      lang: lang,
    );
