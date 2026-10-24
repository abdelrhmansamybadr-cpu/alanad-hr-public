import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../core/api/api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/session/session.dart';
import '../../core/ui/format.dart';
import '../../core/ui/widgets.dart';
import '../data/providers.dart';

/// Employee documents. [employeeId] null = the signed-in employee; HR passes any employee.
class DocumentsScreen extends ConsumerWidget {
  final int? employeeId;
  final String? title;
  const DocumentsScreen({super.key, this.employeeId, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId ?? ref.watch(sessionProvider).user?.employeeId ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(title ?? context.t('home.qa.documents'))),
      body: DocumentsPanel(employeeId: id),
    );
  }
}

class DocumentsPanel extends ConsumerWidget {
  final int employeeId;
  const DocumentsPanel({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(docTypesProvider);
    final docs = ref.watch(employeeDocsProvider(employeeId));

    Future<void> refresh() async {
      ref.invalidate(employeeDocsProvider(employeeId));
      ref.invalidate(docTypesProvider);
      await ref.read(employeeDocsProvider(employeeId).future).catchError((_) => <DocFile>[]);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: AsyncBody<List<DocFile>>(
        value: docs,
        onRetry: () => ref.invalidate(employeeDocsProvider(employeeId)),
        builder: (files) {
          final typeList = types.valueOrNull ?? const <DocType>[];
          if (typeList.isEmpty && files.isEmpty) {
            return ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.folder_open_rounded, title: context.t('docs.empty')))]);
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), physics: const AlwaysScrollableScrollPhysics(), children: [
            for (final t in typeList) ...[
              _TypeCard(type: t, files: files.where((f) => f.typeId == t.id).toList(), employeeId: employeeId),
              const SizedBox(height: 12),
            ],
          ]);
        },
      ),
    );
  }
}

class _TypeCard extends ConsumerStatefulWidget {
  final DocType type;
  final List<DocFile> files;
  final int employeeId;
  const _TypeCard({required this.type, required this.files, required this.employeeId});

  @override
  ConsumerState<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends ConsumerState<_TypeCard> {
  bool _busy = false;

  Future<void> _upload() async {
    final ok = context.t('docs.uploaded');
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx', 'txt']);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).upload('/documents/employee/${widget.employeeId}/upload/${widget.type.id}', path);
      ref.invalidate(employeeDocsProvider(widget.employeeId));
      if (mounted) toast(context, ok);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(DocFile f) async {
    final failed = context.t('docs.open_failed');
    try {
      final dir = await getTemporaryDirectory();
      final dot = f.fileName.lastIndexOf('.');
      final ext = dot >= 0 ? f.fileName.substring(dot) : '';
      final path = '${dir.path}/doc_${f.id}$ext';
      await ref.read(apiProvider).download(f.downloadUrl, path);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) toast(context, failed, error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } on FileSystemException {
      if (mounted) toast(context, failed, error: true);
    }
  }

  Future<void> _delete(DocFile f) async {
    if (!await confirmDialog(context, title: context.t('common.delete'), message: f.fileName, danger: true, confirmLabel: context.t('common.delete'))) return;
    try {
      await ref.read(apiProvider).delete('/documents/employee/${widget.employeeId}/document/${f.id}');
      ref.invalidate(employeeDocsProvider(widget.employeeId));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.files.isNotEmpty;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(has ? Icons.check_circle_rounded : Icons.upload_file_rounded, color: has ? context.colors.success : context.colors.warning),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.type.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(has ? context.t('docs.files', {'n': widget.files.length}) : context.t('docs.missing'), style: TextStyle(color: has ? context.colors.subtext : context.colors.warning, fontSize: 13)),
          ])),
          _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)) : IconButton.filledTonal(onPressed: _upload, icon: const Icon(Icons.add_rounded)),
        ]),
        for (final f in widget.files) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _open(f),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(f.mime.contains('pdf') ? Icons.picture_as_pdf_rounded : f.mime.startsWith('image') ? Icons.image_rounded : Icons.insert_drive_file_rounded, color: context.scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (f.uploadedAt != null) Text(fmtDate(context, f.uploadedAt!), style: TextStyle(color: context.colors.subtext, fontSize: 12)),
                ])),
                IconButton(onPressed: () => _delete(f), icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
