import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:open_filex/open_filex.dart';

import '../models/file_models.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'file_upload_screen.dart';
import 'file_widgets.dart';

enum _Filter { collections, favorites, distribution, installer }

enum _Sort { suggested, name, newest, largest, files }

class FileListScreen extends StatelessWidget {
  const FileListScreen({super.key, required this.service});
  final FileService service;

  @override
  Widget build(BuildContext context) {
    return FileExplorerScreen(service: service);
  }
}

class FileExplorerScreen extends StatefulWidget {
  const FileExplorerScreen({super.key, required this.service, this.folderId});

  final FileService service;
  final String? folderId;

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  final TextEditingController _search = TextEditingController();

  List<FileCollection> _all = const [];
  List<StoredFile> _files = const [];
  StorageUsage? _usage;
  ShareLink? _links;

  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  _Filter _filter = _Filter.collections;
  _Sort _sort = _Sort.suggested;
  Timer? _ticker;

  bool get _isRoot => widget.folderId == null;
  FileService get _service => widget.service;

  FileCollection? get _collection {
    final id = widget.folderId;
    if (id == null) return null;
    for (final row in _all) {
      if (row.id == id) return row;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _busy) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted && _all.isEmpty) setState(() => _loading = true);
    final rows = await _service.listCollections();
    List<StoredFile> files = const [];
    ShareLink? links;
    if (widget.folderId != null) {
      final contents = await _service.collectionContents(widget.folderId!);
      files = contents.files;
      links = await _service.getShareLink(widget.folderId!);
    }
    StorageUsage? usage;
    if (_isRoot && !_service.restrictedToShared) {
      usage = await _service.storageUsage();
    }
    if (!mounted) return;
    setState(() {
      _all = rows;
      _files = files;
      _links = links;
      _usage = usage;
      _loading = false;
    });
  }

  List<FileCollection> _childrenOf(String? parentId) {
    final ids = {for (final row in _all) row.id};
    return _all.where((row) {
      if (row.isInstaller) return false;
      final parent = (row.parentId ?? '').isEmpty ? null : row.parentId;
      final key = parent != null && ids.contains(parent) ? parent : null;
      return key == parentId;
    }).toList();
  }

  List<FileCollection> _pathOf(String id) {
    final byId = {for (final row in _all) row.id: row};
    final out = <FileCollection>[];
    var cursor = byId[id];
    var guard = 0;
    while (cursor != null && guard++ < 100) {
      out.insert(0, cursor);
      final parent = cursor.parentId;
      cursor = (parent == null || parent.isEmpty) ? null : byId[parent];
    }
    return out;
  }

  FolderTotals _subtreeTotals(FileCollection row) {
    if (row.isInstaller) {
      return FolderTotals(
        files: row.fileCount,
        size: row.totalSize,
        folders: 0,
      );
    }
    var files = row.fileCount;
    var size = row.totalSize;
    var folders = 0;
    final stack = _childrenOf(row.id).toList();
    var guard = 0;
    while (stack.isNotEmpty && guard++ < 5000) {
      final current = stack.removeLast();
      folders++;
      files += current.fileCount;
      size += current.totalSize;
      stack.addAll(_childrenOf(current.id));
    }
    return FolderTotals(files: files, size: size, folders: folders);
  }

  List<FileCollection> get _visibleFolders {
    final query = _search.text.trim().toLowerCase();
    Iterable<FileCollection> rows;
    if (_isRoot) {
      rows = switch (_filter) {
        _Filter.installer => _all.where((r) => r.isInstaller),
        _Filter.distribution => _childrenOf(
          null,
        ).where((r) => r.isDistribution),
        _Filter.favorites => _childrenOf(null).where((r) => r.isFavorite),
        _Filter.collections => _childrenOf(null),
      };
    } else {
      rows = _childrenOf(widget.folderId);
    }
    if (query.isNotEmpty) {
      rows = rows.where(
        (r) =>
            r.name.toLowerCase().contains(query) ||
            r.email.toLowerCase().contains(query),
      );
    }
    final list = rows.toList();
    switch (_sort) {
      case _Sort.suggested:
        list.sort((a, b) {
          if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
          return _dateValue(b.createdAt).compareTo(_dateValue(a.createdAt));
        });
      case _Sort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.newest:
        list.sort(
          (a, b) => _dateValue(b.createdAt).compareTo(_dateValue(a.createdAt)),
        );
      case _Sort.largest:
        list.sort(
          (a, b) => _subtreeTotals(b).size.compareTo(_subtreeTotals(a).size),
        );
      case _Sort.files:
        list.sort(
          (a, b) => _subtreeTotals(b).files.compareTo(_subtreeTotals(a).files),
        );
    }
    return list;
  }

  List<StoredFile> get _visibleFiles {
    final query = _search.text.trim().toLowerCase();
    var list = _files.toList();
    if (query.isNotEmpty) {
      list = list.where((f) {
        final dot = f.filename.lastIndexOf('.');
        final ext = dot < 0 ? '' : f.filename.substring(dot + 1);
        return [
          f.filename,
          ext,
          f.mimeType,
          FileTypeStyle.of(f.filename).label,
        ].any((v) => v.toLowerCase().contains(query));
      }).toList();
    }
    switch (_sort) {
      case _Sort.name:
        list.sort(
          (a, b) =>
              a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
        );
      case _Sort.largest:
        list.sort((a, b) => b.fileSize.compareTo(a.fileSize));
      case _Sort.newest:
      case _Sort.suggested:
      case _Sort.files:
        list.sort(
          (a, b) => _dateValue(b.createdAt).compareTo(_dateValue(a.createdAt)),
        );
    }
    return list;
  }

  int _dateValue(String raw) =>
      parseServerDate(raw)?.millisecondsSinceEpoch ?? 0;

  void _clearSearch() {
    _search.clear();
    setState(() {});
  }

  void _toast(String message) => fileToast(context, message);

  Future<void> _openFolder(FileCollection row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FileExplorerScreen(service: _service, folderId: row.id),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    } else {
      await _load();
    }
  }

  Future<void> _openUpload(
    FileUploadMode mode, {
    FileCollection? target,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            FileUploadScreen(service: _service, mode: mode, target: target),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _uploadInto(FileCollection folder) async {
    if (folder.isInstaller) {
      await _openUpload(FileUploadMode.replace, target: folder);
      return;
    }
    final mode = await showModalBottomSheet<FileUploadMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.brand.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Where should these files go?',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
            ),
            const Hairline(),
            ListTile(
              minVerticalPadding: 12,
              leading: const IconTile(
                icon: Icons.folder_open_rounded,
                color: Brand.warning,
                size: 40,
                iconSize: 20,
              ),
              title: Text('Into "${folder.displayName}"'),
              subtitle: const Text(
                'The files land in this folder and share its link.',
              ),
              onTap: () => Navigator.of(ctx).pop(FileUploadMode.intoFolder),
            ),
            ListTile(
              minVerticalPadding: 12,
              leading: const IconTile(
                icon: Icons.create_new_folder_rounded,
                size: 40,
                iconSize: 20,
              ),
              title: const Text('As a new subfolder'),
              subtitle: const Text(
                'Creates a named subfolder here with its own share link.',
              ),
              onTap: () => Navigator.of(ctx).pop(FileUploadMode.subfolder),
            ),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    await _openUpload(mode, target: folder);
  }

  Future<void> _run(Future<FileResult> Function() task, String success) async {
    setState(() => _busy = true);
    final res = await task();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message ?? 'That did not work. Please try again.');
      return;
    }
    _changed = true;
    _toast(success);
    await _load();
  }

  Future<void> _newFolder({FileCollection? parent}) async {
    final name = await promptForText(
      context,
      title: parent == null
          ? 'New folder'
          : 'New folder in "${parent.displayName}"',
      confirmLabel: 'Create folder',
      hint: 'Folder name',
    );
    if (name == null || !mounted) return;
    await _run(
      () => _service.createFolder(name, parentId: parent?.id),
      'Folder created',
    );
  }

  Future<void> _rename(FileCollection row) async {
    final name = await promptForText(
      context,
      title: 'Rename folder',
      confirmLabel: 'Save name',
      initial: row.name,
    );
    if (name == null || !mounted) return;
    await _run(() => _service.renameCollection(row.id, name), 'Folder renamed');
  }

  Future<void> _move(FileCollection row) async {
    final blocked = <String>{row.id};
    final stack = _childrenOf(row.id).toList();
    var guard = 0;
    while (stack.isNotEmpty && guard++ < 5000) {
      final current = stack.removeLast();
      blocked.add(current.id);
      stack.addAll(_childrenOf(current.id));
    }

    final options = <({String? id, String label})>[
      (id: null, label: 'All Collections (root level)'),
    ];
    void walk(String? parentId, int depth) {
      for (final child in _childrenOf(parentId)) {
        if (!blocked.contains(child.id)) {
          options.add((
            id: child.id,
            label: '${'    ' * depth}${child.displayName}',
          ));
        }
        walk(child.id, depth + 1);
      }
    }

    walk(null, 0);

    var selected = row.parentId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('Move "${row.displayName}"'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick the folder it should live in. Everything inside moves '
                  'with it.',
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        _PickRow(
                          label: option.label,
                          selected: selected == option.id,
                          onTap: () => setInner(() => selected = option.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Move folder'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => _service.moveCollection(row.id, selected), 'Folder moved');
  }

  Future<void> _changeType(FileCollection row) async {
    var type = row.isDistribution ? 'distribution' : 'default';
    final url = TextEditingController(text: row.playStoreUrl);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Change type'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Switch how "${row.displayName}" is shared. The files '
                  'themselves are untouched.',
                ),
                const SizedBox(height: 8),
                _PickRow(
                  label: 'Default',
                  subtitle: 'Expiring + permanent link',
                  selected: type == 'default',
                  onTap: () => setInner(() => type = 'default'),
                ),
                _PickRow(
                  label: 'Distribution',
                  subtitle: 'Single permanent link, e.g. an APK',
                  selected: type == 'distribution',
                  onTap: () => setInner(() => type = 'distribution'),
                ),
                if (type == 'distribution') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Play Store URL (optional)',
                      hintText:
                          'https://play.google.com/store/apps/details?id=…',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save type'),
            ),
          ],
        ),
      ),
    );
    final playStore = url.text.trim();
    url.dispose();
    if (confirmed != true || !mounted) return;
    if (type == 'distribution' &&
        playStore.isNotEmpty &&
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(playStore)) {
      _toast('Play Store URL must start with http:// or https://');
      return;
    }
    await _run(
      () =>
          _service.updateCollectionType(row.id, type, playStoreUrl: playStore),
      type == 'distribution'
          ? 'Type changed to Distribution.'
          : 'Type changed to Default.',
    );
  }

  Future<void> _editReleaseNotes(FileCollection row) async {
    final notes = TextEditingController(text: row.releaseNotes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release notes'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.vendorVisible
                    ? 'What this build contains. One change per line — vendors '
                          'see this on their portal dashboard as soon as you save.'
                    : 'What this build contains. One change per line — this '
                          'installer is not published to vendors, so only staff '
                          'see it.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText:
                      'Added BIR 2303 auto-fill\nFixed receipt reprint on '
                      'thermal printers',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save notes'),
          ),
        ],
      ),
    );
    final value = notes.text.trim();
    notes.dispose();
    if (confirmed != true || !mounted) return;
    await _run(
      () => _service.setReleaseNotes(row.id, value),
      value.isEmpty ? 'Release notes cleared.' : 'Release notes saved.',
    );
  }

  Future<void> _toggleFavorite(FileCollection row) async {
    final next = !row.isFavorite;
    await _run(
      () => _service.setFavorite(row.id, next),
      next ? 'Added to favorites' : 'Removed from favorites',
    );
  }

  Future<void> _toggleVendor(FileCollection row) async {
    final next = !row.vendorVisible;
    await _run(
      () => _service.setVendorVisible(row.id, next),
      next
          ? 'Shared — vendors can see this in their portal.'
          : 'Hidden from the vendor portal.',
    );
  }

  Future<void> _toggleOjt(FileCollection row) async {
    final next = !row.ojtVisible;
    setState(() => _busy = true);
    final res = await _service.setOjtVisible(row.id, next);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not change OJT visibility.');
      return;
    }
    _changed = true;
    final access = res.data['ojt_files_access'] == true;
    final shared = int.tryParse('${res.data['ojt_shared_count'] ?? 0}') ?? 0;
    if (next) {
      _toast(
        access
            ? 'Shared — OJT accounts now have Files Management access, limited '
                  'to folders shared with them.'
            : 'Shared — OJT accounts can now see this folder.',
      );
    } else if (!access && shared == 0) {
      _toast(
        'Hidden from OJT accounts. No folders are shared with OJT, so their '
        'Files Management access was turned off.',
      );
    } else {
      _toast('Hidden from OJT accounts.');
    }
    await _load();
  }

  Future<void> _deleteCollection(FileCollection row) async {
    final ok = await confirmAction(
      context,
      title: row.isInstaller
          ? 'Delete this installer?'
          : 'Delete this collection?',
      body: row.isInstaller
          ? 'The installer "${row.displayName}" and its package will be '
                'permanently removed, and its download link will stop working '
                'for anyone who already has it.'
          : 'The collection "${row.displayName}" and all of its files will be '
                'permanently removed.',
      confirmLabel: row.isInstaller ? 'Delete installer' : 'Delete collection',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await _service.deleteCollection(row.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the collection.');
      return;
    }
    _toast(row.isInstaller ? 'Installer deleted' : 'Collection deleted');
    if (!_isRoot && row.id == widget.folderId) {
      Navigator.of(context).pop(true);
      return;
    }
    _changed = true;
    await _load();
  }

  Future<void> _deleteFile(StoredFile file) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this file?',
      body:
          'The file "${file.filename}" will be permanently removed from the '
          'collection.',
      confirmLabel: 'Delete file',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await _service.deleteItem(file.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the file.');
      return;
    }
    _changed = true;
    _toast('File deleted');
    await _load();
  }

  Future<void> _download(StoredFile file) async {
    _toast('Downloading "${file.filename}"…');
    final res = await _service.download(file);
    if (!mounted) return;
    if (res.path == null) {
      _toast(res.error ?? 'Download failed.');
      return;
    }
    final opened = await OpenFilex.open(res.path!);
    if (!mounted) return;
    if (opened.type != ResultType.done) {
      _toast('Saved to ${res.path}');
    }
  }

  Future<void> _showChecksum(StoredFile file) async {
    _toast('Computing checksum…');
    final res = await _service.checksum(file.id);
    if (!mounted) return;
    final sum = res.checksum;
    if (sum == null) {
      _toast(res.error ?? 'Checksum unavailable.');
      return;
    }
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File integrity'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sum.fileName, style: text.titleSmall),
              Text(
                '${_grouped(sum.fileSize)} bytes',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
              const SizedBox(height: 10),
              Text(
                'SHA-256 — the downloaded copy is intact if its size and hash '
                'match exactly:',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: b.surfaceHi,
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  border: Border.all(color: b.rule),
                ),
                child: SelectableText(
                  sum.sha256,
                  style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Windows: certutil -hashfile <file> SHA256 · Linux/macOS: '
                'sha256sum <file>',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sum.sha256));
              Navigator.of(ctx).pop();
              _toast('Hash copied');
            },
            child: const Text('Copy hash'),
          ),
        ],
      ),
    );
  }

  String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  void _copy(String url, String message) {
    Clipboard.setData(ClipboardData(text: url));
    _toast(message);
  }

  Future<void> _copyExpiring(FileCollection row) async {
    final link = await _service.getShareLink(row.id);
    if (!mounted) return;
    if (link == null) {
      _toast('Failed to get share link');
      return;
    }
    if (link.expired || !link.hasExpiring) {
      _toast('This share link has expired. Generate a new one.');
      await _load();
      return;
    }
    _copy(
      _service.shareUrl(link.token!),
      'Share link copied! Expires in 2 hours.',
    );
  }

  Future<void> _generateExpiring(FileCollection row) async {
    final link = await _service.generateExpiringLink(row.id);
    if (!mounted) return;
    if (link == null) {
      _toast('Failed to generate link');
      return;
    }
    _changed = true;
    _copy(
      _service.shareUrl(link.token!),
      'New share link generated & copied! Expires in 2 hours.',
    );
    await _load();
  }

  Future<void> _copyPermanent(FileCollection row, String message) async {
    final link = await _service.getShareLink(row.id);
    if (!mounted) return;
    if (link == null || !link.hasPermanent) {
      _toast('Permanent link unavailable');
      return;
    }
    _copy(_service.shareUrl(link.permanentToken!), message);
  }

  Future<void> _permanentLinkAction(FileCollection row) async {
    if (!row.hasPermanentLink) {
      final ok = await confirmAction(
        context,
        title: 'Generate a permanent link?',
        body:
            'It never expires. Anyone the URL reaches keeps access until you '
            'revoke it. Every visit is logged for audit. Use only when '
            'long-term access is genuinely required.',
        confirmLabel: 'Generate it',
        danger: false,
      );
      if (!ok || !mounted) return;
      final token = await _service.generatePermanentLink(row.id);
      if (!mounted) return;
      if (token == null) {
        _toast('Failed to generate permanent link');
        return;
      }
      _changed = true;
      _copy(
        _service.shareUrl(token),
        'Permanent link generated & copied. Treat it like a password.',
      );
      await _load();
      return;
    }

    final link = await _service.getShareLink(row.id);
    if (!mounted) return;
    if (link == null || !link.hasPermanent) {
      _toast('Permanent link unavailable');
      await _load();
      return;
    }
    final url = _service.shareUrl(link.permanentToken!);
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanent link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Brand.danger.withValues(alpha: b.isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  border: Border.all(
                    color: Brand.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Active. Anyone with the URL can download these files.',
                  style: text.bodySmall?.copyWith(
                    color: chipInk(context, Brand.danger),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(url, style: text.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('revoke'),
            child: const Text('Revoke'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('rotate'),
            child: const Text('Rotate'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('copy'),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'copy') {
      _copy(url, 'Permanent link copied.');
      return;
    }
    if (choice == 'rotate') {
      final ok = await confirmAction(
        context,
        title: 'Rotate permanent link?',
        body:
            'The current URL will stop working immediately. A new one will '
            'replace it.',
        confirmLabel: 'Rotate',
      );
      if (!ok || !mounted) return;
      final token = await _service.generatePermanentLink(row.id);
      if (!mounted) return;
      if (token == null) {
        _toast('Failed to rotate');
        return;
      }
      _changed = true;
      _copy(
        _service.shareUrl(token),
        'Rotated & copied. Old link is now dead.',
      );
      await _load();
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Revoke permanent link?',
      body:
          'The URL will stop working immediately. The expiring link is '
          'unaffected.',
      confirmLabel: 'Revoke',
    );
    if (!ok || !mounted) return;
    await _run(
      () => _service.revokePermanentLink(row.id),
      'Permanent link revoked.',
    );
  }

  Future<void> _actions(FileCollection row, {bool fromHeader = false}) async {
    final installer = row.isInstaller;
    final canShareOjt = _service.canShareOjt;
    final items = <Widget>[];

    void tile({
      required IconData icon,
      required String label,
      String? subtitle,
      Color? color,
      required VoidCallback onTap,
    }) {
      items.add(
        ListTile(
          minVerticalPadding: 12,
          leading: IconTile(icon: icon, color: color, size: 40, iconSize: 20),
          title: Text(label),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
        ),
      );
    }

    if (!fromHeader) {
      tile(
        icon: Icons.folder_open_rounded,
        label: 'Open',
        onTap: () => _openFolder(row),
      );
    }
    if (!installer) {
      tile(
        icon: Icons.create_new_folder_rounded,
        label: 'New subfolder',
        onTap: () => _newFolder(parent: row),
      );
      tile(
        icon: Icons.drive_file_rename_outline_rounded,
        label: 'Rename',
        onTap: () => _rename(row),
      );
      tile(
        icon: Icons.drive_file_move_rounded,
        label: 'Move to…',
        onTap: () => _move(row),
      );
      tile(
        icon: Icons.upload_file_rounded,
        label: 'Add files here',
        subtitle: 'They land in this folder and share its link',
        onTap: () => _openUpload(FileUploadMode.intoFolder, target: row),
      );
      tile(
        icon: Icons.create_new_folder_rounded,
        label: 'Upload as a new subfolder',
        subtitle: 'Creates a named subfolder here with its own share link',
        onTap: () => _openUpload(FileUploadMode.subfolder, target: row),
      );
    }
    tile(
      icon: Icons.published_with_changes_rounded,
      label: installer ? 'Change installer file' : 'Replace all files',
      subtitle: installer
          ? 'Upload the new .zip or .rar package'
          : 'Keeps the name and links, swaps the contents',
      onTap: () => _openUpload(FileUploadMode.replace, target: row),
    );
    tile(
      icon: row.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
      label: row.isFavorite ? 'Remove from favorites' : 'Add to favorites',
      color: Brand.warning,
      onTap: () => _toggleFavorite(row),
    );
    if (installer) {
      tile(
        icon: Icons.checklist_rounded,
        label: 'Release notes',
        onTap: () => _editReleaseNotes(row),
      );
    }
    if (row.isDistribution || installer) {
      tile(
        icon: Icons.all_inclusive_rounded,
        label: installer ? 'Copy installer link' : 'Copy distribution link',
        color: Brand.success,
        onTap: () => _copyPermanent(
          row,
          installer ? 'Installer link copied.' : 'Distribution link copied.',
        ),
      );
    } else {
      if (row.linkExpired) {
        tile(
          icon: Icons.sync_rounded,
          label: 'Generate expiring link',
          color: Brand.info,
          onTap: () => _generateExpiring(row),
        );
      } else {
        tile(
          icon: Icons.link_rounded,
          label: 'Copy expiring link',
          subtitle: 'Valid for 2 hours',
          color: Brand.info,
          onTap: () => _copyExpiring(row),
        );
      }
      tile(
        icon: row.hasPermanentLink
            ? Icons.all_inclusive_rounded
            : Icons.key_rounded,
        label: row.hasPermanentLink ? 'Permanent link' : 'Make permanent',
        color: Brand.success,
        onTap: () => _permanentLinkAction(row),
      );
    }
    if (!installer) {
      tile(
        icon: Icons.swap_horiz_rounded,
        label: 'Change type',
        onTap: () => _changeType(row),
      );
      tile(
        icon: row.vendorVisible
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
        label: 'Share to Vendor Portal',
        onTap: () => _toggleVendor(row),
      );
      if (canShareOjt) {
        tile(
          icon: row.ojtVisible
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          label: 'Share to OJT',
          onTap: () => _toggleOjt(row),
        );
      }
    }
    tile(
      icon: Icons.delete_outline_rounded,
      label: installer ? 'Delete installer' : 'Delete collection',
      color: Brand.danger,
      onTap: () => _deleteCollection(row),
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.brand.surface,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.displayName,
                        style: Theme.of(ctx).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _statusPill(row),
                  ],
                ),
              ),
              const Hairline(),
              Flexible(child: ListView(shrinkWrap: true, children: items)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fileActions(StoredFile file, bool installerCollection) async {
    final style = FileTypeStyle.of(file.filename);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.brand.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  FileTypeTile(
                    icon: style.icon,
                    color: style.color,
                    size: 38,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.filename,
                          style: Theme.of(ctx).textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${humanFileSize(file.fileSize)} · '
                          '${formatDateLabel(file.createdAt)}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Hairline(),
            ListTile(
              minVerticalPadding: 12,
              leading: const IconTile(
                icon: Icons.download_rounded,
                color: Brand.info,
                size: 40,
                iconSize: 20,
              ),
              title: const Text('Download'),
              onTap: () {
                Navigator.of(ctx).pop();
                _download(file);
              },
            ),
            ListTile(
              minVerticalPadding: 12,
              leading: const IconTile(
                icon: Icons.fingerprint_rounded,
                size: 40,
                iconSize: 20,
              ),
              title: const Text('Show SHA-256'),
              subtitle: const Text('Verify the downloaded copy is intact'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showChecksum(file);
              },
            ),
            if (!installerCollection)
              ListTile(
                minVerticalPadding: 12,
                leading: const IconTile(
                  icon: Icons.delete_outline_rounded,
                  color: Brand.danger,
                  size: 40,
                  iconSize: 20,
                ),
                title: const Text('Delete file'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteFile(file);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(FileCollection row) {
    if (row.isInstaller) {
      return const StatusPill(
        label: 'Installer',
        color: Brand.success,
        icon: Icons.all_inclusive_rounded,
      );
    }
    if (row.isDistribution) {
      return const StatusPill(
        label: 'Distribution',
        color: Brand.success,
        icon: Icons.all_inclusive_rounded,
      );
    }
    return row.linkExpired
        ? const StatusPill(
            label: 'Link expired',
            color: Brand.danger,
            icon: Icons.error_outline_rounded,
          )
        : const StatusPill(
            label: 'Active link',
            color: Brand.success,
            icon: Icons.check_circle_outline_rounded,
          );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final current = _collection;
    final title = _isRoot ? 'Files' : (current?.displayName ?? 'Collection');
    return StationScaffold(
      stationNumber: '14',
      stationLabel: _isRoot ? 'Files' : 'Collection',
      title: title,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_changed),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (!_isRoot && current != null)
            StationAction(
              icon: Icons.more_vert_rounded,
              tooltip: 'Collection actions',
              onPressed: () => _actions(current, fromHeader: true),
            ),
          if (current == null || !current.isInstaller)
            StationAction(
              icon: Icons.create_new_folder_rounded,
              tooltip: _isRoot ? 'New folder' : 'New subfolder',
              onPressed: () => _newFolder(parent: current),
            ),
          StationAction(
            icon: Icons.upload_file_rounded,
            tooltip: _isRoot ? 'Upload files' : 'Upload here',
            onPressed: () => current == null
                ? _openUpload(FileUploadMode.newCollection)
                : _uploadInto(current),
          ),
        ],
      ),
      child: RefreshIndicator(
        color: b.signal,
        backgroundColor: b.surface,
        onRefresh: _load,
        child: _loading
            ? const SkeletonList(count: 6)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (_isRoot) ...[
                    _statsRow(),
                    const SizedBox(height: 14),
                  ] else ...[
                    _breadcrumbs(),
                    const SizedBox(height: 14),
                    if (current != null) _folderHero(current),
                    const SizedBox(height: 18),
                  ],
                  AppSearchField(
                    controller: _search,
                    hint: _isRoot
                        ? 'Search collections'
                        : 'Search inside this folder',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _filterRow(),
                  const SizedBox(height: 16),
                  ..._folderSection(),
                  if (!_isRoot && current != null) ...[
                    const SizedBox(height: 20),
                    ..._fileSection(current),
                    const SizedBox(height: 22),
                    _shareSection(current),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _filterRow() {
    final canInstaller = _service.canInstaller;
    final filters = <_Filter>[
      _Filter.collections,
      _Filter.favorites,
      _Filter.distribution,
      if (canInstaller) _Filter.installer,
    ];
    return Row(
      children: [
        if (_isRoot)
          Expanded(
            child: ChoicePills<_Filter>(
              options: filters,
              value: _filter,
              labelOf: (f) => switch (f) {
                _Filter.collections => 'Collections',
                _Filter.favorites => 'Favorites',
                _Filter.distribution => 'Distribution',
                _Filter.installer => 'Installer',
              },
              onChanged: (f) => setState(() => _filter = f),
            ),
          )
        else
          Expanded(
            child: Text(
              'Sorted by ${_sortLabel(_sort).toLowerCase()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(width: 8),
        _sortButton(),
      ],
    );
  }

  String _sortLabel(_Sort sort) => switch (sort) {
    _Sort.suggested => 'Suggested',
    _Sort.name => 'Name',
    _Sort.newest => 'Newest',
    _Sort.largest => 'Largest',
    _Sort.files => 'Most files',
  };

  Widget _sortButton() {
    final b = context.brand;
    return Material(
      color: b.surface,
      shape: StadiumBorder(side: BorderSide(color: b.rule)),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<_Sort>(
        tooltip: 'Sort',
        initialValue: _sort,
        onSelected: (s) => setState(() => _sort = s),
        itemBuilder: (_) => [
          for (final s in _Sort.values)
            PopupMenuItem<_Sort>(value: s, child: Text(_sortLabel(s))),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort_rounded, size: 18, color: b.paperDim),
              const SizedBox(width: 6),
              Text(
                _sortLabel(_sort),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: b.paper),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsRow() {
    final rows = _isRoot
        ? _all.where(
            (r) =>
                _filter == _Filter.installer ? r.isInstaller : !r.isInstaller,
          )
        : const <FileCollection>[];
    final files = rows.fold<int>(0, (sum, r) => sum + r.fileCount);
    final size = rows.fold<int>(0, (sum, r) => sum + r.totalSize);
    final usage = _usage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                Icons.folder_rounded,
                Brand.warning,
                '${rows.length}',
                'Collections',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                Icons.insert_drive_file_rounded,
                Brand.info,
                '$files',
                'Files',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                Icons.storage_rounded,
                Brand.success,
                humanFileSize(size),
                'Total size',
              ),
            ),
          ],
        ),
        if (usage != null) ...[const SizedBox(height: 10), _storageCard(usage)],
      ],
    );
  }

  Widget _statCard(IconData icon, Color color, String value, String label) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      radius: Brand.radius,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FileTypeTile(icon: icon, color: color, size: 32, iconSize: 16),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: b.paperDim),
          ),
        ],
      ),
    );
  }

  Widget _storageCard(StorageUsage usage) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final color = usage.critical
        ? Brand.danger
        : usage.warning
        ? Brand.warning
        : Brand.success;
    if (!usage.available) {
      return AppCard(
        radius: Brand.radiusLg,
        child: Row(
          children: [
            const IconTile(
              icon: Icons.sd_storage_rounded,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Server disk space is not reported by this host.',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: color.withValues(alpha: b.isDark ? 0.34 : 0.26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FileTypeTile(
                icon: Icons.sd_storage_rounded,
                color: color,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${humanFileSize(usage.diskFree)} free',
                      style: text.titleSmall,
                    ),
                    Text(
                      '${usage.usedPercent.toStringAsFixed(1)}% of '
                      '${humanFileSize(usage.diskTotal)} used',
                      style: text.bodySmall?.copyWith(color: b.paperDim),
                    ),
                  ],
                ),
              ),
              if (usage.critical || usage.warning)
                StatusPill(
                  label: usage.critical ? 'Critical' : 'Low',
                  color: color,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressTrack(value: usage.usedPercent / 100, color: color),
          const SizedBox(height: 8),
          Text(
            'This app stores ${humanFileSize(usage.managedBytes)} — '
            'collections ${humanFileSize(usage.collectionsBytes)}, folder sync '
            '${humanFileSize(usage.folderSyncBytes)} '
            '(${usage.folderSyncFiles} files)'
            '${usage.folderSyncPartial ? ', partial scan' : ''}.',
            style: text.bodySmall?.copyWith(color: b.paperDim),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumbs() {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final trail = widget.folderId == null
        ? const <FileCollection>[]
        : _pathOf(widget.folderId!);
    final crumbs = <Widget>[
      _crumb(
        label: 'Files',
        icon: Icons.home_rounded,
        active: false,
        onTap: () {
          final depth = trail.isEmpty ? 1 : trail.length;
          var popped = 0;
          Navigator.of(context).popUntil((_) => popped++ >= depth);
        },
      ),
    ];
    for (var i = 0; i < trail.length; i++) {
      final node = trail[i];
      final last = i == trail.length - 1;
      crumbs.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right_rounded, size: 18, color: b.paperDim),
        ),
      );
      crumbs.add(
        _crumb(
          label: node.displayName,
          icon: last ? Icons.folder_open_rounded : Icons.folder_rounded,
          active: last,
          onTap: last
              ? null
              : () {
                  final depth = trail.length - 1 - i;
                  var popped = 0;
                  Navigator.of(context).popUntil((_) => popped++ >= depth);
                },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: crumbs),
        ),
        const SizedBox(height: 6),
        Text(
          '${_childrenOf(widget.folderId).length} folders · '
          '${_files.length} files',
          style: text.bodySmall?.copyWith(color: b.paperDim),
        ),
      ],
    );
  }

  Widget _crumb({
    required String label,
    required IconData icon,
    required bool active,
    VoidCallback? onTap,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: active ? b.signalInk : b.paperDim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(
                color: active ? b.signalInk : b.paperDim,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (active) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
          border: Border.all(color: b.signal.withValues(alpha: 0.4)),
        ),
        child: body,
      );
    }
    return Material(
      color: b.surface,
      shape: StadiumBorder(side: BorderSide(color: b.rule)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: body),
    );
  }

  Widget _folderHero(FileCollection row) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final totals = _subtreeTotals(row);
    final accent = row.isInstaller
        ? Brand.success
        : row.isDistribution
        ? b.signal
        : Brand.warning;
    return GlassPanel(
      accent: accent,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileTypeTile(
                icon: row.isInstaller
                    ? Icons.inventory_2_rounded
                    : row.isDistribution
                    ? Icons.folder_shared_rounded
                    : Icons.folder_open_rounded,
                color: accent,
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _files.length == 1
                          ? '1 file here'
                          : '${_files.length} files here',
                      style: text.headlineSmall?.copyWith(color: b.paper),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${totals.files} in total · ${humanFileSize(totals.size)}'
                      '${totals.folders > 0 ? ' · ${totals.folders} subfolders' : ''}',
                      style: text.bodySmall?.copyWith(color: b.paperDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusPill(row),
              if (row.isFavorite)
                const StatusPill(
                  label: 'Favorite',
                  color: Brand.warning,
                  icon: Icons.star_rounded,
                ),
              if (row.ojtVisible)
                const StatusPill(
                  label: 'OJT',
                  color: Brand.info,
                  icon: Icons.school_rounded,
                ),
              if (row.vendorVisible)
                const StatusPill(
                  label: 'Vendors',
                  color: Brand.success,
                  icon: Icons.storefront_rounded,
                ),
              if (formatDateLabel(row.createdAt).isNotEmpty)
                StatusPill(
                  label: formatDateLabel(row.createdAt),
                  color: b.paperDim,
                  icon: Icons.schedule_rounded,
                ),
              if (row.email.isNotEmpty)
                StatusPill(
                  label: row.email,
                  color: b.paperDim,
                  icon: Icons.alternate_email_rounded,
                ),
            ],
          ),
          if (row.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Hairline(),
            const SizedBox(height: 12),
            Text('Release notes', style: text.labelLarge),
            const SizedBox(height: 4),
            Text(
              row.releaseNotes.trim(),
              style: text.bodySmall?.copyWith(color: b.paperDim),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _folderSection() {
    final rows = _visibleFolders;
    final label = _isRoot
        ? (_filter == _Filter.installer ? 'Installers' : 'Folders')
        : 'Subfolders';
    final searching = _search.text.trim().isNotEmpty;
    return [
      SectionHeader(
        title: label,
        trailing: Text(
          '${rows.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      if (rows.isEmpty)
        EmptyState(
          icon: searching
              ? Icons.search_off_rounded
              : Icons.folder_open_rounded,
          label: searching ? 'No matches' : 'Nothing here yet',
          hint: searching
              ? 'No folders match your search.'
              : _isRoot
              ? (_filter == _Filter.installer
                    ? 'No installer uploaded yet. Add one global .zip or .rar '
                          'package.'
                    : 'No collections yet. Create a folder or upload your '
                          'first files.')
              : 'No subfolders yet. Use New subfolder to add one here.',
          action: searching
              ? GhostButton(label: 'Clear search', onPressed: _clearSearch)
              : null,
        )
      else
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Stagger(
              index: i,
              child: _CollectionRow(
                row: rows[i],
                totals: _subtreeTotals(rows[i]),
                statusPill: _statusPill(rows[i]),
                onTap: _busy ? null : () => _openFolder(rows[i]),
                onStar: _busy ? null : () => _toggleFavorite(rows[i]),
                onActions: _busy ? null : () => _actions(rows[i]),
              ),
            ),
          ),
    ];
  }

  List<Widget> _fileSection(FileCollection row) {
    final rows = _visibleFiles;
    final searching = _search.text.trim().isNotEmpty;
    return [
      SectionHeader(
        title: 'Files',
        trailing: Text(
          '${rows.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      if (rows.isEmpty)
        EmptyState(
          icon: searching
              ? Icons.search_off_rounded
              : Icons.insert_drive_file_rounded,
          label: searching ? 'No matches' : 'No files',
          hint: searching
              ? 'No files match your search.'
              : 'No files directly in this folder. Pull to refresh.',
          action: searching
              ? GhostButton(label: 'Clear search', onPressed: _clearSearch)
              : null,
        )
      else
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Stagger(
              index: i,
              child: _FileRow(
                file: rows[i],
                onTap: _busy ? null : () => _download(rows[i]),
                onActions: _busy
                    ? null
                    : () => _fileActions(rows[i], row.isInstaller),
              ),
            ),
          ),
    ];
  }

  Widget _shareSection(FileCollection row) {
    final text = Theme.of(context).textTheme;
    final links = _links;
    final expiringUrl =
        (links?.hasExpiring ?? false) && !(links?.expired ?? true)
        ? _service.shareUrl(links!.token!)
        : null;
    final permanentUrl = (links?.hasPermanent ?? false)
        ? _service.shareUrl(links!.permanentToken!)
        : null;
    final expiresAt = parseServerDate(links?.expiresAt);
    final left = expiresAt?.difference(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Share'),
        AppCard(
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const FileTypeTile(
                    icon: Icons.timer_rounded,
                    color: Brand.info,
                    size: 34,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Expiring link', style: text.titleSmall),
                  ),
                  if (links?.expired ?? false)
                    const StatusPill(label: 'Expired', color: Brand.danger),
                ],
              ),
              const SizedBox(height: 12),
              if (expiringUrl != null)
                _linkRow(
                  expiringUrl,
                  subtitle: left == null
                      ? 'Auto-expires 2 hours after it is generated.'
                      : 'Expires in ${formatCountdown(left)}',
                  copyMessage: 'Expiring link copied! Valid for 2 hours.',
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _generateExpiring(row),
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('Generate expiring share link'),
                ),
              const SizedBox(height: 16),
              const Hairline(),
              const SizedBox(height: 16),
              Row(
                children: [
                  const FileTypeTile(
                    icon: Icons.all_inclusive_rounded,
                    color: Brand.success,
                    size: 34,
                    iconSize: 17,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.isInstaller
                          ? 'Installer link'
                          : row.isDistribution
                          ? 'Distribution link'
                          : 'Permanent link',
                      style: text.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (permanentUrl != null) ...[
                _linkRow(
                  permanentUrl,
                  subtitle:
                      'No expiry · every visit is logged. Treat it like a '
                      'password.',
                  copyMessage: 'Permanent link copied.',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Manage',
                        icon: Icons.settings_rounded,
                        onPressed: () => _permanentLinkAction(row),
                      ),
                    ),
                  ],
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _permanentLinkAction(row),
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Generate permanent link'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linkRow(String url, {String? subtitle, required String copyMessage}) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: b.surfaceHi,
            borderRadius: BorderRadius.circular(Brand.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(child: SelectableText(url, style: text.bodySmall)),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _copy(url, copyMessage),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: text.bodySmall?.copyWith(color: b.paperDim)),
        ],
      ],
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.row,
    required this.totals,
    required this.statusPill,
    required this.onTap,
    required this.onStar,
    required this.onActions,
  });

  final FileCollection row;
  final FolderTotals totals;
  final Widget statusPill;
  final VoidCallback? onTap;
  final VoidCallback? onStar;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = row.isInstaller
        ? Brand.success
        : row.isDistribution
        ? b.signal
        : Brand.warning;
    final parts = <String>[
      if (totals.folders > 0)
        '${totals.folders} ${totals.folders == 1 ? 'folder' : 'folders'}',
      '${totals.files} ${totals.files == 1 ? 'file' : 'files'}',
      humanFileSize(totals.size),
    ];
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      borderColor: accent.withValues(alpha: b.isDark ? 0.34 : 0.26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileTypeTile(
                icon: row.isInstaller
                    ? Icons.inventory_2_rounded
                    : row.isDistribution
                    ? Icons.folder_shared_rounded
                    : totals.folders > 0
                    ? Icons.folder_copy_rounded
                    : Icons.folder_rounded,
                color: accent,
                size: 44,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.displayName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      parts.join(' · '),
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: row.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  row.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 20,
                ),
                color: row.isFavorite ? Brand.warning : b.paperDim,
                onPressed: onStar,
              ),
              IconButton(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: b.paperDim,
                onPressed: onActions,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                statusPill,
                if (row.ojtVisible)
                  const StatusPill(
                    label: 'OJT',
                    color: Brand.info,
                    icon: Icons.school_rounded,
                  ),
                if (row.vendorVisible)
                  const StatusPill(
                    label: 'Vendors',
                    color: Brand.success,
                    icon: Icons.storefront_rounded,
                  ),
                if (row.hasPermanentLink)
                  const StatusPill(
                    label: 'Permanent link',
                    color: Brand.success,
                    icon: Icons.link_rounded,
                  ),
                if (formatDateLabel(row.createdAt).isNotEmpty)
                  StatusPill(
                    label: formatDateLabel(row.createdAt),
                    color: b.paperDim,
                    icon: Icons.schedule_rounded,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.onTap,
    required this.onActions,
  });

  final StoredFile file;
  final VoidCallback? onTap;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final style = FileTypeStyle.of(file.filename);
    final date = formatDateLabel(file.createdAt);
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: style.color.withValues(alpha: b.isDark ? 0.34 : 0.26),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          FileTypeTile(icon: style.icon, color: style.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.filename.isEmpty ? 'Unnamed file' : file.filename,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    FileChip(label: style.label, color: style.color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${humanFileSize(file.fileSize)}'
                        '${date.isEmpty ? '' : ' · $date'}',
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'File actions',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            color: b.paperDim,
            onPressed: onActions,
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? b.signal : b.paperDim,
      ),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      selected: selected,
      onTap: onTap,
    );
  }
}
