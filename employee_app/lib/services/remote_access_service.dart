import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
  ///
  /// Idempotent at two levels:
  /// 1. _prepared latches so a single Dart-VM lifetime never re-runs
  ///    the work.
  /// 2. If a RustDesk process is already running on the host (from a
  ///    previous employee-app session, an admin-installed system
  ///    RustDesk, or just the user leaving it open) we extract the
  ///    bundled binary path (so other helpers like getRustDeskId
  ///    still work) but skip the kill + reconfigure + relaunch.
  ///    The employee asked for "open once and leave it running" —
  ///    every employee-app open was previously killing RustDesk and
  ///    spawning a fresh window in the foreground, which was the
  ///    annoying part.
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    try {
      _bundledBinaryPath = await _extractBundled();
      if (await _rustDeskAlreadyRunning()) {
        debugPrint('[remote-access] RustDesk already running — '
            'skipping kill + reconfigure + relaunch.');
        // Existing RustDesk window may currently be in the foreground
        // (e.g. the user just clicked it). Fire the background
        // window-minimizer either way so reopening the employee app
        // never leaves RustDesk visually on top.
        unawaited(_minimizeRustDeskWindow());
        return;
      }
      // Stop any pre-existing RustDesk so it picks up our freshly
      // written config on next launch — RustDesk caches the TOML in
      // memory at startup and won't re-read it while running. Without
      // this, an old instance from a previous build keeps using the
      // public rs-ny.rustdesk.com server even after we point the TOML
      // at our private relay.
      await _killExistingRustDesk();
      await _configureRelay();
      // approve-mode='password,click' = both required: admin must
      // supply the matching password AND the employee must tap the
      // RustDesk Accept popup. Click alone isn't enough in this
      // RustDesk build — it still validates a password first. The
      // password lives in --dart-define=RUSTDESK_PERMANENT_PASSWORD
      // and the employee sets it once in RustDesk Settings → Security
      // → Permanent password. After that, every /remote works.
      await _setOptionInRustDeskToml('approve-mode', 'password-click');
      await launch();
    } catch (e) {
      debugPrint('[remote-access] prepare() failed: $e');
    }
  }

  /// Find RustDesk's main window via Win32 `FindWindow("RustDesk")`
  /// and minimize it to the taskbar so it stops covering the
  /// employee app. Polls up to 8s after the launch call returns
  /// (RustDesk's splash → main-window transition takes 1–3s on
  /// most boxes). Idempotent and forgiving — if the window can't
  /// be found in time, we just give up; the user can minimize
  /// manually. Detached so the employee-app process doesn't wait.
  ///
  /// SW_MINIMIZE (6) is preferred over SW_HIDE (0) because we want
  /// RustDesk's taskbar entry to stay visible — that's how the
  /// cashier finds it when an admin actually starts a remote
  /// session and they need to click Accept.
  Future<void> _minimizeRustDeskWindow() async {
    if (!Platform.isWindows) return;
    const psScript = r'''
Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  public class WUtil {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  }
"@
$deadline = (Get-Date).AddSeconds(8)
$titles = @("RustDesk", "RustDesk - ID")
while ((Get-Date) -lt $deadline) {
  foreach ($t in $titles) {
    $h = [WUtil]::FindWindow($null, $t)
    if ($h -ne [IntPtr]::Zero -and [WUtil]::IsWindowVisible($h)) {
      [WUtil]::ShowWindow($h, 6) | Out-Null  # SW_MINIMIZE
      exit 0
    }
  }
  Start-Sleep -Milliseconds 250
}
''';
    try {
      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy', 'Bypass',
          '-WindowStyle', 'Hidden',
          '-Command', psScript,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    } catch (e) {
      debugPrint('[remote-access] window-minimizer launch failed: $e');
    }
  }

  /// Cheap probe for whether a RustDesk process exists on this
  /// machine. Used by [prepare] to decide whether to leave an
  /// existing instance alone (the common case after the first
  /// employee-app launch of the day).
  Future<bool> _rustDeskAlreadyRunning() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
          'tasklist',
          ['/FI', 'IMAGENAME eq rustdesk.exe', '/NH', '/FO', 'CSV'],
          runInShell: false,
        ).timeout(const Duration(seconds: 4));
        final out = '${r.stdout}'.toLowerCase();
        return out.contains('rustdesk.exe');
      }
      if (Platform.isLinux || Platform.isMacOS) {
        final r = await Process.run(
          'pgrep',
          ['-x', 'rustdesk'],
          runInShell: false,
        ).timeout(const Duration(seconds: 4));
        return r.exitCode == 0;
      }
    } catch (_) {/* probe failed — assume not running */}
    return false;
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
  /// (minimized on Windows) and the admin's connection request will
  /// trigger RustDesk's own accept/deny prompt independently of this
  /// app. Returns true if the process was at least spawned.
  ///
  /// Windows: spawned via `cmd /c start /min` so RustDesk lands in
  /// the taskbar/tray without stealing focus from the POS. The
  /// employee already gets a clear UX signal via the chat header's
  /// "remote password" icon — we don't need RustDesk fighting for
  /// the foreground.
  Future<bool> launch() async {
    final binary = await _resolveBinary();
    if (binary == null) return false;
    try {
      if (Platform.isWindows) {
        // start.exe consumes its first quoted arg as a window title,
        // so we pass an empty "" before the binary path. `/min` is
        // mostly cosmetic for RustDesk specifically (it's a GUI
        // subsystem app that ShowWindow(SW_NORMAL)s on startup,
        // overriding the hint), so we follow up with the
        // _minimizeRustDeskWindow watcher which polls for the
        // RustDesk window and forces it to the taskbar.
        await Process.start(
          'cmd.exe',
          ['/c', 'start', '/min', '', binary],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
        unawaited(_minimizeRustDeskWindow());
        return true;
      }
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

  /// Hand back the ID + a permanent password derived from the
  /// machine's hardware fingerprint. Same machine always produces the
  /// same password (so the employee sets it in RustDesk Settings once
  /// and never has to update it), but every workstation has a
  /// different one — no shared secret across the deployment.
  Future<RemoteSessionConfig?> prepareForIncoming({
    Duration retryFor = const Duration(seconds: 10),
  }) async {
    // Make sure RustDesk is running (idempotent if already up).
    await launch();

    final id = await getRustDeskId(retryFor: retryFor);
    if (id == null || id.isEmpty) return null;
    final password = await derivePermanentPassword();
    return RemoteSessionConfig(id: id, password: password);
  }

  /// HMAC-SHA256(salt, machine-fingerprint) truncated to a 12-char
  /// alphanumeric password. The salt comes from the build via
  /// `--dart-define=RUSTDESK_PASSWORD_SALT=...` so the same hardware
  /// produces a different password under a different deployment
  /// (rotate by changing the salt and rebuilding). Cached after first
  /// call — fingerprint reads are not free.
  String? _cachedPassword;

  /// Returns the active permanent password the employee has agreed to
  /// use with admins. Resolution order:
  ///   1. user-chosen value saved via [setStoredPermanentPassword]
  ///   2. HMAC-SHA256(salt, machine-fingerprint) — the auto default
  /// Either way the same machine returns the same password every call.
  Future<String> derivePermanentPassword() async {
    if (_cachedPassword != null) return _cachedPassword!;

    final stored = await _readStoredPassword();
    if (stored != null && stored.isNotEmpty) {
      _cachedPassword = stored;
      return stored;
    }

    const salt = String.fromEnvironment(
      'RUSTDESK_PASSWORD_SALT',
      defaultValue: 'tinkerpro-remote-default-salt',
    );
    final fingerprint = await _machineFingerprint();
    final mac = Hmac(sha256, utf8.encode(salt));
    final digest = mac.convert(utf8.encode(fingerprint));

    // Base64URL of 9 bytes → 12 chars, all alphanumeric or - / _.
    // Strip the - and _ to keep it copy-friendly into RustDesk's GUI.
    final raw = base64Url.encode(digest.bytes.sublist(0, 9));
    _cachedPassword = raw.replaceAll(RegExp(r'[-_=]'), '0');
    return _cachedPassword!;
  }

  /// Whether the active password is one the employee picked manually
  /// (vs. the auto-derived fingerprint default). The UI uses this to
  /// label the "Edit" button correctly.
  Future<bool> hasUserChosenPassword() async {
    final stored = await _readStoredPassword();
    return stored != null && stored.isNotEmpty;
  }

  /// Save a user-chosen password and switch the active password to it.
  /// Empty/null clears the override (next derive() falls back to the
  /// fingerprint default). Trim and basic validation happen here so
  /// callers don't have to repeat them.
  Future<void> setStoredPermanentPassword(String? password) async {
    final f = await _passwordFile();
    final clean = (password ?? '').trim();
    if (clean.isEmpty) {
      if (await f.exists()) await f.delete();
      _cachedPassword = null;
      return;
    }
    await f.writeAsString(clean, flush: true);
    _cachedPassword = clean;
  }

  Future<String?> _readStoredPassword() async {
    try {
      final f = await _passwordFile();
      if (!await f.exists()) return null;
      final raw = (await f.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (e) {
      debugPrint('[remote-access] read stored password: $e');
      return null;
    }
  }

  Future<File> _passwordFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/remote-password.txt');
  }

  /// Read a stable per-machine identifier. Falls back through several
  /// sources so we always get *something* — never returns empty.
  Future<String> _machineFingerprint() async {
    if (Platform.isWindows) {
      // Windows machine GUID lives in the registry; reg.exe is the
      // most-portable way to read it without pulling in a Win32 plugin.
      try {
        final r = await Process.run(
          'reg',
          [
            'query',
            r'HKLM\SOFTWARE\Microsoft\Cryptography',
            '/v',
            'MachineGuid',
          ],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
        final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]{32,40})')
            .firstMatch('${r.stdout}');
        if (m != null) return 'win:${m.group(1)}';
      } catch (e) {
        debugPrint('[remote-access] reg query failed: $e');
      }
      // Fallback: BIOS serial via wmic.
      try {
        final r = await Process.run(
          'wmic',
          ['csproduct', 'get', 'uuid'],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
        final lines = '${r.stdout}'
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != 'UUID')
            .toList();
        if (lines.isNotEmpty) return 'wmi:${lines.first}';
      } catch (e) {
        debugPrint('[remote-access] wmic uuid failed: $e');
      }
    } else if (Platform.isLinux) {
      try {
        final id = await File('/etc/machine-id').readAsString();
        return 'linux:${id.trim()}';
      } catch (_) {/* try /var path next */}
      try {
        final id = await File('/var/lib/dbus/machine-id').readAsString();
        return 'linux:${id.trim()}';
      } catch (_) {/* fall through */}
    } else if (Platform.isMacOS) {
      try {
        final r = await Process.run(
          'ioreg',
          ['-rd1', '-c', 'IOPlatformExpertDevice'],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
        final m = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"')
            .firstMatch('${r.stdout}');
        if (m != null) return 'mac:${m.group(1)}';
      } catch (_) {/* fall through */}
    }
    // Last resort — never let derivation fail completely. Falls back
    // to a host-network fingerprint that's still stable across reboots
    // on the same machine.
    return 'host:${Platform.localHostname}';
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

/// Result of [RemoteAccessService.prepareForIncoming]. ID is the
/// RustDesk ID for admin to click. Password is the build-baked
/// permanent password the employee set once in RustDesk Settings.
class RemoteSessionConfig {
  RemoteSessionConfig({required this.id, this.password});
  final String id;
  final String? password;
}
