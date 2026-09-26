import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/file_models.dart';
import '../services/file_service.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'file_widgets.dart';

enum FileUploadMode { newCollection, subfolder, intoFolder, replace }

class FileUploadScreen extends StatefulWidget {
  const FileUploadScreen({
    super.key,
    required this.service,
    this.mode = FileUploadMode.newCollection,
    this.target,
  });

  final FileService service;
  final FileUploadMode mode;
  final FileCollection? target;

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _playStore = TextEditingController();
  final _releaseNotes = TextEditingController();

  final List<UploadCandidate> _files = [];
  String _type = 'default';
  String _posVersion = '';
  List<String> _versions = const [];

  bool _busy = false;
  bool _changed = false;
  UploadProgress? _progress;
  UploadCancelToken? _cancel;
  UploadOutcome? _done;
  DateTime? _startedAt;

  bool get _isReplace => widget.mode == FileUploadMode.replace;
  bool get _isIntoFolder => widget.mode == FileUploadMode.intoFolder;
  bool get _isSubfolder => widget.mode == FileUploadMode.subfolder;
  bool get _installerTarget =>
      _isReplace && (widget.target?.isInstaller ?? false);
  bool get _installer => _type == 'installer';
  bool get _namesCollection => !_isReplace && !_isIntoFolder;
  bool get _canPickType =>
      widget.mode == FileUploadMode.newCollection ||
      widget.mode == FileUploadMode.subfolder;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    if (_isReplace && target != null && target.isInstaller) {
      _type = 'installer';
      _posVersion = target.posVersion;
      _releaseNotes.text = target.releaseNotes;
    }
    if (widget.service.canInstaller) {
      widget.service.posVersions().then((list) {
        if (!mounted) return;
        setState(() => _versions = list);
      });
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _name.dispose();
    _email.dispose();
    _playStore.dispose();
    _releaseNotes.dispose();
    super.dispose();
  }

  String get _title {
    if (_installerTarget) return 'Change Installer';
    if (_isReplace) return 'Change File';
    if (_isIntoFolder) return 'Upload Here';
    if (_isSubfolder) return 'New Subfolder';
    return 'Upload';
  }

  String get _subtitle {
    if (_installerTarget) {
      return 'Upload the replacement package for '
          '"${widget.target?.displayName ?? 'this installer'}". One .zip or '
          '.rar only — its download link stays the same.';
    }
    if (_isReplace) {
      return 'Upload the replacement for "${widget.target?.displayName ?? 'this collection'}". '
          'Its name and share links stay exactly the same — only the file '
          'changes. Anything currently in the collection is removed.';
    }
    if (_isIntoFolder) {
      return 'These files go straight into "${widget.target?.displayName ?? 'this folder'}" '
          'and are shared by its link.';
    }
    if (_isSubfolder) {
      return 'Creates a named subfolder inside "${widget.target?.displayName ?? 'this folder'}" '
          'with its own share link.';
    }
    return 'Pick your files, name the collection, then we give you one '
        'shareable link for it.';
  }

  Future<void> _pick() async {
    final picked = await pickWithSource(
      context,
      multiple: !_installer && !_isReplace,
      allowCamera: false,
      allowedExtensions: _installer ? const ['zip', 'rar'] : null,
      fileLabel: 'Choose files',
      onError: (m) => fileToast(context, m),
    );
    if (picked.isEmpty || !mounted) return;
    final next = <UploadCandidate>[];
    for (final file in picked) {
      var size = 0;
      try {
        size = await io.File(file.path).length();
      } catch (_) {}
      next.add((path: file.path, name: file.name, size: size));
    }
    if (!mounted) return;
    setState(() {
      if (_installer || _isReplace) {
        _files
          ..clear()
          ..add(next.first);
      } else {
        for (final candidate in next) {
          if (_files.any((f) => f.path == candidate.path)) continue;
          _files.add(candidate);
        }
      }
      if (_namesCollection && _name.text.trim().isEmpty && !_installer) {
        _name.text = next.first.name;
      }
    });
  }

  Future<void> _loadVersionNotes() async {
    if (_posVersion.isEmpty) return;
    final notes = await widget.service.versionReleaseNotes(_posVersion);
    if (!mounted) return;
    if (notes == null || notes.trim().isEmpty) {
      fileToast(context, 'No release notes are recorded for $_posVersion yet.');
      return;
    }
    setState(() => _releaseNotes.text = notes);
  }

