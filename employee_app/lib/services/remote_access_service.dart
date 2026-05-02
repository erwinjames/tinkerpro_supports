import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Thin wrapper around the locally-available RustDesk client.
///
/// RustDesk is a free, open-source remote-desktop suite. The
/// employee_app ships the platform-appropriate **portable** RustDesk
/// binary as a Flutter asset (Linux AppImage, Windows .exe). On first
/// launch [prepare] extracts it from the read-only Flutter asset bundle
/// into a writable per-user directory and (on Linux/macOS) marks it
/// executable. From then on, [launch] runs that bundled copy — no
/// separate "install RustDesk" step for the employee.
///
/// If a system-wide RustDesk is on PATH (e.g., the user already
/// installed it via package manager), we prefer that — it gets OS
/// integration like `rustdesk://` URL scheme registration. The bundled
/// copy is the always-available fallback.
///
/// We deliberately do NOT pipe RustDesk's incoming-connection prompt
/// through the Flutter UI. Two prompts (employee_app's "Allow remote
/// access" + RustDesk's own "Accept connection") is RustDesk's security
/// model. Bypassing the second one would mean a single compromised
/// chat session can take over the machine.
class RemoteAccessService {
  RemoteAccessService._();
  static final instance = RemoteAccessService._();

  /// Set once after first successful [prepare]. Subsequent calls are
  /// no-ops so we don't re-extract the 80 MB AppImage every launch.
  String? _bundledBinaryPath;
  bool _prepared = false;

