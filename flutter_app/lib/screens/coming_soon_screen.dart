import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/premium.dart';

/// Premium "this screen isn't native yet" placeholder. Instead of a sad
/// "coming soon" dialog, it presents itself as a planned station with a
/// deep-link back to the equivalent web page.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.webPath,
    required this.baseUrl,
  });

  final String title;
  final String webPath;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final url = '$baseUrl/$webPath';
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'COMING SOON',
      title: title,
      onBack: () => Navigator.of(context).pop(),
      showBottomBrand: false,
      child: ListView(
        children: [
          Text(
            'A native surface for this section is on the roadmap. '
            "In the meantime, open it in your browser — you're already "
            'authenticated on the device, so the web version will pick up '
            'your session.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Brand.surface,
              border: Border.all(color: Brand.rule, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WEB LINK',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Text(url,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                GhostButton(
                  label: 'Copy link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('LINK COPIED')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'NATIVE STATUS',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Text('In design review.',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
