import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api_client.dart';
import '../../services/folder_sync_engine.dart';
import '../../services/folder_sync_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_files_dialogs.dart';
import 'admin_list.dart';
import 'folder_sync_dialogs.dart';
import '../../widgets/tp_loader.dart';

const _fsBorder = Color(0xFFE5E7EB);
const _fsText = Color(0xFF1F2937);
const _fsMuted = Color(0xFF6B7280);
const _fsPrimaryLight = Color(0xFFFFF3E6);

const _viewImg = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'];
const _viewTxt = [
  'txt', 'md', 'log', 'csv', 'json', 'xml', 'php', 'js', 'ts', 'css', 'html',
  'htm', 'py', 'sh', 'sql', 'yml', 'yaml', 'ini', 'conf', 'svg'
];

({IconData icon, Color color}) _iconFor(FsEntry e) {
  if (e.isDir) return (icon: Icons.folder, color: const Color(0xFFF59E0B));
  final x = e.ext;
  if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'].contains(x)) {
    return (icon: Icons.image, color: const Color(0xFF10B981));
  }
  if (x == 'pdf') return (icon: Icons.picture_as_pdf, color: const Color(0xFFEF4444));
  if (const ['doc', 'docx', 'rtf', 'odt'].contains(x)) {
    return (icon: Icons.description, color: const Color(0xFF2563EB));
  }
  if (const ['xls', 'xlsx', 'csv', 'ods'].contains(x)) {
    return (icon: Icons.table_chart, color: const Color(0xFF059669));
  }
  if (const ['zip', 'rar', '7z', 'tar', 'gz'].contains(x)) {
    return (icon: Icons.folder_zip, color: const Color(0xFF7C3AED));
  }
  if (const ['php', 'js', 'ts', 'css', 'html', 'json', 'xml', 'py', 'sh', 'sql'].contains(x)) {
    return (icon: Icons.code, color: const Color(0xFF0EA5E9));
  }
  if (const ['txt', 'md', 'log'].contains(x)) {
    return (icon: Icons.article, color: _fsMuted);
  }
  return (icon: Icons.insert_drive_file, color: _fsMuted);
}

class _Drag {
  const _Drag(this.rel, this.name, this.isDir);
  final String rel;
  final String name;
  final bool isDir;
}

class FolderSyncScreen extends StatefulWidget {
  const FolderSyncScreen({
    super.key,
    required this.api,
    required this.onBack,
  });
  final ApiClient api;
  final VoidCallback onBack;

  @override
  State<FolderSyncScreen> createState() => _FolderSyncScreenState();
}

