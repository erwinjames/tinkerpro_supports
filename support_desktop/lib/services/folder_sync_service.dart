import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import 'admin_files_service.dart';

const int kFsBatchSize = 15;
const int kFsBatchBytes = 70 * 1024 * 1024;
const int kFsBigFileBytes = 80 * 1024 * 1024;
const int kFsChunkBytes = 80 * 1024 * 1024;

String fsSafeSegment(String s) {
  final b = StringBuffer();
  for (final c in utf8.encode(s)) {
    final ok = (c >= 48 && c <= 57) ||
        (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        c == 46 ||
        c == 95 ||
        c == 45;
    b.writeCharCode(ok ? c : 95);
  }
  return b.toString();
}

List<String> fsSegs(String rel) => rel
    .replaceAll('\\', '/')
    .split('/')
    .where((s) => s.isNotEmpty && s != '.')
    .toList();

String fsTargetRel(String path, bool strip) {
  var segs = fsSegs(path);
  if (strip && segs.length > 1) segs = segs.sublist(1);
  return segs.map(fsSafeSegment).join('/');
}

String fsJoin(String a, String b) =>
    [a, b].where((s) => s.isNotEmpty).join('/');

String fsHumanSize(num b) {
  if (b <= 0) return '';
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class FolderSyncException implements Exception {
  FolderSyncException(this.message, {this.busy = false});
  final String message;
  final bool busy;
  @override
  String toString() => message;
}

class FsEntry {
  FsEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.mtime,
    required this.ext,
  });
  final String name;
  final bool isDir;
  final int size;
  final int mtime;
  final String ext;

  factory FsEntry.fromJson(Map<String, dynamic> j) {
    final name = '${j['name'] ?? ''}';
    final dot = name.lastIndexOf('.');
    return FsEntry(
      name: name,
      isDir: j['type'] == 'dir',
      size: _int(j['size']),
      mtime: _int(j['mtime']),
      ext: '${j['ext'] ?? (dot > 0 ? name.substring(dot + 1) : '')}'
          .toLowerCase(),
    );
  }
}

class FsWorkspace {
  const FsWorkspace(this.owner, this.name, this.role);
  final int owner;
  final String name;
  final String role;
}

class FsBrowseResult {
  FsBrowseResult({
    required this.exists,
    required this.entries,
    required this.canEdit,
    required this.owner,
  });
  final bool exists;
  final List<FsEntry> entries;
  final bool canEdit;
  final int owner;
}

class FsRemote {
  const FsRemote(this.size, this.mtime);
  final int size;
  final int mtime;
}

class FsMember {
  FsMember(this.userId, this.name, this.username);
  final int userId;
  final String name;
  final String username;
}

class FsPending {
  FsPending(this.token, this.link, this.invitedUserId, this.invitedTo);
  final String token;
  final String link;
  final int? invitedUserId;
  final String? invitedTo;
}

class FsUser {
  FsUser(this.id, this.name, this.username);
  final int id;
  final String name;
  final String username;
}

class FsBatchItem {
  const FsBatchItem(this.abs, this.path, this.size);
  final String abs;
  final String path;
  final int size;
}

class FolderSyncApi {
  FolderSyncApi(this.api);
  final ApiClient api;
  DateTime? _coolUntil;
  final _rand = Random();

  bool get coolingDown =>
      api.coolingDown ||
      (_coolUntil != null && DateTime.now().isBefore(_coolUntil!));

  Duration get coolDownLeft {
    final mine = _coolUntil == null
        ? Duration.zero
        : _coolUntil!.difference(DateTime.now());
    final theirs = api.coolDownLeft;
    final d = mine > theirs ? mine : theirs;
    return d.isNegative ? Duration.zero : d;
  }

  Uri _model(String script, [Map<String, String>? q]) =>
      Uri.parse('${api.baseUrl}/utils/models/$script')
          .replace(queryParameters: (q == null || q.isEmpty) ? null : q);

  Uri _action(String action) => Uri.parse('${api.baseUrl}/api.php')
      .replace(queryParameters: {'action': action});

  Map<String, String> get _headers => {
        ...api.authHeaders(),
        'Accept': 'application/json',
      };

