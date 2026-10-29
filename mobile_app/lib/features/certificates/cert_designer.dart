import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/json.dart';
import '../../core/ui/responsive.dart';
import '../../core/ui/widgets.dart';
import 'cert_model.dart';
import 'cert_render.dart';

const _palette = ['#111827', '#374151', '#6b7280', '#ffffff', '#8a6d2f', '#b8975a', '#7c2d12', '#991b1b', '#1e3a8a', '#0f766e', '#166534', '#6d28d9', '#be185d', '#000000'];

/// Upload a picture for a certificate (background, logo, signature, stamp). Returns {id, width, height}.
Future<Map<String, dynamic>?> pickCertPicture(BuildContext context, Api api) async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 3000);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > 8 * 1024 * 1024) {
    if (context.mounted) toast(context, context.t('cert.pic_big'), error: true);
    return null;
  }
  final name = f.name.toLowerCase();
  final mime = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : 'jpeg');
  final data = asMap(await api.post('/certificates/assets', {'dataUrl': 'data:image/$mime;base64,${base64Encode(bytes)}', 'name': f.name}));
  return data;
}

class CertDesignerScreen extends ConsumerStatefulWidget {
  final CertTemplate initial;
  const CertDesignerScreen({super.key, required this.initial});
  @override
  ConsumerState<CertDesignerScreen> createState() => _CertDesignerScreenState();
}

class _CertDesignerScreenState extends ConsumerState<CertDesignerScreen> {
  late final CertTemplate _t = widget.initial.copy();
  Map<int, ui.Image> _images = {};
  String? _sel;
  bool _saving = false;
  final _text = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = _t.name;
    _sel = _t.blocks.isEmpty ? null : _t.blocks.first.id;
    _syncText();
    _loadImages();
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  CertBlock? get _cur => _t.blocks.where((b) => b.id == _sel).firstOrNull;
  void _syncText() => _text.text = _cur?.isImage == false ? (_cur?.text ?? '') : '';

  Future<void> _loadImages() async {
    final m = await loadCertImages(ref.read(apiProvider), _t);
    if (mounted) setState(() => _images = m);
  }

  void _select(String? id) => setState(() {
        _sel = id;
        _syncText();
      });

  void _addText() {
    final b = CertBlock(id: 'b${DateTime.now().microsecondsSinceEpoch}', text: context.t('cert.new_text'));
    setState(() {
      _t.blocks.add(b);
      _sel = b.id;
      _syncText();
    });
  }

