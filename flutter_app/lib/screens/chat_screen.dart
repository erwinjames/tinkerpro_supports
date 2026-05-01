import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/premium.dart';

/// Placeholder for the in-app chat surface. The TICKET tab has been swapped
/// out for CHAT in the bottom nav while the messaging backend is still being
/// designed — this screen keeps the slot occupied with a station-styled
/// "in development" notice instead of leaving an empty tab.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'CHAT · DIRECT MESSAGES',
      title: 'Talk to your team.',
      showBottomBrand: false,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Brand.surface,
              border: Border.all(color: Brand.rule, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        size: 18, color: Brand.signal),
                    const SizedBox(width: 10),
                    Text('IN DEVELOPMENT', style: text.labelLarge),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'A native chat surface for the support team is on the way. '
                  'You will be able to message customers and teammates from '
                  'this tab without leaving the app.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('STATUS', style: text.labelMedium),
          const SizedBox(height: 6),
          Text('Backend wiring in progress.', style: text.bodyMedium),
        ],
      ),
    );
  }
}