  void _guard() {
    if (coolingDown) {
      throw FolderSyncException(
        'The server is busy. Retrying in ${max(1, coolDownLeft.inSeconds)}s.',
        busy: true,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode == 429 || r.statusCode == 503) {
      final wait =
          (int.tryParse(r.headers['retry-after'] ?? '') ?? 30).clamp(1, 3600);
      _coolUntil = DateTime.now().add(Duration(seconds: wait));
      throw FolderSyncException(
        'The server is busy. Retrying in ${wait}s.',
        busy: true,
      );
    }
    final t = r.body.trim();
    if (t.isNotEmpty) {
      try {
        final d = jsonDecode(t);
        if (d is Map<String, dynamic>) return d;
      } catch (_) {}
    }
    if (r.statusCode == 413) {
      throw FolderSyncException('Upload rejected as too large (HTTP 413).');
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw FolderSyncException(
          t.isNotEmpty && t.length < 200 ? t : 'Access denied.');
    }
    throw FolderSyncException(r.statusCode >= 400
        ? 'Server error (HTTP ${r.statusCode}).'
        : 'Unexpected server response.');
  }

  Map<String, dynamic> _need(Map<String, dynamic> d, String fallback) {
    if (d['success'] == true) return d;
    throw FolderSyncException(
        '${d['error'] ?? d['message'] ?? fallback}'.trim().isEmpty
            ? fallback
            : '${d['error'] ?? d['message'] ?? fallback}');
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    _guard();
    final r = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 60));
    return _decode(r);
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, String> body) async {
    _guard();
    final r = await http
        .post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 120));
    return _decode(r);
  }

  Future<Map<String, dynamic>> _multipart(
    Uri uri,
    Map<String, String> fields,
    List<http.MultipartFile> files, {
    Duration timeout = const Duration(minutes: 30),
  }) async {
    _guard();
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.addAll(files);
    final streamed = await req.send().timeout(timeout);
    final r = await http.Response.fromStream(streamed).timeout(timeout);
    return _decode(r);
  }

  Future<({int me, List<FsWorkspace> list})> workspaces() async {
    final d = _need(
      await _get(_model('folder-sync-share.php', {'action': 'workspaces'})),
      'Could not load workspaces.',
    );
    FsWorkspace ws(dynamic m) => FsWorkspace(
          _int((m as Map)['owner']),
          '${m['name'] ?? ''}',
          '${m['role'] ?? ''}',
        );
    return (
      me: _int(d['me']),
      list: [
        if (d['mine'] is Map) ws(d['mine']),
        if (d['shared'] is List) ...(d['shared'] as List).map(ws),
      ],
    );
  }

  Future<({List<FsMember> members, List<FsPending> pending})> members() async {
    final d = _need(
      await _get(_model('folder-sync-share.php', {'action': 'members'})),
      'Could not load contributors.',
    );
    return (
      members: [
        for (final m in (d['members'] as List? ?? const []))
          if (m is Map)
            FsMember(_int(m['user_id']), '${m['name'] ?? ''}',
                '${m['username'] ?? ''}'),
      ],
      pending: [
        for (final p in (d['pending'] as List? ?? const []))
          if (p is Map)
            FsPending(
              '${p['token'] ?? ''}',
              '${p['link'] ?? ''}',
              p['invited_user_id'] == null ? null : _int(p['invited_user_id']),
              p['invited_to']?.toString(),
            ),
      ],
    );
  }

  Future<List<FsUser>> searchUsers(String q) async {
    final d = _need(
      await _get(
          _model('folder-sync-share.php', {'action': 'users', 'q': q})),
      'Search failed.',
    );
    return [
      for (final u in (d['users'] as List? ?? const []))
        if (u is Map)
          FsUser(_int(u['id']), '${u['name'] ?? ''}', '${u['username'] ?? ''}'),
    ];
  }

  Future<String> inviteLink() async {
    final d = _need(
      await _post(
          _model('folder-sync-share.php', {'action': 'invite_link'}), {}),
      'Could not create link.',
    );
    return '${d['link'] ?? ''}';
  }

  Future<bool> inviteChat(int userId) async {
    final d = _need(
      await _post(_model('folder-sync-share.php', {'action': 'invite_chat'}),
          {'user_id': '$userId'}),
      'Invite failed.',
    );
    return d['chat_sent'] == true;
  }

  Future<({int owner, String name})> accept(String token) async {
    final d = _need(
      await _get(_model(
          'folder-sync-share.php', {'action': 'accept', 'token': token})),
      'Invite could not be accepted.',
    );
    return (owner: _int(d['owner']), name: '${d['name'] ?? 'a folder'}');
  }

  Future<void> removeMember(int userId) async {
    _need(
      await _post(_model('folder-sync-share.php', {'action': 'remove'}),
          {'user_id': '$userId'}),
      'Remove failed.',
    );
  }

  Future<FsBrowseResult> browse(int owner, String sub) async {
    final d = _need(
      await _get(_model(
          'folder-sync-browse.php', {'owner': '$owner', 'sub': sub})),
      'Could not load folder.',
    );
    return FsBrowseResult(
      exists: d['exists'] == true,
      entries: [
        for (final e in (d['entries'] as List? ?? const []))
          if (e is Map) FsEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
      canEdit: d['canEdit'] == true,
      owner: _int(d['owner']),
    );
  }

  Future<Map<String, FsRemote>> manifest(int owner) async {
    final d = _need(
      await _get(_model('folder-sync-manifest.php', {'owner': '$owner'})),
      'Could not read the synced file list.',
    );
    final out = <String, FsRemote>{};
    final files = d['files'];
    if (files is Map) {
      files.forEach((k, v) {
        if (v is Map) out['$k'] = FsRemote(_int(v['size']), _int(v['mtime']));
      });
    }
    return out;
  }

  Future<String> mkdir(int owner, String sub, String name) async {
    final d = _need(
      await _post(_model('folder-sync-mkdir.php'),
          {'owner': '$owner', 'sub': sub, 'name': name}),
      'Could not create folder.',
    );
    return '${d['name'] ?? name}';
  }

  Future<String> rename(int owner, String path, String newName) async {
    final d = _need(
      await _post(_model('folder-sync-rename.php'),
          {'owner': '$owner', 'path': path, 'new_name': newName}),
      'Rename failed.',
    );
    return '${d['name'] ?? newName}';
  }

  Future<({bool moved, String name})> move(
      int owner, String from, String to) async {
    final d = _need(
      await _post(_model('folder-sync-move.php'),
          {'owner': '$owner', 'from': from, 'to': to}),
      'Move failed.',
    );
    return (moved: d['moved'] == true, name: '${d['name'] ?? ''}');
  }

  Future<void> delete(int owner, String path) async {
    _need(
      await _post(_model('folder-sync-delete.php'),
          {'owner': '$owner', 'path': path}),
      'Delete failed.',
    );
  }

  Future<int> prune(int owner, List<String> keep) async {
    final d = _need(
      await _post(_model('folder-sync-prune.php'),
          {'owner': '$owner', 'keep_json': jsonEncode(keep)}),
      'Prune failed.',
    );
    return _int(d['deletedCount']);
  }

  Future<String> sendEmail(int owner, String path,
      {required String to, String subject = '', String message = ''}) async {
    final d = _need(
      await _post(_model('folder-sync-send-email.php'), {
        'owner': '$owner',
        'path': path,
        'to': to,
        'subject': subject,
        'message': message,
      }),
      'Email failed.',
    );
    return '${d['message'] ?? 'Email sent.'}';
  }

  Future<({int saved, int skipped, List<String> errors})> uploadBatch(
    int owner,
    String sub,
    bool strip,
    List<FsBatchItem> items,
  ) async {
    final fields = <String, String>{
      'owner': '$owner',
      'sub': sub,
      'strip_top': strip ? '1' : '0',
    };
    final files = <http.MultipartFile>[];
    for (var i = 0; i < items.length; i++) {
      fields['paths[$i]'] = items[i].path;
      final name = fsSegs(items[i].path).last;
      files.add(await http.MultipartFile.fromPath('files[]', items[i].abs,
          filename: name));
    }
    final d = _need(
      await _multipart(_model('folder-sync-upload.php'), fields, files),
      'Upload failed.',
    );
    return (
      saved: _int(d['saved']),
      skipped: _int(d['skipped']),
      errors: [for (final e in (d['errors'] as List? ?? const [])) '$e'],
    );
  }

  Future<void> uploadChunked(
    int owner,
    String sub,
    bool strip,
    FsBatchItem item, {
    void Function(double fraction)? onProgress,
  }) async {
    final total = max(1, (item.size / kFsChunkBytes).ceil());
    final uploadId =
        'u$owner-${DateTime.now().millisecondsSinceEpoch}-${_rand.nextInt(1 << 32).toRadixString(36)}';
    final file = File(item.abs);
    for (var i = 0; i < total; i++) {
      final start = i * kFsChunkBytes;
      final end = min(item.size, (i + 1) * kFsChunkBytes);
      final part = http.MultipartFile(
        'chunk',
        file.openRead(start, end),
        end - start,
        filename: 'chunk',
      );
      Map<String, dynamic> d;
      try {
        d = await _multipart(
          _model('folder-sync-upload-chunk.php'),
          {
            'owner': '$owner',
            'sub': sub,
            'path': item.path,
            'strip_top': strip ? '1' : '0',
            'upload_id': uploadId,
            'chunk_index': '$i',
            'total_chunks': '$total',
          },
          [part],
        );
      } on FolderSyncException catch (e) {
        throw FolderSyncException('chunk ${i + 1} failed: ${e.message}',
            busy: e.busy);
      }
      _need(d, 'chunk failed');
      onProgress?.call((i + 1) / total);
    }
  }

  Uri viewUri(int owner, String path, {bool download = false}) =>
      _model('folder-sync-view.php', {
        'owner': '$owner',
        'path': path,
        if (download) 'dl': '1',
      });

  Future<void> downloadTo(int owner, String path, File target,
      {void Function(int received, int total)? onProgress}) async {
    _guard();
    final client = http.Client();
    try {
      final req = http.Request('GET', viewUri(owner, path, download: true))
        ..headers.addAll(api.authHeaders());
      final res = await client.send(req).timeout(const Duration(minutes: 2));
      if (res.statusCode == 429 || res.statusCode == 503) {
        final wait = (int.tryParse(res.headers['retry-after'] ?? '') ?? 30)
            .clamp(1, 3600);
        _coolUntil = DateTime.now().add(Duration(seconds: wait));
        throw FolderSyncException('The server is busy. Retrying in ${wait}s.',
            busy: true);
      }
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw FolderSyncException(body.trim().isNotEmpty && body.length < 200
            ? body.trim()
            : 'Download failed (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength ?? 0;
      await target.parent.create(recursive: true);
      final sink = target.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<List<int>> fetchBytes(int owner, String path) async {
    _guard();
    final r = await http
        .get(viewUri(owner, path), headers: api.authHeaders())
        .timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) {
      throw FolderSyncException(r.body.trim().isNotEmpty && r.body.length < 200
          ? r.body.trim()
          : 'Could not load file (HTTP ${r.statusCode}).');
    }
    return r.bodyBytes;
  }

  Future<File> downloadToTemp(int owner, String path, String name) async {
    final base = await getTemporaryDirectory();
    final dir = Directory(
        '${base.path}${Platform.pathSeparator}tp_folder_sync${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}');
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await downloadTo(owner, path, f);
    return f;
  }

  Future<List<FsUser>> chatDirectory(String q) async {
    final d = _need(
      await _get(Uri.parse('${api.baseUrl}/api.php')
          .replace(queryParameters: {'action': 'chat.directory', 'search': q})),
      'Search failed.',
    );
    return [
      for (final u in (d['users'] as List? ?? const []))
        if (u is Map)
          FsUser(
            _int(u['id']),
            '${u['full_name'] ?? ''}'.trim().isNotEmpty
                ? '${u['full_name']}'
                : '${u['username'] ?? ''}',
            '${u['username'] ?? ''}',
          ),
    ];
  }

  Future<void> sendFileToChat({
    required int owner,
    required String path,
    required int peerUserId,
    String message = '',
  }) async {
    final conv = _need(
      await _post(_action('chat.createDirect'), {'peer_user_id': '$peerUserId'}),
      'Could not open chat.',
    );
    final convId = _int(conv['conversation_id']);
    if (convId <= 0) throw FolderSyncException('Could not open chat.');
    final up = await _post(_action('chat.attachFromSync'), {
      'conversation_id': '$convId',
      'owner': '$owner',
      'path': path,
    });
    final att = up['attachment'];
    if (up['success'] != true || att is! Map) {
      throw FolderSyncException('${up['message'] ?? up['error'] ?? 'Attach failed (file type may not be allowed).'}');
    }
    final attId = _int(att['id']);
    _need(
      await _post(_action('chat.send'), {
        'conversation_id': '$convId',
        'body': message.trim(),
        'client_nonce': 'fsfile$convId-$attId',
        'attachment_ids[]': '$attId',
      }),
      'Send failed.',
    );
  }

  Future<void> sendToFilesManagement({
    required int owner,
    required String path,
    required String fileName,
    required String collectionName,
  }) async {
    final tmp = await downloadToTemp(owner, path, fileName);
    try {
      final job = FmChunkedUpload(
        AdminFilesApi(api),
        FmUploadMeta(
          name: collectionName,
          email: '',
          collectionType: 'default',
        ),
      );
      Map<String, dynamic> res;
      try {
        res = await job.run([FmPickedFile(tmp.path, fileName, await tmp.length())]);
      } catch (e) {
        throw FolderSyncException(job.errorMessage(e));
      }
      if (res['success'] != true) {
        throw FolderSyncException('${res['message'] ?? 'Upload failed.'}');
      }
    } finally {
      try {
        await tmp.parent.delete(recursive: true);
      } catch (_) {}
    }
  }
}