  Future<void> _addPicture() async {
    try {
      final a = await pickCertPicture(context, ref.read(apiProvider));
      if (a == null) return;
      final ratio = jDouble(a, 'height', 1) / jDouble(a, 'width', 1);
      final w = 16.0, h = (w * ratio * (_t.width / _t.height)).clamp(3, 40).toDouble();
      final b = CertBlock(id: 'b${DateTime.now().microsecondsSinceEpoch}', isImage: true, asset: jInt(a, 'id'), x: 42, y: 70, w: w, h: h);
      setState(() {
        _t.blocks.add(b);
        _sel = b.id;
      });
      await _loadImages();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _setBackground() async {
    try {
      final a = await pickCertPicture(context, ref.read(apiProvider));
      if (a == null) return;
      final w = 1123.0, h = (w * jDouble(a, 'height', 794) / jDouble(a, 'width', 1123)).clamp(300, 4000).toDouble();
      setState(() {
        _t.bgAssetId = jInt(a, 'id');
        _t.width = w;
        _t.height = h;
      });
      await _loadImages();
      if (mounted) toast(context, context.t('cert.bg_added'));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _save() async {
    _t.name = _name.text;
    if (_t.name.trim().isEmpty) return toast(context, context.t('cert.name_req'), error: true);
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      if (_t.id == null) {
        await api.post('/certificates/templates', _t.payload());
      } else {
        await api.put('/certificates/templates/${_t.id}', _t.payload());
      }
      if (!mounted) return;
      toast(context, context.t('cert.saved'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------ preview with drag handles
  Widget _preview() {
    final values = sampleCertValues(_t.lang);
    return LayoutBuilder(builder: (ctx, c) {
      final maxH = MediaQuery.of(ctx).size.height * (ctx.isDesktop ? 0.7 : 0.42);
      final scale = (c.maxWidth / _t.width) < (maxH / _t.height) ? c.maxWidth / _t.width : maxH / _t.height;
      final w = _t.width * scale, h = _t.height * scale;
      final laid = layoutCert(_t, values, _images);
      return Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(border: Border.all(color: context.colors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)]),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: CertPainter(_t, laid, _images))),
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _select(null))),
            for (final l in laid)
              Positioned(
                left: l.rect.left * scale,
                top: l.rect.top * scale,
                width: l.rect.width * scale,
                height: l.rect.height * scale,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _select(l.block.id),
                  onPanStart: (_) => _select(l.block.id),
                  onPanUpdate: (d) => setState(() {
                    l.block.x = ((l.block.x + d.delta.dx / w * 100) * 10).round() / 10;
                    l.block.y = ((l.block.y + d.delta.dy / h * 100) * 10).round() / 10;
                  }),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: l.block.id == _sel ? context.scheme.primary.withValues(alpha: 0.06) : null,
                      border: l.block.id == _sel ? Border.all(color: context.scheme.primary, width: 1.6) : null,
                    ),
                    child: l.block.id == _sel
                        ? Align(
                            alignment: Alignment.bottomRight,
                            child: GestureDetector(
                              onPanUpdate: (d) => setState(() => l.block.w = (((l.block.w + d.delta.dx / w * 100)).clamp(3, 150) * 10).round() / 10),
                              child: Container(width: 22, height: 22, margin: const EdgeInsets.all(0), decoration: BoxDecoration(color: context.scheme.primary, borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.open_in_full_rounded, size: 13, color: Colors.white)),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }

  // ------------------------------------------------------------ editors
  Widget _colors(Color value, ValueChanged<Color> onPick) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final hex in _palette)
          GestureDetector(
            onTap: () => setState(() => onPick(certColor(hex))),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: certColor(hex), shape: BoxShape.circle, border: Border.all(color: certHex(value) == hex ? context.scheme.primary : context.colors.border, width: certHex(value) == hex ? 3 : 1)),
            ),
          ),
      ]);

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 84, child: Text(label, style: TextStyle(fontSize: 12, color: context.colors.subtext))),
        Expanded(child: Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: (x) => setState(() => on(((x * 10).round() / 10)))))
      ]);

  Widget _blockEditor(CertBlock b) {
    final ar = context.isAr;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(b.isImage ? context.t('cert.picture') : context.t('cert.text_box'), style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
              tooltip: context.t('cert.duplicate'),
              onPressed: () => setState(() {
                    final c = b.copy()..x = b.x + 2..y = b.y + 3;
                    _t.blocks.add(c);
                    _sel = c.id;
                    _syncText();
                  }),
              icon: const Icon(Icons.copy_rounded)),
          IconButton(
              tooltip: context.t('common.delete'),
              onPressed: () => setState(() {
                    _t.blocks.remove(b);
                    _sel = null;
                    _syncText();
                  }),
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger)),
        ]),
        if (!b.isImage) ...[
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 6,
            textDirection: null,
            decoration: InputDecoration(hintText: context.t('cert.text_hint')),
            onChanged: (v) => setState(() => b.text = v),
          ),
          const SizedBox(height: 10),
          Text(context.t('cert.insert'), style: TextStyle(fontSize: 12, color: context.colors.subtext)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in certPlaceholders)
              ActionChip(
                label: Text(ar ? p.$3 : p.$2, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final sel = _text.selection;
                  final t = _text.text;
                  final s = sel.isValid ? sel.start : t.length, e = sel.isValid ? sel.end : t.length;
                  final nt = t.replaceRange(s, e, '{${p.$1}}');
                  _text.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: s + p.$1.length + 2));
                  setState(() => b.text = nt);
                },
              ),
          ]),
          const SizedBox(height: 12),
          _slider(context.t('cert.size'), b.size, 0.8, 15, (v) => b.size = v),
          _slider(context.t('cert.spacing'), b.lh, 1, 2.5, (v) => b.lh = v),
          const SizedBox(height: 4),
          _colors(b.color, (c) => b.color = c),
          const SizedBox(height: 12),
          Row(children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left_rounded)),
                ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center_rounded)),
                ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right_rounded)),
              ],
              selected: {b.align},
              onSelectionChanged: (s) => setState(() => b.align = s.first),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(isSelected: b.bold, onPressed: () => setState(() => b.bold = !b.bold), icon: const Icon(Icons.format_bold_rounded)),
            IconButton.filledTonal(isSelected: b.italic, onPressed: () => setState(() => b.italic = !b.italic), icon: const Icon(Icons.format_italic_rounded)),
          ]),
          const SizedBox(height: 10),
          SegmentBar(labels: [context.t('cert.f_sans'), context.t('cert.f_serif'), context.t('cert.f_mono')], index: ['sans', 'serif', 'mono'].indexOf(b.font), onChanged: (i) => setState(() => b.font = ['sans', 'serif', 'mono'][i])),
        ] else
          _slider(context.t('cert.height'), b.h, 3, 60, (v) => b.h = v),
        const SizedBox(height: 4),
        _slider(context.t('cert.left'), b.x, -10, 100, (v) => b.x = v),
        _slider(context.t('cert.top'), b.y, -10, 100, (v) => b.y = v),
        _slider(context.t('cert.width'), b.w, 3, 120, (v) => b.w = v),
      ]),
    );
  }

  Widget _pageEditor() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('cert.page_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: InputDecoration(labelText: context.t('cert.design_name'), prefixIcon: const Icon(Icons.badge_outlined)), onChanged: (v) => _t.name = v),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _t.kind,
                decoration: InputDecoration(labelText: context.t('cert.type')),
                items: [for (final k in ['experience', 'end_of_service', 'clearance', 'custom']) DropdownMenuItem(value: k, child: Text(context.t('cert.k_$k'), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _t.kind = v ?? 'custom'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _t.lang,
                decoration: InputDecoration(labelText: context.t('cert.language')),
                items: const [DropdownMenuItem(value: 'ar', child: Text('العربية')), DropdownMenuItem(value: 'en', child: Text('English'))],
                onChanged: (v) => setState(() => _t.lang = v ?? 'en'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SegmentBar(
            labels: [context.t('cert.landscape'), context.t('cert.portrait')],
            index: _t.height < _t.width ? 0 : 1,
            onChanged: (i) => setState(() {
              _t.width = i == 0 ? 1123 : 794;
              _t.height = i == 0 ? 794 : 1123;
            }),
          ),
          const SizedBox(height: 14),
          Text(context.t('cert.bg_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(context.t('cert.bg_hint'), style: TextStyle(fontSize: 12, color: context.colors.subtext, height: 1.4)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _setBackground, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(_t.bgAssetId == null ? context.t('cert.upload') : context.t('cert.change_pic')))),
            if (_t.bgAssetId != null) IconButton(onPressed: () => setState(() => _t.bgAssetId = null), icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 12),
          Text(context.t('cert.bg_color'), style: TextStyle(fontSize: 12, color: context.colors.subtext)),
          const SizedBox(height: 6),
          _colors(_t.bgColor, (c) => _t.bgColor = c),
          const SizedBox(height: 14),
          Text(context.t('cert.frame'), style: TextStyle(fontSize: 12, color: context.colors.subtext)),
          const SizedBox(height: 6),
          SegmentBar(labels: [context.t('cert.fr_none'), context.t('cert.fr_single'), context.t('cert.fr_double')], index: ['none', 'single', 'double'].indexOf(_t.frame.style), onChanged: (i) => setState(() => _t.frame.style = ['none', 'single', 'double'][i])),
          if (_t.frame.style != 'none') ...[
            const SizedBox(height: 10),
            _colors(_t.frame.color, (c) => _t.frame.color = c),
            _slider(context.t('cert.thickness'), _t.frame.width, 1, 30, (v) => _t.frame.width = v),
            _slider(context.t('cert.margin'), _t.frame.inset, 0, 120, (v) => _t.frame.inset = v),
          ],
        ]),
      );

  /// The row of chips: one per box on the page, plus the "add" buttons.
  Widget _blockChips({bool scroll = false}) {
    final items = <Widget>[
            for (final b in _t.blocks)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  selected: b.id == _sel,
                  showCheckmark: false,
                  avatar: Icon(b.isImage ? Icons.image_outlined : Icons.text_fields_rounded, size: 16),
                  label: Text(b.isImage ? context.t('cert.picture') : (b.text.split('\n').first.isEmpty ? '…' : (b.text.split('\n').first.length > 14 ? '${b.text.split('\n').first.substring(0, 14)}…' : b.text.split('\n').first))),
                  onSelected: (_) => _select(b.id),
                ),
              ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: Text(context.t('cert.add_text')), onPressed: _addText)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ActionChip(avatar: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: Text(context.t('cert.add_pic')), onPressed: _addPicture)),
    ];
    return scroll ? ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: items) : Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  @override
  Widget build(BuildContext context) {
    final cur = _cur;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t.id == null ? context.t('cert.new_design') : context.t('cert.edit_design')),
        actions: [Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? context.t('cert.saving') : context.t('common.save'))))],
      ),
      body: context.isDesktop
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 12, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _preview(),
                    const SizedBox(height: 8),
                    Text(context.t('cert.drag_hint'), style: TextStyle(fontSize: 12, color: context.colors.subtext)),
                    const SizedBox(height: 8),
                    _blockChips(),
                  ]),
                ),
              ),
              SizedBox(
                width: 420,
                child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 24, 32), children: [
                  if (cur != null) ...[_blockEditor(cur), const SizedBox(height: 12)],
                  _pageEditor(),
                ]),
              ),
            ])
          : Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: _preview()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: AlignmentDirectional.centerStart, child: Text(context.t('cert.drag_hint'), style: TextStyle(fontSize: 11.5, color: context.colors.subtext)))),
              SizedBox(height: 52, child: _blockChips(scroll: true)),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                  if (cur != null) ...[_blockEditor(cur), const SizedBox(height: 12)],
                  _pageEditor(),
                ]),
              ),
            ]),
    );
  }
}
