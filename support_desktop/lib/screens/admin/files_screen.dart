import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

String prettySize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key, required this.service});
  final FilesService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<FileCollection>(
      stationNumber: '14',
      stationLabel: 'FILES MANAGEMENT',
      title: 'Collections.',
      addLabel: 'Upload',
      searchHint: 'Search collections…',
      fetch: (search) => service.listCollections(search: search),
      onAdd: (ctx, refresh) => _upload(ctx, refresh),
      itemBuilder: (ctx, c, refresh) => _CollectionRow(
        collection: c,
        onOpen: () => _openFiles(ctx, c),
        onGetLink: () => _getLink(ctx, c),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete collection',
              message: 'Remove "${c.name}" and its ${c.fileCount} file(s)?')) {
            return;
          }
          final ok = await service.deleteCollection(c.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  /// Pick files, name a new collection, and upload.
  Future<void> _upload(BuildContext context, VoidCallback refresh) async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;
    final paths =
        picked.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    if (!context.mounted) return;

    final nameCtrl = TextEditingController(
        text: paths.length == 1
            ? picked.files.first.name.replaceAll(RegExp(r'\.[^.]+$'), '')
            : '');
    final emailCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload files'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${paths.length} file(s) selected',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Collection name'),
                autofocus: true,
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Notify email (optional)'),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Upload')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (context.mounted) toast(context, 'Collection name is required.');
      return;
    }

    if (context.mounted) toast(context, 'Uploading ${paths.length} file(s)…');
    final res = await service.upload(
        collectionName: name, email: emailCtrl.text.trim(), filePaths: paths);
    if (!context.mounted) return;
    toast(context, res.ok ? 'Uploaded' : (res.message ?? 'Upload failed'));
    if (res.ok) refresh();
  }

  /// Fetch the existing share link (issuing one if absent) and show it with
  /// copy / open actions.
  Future<void> _getLink(BuildContext context, FileCollection c) async {
    final existing = await service.getShareLink(c.id);
    var token = existing.token;
    token ??= await service.generateShareLink(c.id);
    if (!context.mounted) return;
    if (token == null || token.isEmpty) {
      toast(context, 'Could not get a share link.');
      return;
    }
    final permanentUrl = (existing.permanentToken != null &&
            existing.permanentToken!.isNotEmpty)
        ? service.shareUrl(existing.permanentToken!)
        : null;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var currentToken = token!;
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Share link'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _LinkField(label: 'LINK', url: service.shareUrl(currentToken)),
                  if (permanentUrl != null) ...[
                    const SizedBox(height: 12),
                    _LinkField(label: 'PERMANENT LINK', url: permanentUrl),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setLocal(() => busy = true);
                        final fresh = await service.generateShareLink(c.id);
                        if (!ctx.mounted) return;
                        setLocal(() {
                          busy = false;
                          if (fresh != null && fresh.isNotEmpty) {
                            currentToken = fresh;
                          }
                        });
                      },
                child: Text(busy ? 'Regenerating…' : 'Regenerate'),
              ),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFiles(BuildContext context, FileCollection c) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: _FilesDialog(service: service, collection: c),
        ),
      ),
    );
  }
}

class _FilesDialog extends StatefulWidget {
  const _FilesDialog({required this.service, required this.collection});
  final FilesService service;
  final FileCollection collection;

  @override
  State<_FilesDialog> createState() => _FilesDialogState();
}

class _FilesDialogState extends State<_FilesDialog> {
  late Future<List<FileItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.collectionFiles(widget.collection.id);
  }

  void _reload() =>
      setState(() => _future = widget.service.collectionFiles(widget.collection.id));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(widget.collection.name, style: text.titleMedium)),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18)),
            ],
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<FileItem>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.signal));
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final files = snap.data ?? const [];
                if (files.isEmpty) {
                  return Center(
                      child: Text('No files in this collection.',
                          style: text.bodySmall));
                }
                return ListView.separated(
                  itemCount: files.length,
                  itemBuilder: (ctx, i) {
                    final f = files[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(prettySize(f.size)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Download',
                            icon: const Icon(Icons.download, size: 18),
                            onPressed: () => launchUrl(
                                Uri.parse(widget.service.downloadUrl(f.id)),
                                mode: LaunchMode.externalApplication),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final ok = await widget.service.deleteFile(f.id);
                              if (!ctx.mounted) return;
                              toast(ctx, ok ? 'Deleted' : 'Delete failed');
                              if (ok) _reload();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Brand.rule),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow(
      {required this.collection,
      required this.onOpen,
      required this.onGetLink,
      required this.onDelete});
  final FileCollection collection;
  final VoidCallback onOpen;
  final VoidCallback onGetLink;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_outlined, color: Brand.signal, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(collection.name, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${collection.fileCount} file(s)',
                        prettySize(collection.totalSize),
                        if (collection.email.isNotEmpty) collection.email,
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: Brand.paperDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                  tooltip: 'Get share link',
                  onPressed: onGetLink,
                  icon: const Icon(Icons.link, size: 19)),
              IconButton(
                  tooltip: 'Open',
                  onPressed: onOpen,
                  icon: const Icon(Icons.chevron_right, size: 20)),
              IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18)),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Brand.rule),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// A read-only share-URL field with copy + open-in-browser actions.
class _LinkField extends StatelessWidget {
  const _LinkField({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(color: Brand.paperDim)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Brand.rule),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) toast(context, 'Copied to clipboard');
              },
            ),
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ],
    );
  }
}
