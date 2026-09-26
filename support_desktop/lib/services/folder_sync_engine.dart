import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import 'folder_sync_service.dart';
import 'live_sync.dart';

class FsSettings {
  String? localPath;
  bool stripTop = true;
  bool force = false;
  bool mirror = false;
  bool twoWay = true;
  bool auto = false;
}

class FsSyncResult {
  int saved = 0;
  int already = 0;
  int skipped = 0;
  int deleted = 0;
  int downloaded = 0;
  int localDeleted = 0;
  bool empty = false;
  final List<String> errors = [];

  bool get changed =>
      saved > 0 || deleted > 0 || downloaded > 0 || localDeleted > 0;

  String summary() {
    if (empty) return 'That folder has no files.';
    final parts = <String>['$saved synced'];
    if (already > 0) parts.add('$already already synced');
    if (downloaded > 0) parts.add('$downloaded pulled to this computer');
    if (deleted > 0) parts.add('$deleted removed');
    if (localDeleted > 0) parts.add('$localDeleted removed locally');
    if (skipped > 0) parts.add('$skipped skipped');
    return 'Done. ${parts.join(', ')}.';
  }

  String toastText() {
    if (empty) return 'That folder has no files.';
    if (errors.isNotEmpty) {
      return '$saved synced, ${errors.length} issue(s). See details.';
    }
    if (changed) {
      final bits = <String>['$saved synced'];
      if (downloaded > 0) bits.add('$downloaded pulled');
      if (deleted > 0) bits.add('$deleted removed');
      if (localDeleted > 0) bits.add('$localDeleted removed locally');
      return bits.join(', ');
    }
    return 'Already up to date — nothing new.';
  }
}

class _Local {
  _Local(this.abs, this.rel, this.size, this.mtime);
  final String abs;
  final String rel;
  final int size;
  final int mtime;
  String server = '';
}

class _Snap {
  _Snap(this.ls, this.lm, this.ss, this.sm);
  final int ls;
  final int lm;
  final int ss;
  final int sm;
  Map<String, int> toJson() => {'ls': ls, 'lm': lm, 'ss': ss, 'sm': sm};
}

class FolderSyncEngine extends ChangeNotifier {
  FolderSyncEngine._();
  static final FolderSyncEngine instance = FolderSyncEngine._();

  static const Duration watchDebounce = Duration(seconds: 3);
  static const Duration periodic = Duration(minutes: 5);

  ApiClient? _api;
  FolderSyncApi? _fs;
  int _me = 0;
  SharedPreferences? _prefs;

  FsSettings settings = FsSettings();
  bool running = false;
  String status = '';
  double? progress;
  FsSyncResult? lastResult;
  DateTime? lastSynced;
  String? lastError;
  int syncCount = 0;
  bool autoActive = false;

  bool _pending = false;
  bool _writingLocal = false;
  Timer? _debounce;
  Timer? _periodic;
  Timer? _retry;
  VoidCallback? _liveCancel;
  final List<StreamSubscription<FileSystemEvent>> _watchSubs = [];

  FolderSyncApi? get api => _fs;
  int get me => _me;
  bool get hasSource => (settings.localPath ?? '').isNotEmpty;
  bool get twoWayActive => settings.twoWay && hasSource && settings.stripTop;
  String get sourceName => hasSource ? _baseName(settings.localPath!) : '';

  static String _baseName(String p) {
    final segs = p
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segs.isEmpty ? p : segs.last;
  }

  String _k(String n) => 'fs_${n}_u$_me';

  Future<void> attach(ApiClient api) async {
    final uid = api.userId ?? 0;
    if (identical(api, _api) && uid == _me && _fs != null) return;
    detach();
    if (uid <= 0) return;
    _api = api;
    _fs = FolderSyncApi(api);
    _me = uid;
    _prefs = await SharedPreferences.getInstance();
    _loadSettings();
    notifyListeners();
    if (settings.auto && hasSource) {
      var allowed = true;
      try {
        final m = await api.get('desktopFilesPageMeta');
        if (m['success'] == true) allowed = m['can_folder_sync'] == true;
      } catch (_) {}
      if (allowed && _me == uid) _startAuto();
    }
  }

