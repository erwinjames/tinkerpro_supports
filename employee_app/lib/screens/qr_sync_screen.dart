import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api_client.dart';
import '../services/chat_service.dart';
import '../services/session_store.dart';
import '../services/sync_payload.dart';
import '../theme.dart';

/// First-launch screen on the mobile APK. The phone has no store identity
/// and no idea which TinkerPro server to talk to, so it scans the sync QR
/// shown by the already-configured desktop employee app
/// (SyncMobileScreen). The QR carries the server URL + store name; we adopt
/// them, run `chat.employeeStart`, and hand a ready ApiClient + chat info
/// back up to the bootstrap shell.
///
/// Scanning uses flutter_zxing (native ZXing) rather than mobile_scanner:
/// mobile_scanner relies on Google ML Kit, which threw a hard null-pointer
/// crash inside its own barcode engine on some MIUI/Xiaomi devices (both the
/// bundled and Play Services models). ZXing has no Google/ML Kit dependency
/// and decodes the QR itself, so it works where ML Kit doesn't.
///
/// A manual fallback (type the server URL + store name) is kept for any
/// device whose camera is otherwise unavailable.
class QrSyncScreen extends StatefulWidget {
  const QrSyncScreen({
    super.key,
    required this.store,
    required this.onSynced,
  });

  final SessionStore store;

  /// Called once we've saved the scanned config AND resolved a chat
  /// session against it. The shell adopts [api] (re-based on the scanned
  /// server URL) and swaps to the chat screen.
  final void Function(ApiClient api, EmployeeChatInfo info) onSynced;

  @override
  State<QrSyncScreen> createState() => _QrSyncScreenState();
}

class _QrSyncScreenState extends State<QrSyncScreen> with WidgetsBindingObserver {
  bool _handling = false;
  bool _checking = true;
  bool _denied = false;
  bool _permanentlyDenied = false;
  bool _manual = false;
  String? _error;