  int get _totalBytes => _files.fold<int>(0, (sum, f) => sum + f.size);

  bool _validate() {
    if (_files.isEmpty) {
      fileToast(
        context,
        _isReplace
            ? 'Please select the replacement file'
            : 'Please select files to upload',
      );
      return false;
    }
    if (_installer) {
      final ext = _files.first.name.split('.').last.toLowerCase();
      if (_files.length != 1 || (ext != 'zip' && ext != 'rar')) {
        fileToast(
          context,
          'Installer upload accepts one .zip or .rar file only.',
        );
        return false;
      }
      if (_posVersion.isEmpty) {
        fileToast(
          context,
          'Please select the POS version this installer ships.',
        );
        return false;
      }
      return true;
    }
    if (_namesCollection && _name.text.trim().isEmpty) {
      fileToast(context, 'Please enter a collection name');
      return false;
    }
    final url = _playStore.text.trim();
    if (_type == 'distribution' &&
        url.isNotEmpty &&
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      fileToast(context, 'Play Store URL must start with http:// or https://');
      return false;
    }
    return true;
  }

  Future<void> _upload() async {
    if (_busy || !_validate()) return;
    final token = UploadCancelToken();
    setState(() {
      _busy = true;
      _cancel = token;
      _startedAt = DateTime.now();
      _progress = UploadProgress(
        phase: UploadPhase.preparing,
        sent: 0,
        total: _totalBytes,
        note: 'Preparing…',
      );
    });

    final target = widget.target;
    final outcome = await widget.service.uploadFiles(
      files: List<UploadCandidate>.from(_files),
      collectionName: _installerTarget
          ? (widget.target?.name ?? '')
          : _installer
          ? (_name.text.trim().isEmpty
                ? 'POS Installer $_posVersion'
                : _name.text.trim())
          : _name.text.trim(),
      email: _installer || _isReplace || _isIntoFolder
          ? ''
          : _email.text.trim(),
      collectionType: _installerTarget
          ? 'installer'
          : (_isReplace || _isIntoFolder ? 'default' : _type),
      playStoreUrl: _playStore.text.trim(),
      parentId: _isSubfolder ? target?.id : null,
      addToCollectionId: _isIntoFolder ? target?.id : null,
      replaceCollectionId: _isReplace && !_installerTarget ? target?.id : null,
      installerCollectionId: _installerTarget ? target?.id : null,
      installerStrict: _installerTarget,
      posVersion: _posVersion,
      releaseNotes: _releaseNotes.text.trim(),
      cancelToken: token,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _cancel = null;
      _progress = null;
    });