class _FolderSyncScreenState extends State<FolderSyncScreen>
    with LiveRefresh<FolderSyncScreen> {
  final engine = FolderSyncEngine.instance;
  FolderSyncApi get fs => engine.api ?? FolderSyncApi(widget.api);
  int get myId => engine.me > 0 ? engine.me : (widget.api.userId ?? 0);

  List<FsWorkspace> _workspaces = const [];
  int _owner = 0;
  String _label = 'My Folder';
  bool _canEdit = true;
  String _sub = '';
  List<FsEntry> _entries = const [];
  bool _exists = false;
  bool _loading = true;
  String? _error;
  bool _tiles = true;
  final _search = TextEditingController();
  int _seenSync = 0;
  int _loadSeq = 0;
  bool _dropBusy = false;
  String _dropStatus = '';
  double? _dropProgress;
  final Set<String> _hidden = {};
  SharedPreferences? _prefs;

  @override
  List<String> get liveKeys => const ['foldersync'];

  @override
  void onLiveChange() {
    _loadWorkspaces(silent: true);
    _loadExplorer(silent: true);
  }

  @override
  void initState() {
    super.initState();
    engine.addListener(_engineChanged);
    _seenSync = engine.syncCount;
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      _tiles = _prefs!.getString('fs_view_mode') != 'list';
    } catch (_) {}
    await engine.attach(widget.api);
    _owner = myId;
    if (kDebugMode) {
      _owner = int.tryParse(Platform.environment['TP_FS_OWNER'] ?? '') ?? _owner;
    }
    await _loadWorkspaces();
    if (kDebugMode) {
      final d = Platform.environment['TP_FS_DIALOG'];
      if (d != null && mounted) {
        Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          if (d == 'settings') _openSettings();
          if (d == 'invite') _openInvite();
          if (d == 'join') _openJoin();
        });
      }
    }
  }

  @override
  void dispose() {
    engine.removeListener(_engineChanged);
    _search.dispose();
    super.dispose();
  }

  void _engineChanged() {
    if (!mounted) return;
    if (engine.syncCount != _seenSync) {
      _seenSync = engine.syncCount;
      final r = engine.lastResult;
      if (r != null && engine.lastError == null && _syncRequestedHere) {
        _syncRequestedHere = false;
        toast(context, r.toastText());
      } else if (engine.lastError != null && _syncRequestedHere) {
        _syncRequestedHere = false;
        toast(context, engine.lastError!);
      }
      if (_owner == myId) _loadExplorer(silent: true);
    }
    setState(() {});
  }

  bool _syncRequestedHere = false;

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  Future<void> _loadWorkspaces({bool silent = false, int? select}) async {
    try {
      final r = await fs.workspaces();
      if (!mounted) return;
      final target = select ?? _owner;
      final has = r.list.any((w) => w.owner == target);
      final owner = has ? target : (r.list.isNotEmpty ? r.list.first.owner : myId);
      final changed = owner != _owner || !silent;
      setState(() {
        _workspaces = r.list;
        if (owner != _owner) {
          _sub = '';
          _search.clear();
        }
        _owner = owner;
        _label = r.list
            .firstWhere((w) => w.owner == owner,
                orElse: () => FsWorkspace(owner, owner == myId ? 'My Folder' : 'Folder', ''))
            .name;
        _canEdit = owner == myId;
      });
      if (changed) _loadExplorer(silent: silent);
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _switchWorkspace(int owner) {
    final w = _workspaces.firstWhere((w) => w.owner == owner,
        orElse: () => FsWorkspace(owner, 'Folder', ''));
    setState(() {
      _owner = owner;
      _label = w.name;
      _canEdit = owner == myId;
      _sub = '';
      _search.clear();
    });
    _loadExplorer();
  }

  Future<void> _loadExplorer({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await fs.browse(_owner, _sub);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = null;
        _canEdit = r.canEdit;
        _exists = r.exists;
        _entries = _applyOrder(r.entries);
        _hidden.clear();
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (silent && _entries.isNotEmpty) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _open(String sub) {
    setState(() => _sub = sub);
    _loadExplorer();
  }

  String _orderKey() => 'fsOrder:u$_owner|$_sub';

  List<String> _getOrder() {
    try {
      final raw = _prefs?.getString(_orderKey());
      if (raw == null) return const [];
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  List<FsEntry> _applyOrder(List<FsEntry> entries) {
    final order = _getOrder();
    if (order.isEmpty) return entries;
    final byName = {for (final e in entries) e.name: e};
    final out = <FsEntry>[];
    for (final n in order) {
      final e = byName.remove(n);
      if (e != null) out.add(e);
    }
    for (final e in entries) {
      if (byName.containsKey(e.name)) out.add(e);
    }
    return out;
  }

  void _swapInOrder(String a, String b) {
    final names = _entries.map((e) => e.name).toList();
    final ia = names.indexOf(a), ib = names.indexOf(b);
    if (ia < 0 || ib < 0 || ia == ib) return;
    final t = names[ia];
    names[ia] = names[ib];
    names[ib] = t;
    _prefs?.setString(_orderKey(), jsonEncode(names));
    _loadExplorer(silent: true);
  }

  String _rel(FsEntry e) => fsJoin(_sub, e.name);

  void _reportLocal(({bool ok, String message})? r) {
    if (r != null) _toast(r.message);
  }

  Future<void> _moveItem(String from, String toDir) async {
    if (!_canEdit) {
      _toast('This workspace is view-only.');
      return;
    }
    try {
      final r = await fs.move(_owner, from, toDir);
      if (r.moved) {
        _toast('Moved “${r.name}”.');
        _reportLocal(await engine.applyMove(from, toDir));
      }
    } catch (e) {
      _toast('$e');
    }
    _loadExplorer(silent: true);
  }

  Future<void> _newFolder() async {
    final name = await fsPrompt(
      context,
      title: 'New folder',
      label: 'Folder name',
      confirm: 'Create',
      hint: 'e.g. invoices',
      emptyError: 'Please enter a folder name',
      icon: Icons.create_new_folder_outlined,
    );
    if (name == null) return;
    try {
      final made = await fs.mkdir(_owner, _sub, name);
      _toast('Folder “$made” created.');
      _reportLocal(await engine.applyMkdir(_sub, made));
    } catch (e) {
      _toast('$e');
    }
    _loadExplorer(silent: true);
  }

  Future<void> _rename(FsEntry e) async {
    final name = await fsPrompt(
      context,
      title: 'Rename',
      label: 'New name',
      confirm: 'Rename',
      initial: e.name,
    );
    if (name == null || name == e.name) return;
    final rel = _rel(e);
    try {
      final got = await fs.rename(_owner, rel, name);
      _toast('Renamed to “$got”.');
      _reportLocal(await engine.applyRename(rel, got));
    } catch (err) {
      _toast('$err');
    }
    _loadExplorer(silent: true);
  }

  Future<void> _delete(FsEntry e) async {
    final ok = await fmConfirm(
      context,
      title: 'Delete ${e.isDir ? 'folder' : 'file'}?',
      text: 'This will permanently delete ${e.name}'
          '${e.isDir ? ' and everything inside it' : ''}.'
          '${engine.twoWayActive && _owner == myId ? '\nIt will also be deleted from your local folder.' : ''}',
      confirm: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    final rel = _rel(e);
    setState(() => _hidden.add(e.name));
    final commit = await fmUndoWindow(context, 'Deleted “${e.name}”');
    if (!commit) {
      if (mounted) setState(() => _hidden.remove(e.name));
      return;
    }
    try {
      await fs.delete(_owner, rel);
      _reportLocal(await engine.applyDelete(rel));
    } catch (err) {
      _toast('$err');
    }
    _loadExplorer(silent: true);
  }

  Future<void> _download(FsEntry e) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save file',
      fileName: e.name,
    );
    if (path == null || path.isEmpty) return;
    _toast('Downloading “${e.name}”…');
    try {
      await fs.downloadTo(_owner, _rel(e), File(path));
      _toast('Saved to $path');
    } catch (err) {
      _toast('Download failed: $err');
    }
  }

  Future<void> _openExternally(FsEntry e) async {
    try {
      final f = await fs.downloadToTemp(_owner, _rel(e), e.name);
      final r = await OpenFilex.open(f.path);
      if (r.type != ResultType.done) _toast(r.message);
    } catch (err) {
      _toast('$err');
    }
  }

  Future<void> _toFilesManagement(FsEntry e) async {
    final name = await fsPrompt(
      context,
      title: 'Send to Files Management',
      label: 'Collection name',
      confirm: 'Upload',
      initial: e.name,
      icon: Icons.cloud_upload_outlined,
    );
    if (name == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WebModal(
        title: 'Uploading…',
        icon: Icons.cloud_upload_outlined,
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sending to Files Management'),
            SizedBox(height: 14),
            FsProgressBar(),
          ],
        ),
      ),
    );
    Object? error;
    try {
      await fs.sendToFilesManagement(
        owner: _owner,
        path: _rel(e),
        fileName: e.name,
        collectionName: name,
      );
    } catch (err) {
      error = err;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (error != null) {
      _toast('Failed: $error');
      return;
    }
    final open = await fmConfirm(
      context,
      title: 'Sent to Files Management',
      text: '“${e.name}” is now a collection you can share.',
      confirm: 'Open Files Management',
      cancel: 'Stay here',
    );
    if (open) widget.onBack();
  }

  Future<void> _openViewer(FsEntry e) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _Viewer(
        fs: fs,
        owner: _owner,
        rel: _rel(e),
        entry: e,
        onDownload: () => _download(e),
        onOpen: () => _openExternally(e),
      ),
    );
  }

  Future<void> _uploadHere({required bool folder}) async {
    final items = <FsBatchItem>[];
    final written = <({String abs, String rel})>[];
    if (folder) {
      final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose a folder to add here');
      if (dir == null) return;
      final root = Directory(dir);
      final top = dir.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
      await for (final ent in root.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = ent.path
            .substring(root.path.length)
            .replaceAll('\\', '/')
            .replaceAll(RegExp(r'^/+'), '');
        final path = '$top/$rel';
        items.add(FsBatchItem(ent.path, path, await ent.length()));
        written.add((abs: ent.path, rel: fsJoin(_sub, fsTargetRel(path, false))));
      }
    } else {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res == null) return;
      for (final f in res.files) {
        if (f.path == null) continue;
        items.add(FsBatchItem(f.path!, f.name, f.size));
        written.add((abs: f.path!, rel: fsJoin(_sub, fsTargetRel(f.name, false))));
      }
    }
    if (items.isEmpty) {
      _toast('No files detected.');
      return;
    }
    setState(() {
      _dropBusy = true;
      _dropProgress = 0;
      _dropStatus = 'Reading dropped items…';
    });
    try {
      final r = await engine.uploadItems(
        owner: _owner,
        sub: _sub,
        items: items,
        onProgress: (s, p) {
          if (mounted) {
            setState(() {
              _dropStatus = s;
              _dropProgress = p;
            });
          }
        },
      );
      if (mounted) {
        setState(() => _dropStatus = r.summary());
        _toast(r.toastText());
      }
      final local = await engine.writeUploadedLocally(written);
      if (local != null) _toast(local);
    } catch (e) {
      _toast('$e');
    }
    _loadExplorer(silent: true);
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _dropBusy = false);
    });
  }

  void _runFolderSync() {
    if (!engine.hasSource) {
      _toast('No source folder set. Choose one in Folder Sync settings.');
      Timer(const Duration(milliseconds: 350), _openSettings);
      return;
    }
    if (engine.running) {
      _toast('A sync is already running.');
      return;
    }
    _syncRequestedHere = true;
    engine.syncNow();
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => FsSettingsDialog(onSync: _runFolderSync),
    );
  }

  Future<void> _openInvite() async {
    await showDialog<void>(
      context: context,
      builder: (_) => FsInviteDialog(api: fs),
    );
  }

  Future<void> _openJoin() async {
    final raw = await fsPrompt(
      context,
      title: 'Join a shared folder',
      label: 'Invite link',
      confirm: 'Join',
      hint: 'Paste the Folder Sync invite link',
      emptyError: 'Paste an invite link',
      icon: Icons.link,
    );
    if (raw == null) return;
    final token = fsInviteToken(raw);
    if (token == null) {
      _toast('That does not look like a Folder Sync invite link.');
      return;
    }
    try {
      final r = await fs.accept(token);
      _toast('You joined ${r.name}.');
      await _loadWorkspaces(select: r.owner);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _itemMenu(Offset pos, FsEntry e) async {
    final isFile = !e.isDir;
    final acts = <(String, IconData, VoidCallback, bool)>[
      if (e.isDir) ('Open', Icons.folder_open, () => _open(_rel(e)), false),
      if (isFile) ('Open', Icons.visibility_outlined, () => _openViewer(e), false),
      if (isFile) ('Download', Icons.download, () => _download(e), false),
      if (isFile) ('Send email', Icons.email_outlined, () => _email(e), false),
      if (isFile) ('Send to chat', Icons.chat_bubble_outline, () => _chat(e), false),
      if (isFile)
        ('Send to Files Management', Icons.cloud_upload_outlined,
            () => _toFilesManagement(e), false),
      if (_canEdit) ('Rename', Icons.text_fields, () => _rename(e), false),
      if (_canEdit) ('Delete', Icons.delete_outline, () => _delete(e), true),
    ];
    await _showMenu(pos, acts);
  }

  Future<void> _bgMenu(Offset pos) async {
    if (!_canEdit) return;
    await _showMenu(pos, [
      ('New folder', Icons.create_new_folder_outlined, _newFolder, false),
      ('Refresh', Icons.refresh, () => _loadExplorer(), false),
    ]);
  }

  Future<void> _showMenu(
      Offset pos, List<(String, IconData, VoidCallback, bool)> acts) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final i = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
          pos & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        for (var k = 0; k < acts.length; k++)
          PopupMenuItem<int>(
            value: k,
            height: 38,
            child: Row(
              children: [
                Icon(acts[k].$2,
                    size: 16,
                    color: acts[k].$4 ? Brand.danger : const Color(0xFF334155)),
                const SizedBox(width: 10),
                Text(acts[k].$1,
                    style: TextStyle(
                        fontSize: 13.5,
                        color: acts[k].$4
                            ? Brand.danger
                            : const Color(0xFF334155))),
              ],
            ),
          ),
      ],
    );
    if (i != null) acts[i].$3();
  }

  Future<void> _email(FsEntry e) => showDialog<void>(
        context: context,
        builder: (_) =>
            FsEmailDialog(api: fs, owner: _owner, rel: _rel(e), name: e.name),
      );

  Future<void> _chat(FsEntry e) => showDialog<void>(
        context: context,
        builder: (_) =>
            FsChatDialog(api: fs, owner: _owner, rel: _rel(e), name: e.name),
      );

  bool _canDropInto(_Drag d, String target) {
    if (!_canEdit) return false;
    if (d.rel == target) return false;
    if (d.isDir && (target == d.rel || target.startsWith('${d.rel}/'))) {
      return false;
    }
    final parent = fsSegs(d.rel)..removeLast();
    return parent.join('/') != target;
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _fsBorder),
            ),
            child: Icon(icon, size: 17, color: _fsText),
          ),
        ),
      );

  Widget _seg(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1)),
                ]
              : const [],
        ),
        child: Tooltip(
          message: label,
          child: Icon(icon,
              size: 16,
              color: active ? Brand.signal : const Color(0xFF334155)),
        ),
      ),
    );
  }

  Widget _workspaceSelect() {
    final items = _workspaces.isEmpty
        ? [FsWorkspace(_owner, _label, '')]
        : _workspaces;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _fsBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: items.any((w) => w.owner == _owner) ? _owner : items.first.owner,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700, color: _fsText),
          items: [
            for (final w in items)
              DropdownMenuItem<int>(
                value: w.owner,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      w.owner == myId ? Icons.folder_shared : Icons.people_alt,
                      size: 16,
                      color: Brand.signal,
                    ),
                    const SizedBox(width: 8),
                    Text(w.name),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null && v != _owner) _switchWorkspace(v);
          },
        ),
      ),
    );
  }

  Widget _crumbs() {
    final parts = fsSegs(_sub);
    Widget crumb(String label, String sub, bool current, {IconData? icon}) {
      final child = InkWell(
        onTap: current ? null : () => _open(sub),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: current ? _fsText : Brand.signal),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: current ? _fsText : Brand.signal,
                ),
              ),
            ],
          ),
        ),
      );
      if (current) return child;
      return DragTarget<_Drag>(
        onWillAcceptWithDetails: (d) => _canDropInto(d.data, sub),
        onAcceptWithDetails: (d) => _moveItem(d.data.rel, sub),
        builder: (context, cand, _) => Container(
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? _fsPrimaryLight : null,
            borderRadius: BorderRadius.circular(6),
            border: cand.isNotEmpty
                ? Border.all(color: Brand.signal, style: BorderStyle.solid)
                : null,
          ),
          child: child,
        ),
      );
    }

    final children = <Widget>[
      crumb(_label, '', parts.isEmpty, icon: Icons.account_tree_outlined),
    ];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
      children.add(const Text('/', style: TextStyle(color: Color(0xFF9CA3AF))));
      children.add(crumb(parts[i], acc, i == parts.length - 1));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: false,
      child: Row(children: children),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _fsBorder)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final actions = <Widget>[
          SearchField(
            controller: _search,
            hint: 'Search files & folders…',
            width: 230,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _fsBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _seg('Tiles', Icons.grid_view, _tiles, () {
                setState(() => _tiles = true);
                _prefs?.setString('fs_view_mode', 'tiles');
              }),
              _seg('List', Icons.list, !_tiles, () {
                setState(() => _tiles = false);
                _prefs?.setString('fs_view_mode', 'list');
              }),
            ]),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh, 'Refresh', () {
            _loadWorkspaces(silent: true);
            _loadExplorer();
          }),
          const SizedBox(width: 8),
          _iconBtn(Icons.link, 'Join a shared folder', _openJoin),
          if (_canEdit) ...[
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: 'Upload here',
              position: PopupMenuPosition.under,
              onSelected: (v) => _uploadHere(folder: v == 1),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.upload_file, size: 16),
                    SizedBox(width: 10),
                    Text('Upload files'),
                  ]),
                ),
                PopupMenuItem(
                  value: 1,
                  child: Row(children: [
                    Icon(Icons.drive_folder_upload, size: 16),
                    SizedBox(width: 10),
                    Text('Upload a folder'),
                  ]),
                ),
              ],
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _fsBorder),
                ),
                child: const Icon(Icons.upload, size: 17, color: _fsText),
              ),
            ),
            const SizedBox(width: 8),
            _iconBtn(Icons.person_add_alt_1_outlined, 'Invite contributors',
                _openInvite),
            const SizedBox(width: 8),
            _iconBtn(Icons.settings_outlined, 'Folder Sync settings',
                _openSettings),
            const SizedBox(width: 8),
            Opacity(
              opacity: engine.hasSource ? 1 : 0.6,
              child: SignalButton(
                label: engine.running ? 'Syncing…' : 'Sync Folder',
                icon: Icons.cloud_upload_outlined,
                onPressed: engine.running ? null : _runFolderSync,
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_outlined, size: 14, color: _fsMuted),
                SizedBox(width: 6),
                Text('View only',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _fsMuted)),
              ]),
            ),
          ],
        ];
        if (c.maxWidth >= 1150) {
          return Row(children: [
            _workspaceSelect(),
            const SizedBox(width: 12),
            Expanded(child: _crumbs()),
            const SizedBox(width: 12),
            ...actions,
          ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _workspaceSelect(),
              const SizedBox(width: 12),
              Expanded(child: _crumbs()),
            ]),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: actions,
            ),
          ],
        );
      }),
    );
  }

  Widget _syncStrip() {
    if (_dropBusy) {
      return _bar(_dropProgress, _dropStatus);
    }
    if (!_canEdit || _owner != myId) return const SizedBox.shrink();
    if (engine.running) return _bar(engine.progress, engine.status);
    if (!engine.hasSource) return const SizedBox.shrink();
    final err = engine.lastError;
    final errs = engine.lastResult?.errors ?? const <String>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: _fsBorder)),
      ),
      child: Row(
        children: [
          Icon(
            engine.autoActive ? Icons.sync : Icons.sync_disabled,
            size: 15,
            color: engine.autoActive ? const Color(0xFF10B981) : _fsMuted,
          ),
          const SizedBox(width: 6),
          Text(
            engine.autoActive ? 'Auto sync on' : 'Auto sync off',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: _fsText),
          ),
          const _Dot(),
          Flexible(
            child: Tooltip(
              message: engine.settings.localPath ?? '',
              child: Text(
                engine.settings.localPath ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: _fsMuted),
              ),
            ),
          ),
          const _Dot(),
          Text('Last synced ${fsAgo(engine.lastSynced)}',
              style: const TextStyle(fontSize: 12.5, color: _fsMuted)),
          if (err != null) ...[
            const _Dot(),
            Flexible(
              child: Text(err,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFFB91C1C))),
            ),
          ] else if (errs.isNotEmpty) ...[
            const _Dot(),
            InkWell(
              onTap: () => showWebModal<void>(
                context,
                title: 'Sync issues',
                icon: Icons.warning_amber_rounded,
                width: 620,
                builder: (_) => FsErrorLog(errors: errs),
              ),
              child: Text('${errs.length} issue(s) — details',
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFB91C1C),
                      decoration: TextDecoration.underline)),
            ),
          ] else if (engine.lastResult != null) ...[
            const _Dot(),
            Flexible(
              child: Text(engine.lastResult!.summary(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: _fsMuted)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(double? p, String status) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFBF5),
          border: Border(bottom: BorderSide(color: _fsBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsProgressBar(value: p),
            const SizedBox(height: 6),
            Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: _fsText)),
          ],
        ),
      );

  Widget _empty(IconData icon, String title, String text, {Widget? cta}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: const Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: _fsText)),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: _fsMuted)),
            if (cta != null) ...[const SizedBox(height: 16), cta],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    if (_sub.isNotEmpty) {
      return _empty(
        Icons.folder_open,
        'This folder is empty',
        _canEdit
            ? 'Use Upload to add files & folders here, or right-click for New folder.'
            : 'Nothing here yet.',
      );
    }
    if (!_canEdit) {
      return _empty(Icons.folder_open, 'No files here yet',
          'This shared folder is empty.');
    }
    final needs = !engine.hasSource;
    return _empty(
      Icons.folder_open,
      'No files synced here yet',
      needs
          ? 'Choose a source folder to sync from your computer.'
          : 'Use Sync Folder to sync your folder, or upload files here.',
      cta: SignalButton(
        label: needs ? 'Set up Folder Sync' : 'Sync Folder',
        icon: needs ? Icons.settings_outlined : Icons.cloud_upload_outlined,
        onPressed: needs ? _openSettings : _runFolderSync,
      ),
    );
  }

  Widget _itemGestures(FsEntry e, Widget child) {
    final rel = _rel(e);
    final gestures = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: e.isDir ? () => _open(rel) : null,
      onDoubleTap: e.isDir ? null : () => _openViewer(e),
      onSecondaryTapDown: (d) => _itemMenu(d.globalPosition, e),
      child: child,
    );
    final body = DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => e.isDir
          ? _canDropInto(d.data, rel)
          : (d.data.name != e.name && !d.data.isDir && fsSegs(d.data.rel).length == fsSegs(rel).length),
      onAcceptWithDetails: (d) {
        if (e.isDir) {
          _moveItem(d.data.rel, rel);
        } else {
          _swapInOrder(d.data.name, e.name);
        }
      },
      builder: (context, cand, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cand.isNotEmpty ? Brand.signal : Colors.transparent,
            width: 2,
          ),
          color: cand.isNotEmpty ? _fsPrimaryLight : null,
        ),
        child: gestures,
      ),
    );
    final ico = _iconFor(e);
    return Draggable<_Drag>(
      data: _Drag(rel, e.name, e.isDir),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.signal),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 12),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ico.icon, size: 18, color: ico.color),
            const SizedBox(width: 8),
            Text(e.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _fsText)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: body),
      child: body,
    );
  }

  Widget _tile(FsEntry e) {
    final ico = _iconFor(e);
    return _Hover(
      builder: (hover) => Tooltip(
        message: e.name,
        waitDuration: const Duration(milliseconds: 700),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          decoration: BoxDecoration(
            color: hover ? _fsPrimaryLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hover ? const Color(0xFFFFB266) : _fsBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ico.icon, size: 42, color: ico.color),
              const SizedBox(height: 10),
              Text(
                e.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _fsText),
              ),
              if (!e.isDir) ...[
                const SizedBox(height: 3),
                Text(fsHumanSize(e.size),
                    style: const TextStyle(fontSize: 11.5, color: _fsMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _listRow(FsEntry e) {
    final ico = _iconFor(e);
    final m = e.mtime > 0
        ? DateTime.fromMillisecondsSinceEpoch(e.mtime * 1000)
        : null;
    return _Hover(
      builder: (hover) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: hover ? _fsPrimaryLight : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(ico.icon, size: 20, color: ico.color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _fsText)),
            ),
            SizedBox(
              width: 110,
              child: Text(e.isDir ? 'Folder' : fsHumanSize(e.size),
                  style: const TextStyle(fontSize: 12.5, color: _fsMuted)),
            ),
            SizedBox(
              width: 150,
              child: Text(m == null ? '' : fsAgo(m),
                  style: const TextStyle(fontSize: 12.5, color: _fsMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: TpLoader(strokeWidth: 2.5, color: Brand.signal));
    }
    if (_error != null) {
      return _empty(Icons.folder_open, 'Nothing to show', _error!);
    }
    final visible = _entries.where((e) => !_hidden.contains(e.name)).toList();
    if (!_exists || visible.isEmpty) return _emptyState();
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? visible
        : visible.where((e) => e.name.toLowerCase().contains(q)).toList();
    if (list.isEmpty) {
      return _empty(Icons.search, 'No matches',
          'Nothing here matches “${_search.text.trim()}”.');
    }
    if (_tiles) {
      return GridView.builder(
        padding: const EdgeInsets.all(18),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisExtent: 150,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _itemGestures(list[i], _tile(list[i])),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Row(children: [
            SizedBox(width: 32),
            Expanded(
                child: Text('Name',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _fsMuted))),
            SizedBox(
                width: 110,
                child: Text('Size',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _fsMuted))),
            SizedBox(
                width: 150,
                child: Text('Modified',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _fsMuted))),
          ]),
        ),
        for (final e in list) _itemGestures(e, _listRow(e)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Tooltip(
                  message: 'Back to Files Management',
                  child: InkWell(
                    onTap: widget.onBack,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _fsBorder),
                      ),
                      child: const Icon(Icons.arrow_back, size: 18, color: _fsText),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('Folder Sync',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _fsText)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _fsBorder),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _toolbar(),
                    _syncStrip(),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapDown: (d) => _bgMenu(d.globalPosition),
                        child: _body(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: Color(0xFF9CA3AF))),
      );
}

class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(bool hover) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: widget.builder(_hover),
      );
}

