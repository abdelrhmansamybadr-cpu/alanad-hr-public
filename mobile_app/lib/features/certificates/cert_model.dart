import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models/json.dart';

/// Certificate designs: the same JSON the website's designer saves (blocks of text with {placeholders} and pictures).
/// Sizes: x / y / w / h are % of the page, `size` is % of the page height.

Color certColor(String? hex, [Color fallback = const Color(0xFF1F2937)]) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

String certHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class CertBlock {
  String id;
  bool isImage;
  double x, y, w;
  String text;
  double size;
  Color color;
  String align; // left | center | right
  bool bold, italic;
  String font; // sans | serif | mono
  double lh;
  int asset;
  double h;

  CertBlock({
    required this.id,
    this.isImage = false,
    this.x = 20,
    this.y = 30,
    this.w = 60,
    this.text = '',
    this.size = 3.6,
    this.color = const Color(0xFF1F2937),
    this.align = 'center',
    this.bold = false,
    this.italic = false,
    this.font = 'sans',
    this.lh = 1.5,
    this.asset = 0,
    this.h = 10,
  });

  factory CertBlock.fromJson(Map m) => CertBlock(
        id: jStr(m, 'id', 'b${DateTime.now().microsecondsSinceEpoch}'),
        isImage: jStr(m, 'type') == 'image',
        x: jDouble(m, 'x'),
        y: jDouble(m, 'y'),
        w: jDouble(m, 'w', 30),
        text: jStr(m, 'text'),
        size: jDouble(m, 'size', 3),
        color: certColor(jStrN(m, 'color')),
        align: const ['left', 'center', 'right'].contains(jStr(m, 'align')) ? jStr(m, 'align') : 'center',
        bold: jBool(m, 'bold'),
        italic: jBool(m, 'italic'),
        font: const ['sans', 'serif', 'mono'].contains(jStr(m, 'font')) ? jStr(m, 'font') : 'sans',
        lh: jDouble(m, 'lh', 1.5),
        asset: jInt(m, 'asset'),
        h: jDouble(m, 'h', 10),
      );

  Map<String, dynamic> toJson() => isImage
      ? {'id': id, 'type': 'image', 'asset': asset, 'x': x, 'y': y, 'w': w, 'h': h}
      : {'id': id, 'type': 'text', 'text': text, 'x': x, 'y': y, 'w': w, 'size': size, 'color': certHex(color), 'align': align, 'bold': bold, 'italic': italic, 'font': font, 'lh': lh};

  CertBlock copy() => CertBlock.fromJson(toJson())..id = 'b${DateTime.now().microsecondsSinceEpoch}';
}

class CertFrame {
  String style; // none | single | double
  Color color;
  double width, inset;
  CertFrame({this.style = 'none', this.color = const Color(0xFFB8975A), this.width = 6, this.inset = 24});

  factory CertFrame.fromJson(Map m) => CertFrame(
        style: const ['none', 'single', 'double'].contains(jStr(m, 'style')) ? jStr(m, 'style') : 'none',
        color: certColor(jStrN(m, 'color'), const Color(0xFFB8975A)),
        width: jDouble(m, 'width', 6),
        inset: jDouble(m, 'inset', 24),
      );

  Map<String, dynamic> toJson() => {'style': style, 'color': certHex(color), 'width': width, 'inset': inset};
}

class CertTemplate {
  int? id;
  String name;
  String kind; // experience | end_of_service | clearance | custom
  String lang; // ar | en
  double width, height;
  Color bgColor;
  int? bgAssetId;
  CertFrame frame;
  List<CertBlock> blocks;

  CertTemplate({
    this.id,
    this.name = '',
    this.kind = 'custom',
    this.lang = 'ar',
    this.width = 1123,
    this.height = 794,
    this.bgColor = Colors.white,
    this.bgAssetId,
    CertFrame? frame,
    List<CertBlock>? blocks,
  })  : frame = frame ?? CertFrame(),
        blocks = blocks ?? [];

  factory CertTemplate.fromApi(Map raw) {
    Map layout = {};
    final l = raw['layout'];
    try {
      layout = l is String ? (jsonDecode(l) as Map) : (l is Map ? l : {});
    } catch (_) {/* keep empty */}
    return CertTemplate(
      id: jIntN(raw, 'id'),
      name: jStr(raw, 'name'),
      kind: jStr(raw, 'kind', 'custom'),
      lang: jStr(raw, 'lang') == 'ar' ? 'ar' : 'en',
      width: jDouble(raw, 'width', 1123),
      height: jDouble(raw, 'height', 794),
      bgColor: certColor(jStrN(raw, 'bgColor'), Colors.white),
      bgAssetId: jIntN(raw, 'bgAssetId'),
      frame: layout['frame'] is Map ? CertFrame.fromJson(layout['frame'] as Map) : null,
      blocks: [for (final b in (layout['blocks'] as List? ?? const [])) if (b is Map) CertBlock.fromJson(b)],
    );
  }

  CertTemplate copy() => CertTemplate(
        id: id, name: name, kind: kind, lang: lang, width: width, height: height, bgColor: bgColor, bgAssetId: bgAssetId,
        frame: CertFrame.fromJson(frame.toJson()), blocks: [for (final b in blocks) CertBlock.fromJson(b.toJson())..id = b.id],
      );

  /// The body the API wants when saving (the layout travels as a JSON string).
  Map<String, dynamic> payload() => {
        'name': name.trim(),
        'kind': kind,
        'lang': lang,
        'width': width.round(),
        'height': height.round(),
        'bgColor': certHex(bgColor),
        'bgAssetId': bgAssetId,
        'layout': jsonEncode({'frame': frame.toJson(), 'blocks': [for (final b in blocks) b.toJson()]}),
      };
}

/// Placeholders a text block can use: key, English label, Arabic label.
const certPlaceholders = <(String, String, String)>[
  ('name', 'Full name', 'الاسم الكامل'),
  ('position', 'Job title', 'المسمى الوظيفي'),
  ('department', 'Department', 'القسم'),
  ('company', 'Company', 'الشركة'),
  ('start_date', 'Start date', 'تاريخ البدء'),
  ('end_date', 'Leaving date', 'تاريخ المغادرة'),
  ('duration', 'Time worked', 'مدة العمل'),
  ('issue_date', 'Issue date', 'تاريخ الإصدار'),
  ('serial', 'Certificate no.', 'رقم الشهادة'),
  ('note', 'Extra note', 'ملاحظة إضافية'),
];