    if (outcome.cancelled) {
      fileToast(context, 'Upload cancelled');
      return;
    }
    if (!outcome.ok) {
      fileToast(context, outcome.message ?? 'Upload failed.');
      return;
    }
    _changed = true;
    if (outcome.replaced || outcome.added || _isIntoFolder || _isReplace) {
      if (!mounted) return;
      fileToast(context, outcome.message ?? 'Upload complete');
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _done = outcome);
  }

  void _reset() {
    setState(() {
      _done = null;
      _files.clear();
      _name.clear();
      _email.clear();
      _playStore.clear();
      _releaseNotes.clear();
      _posVersion = '';
      _type = 'default';
    });
  }

  void _copy(String url, String message) {
    Clipboard.setData(ClipboardData(text: url));
    fileToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        fileToast(context, 'Cancel the upload before leaving this screen.');
      },
      child: StationScaffold(
        stationNumber: '14',
        stationLabel: 'Files',
        title: _title,
        showBottomBrand: false,
        onBack: _busy ? null : () => Navigator.of(context).pop(_changed),
        child: _done != null ? _successView(_done!) : _formView(),
      ),
    );
  }

  Widget _formView() {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final style = _files.isEmpty ? null : FileTypeStyle.of(_files.first.name);
    final accent = style?.color ?? b.signal;
    final progress = _progress;
    final ready = (_files.isEmpty ? 0.0 : 0.5) + (_readyMeta ? 0.5 : 0.0);

    return ListView(
      children: [
        Text(_subtitle, style: text.bodySmall?.copyWith(color: b.paperDim)),
        const SizedBox(height: 12),
        GlassPanel(
          accent: accent,
          onTap: _busy ? null : _pick,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              UploadRing(
                progress: _busy ? (progress?.fraction ?? 0) : ready,
                busy: _busy,
                color: accent,
                icon: style?.icon ?? Icons.cloud_upload_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _files.isEmpty
                          ? 'Tap to pick files'
                          : _files.length == 1
                          ? _files.first.name
                          : '${_files.length} files selected',
                      style: text.titleMedium?.copyWith(color: b.paper),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _busy
                          ? (progress?.note ?? 'Uploading…')
                          : _files.isEmpty
                          ? (_installer
                                ? 'One .zip or .rar package'
                                : 'Any file type, any size')
                          : '${humanFileSize(_totalBytes)} total · tap to add more',
                      style: text.bodySmall?.copyWith(color: b.paperDim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.attach_file_rounded, color: b.signalInk, size: 20),
            ],
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._files.map(_pickedRow),
        ],
        if (_busy && progress != null) ...[
          const SizedBox(height: 16),
          _progressCard(progress),
        ],
        const SizedBox(height: 16),
        if (!_busy) ...[_metaCard(), const SizedBox(height: 24)],
        if (_busy)
          GhostButton(
            label: 'Cancel upload',
            icon: Icons.close_rounded,
            onPressed: () => _cancel?.cancel(),
          )
        else
          SignalButton(
            label: _installerTarget
                ? 'Change installer'
                : _isReplace
                ? 'Replace file'
                : _isIntoFolder
                ? 'Upload to folder'
                : _installer
                ? 'Upload & publish installer'
                : 'Upload & get link',
            icon: Icons.upload_rounded,
            onPressed: _upload,
          ),
        const SizedBox(height: 40),
      ],
    );
  }

  bool get _readyMeta {
    if (_installer) return _posVersion.isNotEmpty;
    if (!_namesCollection) return true;
    return _name.text.trim().isNotEmpty;
  }

  Widget _pickedRow(UploadCandidate file) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final style = FileTypeStyle.of(file.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        radius: Brand.radius,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            FileTypeTile(
              icon: style.icon,
              color: style.color,
              size: 34,
              iconSize: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: text.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    humanFileSize(file.size),
                    style: text.bodySmall?.copyWith(color: b.paperDim),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove ${file.name}',
              icon: const Icon(Icons.close_rounded, size: 20),
              color: b.paperDim,
              onPressed: _busy
                  ? null
                  : () => setState(() => _files.remove(file)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard(UploadProgress progress) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final pct = (progress.fraction * 100).round();
    final started = _startedAt;
    var detail =
        '${humanFileSize(progress.sent)} of '
        '${humanFileSize(progress.total)}';
    if (started != null &&
        progress.phase == UploadPhase.sending &&
        progress.sent > 0) {
      final elapsed = DateTime.now().difference(started).inMilliseconds / 1000;
      if (elapsed > 1) {
        final speed = progress.sent / elapsed;
        final remaining = ((progress.total - progress.sent) / speed).round();
        final mins = remaining ~/ 60;
        final secs = remaining % 60;
        detail =
            '$detail · ${humanFileSize(speed)}/s · '
            '${mins > 0 ? '${mins}m ${secs}s' : '${secs}s'} left';
      }
    }
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(switch (progress.phase) {
                  UploadPhase.preparing => 'Preparing…',
                  UploadPhase.sending => 'Uploading…',
                  UploadPhase.retrying => 'Retrying…',
                  UploadPhase.finalizing => 'Processing…',
                }, style: text.titleSmall),
              ),
              Text('$pct%', style: text.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          ProgressTrack(value: progress.fraction),
          const SizedBox(height: 8),
          Text(detail, style: text.bodySmall?.copyWith(color: b.paperDim)),
          if (progress.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              progress.note,
              style: text.bodySmall?.copyWith(color: b.paperDim),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaCard() {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final canInstaller = widget.service.canInstaller;
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_namesCollection) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _installer ? 'Installer name' : 'Collection name',
                style: text.labelLarge,
              ),
            ),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _installer
                    ? 'e.g. Windows Installer'
                    : 'e.g. Project Assets, Photos, Documents…',
                prefixIcon: const Icon(Icons.folder_rounded),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_namesCollection && !_installer) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Your email (optional)', style: text.labelLarge),
            ),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_canPickType) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Type', style: text.labelLarge),
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.swap_horiz_rounded),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'default',
                  child: Text('Default — expiring + permanent link'),
                ),
                const DropdownMenuItem(
                  value: 'distribution',
                  child: Text('Distribution — single permanent link'),
                ),
                if (canInstaller && widget.mode == FileUploadMode.newCollection)
                  const DropdownMenuItem(
                    value: 'installer',
                    child: Text('Installer — published to vendors'),
                  ),
              ],
              onChanged: (v) => setState(() {
                _type = v ?? 'default';
                if (_installer && _files.length > 1) {
                  _files.removeRange(1, _files.length);
                }
              }),
            ),
            const SizedBox(height: 16),
          ],
          if (_type == 'distribution') ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Play Store URL (optional, Android redirect)',
                style: text.labelLarge,
              ),
            ),
            TextField(
              controller: _playStore,
              keyboardType: TextInputType.url,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'https://play.google.com/store/apps/details?id=…',
                prefixIcon: Icon(Icons.link_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_installer) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('POS version', style: text.labelLarge),
            ),
            DropdownButtonFormField<String>(
              initialValue: _posVersion.isEmpty ? null : _posVersion,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'Select a POS version',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              items: [
                for (final v in _versions)
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) {
                setState(() => _posVersion = v ?? '');
                _loadVersionNotes();
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Release notes — what vendors see in their portal',
                    style: text.labelLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _posVersion.isEmpty ? null : _loadVersionNotes,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Reload'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _releaseNotes,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText:
                    'One change per line, e.g.\nAdded BIR 2303 auto-fill\n'
                    'Fixed receipt reprint on thermal printers',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Each installer is global. Uploading one replaces the file for '
              'the selected POS version.',
              style: text.bodySmall?.copyWith(color: b.paperDim),
            ),
          ],
        ],
      ),
    );
  }

  Widget _successView(UploadOutcome outcome) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final distribution =
        outcome.collectionType == 'distribution' ||
        outcome.collectionType == 'installer';
    final expiringUrl = outcome.shareToken.isEmpty
        ? null
        : widget.service.shareUrl(outcome.shareToken);
    final permanentUrl = outcome.permanentShareToken.isEmpty
        ? null
        : widget.service.shareUrl(outcome.permanentShareToken);

    return ListView(
      children: [
        GlassPanel(
          accent: Brand.success,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const FileTypeTile(
                icon: Icons.check_rounded,
                color: Brand.success,
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload complete',
                      style: text.titleMedium?.copyWith(color: b.paper),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your files are ready to share.',
                      style: text.bodySmall?.copyWith(color: b.paperDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!distribution && expiringUrl != null) ...[
          const SectionHeader(title: 'Expiring link'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-expires in 2 hours.',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 10),
                _linkBox(
                  expiringUrl,
                  'Expiring link copied! Valid for 2 hours.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        SectionHeader(
          title: outcome.collectionType == 'installer'
              ? 'Installer link'
              : distribution
              ? 'Distribution link'
              : 'Permanent link',
        ),
        AppCard(
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                permanentUrl == null
                    ? 'A permanent URL stays live until you revoke it. Anyone '
                          'the link reaches keeps access — every visit is logged.'
                    : 'No expiry · revoke from the collection actions anytime.',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
              const SizedBox(height: 10),
              if (permanentUrl != null)
                _linkBox(
                  permanentUrl,
                  'Permanent link copied. Treat it like a password.',
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final token = await widget.service.generatePermanentLink(
                      outcome.collectionId,
                    );
                    if (!mounted) return;
                    if (token == null) {
                      fileToast(context, 'Failed to generate permanent link');
                      return;
                    }
                    setState(() {
                      _done = UploadOutcome(
                        ok: true,
                        collectionId: outcome.collectionId,
                        collectionType: outcome.collectionType,
                        shareToken: outcome.shareToken,
                        expiresAt: outcome.expiresAt,
                        permanentShareToken: token,
                      );
                    });
                    _copy(
                      widget.service.shareUrl(token),
                      'Permanent link generated & copied. Treat it like a password.',
                    );
                  },
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Generate permanent link'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SignalButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Upload more files',
          icon: Icons.add_rounded,
          onPressed: _reset,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _linkBox(String url, String copyMessage) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Container(
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
    );
  }
}