  void detach() {
    _stopAuto();
    _retry?.cancel();
    _api = null;
    _fs = null;
    _me = 0;
    settings = FsSettings();
    running = false;
    status = '';
    progress = null;
    lastResult = null;
    lastSynced = null;
    lastError = null;
    _pending = false;
  }

  void _loadSettings() {
    final p = _prefs!;
    settings = FsSettings()
      ..localPath = p.getString(_k('local_path'))
      ..stripTop = p.getBool(_k('strip_top')) ?? true
      ..force = p.getBool(_k('force')) ?? false
      ..mirror = p.getBool(_k('mirror')) ?? false
      ..twoWay = p.getBool(_k('two_way')) ?? true
      ..auto = p.getBool(_k('auto')) ?? false;
    final last = p.getInt(_k('last_synced'));
    lastSynced =
        last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
  }

  Future<void> setLocalPath(String? path) async {
    final p = _prefs;
    if (p == null) return;
    settings.localPath = (path ?? '').isEmpty ? null : path;
    if (settings.localPath == null) {
      await p.remove(_k('local_path'));
      settings.auto = false;
      await p.setBool(_k('auto'), false);
    } else {
      await p.setString(_k('local_path'), settings.localPath!);
    }
    await _deleteSnap();
    if (settings.auto && hasSource) {
      _startAuto();
    } else {
      _stopAuto();
    }
    notifyListeners();
  }

  Future<void> setOption({
    bool? stripTop,
    bool? force,
    bool? mirror,
    bool? twoWay,
    bool? auto,
  }) async {
    final p = _prefs;
    if (p == null) return;
    if (stripTop != null) {
      settings.stripTop = stripTop;
      await p.setBool(_k('strip_top'), stripTop);
    }
    if (force != null) {
      settings.force = force;
      await p.setBool(_k('force'), force);
    }
    if (mirror != null) {
      settings.mirror = mirror;
      await p.setBool(_k('mirror'), mirror);
    }
    if (twoWay != null) {
      settings.twoWay = twoWay;
      await p.setBool(_k('two_way'), twoWay);
    }
    if (auto != null) {
      settings.auto = auto && hasSource;
      await p.setBool(_k('auto'), settings.auto);
      if (settings.auto) {
        _startAuto();
      } else {
        _stopAuto();
      }
    }
    notifyListeners();
  }

  void _startAuto() {
    _stopAuto();
    if (!hasSource || _fs == null) return;
    autoActive = true;
    _liveCancel = LiveSync.instance.listen('foldersync', () {
      if (twoWayActive && !_writingLocal) requestSync(delay: watchDebounce);
    });
    _periodic = Timer.periodic(periodic, (_) => requestSync());
    unawaited(_rewatch());
    requestSync(delay: const Duration(seconds: 1));
    notifyListeners();
  }

  void _stopAuto() {
    autoActive = false;
    _debounce?.cancel();
    _periodic?.cancel();
    _periodic = null;
    _liveCancel?.call();
    _liveCancel = null;
    _cancelWatches();
  }

  void _cancelWatches() {
    for (final s in _watchSubs) {
      s.cancel();
    }
    _watchSubs.clear();
  }

  Future<void> _rewatch() async {
    _cancelWatches();
    if (!autoActive || !hasSource) return;
    final root = Directory(settings.localPath!);
    if (!await root.exists()) return;
    void onEvent(FileSystemEvent e) {
      if (_writingLocal) return;
      if (e.path.contains('.fsdl-')) return;
      if (running) {
        _pending = true;
        return;
      }
      requestSync(delay: watchDebounce);
    }

    if (Platform.isLinux) {
      final dirs = <Directory>[root];
      final stack = <Directory>[root];
      while (stack.isNotEmpty && dirs.length < 3000) {
        final d = stack.removeLast();
        try {
          await for (final e in d.list(followLinks: false)) {
            if (e is Directory) {
              dirs.add(e);
              stack.add(e);
            }
          }
        } catch (_) {}
      }
      for (final d in dirs) {
        try {
          _watchSubs.add(d.watch().listen(onEvent, onError: (_) {}));
        } catch (_) {}
      }
    } else {
      try {
        _watchSubs.add(root.watch(recursive: true).listen(onEvent, onError: (_) {}));
      } catch (_) {}
    }
  }

