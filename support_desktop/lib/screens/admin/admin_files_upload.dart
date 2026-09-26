import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/admin_files_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_files_dialogs.dart';
import 'admin_list.dart';

class FmUploadResult {
  const FmUploadResult({this.switchToInstaller = false});
  final bool switchToInstaller;
}

class FmUploadModal extends StatefulWidget {
  const FmUploadModal({
    super.key,
    required this.api,
    required this.mode,
    required this.collections,
    required this.posVersions,
    this.targetId = '',
    this.targetName = '',
    this.folderTarget,
    this.explorerCollectionId,
    required this.onCollectionsChanged,
  });

  final AdminFilesApi api;
  final String mode;
  final List<FmRow> collections;
  final List<({String value, String label})> posVersions;
  final String targetId;
  final String targetName;
  final FmRow? folderTarget;
  final String? explorerCollectionId;
  final VoidCallback onCollectionsChanged;

  @override
  State<FmUploadModal> createState() => _FmUploadModalState();
}

class _FmUploadModalState extends State<FmUploadModal> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  final _play = TextEditingController();
  String _type = 'default';
  String _posVersion = '';
  String _installerId = '';
  String _target = 'folder';
  List<FmPickedFile> _files = [];
  bool _uploading = false;
  FmChunkedUpload? _job;
  bool _showProgress = false;
  int _loaded = 0;
  String _progressLabel = 'Uploading...';
  DateTime _started = DateTime.now();
  bool _cancelVisible = false;
  String _autoNotes = '';
  int _notesReq = 0;
  String _notesHint = '';
  bool _notesReload = false;

  FmRow? _success;
  String _shareLink = '';
  String _permanentLink = '';
  String _permanentLabel = 'Permanent link';
  String _permanentMeta = 'No expiry · revoke from list anytime';
  bool _expiringVisible = true;
  bool _permWarnVisible = true;
  bool _permRowVisible = false;
  bool _permBusy = false;

  bool get _installer => widget.mode == 'installer';
  bool get _replace => widget.mode == 'replace';
  bool get _collections => widget.mode == 'collections';
  bool get _targetEligible => _collections && widget.folderTarget != null;
  bool get _intoFolder => _targetEligible && _target == 'folder';
  bool get _installerType =>
      _collections && _type == 'installer' && !_intoFolder;

  @override
  void initState() {
    super.initState();
    if (_installer) {
      _installerId = widget.targetId;
      final sel = _installerRows.where((c) => '${c['id']}' == _installerId);
      _name.text = sel.isNotEmpty ? '${sel.first['name'] ?? ''}' : 'Installer';
      _notes.text = sel.isNotEmpty ? '${sel.first['release_notes'] ?? ''}' : '';
    }
    if (_collections) _syncNotes(false);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _notes.dispose();
    _play.dispose();
    super.dispose();
  }

  List<FmRow> get _installerRows => widget.collections
      .where((c) => '${c['collection_type']}' == 'installer')
      .toList();

  FmRow? get _currentPublishedInstaller {
    final published = _installerRows
        .where((c) => int.tryParse('${c['vendor_visible']}') == 1)
        .toList();
    published.sort((a, b) {
      final da = DateTime.tryParse('${b['created_at']}') ?? DateTime(0);
      final db = DateTime.tryParse('${a['created_at']}') ?? DateTime(0);
      return da.compareTo(db);
    });
    return published.isEmpty ? null : published.first;
  }

  String get _title {
    if (_replace) return 'Change File';
    if (_installer) {
      return _installerId.isNotEmpty ? 'Change Installer' : 'Upload Installer';
    }
    return 'Upload & Get Link';
  }

  String get _subtitle {
    if (_replace) {
      return 'Upload the replacement for "${widget.targetName.isEmpty ? 'this collection' : widget.targetName}". Its name and share links stay exactly the same — only the file changes. Anything currently in the collection is removed.';
    }
    if (_installer) {
      return 'Each installer is global. Upload one .zip or .rar; when an existing installer is selected, its file is replaced.';
    }
    if (_intoFolder) {
      return 'These files go straight into "${widget.folderTarget!['name'] ?? 'this folder'}" and are shared by its link. Pick the other option if you want them in a subfolder of their own.';
    }
    if (_targetEligible) {
      return "Drop your files in, name the subfolder, then we'll give you one shareable link for it.";
    }
    return "Drop your files in, optionally name the collection, then we'll give you one shareable link.";
  }

  (String, IconData) get _buttonLabel {
    if (_intoFolder) return ('Upload to Folder', Icons.cloud_upload);
    if (_replace) return ('Replace File', Icons.upload);
    if (_installer) {
      return _installerId.isNotEmpty
          ? ('Change Installer', Icons.archive)
          : ('Upload Installer', Icons.archive);
    }
    if (_collections && _type == 'installer') {
      return _currentPublishedInstaller != null
          ? ('Upload & Replace Installer', Icons.sync)
          : ('Upload & Publish Installer', Icons.send);
    }
    return ('Upload & Get Link', Icons.send);
  }

  bool _notesUntouched() =>
      _notes.text.trim().isEmpty || _notes.text == _autoNotes;

  Future<void> _syncNotes(bool force) async {
    final version = _posVersion.trim();
    if (version.isEmpty) {
      if (_notesUntouched()) {
        _notes.text = '';
        _autoNotes = '';
      }
      setState(() {
        _notesHint =
            'Pick a POS version to pull its notes from the Release Notes page.';
        _notesReload = false;
      });
      return;
    }
    if (!force && !_notesUntouched()) {
      setState(() {
        _notesHint =
            'Your own notes are kept — reload to replace them with the Release Notes entries for $version.';
        _notesReload = true;
      });
      return;
    }
    final req = ++_notesReq;
    setState(() {
      _notesHint = 'Loading release notes for $version…';
      _notesReload = false;
    });
    try {
      final data = await widget.api.versionReleaseNotes(version);
      if (!mounted || req != _notesReq) return;
      if (data['success'] != true) throw Exception();
      final notes = '${data['notes'] ?? ''}';
      final count = int.tryParse('${data['count']}') ?? 0;
      setState(() {
        if (notes.isNotEmpty) {
          _notes.text = notes;
          _autoNotes = notes;
          _notesHint =
              'Filled from the Release Notes page — $count entr${count == 1 ? 'y' : 'ies'} for $version. You can edit before uploading.';
        } else {
          if (_notesUntouched()) {
            _notes.text = '';
            _autoNotes = '';
          }
          _notesHint =
              'No entries on the Release Notes page for $version yet — type them here or add them there first.';
        }
        _notesReload = true;
      });
    } catch (_) {
      if (!mounted || req != _notesReq) return;
      setState(() {
        _notesHint = 'Could not load the Release Notes entries for $version.';
        _notesReload = true;
      });
    }
  }

  bool _isInstallerFile(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return ext == 'zip' || ext == 'rar';
  }

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: !_installer,
      type: _installer ? FileType.custom : FileType.any,
      allowedExtensions: _installer ? const ['zip', 'rar'] : null,
    );
    if (picked == null || !mounted) return;
    final got = picked.files
        .where((f) => f.path != null)
        .map((f) => FmPickedFile(f.path!, f.name, f.size))
        .toList();
    if (got.isEmpty) return;
    if (_installer) {
      if (!_isInstallerFile(got.first.name)) {
        toast(context, 'Installer upload accepts .zip or .rar only.');
        return;
      }
      setState(() => _files = [got.first]);
      return;
    }
    setState(() {
      for (final f in got) {
        if (!_files.any((s) => s.name == f.name && s.size == f.size)) {
          _files.add(f);
        }
      }
    });
  }

  int get _total => _files.fold<int>(0, (s, f) => s + f.size);

  Future<void> _upload() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final intoFolderId = _intoFolder ? '${widget.folderTarget!['id']}' : '';
    final collectionType = _installer
        ? 'installer'
        : (intoFolderId.isNotEmpty
              ? 'default'
              : (_type == 'distribution' || _type == 'installer'
                    ? _type
                    : 'default'));
    final posVersion = collectionType == 'installer' ? _posVersion.trim() : '';
    final releaseNotes = collectionType == 'installer'
        ? _notes.text.trim()
        : '';
    final playStoreUrl = _play.text.trim();

    if (_replace && widget.targetId.isEmpty) {
      toast(
        context,
        'No collection selected to change. Please reopen the action.',
      );
      return;
    }
    if (name.isEmpty &&
        _collections &&
        collectionType != 'installer' &&
        intoFolderId.isEmpty) {
      toast(context, 'Please enter a collection name');
      return;
    }
    if (name.isEmpty && _installer) {
      toast(context, 'Please enter an installer name');
      return;
    }
    if (collectionType == 'installer' && _collections && posVersion.isEmpty) {
      toast(context, 'Please select the POS version this installer ships.');
      return;
    }
    if (_files.isEmpty) {
      toast(
        context,
        _replace
            ? 'Please select the replacement file'
            : 'Please select files to upload',
      );
      return;
    }
    if (_installer &&
        (_files.length != 1 || !_isInstallerFile(_files.first.name))) {
      toast(context, 'Installer upload accepts one .zip or .rar file only.');
      return;
    }
    if (collectionType == 'distribution' &&
        playStoreUrl.isNotEmpty &&
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(playStoreUrl)) {
      toast(context, 'Play Store URL must start with http:// or https://');
      return;
    }

    var finalName = name;
    if (collectionType == 'installer' && _collections) {
      try {
        final n = await widget.api.installerName(
          name: name,
          posVersion: posVersion,
          firstFileName: _files.first.name,
        );
        if (n['success'] == true) finalName = '${n['name']}';
      } catch (_) {}
    }

    final meta = FmUploadMeta(
      name: finalName,
      email: collectionType == 'installer' ? '' : email,
      collectionType: collectionType,
      posVersion: posVersion,
      releaseNotes: releaseNotes,
      installerStrict: _installer,
      playStoreUrl: playStoreUrl,
      installerId: _installer ? _installerId : '',
      replaceId: _replace ? widget.targetId : '',
      addToId: intoFolderId,
      parentId:
          (intoFolderId.isEmpty &&
              _collections &&
              (widget.explorerCollectionId ?? '').isNotEmpty)
          ? widget.explorerCollectionId!
          : '',
    );

    final job = FmChunkedUpload(widget.api, meta);
    job.onProgress = (l) {
      if (!mounted) return;
      setState(() {
        _loaded = l;
        final elapsed =
            DateTime.now().difference(_started).inMilliseconds / 1000;
        final pct = _total > 0 ? (l / _total * 100).round().clamp(0, 100) : 0;
        if (pct < 100 && elapsed > 1 && l > 0) {
          final speed = l / elapsed;
          final remaining = (_total - l) / speed;
          final mins = remaining ~/ 60;
          final secs = (remaining % 60).round();
          final eta = mins > 0 ? '${mins}m ${secs}s left' : '${secs}s left';
          _progressLabel = 'Uploading... ${fmSize(speed.round())}/s — $eta';
        }
      });
    };
    job.onLabel = (s) {
      if (mounted) setState(() => _progressLabel = s);
    };
    job.onFinalizing = () {
      if (mounted) {
        setState(() {
          _progressLabel = 'Processing...';
          _cancelVisible = false;
        });
      }
    };
    job.onRetrying = () {
      if (mounted) setState(() => _cancelVisible = true);
    };

    setState(() {
      _job = job;
      _uploading = true;
      _cancelVisible = true;
      _showProgress = true;
      _loaded = 0;
      _progressLabel = 'Uploading...';
      _started = DateTime.now();
    });

    Map<String, dynamic> res;
    try {
      res = await job.run(_files);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _cancelVisible = false;
        _showProgress = false;
        _job = null;
      });
      toast(context, job.errorMessage(err));
      return;
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _cancelVisible = false;
      _job = null;
    });

    if (res['success'] != true) {
      toast(context, '${res['message'] ?? ''}');
      setState(() => _showProgress = false);
      return;
    }
    setState(() {
      _loaded = _total;
      _progressLabel = res['replaced'] == true
          ? 'Replace complete!'
          : 'Upload complete!';
    });
    final installerUpload = '${res['collection_type']}' == 'installer';
    if (!installerUpload) toast(context, '${res['message'] ?? ''}');
    if (installerUpload) {
      final published =
          meta.collectionType == 'installer' &&
          !meta.installerStrict &&
          meta.replaceId.isEmpty;
      final nav = Navigator.of(context, rootNavigator: true);
      Navigator.pop(context, const FmUploadResult(switchToInstaller: true));
      widget.onCollectionsChanged();
      unawaited(
        showWebModal<void>(
          nav.context,
          title: res['replaced'] == true
              ? 'Installer file updated'
              : (meta.posVersion.isNotEmpty
                    ? 'Installer ${meta.posVersion} uploaded'
                    : 'Installer uploaded'),
          icon: Icons.check_circle_outline,
          width: 460,
          builder: (_) => Text(
            published
                ? 'It is now the installer published to vendors in their portal.'
                : 'It is now available on the Installer tab.',
          ),
        ),
      );
      Timer(const Duration(milliseconds: 2600), () {
        if (nav.canPop()) nav.pop();
      });
      return;
    }
    if (res['replaced'] == true || res['added'] == true) {
      Navigator.pop(context, const FmUploadResult());
      widget.onCollectionsChanged();
      return;
    }
    final isDistribution = '${res['collection_type']}' == 'distribution';
    final isInstaller = '${res['collection_type']}' == 'installer';
    setState(() {
      _success = res;
      _files = [];
      _showProgress = false;
      _shareLink = widget.api.shareUrl('${res['share_token'] ?? ''}');
      if (isDistribution || isInstaller) {
        _expiringVisible = false;
        _permWarnVisible = false;
        _permRowVisible = true;
        _permanentLabel = isInstaller ? 'Installer link' : 'Distribution link';
        _permanentMeta = isInstaller
            ? 'Global installer download link'
            : 'For long-term download (e.g. APK)';
        _permanentLink = widget.api.shareUrl(
          '${res['permanent_share_token'] ?? ''}',
        );
      } else {
        _expiringVisible = true;
        _permWarnVisible = true;
        _permRowVisible = false;
        _permanentLabel = 'Permanent link';
        _permanentMeta = 'No expiry · revoke from list anytime';
        _permanentLink = '';
      }
    });
    widget.onCollectionsChanged();
  }

  Future<void> _generatePermanent() async {
    final id = '${_success?['collection_id'] ?? ''}';
    if (id.isEmpty) {
      toast(context, 'Missing collection reference. Please re-upload.');
      return;
    }
    setState(() => _permBusy = true);
    final ok = await fmConfirm(
      context,
      title: 'Issue a permanent link?',
      text:
          'It never expires. Anyone with the URL can download these files until you revoke it.\n\nUse only when you genuinely need long-term access.',
      confirm: 'Yes, generate it',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _permBusy = false);
      return;
    }
    try {
      final res = await widget.api.generatePermanent(id);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(
          context,
          '${res['message'] ?? 'Failed to generate permanent link'}',
        );
        setState(() => _permBusy = false);
        return;
      }
      setState(() {
        _permanentLink = widget.api.shareUrl('${res['permanent_share_token']}');
        _permRowVisible = true;
        _permWarnVisible = false;
      });
      toast(context, 'Permanent link ready. Treat it like a password.');
      widget.onCollectionsChanged();
    } catch (_) {
      if (!mounted) return;
      toast(context, 'Failed to generate permanent link');
      setState(() => _permBusy = false);
    }
  }

  void _reset() {
    setState(() {
      _files = [];
      _target = 'folder';
      _name.text = _installer ? 'Installer' : '';
      _email.text = '';
      _notes.text = '';
      _posVersion = '';
      _autoNotes = '';
      _notesHint = '';
      _notesReload = false;
      if (!_installer) _type = 'default';
      _success = null;
      _permRowVisible = false;
      _permanentLink = '';
      _permWarnVisible = true;
      _permBusy = false;
      _showProgress = false;
    });
  }

  Widget _label(String text, {String? hint, bool req = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 12),
    child: Text.rich(
      TextSpan(
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        children: [
          TextSpan(text: text),
          if (hint != null)
            TextSpan(
              text: ' $hint',
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                color: Color(0xFF3E4042),
              ),
            ),
          if (req)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFD9534F)),
            ),
        ],
      ),
    ),
  );

  Widget _targetOpt(String value, IconData icon, Widget title, String sub) {
    final active = _target == value;
    return Expanded(
      child: InkWell(
        onTap: _uploading ? null : () => setState(() => _target = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF3E6) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? Brand.signal : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                active ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: Brand.signal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: Brand.signal),
                        const SizedBox(width: 6),
                        Flexible(child: title),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final showName = !_replace && !_intoFolder && !_installerType;
    final showEmail =
        !_installer && !_replace && !_intoFolder && !_installerType;
    final showType = !_installer && !_replace && !_intoFolder;
    final showVersion = _installerType;
    final showNotes = _installer || _installerType;
    final showPlay = showType && _type == 'distribution';
    final current = _installerType ? _currentPublishedInstaller : null;
    final pct = _total > 0 ? (_loaded / _total * 100).round().clamp(0, 100) : 0;
    final (btnLabel, btnIcon) = _buttonLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_subtitle, style: const TextStyle(color: Color(0xFF3E4042))),
        if (_targetEligible) ...[
          _label('Where should these files go?'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _targetOpt(
                'folder',
                Icons.folder_open,
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Into '),
                      TextSpan(
                        text:
                            '${widget.folderTarget!['name'] ?? 'this folder'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                'The files land in this folder and share its link.',
              ),
              const SizedBox(width: 10),
              _targetOpt(
                'subfolder',
                Icons.create_new_folder,
                const Text('As a new subfolder'),
                'Creates a named subfolder here with its own share link.',
              ),
            ],
          ),
        ],
        if (showName) ...[
          _label(_installer ? 'Installer name' : 'Collection name'),
          TextField(
            controller: _name,
            enabled: !_uploading,
            decoration: InputDecoration(
              hintText: _installer
                  ? 'e.g. Windows Installer, Linux Installer...'
                  : 'e.g. Project Assets, Photos, Documents...',
            ),
          ),
        ],
        if (_installer) ...[
          _label('Installer to change'),
          DropdownButtonFormField<String>(
            initialValue: _installerId,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: '', child: Text('New installer')),
              for (final c in _installerRows)
                DropdownMenuItem(
                  value: '${c['id']}',
                  child: Text('${c['name'] ?? 'Installer'}'),
                ),
            ],
            onChanged: _uploading
                ? null
                : (v) => setState(() {
                    _installerId = v ?? '';
                    final sel = _installerRows.where(
                      (c) => '${c['id']}' == _installerId,
                    );
                    _name.text = sel.isNotEmpty ? '${sel.first['name']}' : '';
                  }),
          ),
        ],
        if (showEmail) ...[
          _label('Your email', hint: '(optional)'),
          TextField(
            controller: _email,
            enabled: !_uploading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
        ],
        if (showType) ...[
          _label('Type'),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: 'default',
                child: Text('Default — expiring + permanent link'),
              ),
              DropdownMenuItem(
                value: 'distribution',
                child: Text(
                  'Distribution — single permanent link (e.g. APK download)',
                ),
              ),
              DropdownMenuItem(
                value: 'installer',
                child: Text(
                  'Installer — published also to vendors in their portal',
                ),
              ),
            ],
            onChanged: _uploading
                ? null
                : (v) {
                    setState(() => _type = v ?? 'default');
                    if (_type == 'installer') _syncNotes(false);
                  },
          ),
        ],
        if (showVersion) ...[
          _label('POS version', req: true),
          DropdownButtonFormField<String>(
            initialValue: _posVersion,
            isExpanded: true,
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Select a POS version'),
              ),
              for (final v in widget.posVersions)
                DropdownMenuItem(value: v.value, child: Text(v.label)),
            ],
            onChanged: _uploading
                ? null
                : (v) {
                    setState(() => _posVersion = v ?? '');
                    _syncNotes(false);
                  },
          ),
        ],
        if (showNotes) ...[
          _label(
            'Release notes',
            hint: "(what's in this build — shown to vendors in their portal)",
          ),
          TextField(
            controller: _notes,
            enabled: !_uploading,
            minLines: 5,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText:
                  'One change per line, e.g.\nAdded BIR 2303 auto-fill\nFixed receipt reprint on thermal printers\nFaster end-of-day report',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _notesHint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3E4042),
                  ),
                ),
              ),
              if (_notesReload)
                TextButton.icon(
                  onPressed: () => _syncNotes(true),
                  icon: const Icon(Icons.sync, size: 14),
                  label: const Text('Reload from Release Notes'),
                ),
            ],
          ),
        ],
        if (_installerType) ...[
          const SizedBox(height: 10),
          FmNote(
            icon: Icons.sync,
            title: '',
            text: current != null
                ? 'This replaces the installer currently published to vendors — "${current['name'] ?? 'Installer'}${(current['pos_version'] ?? '').toString().isNotEmpty ? ' (${current['pos_version']})' : ''}". Its files are removed and its share links keep working, now pointing at what you upload here.'
                : 'No installer is published to vendors yet — this upload becomes the published one. Every later installer upload replaces it.',
          ),
        ],
        if (showPlay) ...[
          _label('Play Store URL', hint: '(optional, Android mobile redirect)'),
          TextField(
            controller: _play,
            enabled: !_uploading,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText:
                  'https://play.google.com/store/apps/details?id=io.tinkerpro.app',
              counterText: '',
            ),
          ),
        ],
        const SizedBox(height: 14),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _uploading ? null : _pick,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Brand.signalGlow(0.05),
                border: Border.all(color: Brand.signalGlow(0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload, size: 34, color: Brand.signal),
                  const SizedBox(height: 8),
                  Text(
                    _installer
                        ? 'Choose installer package'
                        : (_replace
                              ? 'Choose the replacement file'
                              : 'Choose files'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0C233E),
                    ),
                  ),
                  Text(
                    _installer
                        ? 'click to browse .zip / .rar'
                        : 'click to browse',
                    style: const TextStyle(color: Color(0xFF0C233E)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < _files.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: Brand.signal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _files[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    fmSize(_files[i].size),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (!_uploading)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _files.removeAt(i)),
                    ),
                ],
              ),
            ),
        ],
        if (_showProgress) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _progressLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation(Brand.signal),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmSize(_loaded), style: const TextStyle(fontSize: 12)),
              Text(fmSize(_total), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (!_uploading)
          SignalButton(
            label: btnLabel,
            icon: btnIcon,
            expand: true,
            onPressed: _files.isEmpty ? null : _upload,
          ),
        if (_uploading && _cancelVisible)
          GhostButton(
            label: 'Cancel Upload',
            icon: Icons.cancel_outlined,
            onPressed: () => _job?.cancel(),
          ),
      ],
    );
  }

  Widget _linkCard(String label, String meta, String url, VoidCallback onCopy) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 8, color: Brand.signal),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                meta,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: SelectableText(url, maxLines: 1),
                ),
              ),
              const SizedBox(width: 8),
              GhostButton(label: 'Copy', icon: Icons.copy, onPressed: onCopy),
            ],
          ),
        ],
      ),
    );
  }

  Widget _successBox() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFECFDF5),
            child: Icon(Icons.check, color: Color(0xFF059669)),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Upload complete',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const Center(child: Text('Your files are ready to share.')),
        if (_expiringVisible)
          _linkCard(
            'Expiring link',
            'Auto-expires in 2 hours',
            _shareLink,
            () => fmCopy(
              context,
              _shareLink,
              'Expiring link copied! Valid for 2 hours.',
            ),
          ),
        if (_permWarnVisible) ...[
          const SizedBox(height: 12),
          FmNote(
            icon: Icons.shield_outlined,
            title: "Need a link that doesn't expire?",
            text:
                'A permanent URL stays live until you revoke it. Anyone the link reaches keeps access — every visit is logged.',
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SignalButton(
                  label: _permBusy
                      ? 'Generating...'
                      : 'Generate permanent link',
                  icon: Icons.key,
                  onPressed: _permBusy ? null : _generatePermanent,
                ),
              ),
            ),
          ),
        ],
        if (_permRowVisible)
          _linkCard(_permanentLabel, _permanentMeta, _permanentLink, () {
            if (_permanentLink.isEmpty) return;
            fmCopy(
              context,
              _permanentLink,
              'Permanent link copied. Treat it like a password.',
            );
          }),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Upload more files'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      child: WebModal(
        title: _title,
        icon: _installer ? Icons.archive_outlined : Icons.cloud_upload_outlined,
        width: 640,
        onClose: _uploading ? () {} : null,
        child: _success != null ? _successBox() : _form(),
      ),
    );
  }
}