class _Viewer extends StatefulWidget {
  const _Viewer({
    required this.fs,
    required this.owner,
    required this.rel,
    required this.entry,
    required this.onDownload,
    required this.onOpen,
  });
  final FolderSyncApi fs;
  final int owner;
  final String rel;
  final FsEntry entry;
  final VoidCallback onDownload;
  final VoidCallback onOpen;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  Uint8List? _bytes;
  String? _error;
  bool get _img => _viewImg.contains(widget.entry.ext);
  bool get _txt => _viewTxt.contains(widget.entry.ext);
  bool get _previewable => (_img || _txt) && widget.entry.size <= 25 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    if (_previewable) _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.fs.fetchBytes(widget.owner, widget.rel);
      if (mounted) setState(() => _bytes = Uint8List.fromList(b));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    Widget body;
    if (!_previewable) {
      body = SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(widget.entry).icon, size: 46, color: const Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text('Preview not available',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                widget.entry.ext == 'pdf'
                    ? 'Open it in your PDF viewer, or download it.'
                    : "This file type can't be shown here.",
                style: const TextStyle(color: _fsMuted),
              ),
              const SizedBox(height: 16),
              Row(mainAxisSize: MainAxisSize.min, children: [
                GhostButton(label: 'Open', icon: Icons.open_in_new, onPressed: widget.onOpen),
                const SizedBox(width: 10),
                SignalButton(label: 'Download', icon: Icons.download, onPressed: widget.onDownload),
              ]),
            ],
          ),
        ),
      );
    } else if (_error != null) {
      body = SizedBox(
          height: 200,
          child: Center(child: Text(_error!, style: const TextStyle(color: Brand.danger))));
    } else if (_bytes == null) {
      body = const SizedBox(
          height: 300,
          child: Center(child: TpLoader(strokeWidth: 2.5, color: Brand.signal)));
    } else if (_img) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.72),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_bytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('This image could not be displayed.'),
                      )),
            ),
          ),
        ),
      );
    } else {
      body = Container(
        height: size.height * 0.72,
        decoration: BoxDecoration(
          border: Border.all(color: _fsBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: SelectableText(
            utf8.decode(_bytes!, allowMalformed: true),
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5, height: 1.45),
          ),
        ),
      );
    }
    return WebModal(
      title: widget.entry.name,
      icon: Icons.visibility_outlined,
      width: 1100,
      scrollable: false,
      actions: [
        GhostButton(label: 'Open externally', icon: Icons.open_in_new, onPressed: widget.onOpen),
        SignalButton(label: 'Download', icon: Icons.download, onPressed: widget.onDownload),
      ],
      child: body,
    );
  }
}
