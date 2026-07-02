import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/file_models.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// File Management — native screens. Lists upload collections (name +
/// file count + total size); tapping one opens its files with per-file
/// delete and a share-link action. A + action uploads a new file into a
/// freshly-named collection. Backed by the `file_*` actions on api.php.
class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key, required this.service});
  final FileService service;

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<FileCollection> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.listCollections();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openCollection(FileCollection c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _CollectionFilesScreen(service: widget.service, collection: c),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _upload() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _UploadScreen(service: widget.service),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'FILE MANAGEMENT',
      title: 'Files.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.upload_file,
        tooltip: 'Upload file',
        onPressed: _upload,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 64),
                      EmptyState(
                        label: 'No file collections',
                        hint: 'Tap the upload icon to add a file. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _CollectionRow(
                      row: _rows[i],
                      onTap: () => _openCollection(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.row, required this.onTap});
  final FileCollection row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final files = row.fileCount == 1 ? '1 file' : '${row.fileCount} files';
    final subtitle = '$files · ${humanFileSize(row.totalSize)}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: row.hasPermanentLink ? Brand.signal : Brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name.isEmpty ? 'Untitled collection' : row.name,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              row.isDistribution ? 'DIST' : 'FILES',
              style: text.labelMedium?.copyWith(
                color: row.isDistribution ? Brand.signal : Brand.paperDim,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-collection file list. Each file shows its name + size with a delete
/// action. Header actions: copy a share link, or delete the whole collection.
class _CollectionFilesScreen extends StatefulWidget {
  const _CollectionFilesScreen({required this.service, required this.collection});
  final FileService service;
  final FileCollection collection;

  @override
  State<_CollectionFilesScreen> createState() => _CollectionFilesScreenState();
}

class _CollectionFilesScreenState extends State<_CollectionFilesScreen> {
  List<StoredFile> _files = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  ShareLink? _links;
  bool _linkBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLinks();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await widget.service.collectionFiles(widget.collection.id);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _loadLinks() async {
    final links = await widget.service.getShareLink(widget.collection.id);
    if (!mounted) return;
    setState(() => _links = links);
  }

  Future<void> _genExpiring() async {
    setState(() => _linkBusy = true);
    final link = await widget.service.generateExpiringLink(widget.collection.id);
    if (!mounted) return;
    setState(() {
      _linkBusy = false;
      if (link != null) {
        _links = ShareLink(
          token: link.token,
          expiresAt: link.expiresAt,
          permanentToken: _links?.permanentToken,
        );
      }
    });
    if (link == null) _toast('Could not generate the link.');
  }

  Future<void> _genPermanent() async {
    setState(() => _linkBusy = true);
    final token =
        await widget.service.generatePermanentLink(widget.collection.id);
    if (!mounted) return;
    setState(() {
      _linkBusy = false;
      if (token != null) {
        _links = ShareLink(
          token: _links?.token,
          expiresAt: _links?.expiresAt,
          expired: _links?.expired ?? false,
          permanentToken: token,
        );
      }
    });
    if (token == null) _toast('Could not generate the permanent link.');
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    _toast('Link copied');
  }

  Future<void> _deleteFile(StoredFile file) async {
    final ok = await _confirm(
      'Delete file?',
      'This removes "${file.filename}" from the collection.',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await widget.service.deleteItem(file.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      _changed = true;
      _load();
    } else {
      _toast(res.message ?? 'Could not delete the file.');
    }
  }

  Future<void> _deleteCollection() async {
    final ok = await _confirm(
      'Delete collection?',
      'This permanently removes the collection and all of its files.',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await widget.service.deleteCollection(widget.collection.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the collection.');
    }
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.collection;
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'COLLECTION',
      title: c.name.isEmpty ? 'Files.' : '${c.name}.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_changed),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_files.isEmpty) ...[
                    const SizedBox(height: 48),
                    const EmptyState(
                      label: 'No files',
                      hint: 'This collection is empty. Pull to refresh.',
                    ),
                  ] else
                    ..._intersperse(
                      _files.map((f) => _FileRow(
                            file: f,
                            onDelete: _busy ? null : () => _deleteFile(f),
                          )),
                    ),
                  const SizedBox(height: 36),
                  _shareSection(),
                  const SizedBox(height: 36),
                  GhostButton(
                    label: 'Delete collection',
                    onPressed: _deleteCollection,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _shareSection() {
    final text = Theme.of(context).textTheme;
    final links = _links;
    final expiringUrl = (links?.hasExpiring ?? false)
        ? widget.service.shareUrl(links!.token!)
        : null;
    final permUrl = (links?.hasPermanent ?? false)
        ? widget.service.shareUrl(links!.permanentToken!)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Share', style: text.headlineMedium),
        const SizedBox(height: 8),
        const Hairline(),
        const SizedBox(height: 16),
        Text('EXPIRING LINK', style: text.labelMedium),
        const SizedBox(height: 8),
        if (expiringUrl != null)
          _linkRow(
            expiringUrl,
            subtitle: links!.expired
                ? 'This link has expired.'
                : (links.expiresAt != null ? 'Expires ${links.expiresAt}' : null),
          )
        else
          _genButton('Generate expiring share link',
              _linkBusy ? null : _genExpiring),
        const SizedBox(height: 20),
        Text('PERMANENT LINK', style: text.labelMedium),
        const SizedBox(height: 8),
        if (permUrl != null)
          _linkRow(permUrl)
        else
          _genButton('Generate permanent link',
              _linkBusy ? null : _genPermanent),
      ],
    );
  }

  Widget _linkRow(String url, {String? subtitle}) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(url, style: text.bodySmall),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _copy(url),
              child: Row(
                children: [
                  const Icon(Icons.copy, size: 14, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('COPY',
                      style: text.labelMedium?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: text.labelMedium),
        ],
      ],
    );
  }

  Widget _genButton(String label, VoidCallback? onTap) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(
              color: enabled ? Brand.signal : Brand.rule, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_link,
                size: 16, color: enabled ? Brand.signal : Brand.paperDim),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: text.labelMedium?.copyWith(
                color: enabled ? Brand.signal : Brand.paperDim,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Hairline separators between rows (ListView.separated isn't usable here
  // because we mix rows with trailing buttons in one scroll view).
  List<Widget> _intersperse(Iterable<Widget> rows) {
    final out = <Widget>[];
    var first = true;
    for (final r in rows) {
      if (!first) out.add(const Hairline());
      out.add(r);
      first = false;
    }
    return out;
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onDelete});
  final StoredFile file;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.filename.isEmpty ? 'Unnamed file' : file.filename,
                    style: text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(humanFileSize(file.fileSize), style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Brand.paperDim,
            tooltip: 'Delete file',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Upload screen: pick a file, name the collection, then post it.
class _UploadScreen extends StatefulWidget {
  const _UploadScreen({required this.service});
  final FileService service;

  @override
  State<_UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<_UploadScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _filePath;
  String? _fileName;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      setState(() {
        _filePath = file.path;
        _fileName = file.name;
        if (_name.text.trim().isEmpty) _name.text = file.name;
      });
    } catch (_) {
      _toast('Could not pick file.');
    }
  }

  Future<void> _save() async {
    final path = _filePath;
    if (path == null) {
      _toast('Pick a file to upload.');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('A collection name is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.upload(
      collectionName: name,
      email: _email.text.trim(),
      filePath: path,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Upload failed.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'UPLOAD FILE',
      title: 'Upload.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          StationDataRow(
            label: 'FILE',
            value: _fileName ?? 'Tap to pick a file',
            onTap: _pickFile,
            trailingIcon: Icons.attach_file,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'COLLECTION NAME'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'EMAIL (OPTIONAL)'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: 'Upload file',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