  void requestSync({Duration delay = Duration.zero}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => syncNow());
  }

  void _scheduleRetry(Duration after) {
    _retry?.cancel();
    if (!autoActive) return;
    _retry = Timer(after + const Duration(seconds: 1), () => syncNow());
  }

  Future<FsSyncResult?> syncNow() async {
    final fs = _fs;
    if (fs == null || _me <= 0) return null;
    if (running) {
      _pending = true;
      return null;
    }
    if (!hasSource) {
      lastError = 'No source folder set. Choose one in Folder Sync settings.';
      notifyListeners();
      return null;
    }
    if (fs.coolingDown) {
      final left = fs.coolDownLeft;
      status = 'The server is busy. Retrying in ${left.inSeconds + 1}s.';
      _scheduleRetry(left);
      notifyListeners();
      return null;
    }
    running = true;
    progress = 0;
    status = 'Reading source…';
    lastError = null;
    notifyListeners();
    FsSyncResult? result;
    final owner = _me;
    try {
      result = await _doSync(fs, owner);
      if (owner == _me) {
        lastResult = result;
        lastSynced = DateTime.now();
        await _prefs?.setInt(
            _k('last_synced'), lastSynced!.millisecondsSinceEpoch);
        status = result.summary();
      }
    } on FolderSyncException catch (e) {
      lastError = e.message;
      status = e.message;
      if (e.busy) _scheduleRetry(fs.coolDownLeft);
    } catch (e) {
      lastError = '$e';
      status = '$e';
    } finally {
      _writingLocal = false;
      running = false;
      progress = null;
      syncCount++;
      notifyListeners();
      if (autoActive && Platform.isLinux) unawaited(_rewatch());
      if (_pending) {
        _pending = false;
        requestSync(delay: const Duration(seconds: 2));
      }
    }
    return result;
  }

  void _setStatus(String s, [double? p]) {
    status = s;
    if (p != null) progress = p.clamp(0, 1).toDouble();
    notifyListeners();
  }

  Future<List<_Local>> _scan(Directory root) async {
    final out = <_Local>[];
    final stack = <Directory>[root];
    final rootLen = root.path.length;
    while (stack.isNotEmpty) {
      final d = stack.removeLast();
      List<FileSystemEntity> kids;
      try {
        kids = await d.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final e in kids) {
        if (e is Directory) {
          stack.add(e);
        } else if (e is File) {
          final name = _baseName(e.path);
          if (name.startsWith('.fsdl-')) continue;
          try {
            final st = await e.stat();
            final rel = e.path
                .substring(rootLen)
                .replaceAll('\\', '/')
                .replaceAll(RegExp(r'^/+'), '');
            out.add(_Local(
                e.path, rel, st.size, st.modified.millisecondsSinceEpoch));
          } catch (_) {}
        }
      }
    }
    return out;
  }

  Future<File> _snapFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(
        '${dir.path}${Platform.pathSeparator}folder_sync_snap_u$_me.json');
  }

  Future<Map<String, _Snap>> _loadSnap(String root, bool strip) async {
    try {
      final f = await _snapFile();
      if (!await f.exists()) return {};
      final d = jsonDecode(await f.readAsString());
      if (d is! Map || d['root'] != root || d['strip'] != strip) return {};
      final files = d['files'];
      if (files is! Map) return {};
      final out = <String, _Snap>{};
      files.forEach((k, v) {
        if (v is Map) {
          out['$k'] = _Snap(
            (v['ls'] as num?)?.toInt() ?? -1,
            (v['lm'] as num?)?.toInt() ?? -1,
            (v['ss'] as num?)?.toInt() ?? -1,
            (v['sm'] as num?)?.toInt() ?? -1,
          );
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSnap(String root, bool strip, Map<String, _Snap> s) async {
    try {
      final f = await _snapFile();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'root': root,
        'strip': strip,
        'files': s.map((k, v) => MapEntry(k, v.toJson())),
      }));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<void> _deleteSnap() async {
    try {
      final f = await _snapFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<FsSyncResult> _doSync(FolderSyncApi fs, int owner) async {
    final r = FsSyncResult();
    final rootPath = settings.localPath!;
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw FolderSyncException(
          'Local folder not found: $rootPath. Choose it again in Folder Sync settings.');
    }
    final strip = settings.stripTop;
    final two = twoWayActive;
    final top = _baseName(rootPath);
    _setStatus('Reading folder…', 0);
    final local = await _scan(root);
    if (local.isEmpty && !two) {
      r.empty = true;
      return r;
    }

    _setStatus('Checking what is already synced…');
    final manifest = await fs.manifest(owner);
    final snap = await _loadSnap(rootPath, strip);

    final byRel = <String, _Local>{};
    for (final l in local) {
      l.server = fsTargetRel('$top/${l.rel}', strip);
      if (l.server.isEmpty) continue;
      byRel.putIfAbsent(l.server, () => l);
    }

    final uploads = <_Local>[];
    final downloads = <String>[];
    final localDeletes = <_Local>[];
    byRel.forEach((rel, l) {
      final ex = manifest[rel];
      final s = snap[rel];
      final localChanged = s == null || l.size != s.ls || l.mtime != s.lm;
      if (settings.force) {
        uploads.add(l);
        return;
      }
      if (ex == null) {
        if (two && s != null && !localChanged) {
          localDeletes.add(l);
        } else {
          uploads.add(l);
        }
        return;
      }
      if (s == null) {
        if (ex.size == l.size) {
          r.already++;
        } else {
          uploads.add(l);
        }
        return;
      }
      if (localChanged) {
        uploads.add(l);
        return;
      }
      final serverChanged = ex.size != s.ss || ex.mtime != s.sm;
      if (!serverChanged) {
        r.already++;
      } else if (two) {
        downloads.add(rel);
      } else if (ex.size == l.size) {
        r.already++;
      } else {
        uploads.add(l);
      }
    });
    if (two) {
      manifest.forEach((rel, ex) {
        if (byRel.containsKey(rel)) return;
        final s = snap[rel];
        if (s == null || ex.size != s.ss || ex.mtime != s.sm) downloads.add(rel);
      });
    }

    if (localDeletes.length > 10 && localDeletes.length * 2 > snap.length) {
      r.errors.add(
          'The server copy is missing ${localDeletes.length} files at once — local deletions were skipped and the files re-uploaded.');
      uploads.addAll(localDeletes);
      localDeletes.clear();
    }

    final failed = <String>{};
    final total = uploads.length + downloads.length + localDeletes.length;
    var done = 0;
    double frac() => total == 0 ? 1 : done / total;

    if (localDeletes.isNotEmpty) {
      _writingLocal = true;
      final touched = <Directory>{};
      for (final l in localDeletes) {
        try {
          await File(l.abs).delete();
          byRel.remove(l.server);
          touched.add(File(l.abs).parent);
          r.localDeleted++;
        } catch (e) {
          r.errors.add('${l.rel}: could not delete locally ($e)');
        }
        done++;
      }
      for (final d in touched) {
        await _removeEmptyUp(d, root);
      }
      _setStatus('Removed ${r.localDeleted} file(s) deleted on the web…', frac());
    }

    for (final rel in downloads) {
      _writingLocal = true;
      _setStatus('Pulling ${done + 1} of $total: ${fsSegs(rel).last}', frac());
      try {
        final target = await _localTargetFor(root, rel, create: true);
        final tmp = File(
            '${target.parent.path}${Platform.pathSeparator}.fsdl-${DateTime.now().microsecondsSinceEpoch}');
        try {
          await fs.downloadTo(owner, rel, tmp);
          if (await target.exists()) await target.delete();
          await tmp.rename(target.path);
        } finally {
          if (await tmp.exists()) await tmp.delete();
        }
        final ex = manifest[rel];
        if (ex != null && ex.mtime > 0) {
          try {
            await target.setLastModified(
                DateTime.fromMillisecondsSinceEpoch(ex.mtime * 1000));
          } catch (_) {}
        }
        final st = await target.stat();
        final l = _Local(target.path, rel, st.size,
            st.modified.millisecondsSinceEpoch)
          ..server = rel;
        byRel[rel] = l;
        r.downloaded++;
      } on FolderSyncException catch (e) {
        if (e.busy) rethrow;
        failed.add(rel);
        r.errors.add('$rel: ${e.message}');
      } catch (e) {
        failed.add(rel);
        r.errors.add('$rel: $e');
      }
      done++;
    }
    _writingLocal = false;

    final big = <_Local>[];
    final small = <_Local>[];
    for (final l in uploads) {
      (l.size > kFsBigFileBytes ? big : small).add(l);
    }
    var batch = <_Local>[];
    var batchBytes = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      _setStatus('Syncing ${done + batch.length} of $total file(s)…', frac());
      try {
        final res = await fs.uploadBatch(owner, '', strip, [
          for (final l in batch)
            FsBatchItem(l.abs, '$top/${l.rel}', l.size),
        ]);
        r.saved += res.saved;
        r.skipped += res.skipped;
        r.errors.addAll(res.errors);
        for (final l in batch) {
          final label = '$top/${l.rel}';
          if (res.errors.any((e) => e.startsWith('$label:'))) {
            failed.add(l.server);
          }
        }
      } on FolderSyncException catch (e) {
        if (e.busy) rethrow;
        r.errors.add(e.message);
        failed.addAll(batch.map((l) => l.server));
      } catch (e) {
        r.errors.add('$e');
        failed.addAll(batch.map((l) => l.server));
      }
      done += batch.length;
      _setStatus(status, frac());
      batch = [];
      batchBytes = 0;
    }

    for (final l in small) {
      if (batch.length >= kFsBatchSize ||
          (batch.isNotEmpty && batchBytes + l.size > kFsBatchBytes)) {
        await flush();
      }
      batch.add(l);
      batchBytes += l.size;
    }
    await flush();

    for (final l in big) {
      final name = fsSegs(l.rel).last;
      try {
        await fs.uploadChunked(
          owner,
          '',
          strip,
          FsBatchItem(l.abs, '$top/${l.rel}', l.size),
          onProgress: (f) => _setStatus(
            'Syncing ${done + 1} of $total: $name — ${(f * 100).round()}%',
            total == 0 ? f : (done + f) / total,
          ),
        );
        r.saved++;
      } on FolderSyncException catch (e) {
        if (e.busy) rethrow;
        failed.add(l.server);
        r.errors.add('${l.rel}: ${e.message}');
      } catch (e) {
        failed.add(l.server);
        r.errors.add('${l.rel}: $e');
      }
      done++;
      _setStatus(status, frac());
    }

    if (settings.mirror && byRel.isNotEmpty) {
      _setStatus('Removing files not in the source…');
      try {
        r.deleted = await fs.prune(owner, byRel.keys.toList());
      } on FolderSyncException catch (e) {
        if (e.busy) rethrow;
        r.errors.add('Prune: ${e.message}');
      }
    }

    final fresh = (uploads.isNotEmpty || r.deleted > 0)
        ? await fs.manifest(owner)
        : manifest;
    final next = <String, _Snap>{};
    byRel.forEach((rel, l) {
      if (failed.contains(rel)) return;
      final ex = fresh[rel];
      if (ex == null) return;
      next[rel] = _Snap(l.size, l.mtime, ex.size, ex.mtime);
    });
    snap.forEach((rel, s) {
      if (next.containsKey(rel) || byRel.containsKey(rel)) return;
      if (fresh.containsKey(rel)) next[rel] = s;
    });
    await _saveSnap(rootPath, strip, next);
    _setStatus(r.summary(), 1);
    return r;
  }

  Future<void> _removeEmptyUp(Directory d, Directory root) async {
    var cur = d;
    while (cur.path.length > root.path.length &&
        cur.path.startsWith(root.path)) {
      try {
        if (await cur.list().isEmpty) {
          await cur.delete();
        } else {
          return;
        }
      } catch (_) {
        return;
      }
      cur = cur.parent;
    }
  }

  Future<String?> _matchChild(Directory dir, String seg, {required bool wantDir}) async {
    if (!await dir.exists()) return null;
    String? loose;
    try {
      await for (final e in dir.list(followLinks: false)) {
        final isDir = e is Directory;
        if (isDir != wantDir) continue;
        final name = _baseName(e.path);
        if (name == seg) return name;
        if (loose == null && fsSafeSegment(name) == seg) loose = name;
      }
    } catch (_) {}
    return loose;
  }

  Future<File> _localTargetFor(Directory root, String rel,
      {bool create = false}) async {
    final segs = fsSegs(rel);
    var cur = root;
    for (var i = 0; i < segs.length - 1; i++) {
      final hit = await _matchChild(cur, segs[i], wantDir: true);
      cur = Directory('${cur.path}${Platform.pathSeparator}${hit ?? segs[i]}');
      if (hit == null && create) await cur.create(recursive: true);
    }
    final name = await _matchChild(cur, segs.last, wantDir: false) ?? segs.last;
    return File('${cur.path}${Platform.pathSeparator}$name');
  }

  Future<FileSystemEntity?> resolveLocal(String rel) async {
    if (!hasSource) return null;
    final root = Directory(settings.localPath!);
    final segs = fsSegs(rel);
    if (segs.isEmpty) return root;
    var cur = root;
    for (var i = 0; i < segs.length - 1; i++) {
      final hit = await _matchChild(cur, segs[i], wantDir: true);
      if (hit == null) return null;
      cur = Directory('${cur.path}${Platform.pathSeparator}$hit');
    }
    final f = await _matchChild(cur, segs.last, wantDir: false);
    if (f != null) return File('${cur.path}${Platform.pathSeparator}$f');
    final d = await _matchChild(cur, segs.last, wantDir: true);
    if (d != null) return Directory('${cur.path}${Platform.pathSeparator}$d');
    return null;
  }

  Future<Directory?> _localDirAt(String rel, {bool create = false}) async {
    if (!hasSource) return null;
    var cur = Directory(settings.localPath!);
    for (final s in fsSegs(rel)) {
      final hit = await _matchChild(cur, s, wantDir: true);
      cur = Directory('${cur.path}${Platform.pathSeparator}${hit ?? s}');
      if (hit == null) {
        if (!create) return null;
        await cur.create(recursive: true);
      }
    }
    return cur;
  }

  Future<({bool ok, String message})?> localApply(
      String verb, Future<void> Function() fn) async {
    if (!twoWayActive) {
      if (settings.twoWay && !hasSource) {
        return (
          ok: true,
          message: '$verb applied on web only (no remembered folder to write back to).'
        );
      }
      return null;
    }
    _writingLocal = true;
    try {
      await fn();
      return (ok: true, message: '$verb also applied to your local folder.');
    } catch (e) {
      return (
        ok: false,
        message: '$verb on web ok, but local update failed: $e'
      );
    } finally {
      Timer(const Duration(milliseconds: 800), () {
        if (!running) _writingLocal = false;
      });
    }
  }

  Future<({bool ok, String message})?> applyMkdir(String sub, String name) =>
      localApply('New folder', () async {
        final parent = await _localDirAt(sub, create: true);
        await Directory('${parent!.path}${Platform.pathSeparator}$name')
            .create(recursive: true);
      });

  Future<({bool ok, String message})?> applyRename(String rel, String newName) =>
      localApply('Rename', () async {
        final e = await resolveLocal(rel);
        if (e == null) throw 'item not found locally';
        await e.rename('${e.parent.path}${Platform.pathSeparator}$newName');
      });

  Future<({bool ok, String message})?> applyMove(String from, String toDir) =>
      localApply('Move', () async {
        final e = await resolveLocal(from);
        if (e == null) throw 'item not found locally';
        final dest = await _localDirAt(toDir, create: true);
        await e.rename(
            '${dest!.path}${Platform.pathSeparator}${fsSegs(from).last}');
      });

  Future<({bool ok, String message})?> applyDelete(String rel) =>
      localApply('Delete', () async {
        final e = await resolveLocal(rel);
        if (e == null) throw 'item not found locally';
        await e.delete(recursive: true);
      });

  Future<String?> writeUploadedLocally(
      List<({String abs, String rel})> items) async {
    if (!twoWayActive) {
      if (settings.twoWay && !hasSource) {
        return 'Added on web only (no remembered folder to write back to).';
      }
      return null;
    }
    _writingLocal = true;
    var ok = 0;
    try {
      for (final it in items) {
        try {
          final segs = fsSegs(it.rel);
          final dir = await _localDirAt(
              segs.sublist(0, segs.length - 1).join('/'),
              create: true);
          await File(it.abs)
              .copy('${dir!.path}${Platform.pathSeparator}${segs.last}');
          ok++;
        } catch (_) {}
      }
    } finally {
      Timer(const Duration(milliseconds: 800), () {
        if (!running) _writingLocal = false;
      });
    }
    return ok > 0 ? '$ok file(s) also saved to your local folder.' : null;
  }

  Future<FsSyncResult> uploadItems({
    required int owner,
    required String sub,
    required List<FsBatchItem> items,
    void Function(String status, double progress)? onProgress,
  }) async {
    final fs = _fs;
    final r = FsSyncResult();
    if (fs == null) throw FolderSyncException('Not signed in.');
    if (items.isEmpty) {
      r.empty = true;
      return r;
    }
    ui(String s, double p) => onProgress?.call(s, p);
    ui('Checking what is already synced…', 0);
    Map<String, FsRemote> existing = {};
    if (!settings.force) {
      try {
        existing = await fs.manifest(owner);
      } catch (_) {}
    }
    final toUpload = <FsBatchItem>[];
    for (final it in items) {
      final ex = existing[fsJoin(sub, fsTargetRel(it.path, false))];
      if (ex != null && ex.size == it.size) {
        r.already++;
      } else {
        toUpload.add(it);
      }
    }
    final total = toUpload.length;
    var done = 0;
    var batch = <FsBatchItem>[];
    var bytes = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      ui('Syncing ${done + batch.length} of $total file(s)…',
          total == 0 ? 1 : done / total);
      try {
        final res = await fs.uploadBatch(owner, sub, false, batch);
        r.saved += res.saved;
        r.skipped += res.skipped;
        r.errors.addAll(res.errors);
      } catch (e) {
        r.errors.add('$e');
      }
      done += batch.length;
      batch = [];
      bytes = 0;
    }

    for (final it in toUpload.where((i) => i.size <= kFsBigFileBytes)) {
      if (batch.length >= kFsBatchSize ||
          (batch.isNotEmpty && bytes + it.size > kFsBatchBytes)) {
        await flush();
      }
      batch.add(it);
      bytes += it.size;
    }
    await flush();
    for (final it in toUpload.where((i) => i.size > kFsBigFileBytes)) {
      try {
        await fs.uploadChunked(owner, sub, false, it,
            onProgress: (f) => ui(
                'Syncing ${done + 1} of $total: ${fsSegs(it.path).last} — ${(f * 100).round()}%',
                total == 0 ? f : (done + f) / total));
        r.saved++;
      } catch (e) {
        r.errors.add('${it.path}: $e');
      }
      done++;
    }
    ui(r.summary(), 1);
    return r;
  }
}
