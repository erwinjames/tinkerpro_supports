import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api_client.dart';
import '../services/chat_realtime.dart';
import '../services/session_store.dart';
import '../services/sync_payload.dart';
import '../theme.dart';

/// Desktop-only screen that renders a sync QR for the mobile APK to scan.
///
/// The desktop employee app already knows its server URL ([ApiClient.baseUrl])
/// and store identity ([SessionStore.storeName]); it packs both (plus the
/// Help Center origin and any tinker-chat key) into a [SyncPayload] and shows
/// it as a QR. A phone running the employee APK scans it on first launch
/// (QrSyncScreen) to sign in as the same store.
class SyncMobileScreen extends StatelessWidget {
  const SyncMobileScreen({
    super.key,
    required this.api,
    required this.store,
  });

  final ApiClient api;
  final SessionStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final storeName = (store.storeName ?? '').trim();
    // Resolve the realtime endpoint this (working) desktop uses and ship it
    // in the QR so the phone connects to the same Soketi instead of the
    // wrong compile-time default port.
    final rt = ChatRealtimeConfig.fromBaseUrl(api.baseUrl);
    final payload = SyncPayload(
      baseUrl: api.baseUrl,
      storeName: storeName,
      helpBaseUrl: kHelpBaseUrl,
      tinkerChatApiKey: store.tinkerChatApiKey ?? '',
      soketiHost: rt.host,
      soketiPort: rt.port,
      soketiKey: rt.apiKey,
      soketiTls: rt.useTls,
      soketiPath: rt.path,
    );

    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        title: const Text('Sync mobile'),
        backgroundColor: Brand.surface,
        foregroundColor: Brand.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Scan to sign in on your phone',
                      textAlign: TextAlign.center, style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Open the TinkerPro Employee app on your phone and scan '
                    'this code. It will sign in as the same store — no typing.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (storeName.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Set up this desktop with a store name first, then '
                        'come back to generate the sync code.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium
                            ?.copyWith(color: Brand.textMuted),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Brand.canvas,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Brand.stroke),
                      ),
                      child: QrImageView(
                        data: payload.encode(),
                        version: QrVersions.auto,
                        size: 260,
                        backgroundColor: Brand.canvas,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Brand.textPrimary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Brand.textPrimary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (storeName.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Brand.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Brand.stroke),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Can't scan? Type these on the phone:",
                            style: text.bodySmall
                                ?.copyWith(color: Brand.textMuted),
                          ),
                          const SizedBox(height: 10),
                          _DetailRow(
                            icon: Icons.dns_outlined,
                            label: 'Server URL',
                            value: api.baseUrl,
                          ),
                          const SizedBox(height: 8),
                          _DetailRow(
                            icon: Icons.storefront,
                            label: 'Store name',
                            value: storeName,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Remote desktop stays on this computer only — the phone '
                    'app handles chat, tickets and calls.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: Brand.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled, selectable key/value row used in the "type these manually"
/// panel so the cashier can read (or copy) the value onto the phone.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Brand.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: text.bodySmall?.copyWith(
                      color: Brand.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.6)),
              SelectableText(value,
                  style: text.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
