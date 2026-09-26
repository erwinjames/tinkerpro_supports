import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_files_service.dart';
import '../../services/admin_services.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_files_dialogs.dart';
import 'admin_files_upload.dart';
import 'admin_list.dart';
import 'folder_sync_screen.dart';
import '../../widgets/tp_loader.dart';

String prettySize(int bytes) => fmSize(bytes);

typedef _C = Map<String, dynamic>;

String _cs(_C c, String k) => (c[k] ?? '').toString();
int _ci(_C c, String k) => int.tryParse(_cs(c, k)) ?? 0;

String _dateLabel(String raw) {
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return '';
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

String _countdown(int ms) {
  if (ms <= 0) return 'expired';
  var s = ms ~/ 1000;
  final h = s ~/ 3600;
  s -= h * 3600;
  final mi = s ~/ 60;
  final sec = s - mi * 60;
  if (h > 0) return '${h}h ${mi}m';
  if (mi > 0) return '${mi}m ${sec < 10 ? '0' : ''}${sec}s';
  return '${sec}s';
}

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.service});
  final FilesService service;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _Act {
  const _Act(this.label, this.icon, this.run, {this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback run;
  final bool danger;
}

class _FilesScreenState extends State<FilesScreen>
    with LiveRefresh<FilesScreen> {
  late final AdminFilesApi api = AdminFilesApi(widget.service.api);
  List<_C> _all = const [];
  Map<String, dynamic> _storage = const {};
  Map<String, dynamic> _meta = const {};
  bool _loading = true;
  String? _error;
  bool _installer = false;
  bool _tiles = true;
  String? _folder;
  _C? _folderRow;
  List<_C> _files = const [];
  final Set<String> _hidden = {};
  final _searchCtrl = TextEditingController();
  Timer? _ticker;

  bool get _canInstaller => _meta['can_installer'] == true;
  bool get _isOjt => _meta['is_ojt_viewer'] == true;
  bool get _canShareOjt => _meta['can_share_ojt'] == true;
  bool get _canFolderSync => _meta['can_folder_sync'] == true;
  bool _folderSync =
      kDebugMode && Platform.environment['TP_OPEN_FOLDER_SYNC'] == '1';
  String get _q => _searchCtrl.text.trim().toLowerCase();

  @override
  List<String> get liveKeys => const ['files'];

  @override
  void onLiveChange() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    var changed = false;
    for (final c in _all) {
      if (_ci(c, 'link_expired') == 1) continue;
      final exp = DateTime.tryParse(_cs(c, 'share_token_expires_at'));
      if (exp == null || exp.isAfter(now)) continue;
      c['link_expired'] = 1;
      changed = true;
    }
    final showsCountdown =
        _folderRow != null && _cs(_folderRow!, 'share_token').isNotEmpty;
    if (changed || showsCountdown) setState(() {});
  }

  Future<void> _loadMeta() async {
    try {
      final m = await api.pageMeta();
      if (mounted && m['success'] == true) setState(() => _meta = m);
    } catch (_) {}
  }

  List<({String value, String label})> get _posVersions {
    final raw = _meta['pos_versions'];
    if (raw is! List) return const [];
    return [
      for (final v in raw.whereType<Map>())
        (value: '${v['value']}', label: '${v['label']}'),
    ];
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _all.isEmpty;
        _error = null;
      });
    }
    try {
      final res = await api.listCollections();
      if (res['success'] != true) {
        throw Exception(res['message'] ?? 'Failed to load collections');
      }
      final raw = res['data'];
      final rows = raw is List
          ? raw
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList()
          : <_C>[];
      Map<String, dynamic> st = const {};
      try {
        st = await api.storageUsage();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _all = rows;
        _storage = st;
        _loading = false;
        _error = null;
      });
      if (_folder != null) {
        final row = _byId(_folder!);
        if (row == null) {
          setState(() {
            _folder = null;
            _folderRow = null;
            _files = const [];
          });
        } else {
          await _refreshFolderFiles();
        }
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshFolderFiles() async {
    final id = _folder;
    if (id == null) return;
    try {
      final res = await api.collectionFiles(id);
      if (!mounted || _folder != id || res['success'] != true) return;
      setState(() {
        _folderRow = {
          ...(res['collection'] is Map
              ? Map<String, dynamic>.from(res['collection'] as Map)
              : <String, dynamic>{}),
          ...?_byId(id),
        };
        _files = (res['files'] is List)
            ? (res['files'] as List)
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList()
            : const [];
      });
    } catch (_) {}
  }

  Future<void> _openFolder(String? id) async {
    if (id == null) {
      setState(() {
        _folder = null;
        _folderRow = null;
        _files = const [];
        _searchCtrl.clear();
      });
      return;
    }
    try {
      final res = await api.collectionFiles(id);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, 'Failed to load files');
        return;
      }
      setState(() {
        _folder = id;
        _folderRow = {
          ...(res['collection'] is Map
              ? Map<String, dynamic>.from(res['collection'] as Map)
              : <String, dynamic>{}),
          ...?_byId(id),
        };
        _files = (res['files'] is List)
            ? (res['files'] as List)
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList()
            : const [];
        _searchCtrl.clear();
      });
    } catch (_) {
      if (mounted) toast(context, 'Failed to load files');
    }
  }

  _C? _byId(String id) {
    for (final c in _all) {
      if (_cs(c, 'id') == id) return c;
    }
    return null;
  }

  List<_C> _childFolders(String? id) {
    final key = id ?? '';
    return _all.where((c) {
      if (_cs(c, 'collection_type') == 'installer') return false;
      if (_hidden.contains(_cs(c, 'id'))) return false;
      final p = _cs(c, 'parent_id');
      final parent = p.isNotEmpty && _byId(p) != null ? p : '';
      return parent == key;
    }).toList();
  }

  List<_C> get _viewRows => _all
      .where((c) => (_cs(c, 'collection_type') == 'installer') == _installer)
      .toList();

  List<_C> get _currentChildren {
    if (_installer) {
      return _folder != null
          ? const []
          : _viewRows.where((c) => !_hidden.contains(_cs(c, 'id'))).toList();
    }
    return _childFolders(_folder);
  }

  bool _matches(_C c) {
    if (_q.isEmpty) return true;
    return _cs(c, 'name').toLowerCase().contains(_q) ||
        _cs(c, 'email').toLowerCase().contains(_q);
  }

  ({int files, int size, int folders}) _totals(_C c) {
    if (_cs(c, 'collection_type') == 'installer') {
      return (
        files: _ci(c, 'file_count'),
        size: _ci(c, 'total_size'),
        folders: 0,
      );
    }
    var files = _ci(c, 'file_count');
    var size = _ci(c, 'total_size');
    var folders = 0;
    final stack = [..._childFolders(_cs(c, 'id'))];
    var guard = 0;
    while (stack.isNotEmpty && guard++ < 5000) {
      final k = stack.removeLast();
      folders++;
      files += _ci(k, 'file_count');
      size += _ci(k, 'total_size');
      stack.addAll(_childFolders(_cs(k, 'id')));
    }
    return (files: files, size: size, folders: folders);
  }

  List<_C> _pathOf(String id) {
    final out = <_C>[];
    var cur = _byId(id);
    var guard = 0;
    while (cur != null && guard++ < 100) {
      out.insert(0, cur);
      final p = _cs(cur, 'parent_id');
      cur = p.isEmpty ? null : _byId(p);
    }
    return out;
  }

  _C? get _uploadFolderTarget =>
      (!_installer &&
          _folderRow != null &&
          _cs(_folderRow!, 'collection_type') != 'installer')
      ? _folderRow
      : null;

  Future<void> _showUpload(
    String mode, {
    String targetId = '',
    String targetName = '',
  }) async {
    final res = await showDialog<FmUploadResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FmUploadModal(
        api: api,
        mode: mode,
        collections: _all,
        posVersions: _posVersions,
        targetId: targetId,
        targetName: targetName,
        folderTarget: mode == 'collections' ? _uploadFolderTarget : null,
        explorerCollectionId: _folder,
        onCollectionsChanged: () => _load(silent: true),
      ),
    );
    if (!mounted) return;
    if (res?.switchToInstaller == true) {
      setState(() {
        _installer = true;
        _folder = null;
        _folderRow = null;
        _files = const [];
      });
    }
    _load(silent: true);
  }

  Future<void> _newFolder(String? parentId) async {
    final parent = parentId == null ? null : _byId(parentId);
    final name = await fmFolderPrompt(
      context,
      title: parent != null
          ? 'New folder in "${_cs(parent, 'name')}"'
          : 'New folder',
      confirm: 'Create folder',
    );
    if (name == null || !mounted) return;
    try {
      final res = await api.createFolder(name, parentId);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not create the folder'}');
        return;
      }
      toast(context, 'Folder created');
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not create the folder');
    }
  }

  Future<void> _rename(_C c) async {
    final name = await fmFolderPrompt(
      context,
      title: 'Rename folder',
      confirm: 'Save name',
      initial: _cs(c, 'name'),
    );
    if (name == null || !mounted) return;
    try {
      final res = await api.rename(_cs(c, 'id'), name);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not rename the folder'}');
        return;
      }
      toast(context, 'Folder renamed');
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not rename the folder');
    }
  }

  List<({String id, String label})> _moveOptions(String id) {
    final blocked = <String>{id};
    final stack = [..._childFolders(id)];
    var guard = 0;
    while (stack.isNotEmpty && guard++ < 5000) {
      final c = stack.removeLast();
      blocked.add(_cs(c, 'id'));
      stack.addAll(_childFolders(_cs(c, 'id')));
    }
    final out = <({String id, String label})>[];
    void walk(String? parent, int depth) {
      for (final c in _childFolders(parent)) {
        if (!blocked.contains(_cs(c, 'id'))) {
          out.add((
            id: _cs(c, 'id'),
            label: '${' ' * (depth * 4)}${_cs(c, 'name')}',
          ));
        }
        walk(_cs(c, 'id'), depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  Future<void> _move(_C c) async {
    final r = await fmMovePrompt(
      context,
      name: _cs(c, 'name'),
      current: _cs(c, 'parent_id'),
      options: _moveOptions(_cs(c, 'id')),
    );
    if (!r.ok || !mounted) return;
    try {
      final res = await api.move(
        _cs(c, 'id'),
        r.value.isEmpty ? null : r.value,
      );
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not move the folder'}');
        return;
      }
      toast(context, 'Folder moved');
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not move the folder');
    }
  }

  Future<void> _releaseNotes(_C c) async {
    final notes = await fmReleaseNotesPrompt(
      context,
      shared: _ci(c, 'vendor_visible') == 1,
      initial: _cs(c, 'release_notes'),
    );
    if (notes == null || !mounted) return;
    try {
      final res = await api.setReleaseNotes(_cs(c, 'id'), notes);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(
          context,
          '${res['message'] ?? 'Could not save the release notes.'}',
        );
        return;
      }
      toast(
        context,
        notes.isNotEmpty ? 'Release notes saved.' : 'Release notes cleared.',
      );
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    }
  }

  void _changeFile(_C c) {
    if (_cs(c, 'collection_type') == 'installer') {
      _showUpload('installer', targetId: _cs(c, 'id'));
      return;
    }
    _showUpload('replace', targetId: _cs(c, 'id'), targetName: _cs(c, 'name'));
  }

  void _changeType(_C c) {
    if (_cs(c, 'collection_type') == 'installer') {
      toast(
        context,
        'Installers are published from the Installer tab and keep their own type.',
      );
      return;
    }
    fmChangeTypeDialog(
      context,
      api: api,
      row: c,
      onSaved: () => _load(silent: true),
    );
  }

  Future<void> _toggleVendor(_C c) async {
    final next = _ci(c, 'vendor_visible') != 1;
    try {
      final res = await api.setVendorVisible(_cs(c, 'id'), next);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(
          context,
          '${res['message'] ?? 'Could not change vendor visibility.'}',
        );
        return;
      }
      toast(
        context,
        next
            ? 'Shared — vendors can see this in their portal.'
            : 'Hidden from the vendor portal.',
      );
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    }
  }

  Future<void> _toggleOjt(_C c) async {
    final next = _ci(c, 'ojt_visible') != 1;
    try {
      final res = await api.setOjtVisible(_cs(c, 'id'), next);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(
          context,
          '${res['message'] ?? 'Could not change OJT visibility.'}',
        );
        return;
      }
      if (next) {
        toast(
          context,
          res['ojt_files_access'] == true
              ? 'Shared — OJT accounts now have Files Management access, limited to folders shared with them.'
              : 'Shared — OJT accounts can now see this folder.',
        );
      } else if (res['ojt_files_access'] != true &&
          (int.tryParse('${res['ojt_shared_count']}') ?? -1) == 0) {
        toast(
          context,
          'Hidden from OJT accounts. No folders are shared with OJT, so their Files Management access was turned off.',
        );
      } else {
        toast(context, 'Hidden from OJT accounts.');
      }
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    }
  }

  Future<void> _toggleFav(_C c) async {
    final was = _ci(c, 'is_favorite') == 1;
    setState(() => c['is_favorite'] = was ? 0 : 1);
    try {
      final res = await api.toggleFavorite(_cs(c, 'id'), !was);
      if (!mounted) return;
      if (res['success'] != true) {
        setState(() => c['is_favorite'] = was ? 1 : 0);
        toast(context, '${res['message'] ?? 'Could not update favorite'}');
        return;
      }
      _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => c['is_favorite'] = was ? 1 : 0);
      toast(context, 'Could not update favorite');
    }
  }

  Future<void> _copyLink(_C c) async {
    try {
      final res = await api.getShareLink(_cs(c, 'id'));
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, 'Failed to get share link');
        return;
      }
      if (res['expired'] == true) {
        toast(
          context,
          'This share link has expired. Click "Generate" to create a new one.',
        );
        _load(silent: true);
        return;
      }
      await fmCopy(
        context,
        api.shareUrl('${res['share_token']}'),
        'Share link copied! Expires in 2 hours.',
      );
    } catch (_) {
      if (mounted) toast(context, 'Failed to get share link');
    }
  }

  Future<void> _copyDistribution(_C c, String message) async {
    try {
      final res = await api.getShareLink(_cs(c, 'id'));
      if (!mounted) return;
      final tok = '${res['permanent_share_token'] ?? ''}';
      if (res['success'] != true || tok.isEmpty) {
        toast(context, 'Permanent link unavailable');
        return;
      }
      await fmCopy(context, api.shareUrl(tok), message);
    } catch (_) {
      if (mounted) toast(context, 'Failed to copy link');
    }
  }

  Future<void> _generateLink(_C c) async {
    try {
      final res = await api.generateShareLink(_cs(c, 'id'));
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Failed to generate link'}');
        return;
      }
      await fmCopy(
        context,
        api.shareUrl('${res['share_token']}'),
        'New share link generated & copied! Expires in 2 hours.',
      );
      _load(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Failed to generate link');
    }
  }

  Future<void> _permanentAction(_C c) async {
    final id = _cs(c, 'id');
    if (_ci(c, 'has_permanent_link') != 1) {
      final ok = await fmConfirm(
        context,
        title: 'Generate a permanent link?',
        text:
            'It never expires. Anyone the URL reaches keeps access until you revoke it.\n\nEvery visit is logged for audit. Use only when long-term access is genuinely required.',
        confirm: 'Generate it',
      );
      if (!ok || !mounted) return;
      try {
        final res = await api.generatePermanent(id);
        if (!mounted) return;
        if (res['success'] != true) {
          toast(
            context,
            '${res['message'] ?? 'Failed to generate permanent link'}',
          );
          return;
        }
        await fmCopy(
          context,
          api.shareUrl('${res['permanent_share_token']}'),
          'Permanent link generated & copied. Treat it like a password.',
        );
        _load(silent: true);
      } catch (_) {
        if (mounted) toast(context, 'Failed to generate permanent link');
      }
      return;
    }
    Map<String, dynamic> res;
    try {
      res = await api.getShareLink(id);
    } catch (_) {
      if (mounted) toast(context, 'Failed to load permanent link');
      return;
    }
    if (!mounted) return;
    final tok = '${res['permanent_share_token'] ?? ''}';
    if (res['success'] != true || tok.isEmpty) {
      toast(context, '${res['message'] ?? 'Permanent link unavailable'}');
      _load(silent: true);
      return;
    }
    final url = api.shareUrl(tok);
    final choice = await fmPermanentLinkDialog(context, url);
    if (!mounted || choice == null) return;
    if (choice == FmPermChoice.copy) {
      await fmCopy(context, url, 'Permanent link copied.');
    } else if (choice == FmPermChoice.rotate) {
      final ok = await fmConfirm(
        context,
        title: 'Rotate permanent link?',
        text:
            'The current URL will stop working immediately. A new one will replace it.',
        confirm: 'Rotate',
      );
      if (!ok || !mounted) return;
      final r2 = await api.generatePermanent(id);
      if (!mounted) return;
      if (r2['success'] != true) {
        toast(context, '${r2['message'] ?? 'Failed to rotate'}');
        return;
      }
      await fmCopy(
        context,
        api.shareUrl('${r2['permanent_share_token']}'),
        'Rotated & copied. Old link is now dead.',
      );
      _load(silent: true);
    } else {
      final ok = await fmConfirm(
        context,
        title: 'Revoke permanent link?',
        text:
            'The URL will stop working immediately. The expiring link is unaffected.',
        confirm: 'Revoke',
        cancel: 'Keep it',
      );
      if (!ok || !mounted) return;
      final r3 = await api.revokePermanent(id);
      if (!mounted) return;
      if (r3['success'] != true) {
        toast(context, '${r3['message'] ?? 'Failed to revoke'}');
        return;
      }
      toast(context, 'Permanent link revoked.');
      _load(silent: true);
    }
  }

  Future<void> _deleteCollection(_C c) async {
    final installer = _cs(c, 'collection_type') == 'installer';
    final name = _cs(c, 'name');
    final ok = await fmConfirm(
      context,
      title: installer ? 'Delete this installer?' : 'Delete this collection?',
      text: installer
          ? 'The installer "$name" and its package will be permanently removed, and its download link will stop working for anyone who already has it.'
          : 'The collection "$name" and all of its files will be permanently removed.',
      confirm: installer ? 'Delete installer' : 'Delete collection',
      danger: true,
    );
    if (!ok || !mounted) return;
    final id = _cs(c, 'id');
    setState(() => _hidden.add(id));
    final commit = await fmUndoWindow(
      context,
      installer ? 'Installer deleted' : 'Collection deleted',
    );
    if (!commit) {
      if (mounted) setState(() => _hidden.remove(id));
      return;
    }
    try {
      final res = await api.deleteCollection(id);
      if (mounted && res['success'] != true) {
        toast(context, '${res['message'] ?? ''}');
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _hidden.remove(id));
    _load(silent: true);
  }

  Future<void> _deleteFile(_C f) async {
    final ok = await fmConfirm(
      context,
      title: 'Delete this file?',
      text: 'The file will be permanently removed from the collection.',
      confirm: 'Delete file',
      danger: true,
    );
    if (!ok || !mounted) return;
    final id = _cs(f, 'id');
    setState(() => _hidden.add(id));
    final commit = await fmUndoWindow(context, 'File deleted');
    if (!commit) {
      if (mounted) setState(() => _hidden.remove(id));
      return;
    }
    try {
      final res = await api.deleteItem(id);
      if (mounted && res['success'] != true) {
        toast(context, '${res['message'] ?? ''}');
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _hidden.remove(id));
    _load(silent: true);
  }

  List<_Act> _actions(_C c) {
    final installer = _cs(c, 'collection_type') == 'installer';
    final dist = _cs(c, 'collection_type') == 'distribution';
    final hasPerm = _ci(c, 'has_permanent_link') == 1;
    final vendor = _ci(c, 'vendor_visible') == 1;
    final ojt = _ci(c, 'ojt_visible') == 1;
    return [
      _Act('Open', Icons.folder_open, () => _openFolder(_cs(c, 'id'))),
      if (!installer)
        _Act(
          'New Subfolder',
          Icons.create_new_folder,
          () => _newFolder(_cs(c, 'id')),
        ),
      if (!installer) _Act('Rename', Icons.text_fields, () => _rename(c)),
      if (!installer) _Act('Move To…', Icons.open_with, () => _move(c)),
      _Act(
        'Change File',
        installer ? Icons.upload : Icons.upload_file,
        () => _changeFile(c),
      ),
      if (installer)
        _Act(
          'Release Notes',
          Icons.assignment_outlined,
          () => _releaseNotes(c),
        ),
      if (dist || installer)
        _Act(
          installer ? 'Installer Link' : 'Distribution Link',
          Icons.all_inclusive,
          () => _copyDistribution(
            c,
            installer ? 'Installer link copied.' : 'Distribution link copied.',
          ),
        )
      else ...[
        _ci(c, 'link_expired') == 1
            ? _Act('Generate Link', Icons.sync, () => _generateLink(c))
            : _Act('Copy Link', Icons.link, () => _copyLink(c)),
        _Act(
          hasPerm ? 'Permanent' : 'Make Permanent',
          hasPerm ? Icons.all_inclusive : Icons.key,
          () => _permanentAction(c),
        ),
      ],
      if (!installer)
        _Act('Change Type', Icons.swap_horiz, () => _changeType(c)),
      if (!installer)
        _Act(
          'Share to Vendor Portal',
          vendor ? Icons.check_box : Icons.check_box_outline_blank,
          () => _toggleVendor(c),
        ),
      if (_canShareOjt && !installer)
        _Act(
          'Share to OJT',
          ojt ? Icons.check_box : Icons.check_box_outline_blank,
          () => _toggleOjt(c),
        ),
      _Act(
        'Delete',
        Icons.delete_outline,
        () => _deleteCollection(c),
        danger: true,
      ),
    ];
  }

  Widget _actionsMenu(_C c, {bool kebab = true}) {
    final acts = _actions(c);
    return PopupMenuButton<int>(
      tooltip: 'Actions',
      position: PopupMenuPosition.under,
      onSelected: (i) => acts[i].run(),
      itemBuilder: (_) => [
        for (var i = 0; i < acts.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 38,
            child: Row(
              children: [
                Icon(
                  acts[i].icon,
                  size: 16,
                  color: acts[i].danger
                      ? Brand.danger
                      : const Color(0xFF334155),
                ),
                const SizedBox(width: 10),
                Text(
                  acts[i].label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: acts[i].danger
                        ? Brand.danger
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: kebab ? 0 : 10),
        width: kebab ? 30 : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: kebab
            ? const Icon(Icons.more_vert, size: 16, color: Color(0xFF334155))
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Actions',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
      ),
    );
  }

  Widget _statCard(
    IconData icon,
    String value,
    String label, {
    Widget? extra,
    double? width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: Brand.signal),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C233E),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final data = _viewRows;
    final files = data.fold<int>(0, (a, c) => a + _ci(c, 'file_count'));
    final size = data.fold<int>(0, (a, c) => a + _ci(c, 'total_size'));
    final pct = double.tryParse('${_storage['used_percent'] ?? ''}') ?? 0;
    final free = (_storage['disk_free'] is num)
        ? prettySize((_storage['disk_free'] as num).toInt())
        : '${_storage['disk_free_human'] ?? '—'}';
    final total = '${_storage['disk_total_human'] ?? ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 8,
        children: [
          _statCard(Icons.folder, '${data.length}', 'Collections'),
          _statCard(Icons.insert_drive_file, '$files', 'Total Files'),
          _statCard(Icons.storage, prettySize(size), 'Total Size'),
          if (!_isOjt && _storage['available'] == true)
            _statCard(
              Icons.dns,
              '$free free',
              '${pct.toStringAsFixed(1)}% of $total used',
              width: 210,
              extra: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0, 1),
                    minHeight: 4,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation(
                      pct >= 95 ? Brand.danger : Brand.signal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _seg(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Brand.signal : const Color(0xFF334155),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Brand.signal : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segGroup(List<Widget> children) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );

  bool _isAncestorOrSelf(String ancestor, String id) {
    String? cur = id;
    var guard = 0;
    while (cur != null && guard++ < 100) {
      if (cur == ancestor) return true;
      final row = _byId(cur);
      final p = row == null ? '' : _cs(row, 'parent_id');
      cur = p.isEmpty ? null : p;
    }
    return false;
  }

  List<Widget> _treeRows(String? parent, int depth) {
    final out = <Widget>[];
    for (final c in _childFolders(parent)) {
      final id = _cs(c, 'id');
      final active = _folder == id;
      out.add(
        InkWell(
          onTap: () => _openFolder(id),
          child: Container(
            height: 31.5,
            padding: EdgeInsets.only(left: 22.0 + depth * 14, right: 10),
            color: active ? const Color(0xFFFFF4EA) : null,
            child: Row(
              children: [
                Icon(
                  active ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: Brand.signal,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _cs(c, 'name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
                Text(
                  '${_ci(c, 'file_count')}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (_folder != null && _isAncestorOrSelf(id, _folder!)) {
        out.addAll(_treeRows(id, depth + 1));
      }
    }
    return out;
  }

  Widget _tree() {
    return Container(
      width: 245,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: const Row(
              children: [
                Icon(Icons.account_tree, size: 14, color: Brand.signal),
                SizedBox(width: 8),
                Text(
                  'FOLDER TREE',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Material(
              color: _folder == null ? Brand.signal : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openFolder(null),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All Collections',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _folder == null
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      Text(
                        '${_childFolders(null).length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _folder == null
                              ? Colors.white
                              : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: ListView(children: _treeRows(null, 0))),
        ],
      ),
    );
  }

  String get _rootLabel => _installer ? 'Installer' : 'All Collections';

  Widget _crumbs() {
    final chain = _folder == null ? <_C>[] : _pathOf(_folder!);
    Widget crumb(String label, VoidCallback? onTap, bool last) => InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: last ? const Color(0xFF0C233E) : Brand.signal,
        ),
      ),
    );
    final folders = _currentChildren.length;
    final files = _folder != null ? _visibleFiles.length : 0;
    final parts = ['$folders folder${folders == 1 ? '' : 's'}'];
    if (_folder != null) parts.add('$files file${files == 1 ? '' : 's'}');
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          crumb(
            _rootLabel,
            chain.isEmpty ? null : () => _openFolder(null),
            chain.isEmpty,
          ),
          for (var i = 0; i < chain.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
            ),
            crumb(
              _cs(chain[i], 'name'),
              i == chain.length - 1
                  ? null
                  : () => _openFolder(_cs(chain[i], 'id')),
              i == chain.length - 1,
            ),
          ],
          const Spacer(),
          Text(
            parts.join(' · '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _pillBox(IconData icon, String label, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statusPill(_C c) {
    final type = _cs(c, 'collection_type');
    final ojt = !_isOjt && _ci(c, 'ojt_visible') == 1
        ? _pillBox(
            Icons.school,
            'OJT',
            const Color(0xFF7C3AED),
            const Color(0xFFF3E8FF),
          )
        : null;
    Widget main;
    if (type == 'distribution' || type == 'installer') {
      main = _pillBox(
        Icons.all_inclusive,
        type == 'installer' ? 'Installer' : 'Distribution',
        const Color(0xFF059669),
        const Color(0xFFECFDF5),
      );
    } else {
      main = _ci(c, 'link_expired') == 1
          ? _pillBox(
              Icons.error,
              'Link expired',
              const Color(0xFFDC2626),
              const Color(0xFFFEF2F2),
            )
          : _pillBox(
              Icons.check_circle,
              'Active link',
              const Color(0xFF059669),
              const Color(0xFFECFDF5),
            );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: main),
        if (ojt != null) ...[const SizedBox(width: 4), Flexible(child: ojt)],
      ],
    );
  }

  Widget _tile(_C c) {
    final fav = _ci(c, 'is_favorite') == 1;
    final t = _totals(c);
    final direct = _ci(c, 'subfolder_count') > 0
        ? _ci(c, 'subfolder_count')
        : _childFolders(_cs(c, 'id')).length;
    return _TileHover(
      onTap: () => _openFolder(_cs(c, 'id')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    direct > 0 ? Icons.folder_copy : Icons.folder,
                    color: Brand.signal,
                    size: 22,
                  ),
                ),
                const Spacer(),
                Flexible(child: _statusPill(c)),
                const SizedBox(width: 4),
                Tooltip(
                  message: fav ? 'Remove from favorites' : 'Add to favorites',
                  child: InkWell(
                    onTap: () => _toggleFav(c),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        fav ? Icons.star : Icons.star_border,
                        size: 19,
                        color: fav
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _cs(c, 'name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C233E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (direct > 0) '$direct ${direct == 1 ? 'folder' : 'folders'}',
                '${t.files} ${t.files == 1 ? 'file' : 'files'}',
                prettySize(t.size),
              ].join('  ·  '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const Spacer(),
            const Divider(height: 14, color: Color(0xFFF1F5F9)),
            Row(
              children: [
                const Icon(Icons.schedule, size: 13, color: Color(0xFF475569)),
                const SizedBox(width: 5),
                Text(
                  _dateLabel(_cs(c, 'created_at')),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                _actionsMenu(c),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_C> get _visibleFiles => _files
      .where((f) => !_hidden.contains(_cs(f, 'id')))
      .where(
        (f) => _q.isEmpty || _cs(f, 'file_name').toLowerCase().contains(_q),
      )
      .toList();

  Widget _sectionTitle(IconData icon, String label, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Brand.signal),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4EA),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Brand.signal,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _inlineEmpty(String text) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF475569))),
  );

  Widget _linkLine(
    IconData icon,
    Color color,
    String url,
    String copyMsg, {
    int? expiresMs,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          if (expiresMs != null) ...[
            const SizedBox(width: 8),
            Text(
              _countdown(expiresMs - DateTime.now().millisecondsSinceEpoch),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: expiresMs <= DateTime.now().millisecondsSinceEpoch
                    ? Brand.danger
                    : const Color(0xFF475569),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 15),
            onPressed: () => fmCopy(context, url, copyMsg),
          ),
        ],
      ),
    );
  }

  Widget _folderHead(_C c) {
    final installer = _cs(c, 'collection_type') == 'installer';
    final t = installer
        ? (files: _files.length, size: _ci(c, 'total_size'), folders: 0)
        : _totals(c);
    final links = <Widget>[];
    final exp = DateTime.tryParse(_cs(c, 'share_token_expires_at'));
    if (_cs(c, 'share_token').isNotEmpty &&
        exp != null &&
        _ci(c, 'link_expired') != 1 &&
        exp.isAfter(DateTime.now())) {
      links.add(
        _linkLine(
          Icons.schedule,
          Brand.signal,
          api.shareUrl(_cs(c, 'share_token')),
          'Expiring link copied! Valid for 2 hours.',
          expiresMs: exp.millisecondsSinceEpoch,
        ),
      );
    }
    if (_cs(c, 'permanent_share_token').isNotEmpty) {
      links.add(
        _linkLine(
          Icons.all_inclusive,
          const Color(0xFF059669),
          api.shareUrl(_cs(c, 'permanent_share_token')),
          'Permanent link copied.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_open,
                color: Brand.signal,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cs(c, 'name'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0C233E),
                    ),
                  ),
                  Text(
                    [
                      '${_files.length} ${_files.length == 1 ? 'file' : 'files'} here',
                      '${t.files} in total (${prettySize(t.size)})',
                      _dateLabel(_cs(c, 'created_at')),
                      if (_cs(c, 'email').isNotEmpty) _cs(c, 'email'),
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            _statusPill(c),
            const SizedBox(width: 8),
            _actionsMenu(c, kebab: false),
          ],
        ),
        if (links.isNotEmpty) ...[const SizedBox(height: 10), ...links],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _folderTable(List<_C> rows) {
    return ColumnResizeScope(
      tableId: 'files:folders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WebTableHeader(
            cells: [
              Expanded(flex: 5, child: Text('NAME')),
              SizedBox(width: 170, child: Text('STATUS')),
              SizedBox(width: 80, child: Text('FOLDERS')),
              SizedBox(width: 70, child: Text('FILES')),
              SizedBox(width: 90, child: Text('SIZE')),
              SizedBox(width: 120, child: Text('DATE')),
              SizedBox(width: 60, child: Text('')),
            ],
          ),
          for (final c in rows)
            WebTableRow(
              onTap: () => _openFolder(_cs(c, 'id')),
              cells: [
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      const Icon(Icons.folder, color: Brand.signal, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AdminCellText(_cs(c, 'name'), bold: true),
                      ),
                      InkWell(
                        onTap: () => _toggleFav(c),
                        child: Icon(
                          _ci(c, 'is_favorite') == 1
                              ? Icons.star
                              : Icons.star_border,
                          size: 17,
                          color: _ci(c, 'is_favorite') == 1
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusPill(c),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: AdminCellText(
                    '${_ci(c, 'subfolder_count') > 0 ? _ci(c, 'subfolder_count') : _childFolders(_cs(c, 'id')).length}',
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: AdminCellText('${_totals(c).files}'),
                ),
                SizedBox(
                  width: 90,
                  child: AdminCellText(prettySize(_totals(c).size)),
                ),
                SizedBox(
                  width: 120,
                  child: AdminCellText(_dateLabel(_cs(c, 'created_at'))),
                ),
                SizedBox(
                  width: 60,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _actionsMenu(c),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _fileRow(_C f, bool installer) {
    final url = api.downloadUrl(_cs(f, 'id'));
    return WebTableRow(
      cells: [
        Expanded(
          flex: 6,
          child: Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: Brand.signal,
              ),
              const SizedBox(width: 10),
              Expanded(child: AdminCellText(_cs(f, 'file_name'), bold: true)),
            ],
          ),
        ),
        SizedBox(
          width: 110,
          child: AdminCellText(prettySize(_ci(f, 'file_size'))),
        ),
        SizedBox(
          width: 130,
          child: AdminCellText(_dateLabel(_cs(f, 'created_at')), muted: true),
        ),
        SizedBox(
          width: 90,
          child: AdminRowActions(
            children: [
              AdminRowAction(
                icon: Icons.download,
                tooltip: 'Download',
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              if (!installer)
                AdminRowAction(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  color: Brand.danger,
                  onPressed: () => _deleteFile(f),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _explorerBody() {
    final inFolder = _folderRow != null && _folder != null;
    final folders = _currentChildren.where(_matches).toList();
    final files = inFolder ? _visibleFiles : const <_C>[];
    final showFolderSection = !(_installer && inFolder);
    final folderLabel = _installer
        ? 'Installers'
        : (inFolder ? 'Subfolders' : 'Folders');
    Widget foldersWidget;
    if (folders.isNotEmpty) {
      foldersWidget = _tiles
          ? LayoutBuilder(
              builder: (ctx, c) {
                const gap = 14.0;
                final cols = ((c.maxWidth + gap) / (240 + gap)).floor().clamp(
                  1,
                  12,
                );
                final w = (c.maxWidth - gap * (cols - 1) - 1) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final f in folders)
                      SizedBox(width: w, height: 204, child: _tile(f)),
                  ],
                );
              },
            )
          : _folderTable(folders);
    } else if (_q.isNotEmpty) {
      foldersWidget = _inlineEmpty('No folders match your search.');
    } else if (inFolder) {
      foldersWidget = _inlineEmpty(
        'No subfolders yet. Use New Folder to add one here.',
      );
    } else {
      foldersWidget = _inlineEmpty(
        _installer
            ? 'No installer uploaded yet. Add one global .zip or .rar package.'
            : 'No collections yet. Create a folder or upload your first files!',
      );
    }
    final installerFolder =
        inFolder && _cs(_folderRow!, 'collection_type') == 'installer';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inFolder) _folderHead(_folderRow!),
          if (showFolderSection) ...[
            _sectionTitle(Icons.folder, folderLabel, folders.length),
            foldersWidget,
            const SizedBox(height: 16),
          ],
          if (inFolder) ...[
            _sectionTitle(Icons.insert_drive_file, 'Files', files.length),
            if (files.isEmpty)
              _inlineEmpty(
                _q.isNotEmpty
                    ? 'No files match your search.'
                    : 'No files directly in this folder.',
              )
            else ...[
              ColumnResizeScope(
                tableId: 'files:files',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WebTableHeader(
                      cells: [
                        Expanded(flex: 6, child: Text('FILE')),
                        SizedBox(width: 110, child: Text('SIZE')),
                        SizedBox(width: 130, child: Text('DATE')),
                        SizedBox(width: 90, child: Text('')),
                      ],
                    ),
                    for (final f in files) _fileRow(f, installerFolder),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _switchView(bool installer) {
    setState(() {
      _installer = installer;
      _folder = null;
      _folderRow = null;
      _files = const [];
      _searchCtrl.clear();
    });
  }

  Widget _collectionsHeader(bool inFolder, bool uploadHere) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _installer ? Icons.archive : Icons.layers,
              color: Brand.signal,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              _installer ? 'Installer' : 'All Collections',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C233E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _segGroup([
          _seg('Collections', Icons.layers, !_installer, () => _switchView(false)),
          if (_canInstaller)
            _seg('Installer', Icons.archive, _installer, () => _switchView(true)),
        ]),
      ],
    );
    ButtonStyle outlined(bool full) => OutlinedButton.styleFrom(
      foregroundColor: Brand.signal,
      side: const BorderSide(color: Brand.signal),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      minimumSize: full ? const Size.fromHeight(46) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
    Widget viewMode(bool full) {
      final g = _segGroup([
        _seg('Tiles', Icons.grid_view, _tiles, () => setState(() => _tiles = true)),
        _seg('Table', Icons.list, !_tiles, () => setState(() => _tiles = false)),
      ]);
      return full ? Align(alignment: Alignment.centerLeft, child: g) : g;
    }

    Widget search(bool full) => SearchField(
      controller: _searchCtrl,
      hint: inFolder
          ? 'Search inside this folder...'
          : (_installer ? 'Search installer...' : 'Search collections...'),
      width: full ? null : 280,
      onChanged: (_) => setState(() {}),
    );
    Widget newFolder(bool full) => OutlinedButton.icon(
      onPressed: () => _newFolder(_folder),
      icon: const Icon(Icons.create_new_folder, size: 16),
      label: Text(
        inFolder ? 'New Subfolder' : 'New Folder',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      style: outlined(full),
    );
    Widget upload(bool full) => SignalButton(
      label: uploadHere ? 'Upload Here' : 'Upload & Get Link',
      icon: Icons.cloud_upload,
      expand: full,
      onPressed: () => _showUpload('collections'),
    );
    Widget folderSync(bool full) => OutlinedButton.icon(
      onPressed: () => setState(() => _folderSync = true),
      icon: const Icon(Icons.folder_open, size: 16),
      label: const Text(
        'Folder Sync',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      style: outlined(full),
    );
    Widget installer(bool full) => SignalButton(
      label: 'Upload Installer',
      icon: Icons.archive,
      expand: full,
      onPressed: () => _showUpload('installer'),
    );
    final showCollectionsActions = !_installer;
    final showFolderSync = !_installer && _canFolderSync;
    final showInstaller = _installer && _canInstaller;

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth > 768) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              left,
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    viewMode(false),
                    search(false),
                    if (showCollectionsActions) newFolder(false),
                    if (showCollectionsActions) upload(false),
                    if (showFolderSync) folderSync(false),
                    if (showInstaller) installer(false),
                  ],
                ),
              ),
            ],
          );
        }
        final half = <Widget>[
          if (showCollectionsActions) newFolder(true),
          if (showFolderSync) folderSync(true),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: left),
            const SizedBox(height: 16),
            viewMode(true),
            const SizedBox(height: 8),
            search(true),
            for (var i = 0; i < half.length; i += 2) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: half[i]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < half.length ? half[i + 1] : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
            if (showCollectionsActions) ...[
              const SizedBox(height: 8),
              upload(true),
            ],
            if (showInstaller) ...[
              const SizedBox(height: 8),
              installer(true),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_folderSync) {
      return FolderSyncScreen(
        api: widget.service.api,
        onBack: () {
          setState(() => _folderSync = false);
          _load(silent: true);
        },
      );
    }
    final inFolder = _folderRow != null;
    final uploadHere = _uploadFolderTarget != null;
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: LayoutBuilder(
        builder: (context, box) {
          final page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _collectionsHeader(inFolder, uploadHere),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: TpLoader(
                                strokeWidth: 2.5,
                              ),
                            )
                          : _error != null
                          ? EmptyState(label: 'Could not load', hint: _error!)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!_installer && box.maxWidth >= 640) ...[
                                  _tree(),
                                  const SizedBox(width: 14),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _crumbs(),
                                      const SizedBox(height: 14),
                                      Expanded(child: _explorerBody()),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
          if (box.maxHeight >= 760) return page;
          return SingleChildScrollView(
            child: SizedBox(height: 760, child: page),
          );
        },
      ),
    );
  }
}

class _TileHover extends StatefulWidget {
  const _TileHover({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_TileHover> createState() => _TileHoverState();
}

class _TileHoverState extends State<_TileHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover ? const Color(0xFFFFB266) : const Color(0xFFE5E7EB),
            ),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
