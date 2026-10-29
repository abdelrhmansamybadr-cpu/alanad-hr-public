import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_mobile_app/features/certificates/cert_model.dart';
import 'package:hr_mobile_app/features/certificates/cert_render.dart';
import 'package:hr_mobile_app/features/certificates/contract_widgets.dart';

// The layout the server sends for its first sample (same JSON the website designer saves).
final _serverTemplate = {
  'id': 7,
  'name': 'Sample',
  'kind': 'experience',
  'lang': 'ar',
  'width': 1123,
  'height': 794,
  'bgColor': '#fffdf8',
  'bgAssetId': null,
  'layout': jsonEncode({
    'frame': {'style': 'double', 'color': '#b8975a', 'width': 7, 'inset': 26},
    'blocks': [
      {'id': 'title', 'type': 'text', 'text': 'شهادة خبرة', 'x': 10, 'y': 13, 'w': 80, 'size': 6.4, 'color': '#8a6d2f', 'align': 'center', 'bold': true, 'italic': false, 'font': 'serif', 'lh': 1.5},
      {'id': 'name', 'type': 'text', 'text': '{name}', 'x': 10, 'y': 40, 'w': 80, 'size': 7, 'color': '#111827', 'align': 'center', 'bold': true, 'italic': false, 'font': 'serif', 'lh': 1.5},
      {'id': 'body', 'type': 'text', 'text': 'عمل لدى {company} بوظيفة {position} من {start_date} إلى {end_date} ({duration})', 'x': 12, 'y': 54, 'w': 76, 'size': 3.4, 'color': '#1f2937', 'align': 'center', 'bold': false, 'italic': false, 'font': 'sans', 'lh': 1.8},
      {'id': 'serial', 'type': 'text', 'text': 'Certificate No: {serial}', 'x': 8, 'y': 84, 'w': 34, 'size': 2.5, 'color': '#6b7280', 'align': 'left', 'bold': false, 'italic': false, 'font': 'sans', 'lh': 1.5},
      {'id': 'logo', 'type': 'image', 'asset': 99, 'x': 5, 'y': 5, 'w': 10, 'h': 10},
    ],
  }),
};

void main() {
  test('dates and durations in both languages', () {
    expect(certDate(DateTime(2026, 3, 5), 'en'), '5 March 2026');
    expect(certDate(DateTime(2026, 3, 5), 'ar'), '5 مارس 2026');
    expect(certDuration(DateTime(2022, 3, 1), DateTime(2026, 3, 1), 'en'), '4 years');
    expect(certDuration(DateTime(2022, 3, 1), DateTime(2026, 2, 28), 'en'), '3 years and 11 months');
    expect(certDuration(DateTime(2026, 1, 1), DateTime(2026, 1, 10), 'en'), '10 days');
    expect(certDuration(DateTime(2024, 1, 1), DateTime(2026, 2, 28), 'ar'), 'سنتان وشهر');
    expect(certDuration(DateTime(2023, 1, 1), DateTime(2026, 4, 30), 'ar'), '3 سنوات و3 أشهر');
    expect(certDuration(DateTime(2026, 3, 1), DateTime(2026, 2, 1), 'en'), '');
  });

  test('contract end = start + months - 1 day, month ends respected', () {
    expect(contractEndFor(DateTime(2026, 10, 24), 12), DateTime(2027, 10, 23));
    expect(contractEndFor(DateTime(2026, 1, 1), 6), DateTime(2026, 6, 30));
    expect(contractEndFor(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 27));
    expect(contractEndFor(DateTime(2025, 11, 15), 3), DateTime(2026, 2, 14));
  });

  test('a design from the server reads, keeps its values and writes back the same shape', () {
    final t = CertTemplate.fromApi(_serverTemplate);
    expect(t.id, 7);
    expect(t.lang, 'ar');
    expect(t.blocks.length, 5);
    expect(t.blocks.last.isImage, isTrue);
    expect(t.frame.style, 'double');
    final p = t.payload();
    final back = jsonDecode(p['layout'] as String) as Map;
    expect((back['blocks'] as List).length, 5);
    expect((back['blocks'] as List).first['text'], 'شهادة خبرة');
    expect(p['bgColor'], '#fffdf8');
    expect(p['width'], 1123);
  });

  test('values for the placeholders (Arabic keeps the serial in its own left-to-right run)', () {
    final v = buildCertValues(firstName: 'ليلى', lastName: 'محمود', position: 'محاسب', department: 'المالية', company: 'شركة', serial: 'CERT-2026-0001', issueDate: DateTime(2026, 10, 24), startDate: DateTime(2022, 3, 1), endDate: DateTime(2026, 10, 24), lang: 'ar');
    expect(v['name'], 'ليلى محمود');
    expect(v['serial'], '\u2066CERT-2026-0001\u2069');
    expect(v['issue_date'], '24 أكتوبر 2026');
    expect(buildCertValues(firstName: 'A', lastName: 'B', company: 'C', serial: 'CERT-2026-0002', issueDate: DateTime(2026, 1, 1), lang: 'en')['serial'], 'CERT-2026-0002');
  });

  testWidgets('a design is laid out and drawn to a real PNG', (tester) async {
    await tester.runAsync(() async {
      final t = CertTemplate.fromApi(_serverTemplate);
      final values = sampleCertValues('ar');
      final laid = layoutCert(t, values, const {});
      expect(laid.length, 5);
      expect(laid.first.rect.width, closeTo(t.width * 0.8, 0.01));          // a text box keeps its width
      final body = laid.firstWhere((l) => l.block.id == 'body');
      expect(body.lines.first.$1.height, greaterThan(0));
      expect(body.rect.height, greaterThan(laid.first.rect.height * 0.5));   // long text wraps over several lines
      final png = await renderCertPng(t, values, const {}, scale: 1);
      expect(png.length, greaterThan(2000));
      expect(Uint8List.sublistView(png, 0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });
  });
}