  /// Idempotent. Call once at app startup (after the user has gotten
  /// past the store-setup screen). Extracts the bundled binary out of
  /// `assets/rustdesk/...` into a writable runtime location and marks
  /// it executable. Cheap on subsequent calls.
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    try {
      _bundledBinaryPath = await _extractBundled();
      // Stop any pre-existing RustDesk so it picks up our freshly
      // written config on next launch — RustDesk caches the TOML in
      // memory at startup and won't re-read it while running. Without
      // this, an old instance from a previous build keeps using the
      // public rs-ny.rustdesk.com server even after we point the TOML
      // at our private relay.
      await _killExistingRustDesk();
      await _configureRelay();
      // approve-mode='click' so RustDesk pops up an Accept prompt on
      // the employee's screen for incoming connections. Yes, that's
      // a second tap on top of the chat /remote Allow — but it's the
      // only auth path that's actually reliable on Windows portable.
      // `--password` for the permanent password runs over IPC and
      // silently no-ops on Windows portable, leaving RustDesk.toml's
      // password = '' even after we set it. With click mode, password
      // is moot — the employee's tap is what authorizes.
      await _setOptionInRustDeskToml('approve-mode', 'click');
      await launch();
    } catch (e) {
      debugPrint('[remote-access] prepare() failed: $e');
    }
  }

  Future<void> _killExistingRustDesk() async {
    try {
      if (Platform.isWindows) {
        await Process.run(
          'taskkill',
          ['/F', '/IM', 'rustdesk.exe', '/T'],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
      } else if (Platform.isLinux || Platform.isMacOS) {
        await Process.run(
          'pkill',
          ['-x', 'rustdesk'],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {/* nothing to kill — fine */}
  }

  /// If the build supplied a self-hosted RustDesk relay via
  /// `--dart-define=RUSTDESK_RELAY_HOST=...` (and optionally
  /// `RUSTDESK_RELAY_KEY=...`), pre-write those into RustDesk2.toml so
  /// the bundled RustDesk skips the public rendezvous (rs-ny.rustdesk.com)
  /// and registers with our relay instead. Idempotent — `_setTopLevel`
  /// and `_setOptionInRustDeskToml` both replace existing values rather
  /// than duplicating them.
  Future<void> _configureRelay() async {
    const host = String.fromEnvironment('RUSTDESK_RELAY_HOST');
    const key = String.fromEnvironment('RUSTDESK_RELAY_KEY');
    if (host.isEmpty) return; // build wasn't pinned to a private relay

    final tomlPath = _rustDeskTomlPath();
    if (tomlPath == null) return;
    final f = File(tomlPath);
    if (!await f.parent.exists()) {
      await f.parent.create(recursive: true);
    }

    await _setTopLevelInRustDeskToml('rendezvous_server', '$host:21116');
    await _setOptionInRustDeskToml('custom-rendezvous-server', host);
    await _setOptionInRustDeskToml('relay-server', host);
    if (key.isNotEmpty) {
      await _setOptionInRustDeskToml('key', key);
    }
    // Disable RustDesk's public API server so it doesn't try to phone
    // home for updates / address-book sync.
    await _setOptionInRustDeskToml('api-server', '');
  }

  /// Like `_setOptionInRustDeskToml` but for top-level keys (the ones
  /// that live above the first `[section]` header — e.g.
  /// `rendezvous_server = '...'`).
  Future<void> _setTopLevelInRustDeskToml(String key, String value) async {
    final tomlPath = _rustDeskTomlPath();
    if (tomlPath == null) return;
    try {
      final f = File(tomlPath);
      var contents = await f.exists() ? await f.readAsString() : '';

      final sectionMatch =
          RegExp(r'^\s*\[', multiLine: true).firstMatch(contents);
      final sectionIdx = sectionMatch?.start ?? contents.length;

      final keyRe = RegExp(
        '^\\s*${RegExp.escape(key)}\\s*=.*\$',
        multiLine: true,
      );
      final newLine = "$key = '$value'";
      final existing = keyRe.firstMatch(contents);

      if (existing != null && existing.start < sectionIdx) {
        contents = contents.replaceFirst(keyRe, newLine);
      } else {
        final before = contents.substring(0, sectionIdx);
        final after = contents.substring(sectionIdx);
        final sep = before.isEmpty || before.endsWith('\n') ? '' : '\n';
        contents = '$before$sep$newLine\n$after';
      }
      await f.writeAsString(contents, flush: true);
    } catch (e) {
      debugPrint('[remote-access] _setTopLevelInRustDeskToml($key): $e');
    }
  }

  /// Resolved plaintext RustDesk ID (the 6-12 digit one shown in the
  /// RustDesk GUI). Returns null if RustDesk isn't available, hasn't
  /// finished initializing, or somehow doesn't expose `--get-id`.
  ///
  /// Implementation: shells out to `rustdesk --get-id`. The on-disk
  /// config TOML doesn't store the plaintext ID anywhere — only
  /// `enc_id`, which is XChaCha20-encrypted with a hardware-derived
  /// key. Parsing it externally is impractical; the CLI flag is the
  /// supported path.
  Future<String?> getRustDeskId({Duration retryFor = Duration.zero}) async {
    final deadline = DateTime.now().add(retryFor);
    while (true) {
      final id = await _readIdViaCli();
      if (id != null && id.isNotEmpty) return id;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future.delayed(const Duration(milliseconds: 800));
    }
  }

  Future<String?> _readIdViaCli() async {
    final binary = await _resolveBinary();
    if (binary == null) return null;
    try {
      final result = await Process.run(
        binary,
        ['--get-id'],
        runInShell: false,
      ).timeout(const Duration(seconds: 6));
      // RustDesk prints the ID to stdout but also emits some
      // gtk/flutter init noise on stderr — and on first run the ID
      // line is interleaved with FFI logs on stdout. Extract the
      // first standalone digit run of 6–12 chars (the ID range
      // RustDesk allocates).
      final out = '${result.stdout}\n${result.stderr}';
      final m = RegExp(r'(?<![\d.-])(\d{6,12})(?![\d.-])').firstMatch(out);
      return m?.group(1);
    } catch (e) {
      debugPrint('[remote-access] --get-id failed: $e');
      return null;
    }
  }

  /// Launch the RustDesk client. Best-effort — we can't reliably wait
  /// for it to be "ready"; the user will see RustDesk's window open
  /// and the admin's connection request will trigger RustDesk's own
  /// accept/deny prompt independently of this app. Returns true if
  /// the process was at least spawned.
  Future<bool> launch() async {
    final binary = await _resolveBinary();
    if (binary == null) return false;
    try {
      // Detached so the RustDesk window outlives a brief Flutter
      // foreground/background transition.
      await Process.start(
        binary,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } catch (e) {
      debugPrint('[remote-access] launch($binary) failed: $e');
      return false;
    }
  }

  /// Hand back the RustDesk ID admin needs to click. Authorization
  /// happens via RustDesk's own Accept popup on the employee's screen
  /// (we set approve-mode='click' during prepare()) — no password
  /// handoff through chat is needed.
  Future<RemoteSessionConfig?> prepareForIncoming({
    Duration retryFor = const Duration(seconds: 10),
  }) async {
    // Make sure RustDesk is running (idempotent if already up).
    await launch();

    final id = await getRustDeskId(retryFor: retryFor);
    if (id == null || id.isEmpty) return null;
    return RemoteSessionConfig(id: id);
  }

  // Kept for any future "share a one-shot temp password" flow — not
  // currently called.
  // ignore: unused_element
  String _randomPassword(int length) {
    // No I/O, l, 0, O — confusable in some fonts when a user reads
    // the password aloud over the chat handoff.
    const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  /// Idempotent edit of `~/.config/rustdesk/RustDesk2.toml` (or the
  /// platform equivalent): inserts/replaces `<key> = '<value>'` inside
  /// the `[options]` table. We avoid pulling in a TOML parser because
  /// RustDesk's config is a shallow file we only ever touch one line
  /// of — string substitution is safer than a half-implemented parser.
  Future<void> _setOptionInRustDeskToml(String key, String value) async {
    final tomlPath = _rustDeskTomlPath();
    if (tomlPath == null) return;
    try {
      final f = File(tomlPath);
      var contents = await f.exists() ? await f.readAsString() : '';

      final keyRe = RegExp(
        '^\\s*${RegExp.escape(key)}\\s*=.*\$',
        multiLine: true,
      );
      final newLine = "$key = '$value'";

      if (keyRe.hasMatch(contents)) {
        contents = contents.replaceFirst(keyRe, newLine);
      } else if (contents.contains('[options]')) {
        contents = contents.replaceFirst(
          '[options]',
          '[options]\n$newLine',
        );
      } else {
        if (contents.isNotEmpty && !contents.endsWith('\n')) {
          contents += '\n';
        }
        contents += '\n[options]\n$newLine\n';
      }
      await f.writeAsString(contents, flush: true);
    } catch (e) {
      debugPrint('[remote-access] _setOptionInRustDeskToml($key): $e');
    }
  }

  String? _rustDeskTomlPath() {
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home == null) return null;
      return '$home/.config/rustdesk/RustDesk2.toml';
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return null;
      return '$appData\\RustDesk\\config\\RustDesk2.toml';
    }
    return null;
  }

  /// Used by the chat screen's friendly fallback message — true when
  /// either a system-installed RustDesk is on PATH OR the bundled
  /// portable copy was successfully extracted.
  Future<bool> isAvailable() async {
    if (await _systemBinary() != null) return true;
    return _bundledBinaryPath != null;
  }

  // ── internals ───────────────────────────────────────────────────────

  /// Resolution order: system PATH first (better OS integration), then
  /// the bundled portable copy. Cached after first hit on PATH so we
  /// don't `which` on every launch.
  String? _cachedSystem;
  bool _systemChecked = false;

  Future<String?> _resolveBinary() async {
    final sys = await _systemBinary();
    if (sys != null) return sys;
    return _bundledBinaryPath;
  }

  Future<String?> _systemBinary() async {
    if (_systemChecked) return _cachedSystem;
    _systemChecked = true;
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final r =
            await Process.run('which', ['rustdesk'], runInShell: false);
        if (r.exitCode == 0) {
          _cachedSystem = (r.stdout as String).trim();
        }
      } else if (Platform.isWindows) {
        final r =
            await Process.run('where', ['rustdesk.exe'], runInShell: false);
        if (r.exitCode == 0) {
          _cachedSystem = (r.stdout as String).split('\n').first.trim();
        }
      }
    } catch (_) {/* fall through */}
    return _cachedSystem;
  }

  /// Copy the platform-appropriate RustDesk binary from
  /// `data/flutter_assets/assets/rustdesk/...` to the app's writable
  /// support directory. Returns the absolute path to the extracted
  /// binary, or null if the platform isn't supported.
  ///
  /// Idempotent on the file system: re-extracts only if the asset is
  /// newer (compared by size — Flutter doesn't expose mtime here).
  Future<String?> _extractBundled() async {
    final assetName = _bundledAssetName();
    if (assetName == null) return null; // unsupported platform

    final supportDir = await getApplicationSupportDirectory();
    final rustdeskDir = Directory('${supportDir.path}/rustdesk');
    if (!await rustdeskDir.exists()) {
      await rustdeskDir.create(recursive: true);
    }
    final outPath = '${rustdeskDir.path}/${_runtimeBinaryName()}';
    final outFile = File(outPath);

    final assetData = await rootBundle.load('assets/rustdesk/$assetName');
    final assetBytes = assetData.buffer.asUint8List(
      assetData.offsetInBytes,
      assetData.lengthInBytes,
    );

    // Re-extract if missing OR size differs (handles app upgrades that
    // ship a newer RustDesk).
    final needsWrite = !await outFile.exists() ||
        (await outFile.length()) != assetBytes.length;
    if (needsWrite) {
      await outFile.writeAsBytes(assetBytes, flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['+x', outPath], runInShell: false);
      }
      debugPrint(
          '[remote-access] extracted bundled RustDesk to $outPath '
          '(${assetBytes.length} bytes)');
    }
    return outPath;
  }

  String? _bundledAssetName() {
    if (Platform.isLinux) return 'rustdesk-linux-x86_64.AppImage';
    if (Platform.isWindows) return 'rustdesk-windows-x86_64.exe';
    return null; // macOS / Android: bundled binary not shipped (yet)
  }

  String _runtimeBinaryName() {
    if (Platform.isWindows) return 'rustdesk.exe';
    return 'rustdesk-portable'; // .AppImage extension stripped — chmod +x is what matters
  }
}

/// Result of [RemoteAccessService.prepareForIncoming]. In click mode
/// the admin only needs the ID — RustDesk asks the employee to accept
/// the inbound connection on their own screen.
class RemoteSessionConfig {
  RemoteSessionConfig({required this.id});
  final String id;
}
