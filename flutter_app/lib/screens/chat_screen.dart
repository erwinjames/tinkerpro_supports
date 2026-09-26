import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/premium.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'Chat',
      title: 'Talk to your team',
      showBottomBrand: false,
      child: ListView(
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconTile(icon: Icons.chat_bubble_outline_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chat is coming soon',
                        style: text.titleMedium,
                      ),
                    ),
                    const GlowBadge(
                      label: 'In development',
                      color: Brand.warning,
                      icon: Icons.bolt_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'A native chat surface for the support team is on the way. '
                  'You will be able to message customers and teammates from '
                  'this tab without leaving the app.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AppCard(
            radius: Brand.radiusLg,
            child: StationDataRow(
              label: 'Status',
              value: 'Backend wiring in progress.',
            ),
          ),
        ],
      ),
    );
  }
}
