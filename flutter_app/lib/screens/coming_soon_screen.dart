import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/premium.dart';

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
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'Coming soon',
      title: title,
      onBack: () => Navigator.of(context).pop(),
      showBottomBrand: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
                    border: Border.all(color: b.signal.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    Icons.rocket_launch_rounded,
                    size: 26,
                    color: b.signal,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Native screen on the way', style: text.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'A native surface for this section is on the roadmap. '
                  "In the meantime, open it in your browser — you're already "
                  'authenticated on the device, so the web version will pick up '
                  'your session.',
                  style: text.bodyMedium?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 14),
                const GlowBadge(
                  label: 'In design review',
                  color: Brand.warning,
                  icon: Icons.draw_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Web link'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Brand.info.withValues(
                          alpha: b.isDark ? 0.18 : 0.12,
                        ),
                        border: Border.all(
                          color: Brand.info.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.link_rounded,
                        size: 20,
                        color: Brand.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        url,
                        style: text.bodyMedium?.copyWith(color: b.paper),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GhostButton(
                  label: 'Copy link',
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
