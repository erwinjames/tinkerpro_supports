import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// "Update available" popup — shows the published changelog and a button that
/// opens the new APK download. Shown on launch when [UpdateService.check]
/// reports a newer build.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.update, required this.service});

  final AppUpdate update;
  final UpdateService service;

  static Future<void> show(
    BuildContext context,
    AppUpdate update,
    UpdateService service,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(update: update, service: service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: context.brand.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.brand.rule, width: 1),
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt,
                    size: 18, color: Brand.signal),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Update available', style: text.headlineMedium)),
              ],
            ),
            const SizedBox(height: 6),
            if (update.version.isNotEmpty)
              Text('Version ${update.version}', style: text.labelMedium),
            const SizedBox(height: 12),
            const Hairline(),
            const SizedBox(height: 16),
            if (update.changelog.isEmpty)
              Text('A new version of the app is available.',
                  style: text.bodyMedium)
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in update.changelog)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 6, right: 8),
                                child: Icon(Icons.circle,
                                    size: 5, color: Brand.signal),
                              ),
                              Expanded(
                                  child: Text(line, style: text.bodyMedium)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SignalButton(
              label: 'Update now',
              icon: Icons.download,
              onPressed: () async {
                final url = update.apkUrl;
                if (url.isNotEmpty) {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Later',
              onPressed: () {
                service.snooze(update.build);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