  final _urlCtrl = TextEditingController();
  final _storeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlCtrl.dispose();
    _storeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _denied && !_manual) {
      _init();
    }
  }

  Future<void> _init() async {
    if (mounted) setState(() => _checking = true);
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      setState(() {
        _denied = false;
        _permanentlyDenied = false;
        _checking = false;
      });
    } else {
      setState(() {
        _denied = true;
        _permanentlyDenied = status.isPermanentlyDenied;
        _checking = false;
      });
    }
  }

  void _switchToManual() {
    _urlCtrl.text = widget.store.serverBaseUrl ?? '';
    setState(() {
      _manual = true;
      _error = null;
    });
  }

  void _switchToCamera() {
    setState(() {
      _manual = false;
      _error = null;
    });
    _init();
  }

  Future<void> _submitManual() async {
    final url = _urlCtrl.text.trim();
    final store = _storeCtrl.text.trim();
    if (url.isEmpty || store.isEmpty) {
      setState(() => _error = 'Enter both the server URL and the store name.');
      return;
    }
    await _adopt(SyncPayload(baseUrl: url, storeName: store));
  }

  void _onCode(Code code) {
    if (_handling) return;
    final raw = code.text;
    if (raw == null || raw.isEmpty || !code.isValid) return;
    final payload = SyncPayload.tryDecode(raw);
    if (payload == null) return; // not our QR — keep scanning
    _adopt(payload);
  }

  Future<void> _adopt(SyncPayload payload) async {
    setState(() {
      _handling = true;
      _error = null;
    });
    try {
      final api = await ApiClient.create(overrideBaseUrl: payload.baseUrl);
      final chat = ChatService(api);
      final info = await chat.employeeStart(payload.storeName);
      if (info == null) {
        _fail('Couldn\'t reach the support server. Check the URL and that the '
            'phone is online, then try again.');
        return;
      }
      await widget.store.saveServerBaseUrl(payload.baseUrl);
      await widget.store.saveStoreName(payload.storeName);
      await widget.store.saveHelpBaseUrl(
          payload.helpBaseUrl.isEmpty ? null : payload.helpBaseUrl);
      if (payload.tinkerChatApiKey.isNotEmpty) {
        await widget.store.setTinkerChatApiKey(payload.tinkerChatApiKey);
      }
      if (payload.hasSoketi) {
        await widget.store.saveWsConfig(
          host: payload.soketiHost,
          port: payload.soketiPort,
          key: payload.soketiKey,
          tls: payload.soketiTls,
          path: payload.soketiPath,
        );
      }
      await widget.store.saveIdentity(
        userId: info.meId,
        convId: info.conversationId,
      );
      if (!mounted) return;
      widget.onSynced(api, info);
    } catch (_) {
      _fail('Something went wrong while syncing. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _handling = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Brand.signal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        color: Brand.canvas, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text('Sync with desktop',
                      textAlign: TextAlign.center, style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    _manual
                        ? 'On the desktop "Sync mobile" screen, read the server '
                            'URL and store name shown under the QR and type them here.'
                        : 'On the desktop employee app, open "Sync mobile" and point '
                            'this phone\'s camera at the QR code to sign in.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _manual
                    ? _buildManualForm(text)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _buildCameraBody(text),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextButton.icon(
                    onPressed: _handling
                        ? null
                        : (_manual ? _switchToCamera : _switchToManual),
                    icon: Icon(_manual ? Icons.qr_code_scanner : Icons.keyboard),
                    label: Text(_manual ? 'Scan QR instead' : 'Enter manually'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera (ZXing) ─────────────────────────────────────────────────────
  Widget _buildCameraBody(TextTheme text) {
    if (_checking) {
      return Container(
        color: Brand.canvas,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16),
            Text('Starting camera…'),
          ],
        ),
      );
    }
    if (_denied) return _buildPermissionDenied(text);
    return Stack(
      fit: StackFit.expand,
      children: [
        ReaderWidget(
          onScan: _onCode,
          codeFormat: Format.qrCode,
          tryHarder: true,
          tryInverted: true,
          tryRotate: true,
          showFlashlight: false,
          showToggleCamera: false,
          showGallery: false,
          // Disable the built-in overlay (it renders small/misaligned inside
          // a constrained, rounded container) and draw our own frame below.
          showScannerOverlay: false,
          // Scan almost the whole frame instead of just the centre 50%, so a
          // QR anywhere in view is picked up.
          cropPercent: 0.9,
          scanDelay: const Duration(milliseconds: 400),
          loading: Container(
            color: Brand.canvas,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        // Our own centred viewfinder frame.
        IgnorePointer(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.biggest.shortestSide * 0.7;
                return Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    border: Border.all(color: Brand.canvas, width: 3),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (_handling)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2, color: Brand.canvas),
                SizedBox(height: 16),
                Text('Signing in…', style: TextStyle(color: Brand.canvas)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionDenied(TextTheme text) {
    return Container(
      color: Brand.canvas,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 48, color: Brand.textMuted),
            const SizedBox(height: 16),
            Text('Camera access is needed to scan the sync QR.',
                textAlign: TextAlign.center, style: text.bodyMedium),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                if (_permanentlyDenied) {
                  await openAppSettings();
                } else {
                  await _init();
                }
              },
              icon: const Icon(Icons.lock_open),
              label: Text(_permanentlyDenied
                  ? 'Open app settings'
                  : 'Allow camera access'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Manual entry ───────────────────────────────────────────────────────
  Widget _buildManualForm(TextTheme text) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            enabled: !_handling,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://tinkerpro.example.com/tinkerpro_support',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _storeCtrl,
            enabled: !_handling,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitManual(),
            decoration: const InputDecoration(
              labelText: 'Store name',
              hintText: 'Exactly as set on the desktop',
              prefixIcon: Icon(Icons.storefront),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _handling ? null : _submitManual,
              child: _handling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.canvas),
                    )
                  : const Text('Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}
