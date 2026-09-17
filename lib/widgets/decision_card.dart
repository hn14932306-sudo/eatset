import 'package:flutter/material.dart';

import '../models/place.dart';

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.decision,
  });

  final Decision decision;

  @override
  Widget build(BuildContext context) {
    final place = decision.place;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (decision.isBalanceNudge)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  avatar: const Icon(Icons.eco_outlined, size: 18),
                  label: const Text('均衡小提醒'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: scheme.secondaryContainer,
                ),
              ),
            Text(
              place.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 4),
                Text(place.distanceLabel),
                if (place.rating > 0) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.star_rounded, size: 18, color: scheme.tertiary),
                  const SizedBox(width: 2),
                  Text(
                    '${place.rating.toStringAsFixed(1)}'
                    '${place.userRatingsTotal > 0 ? '（${place.userRatingsTotal}）' : ''}',
                  ),
                ],
              ],
            ),
            if (place.vicinity != null) ...[
              const SizedBox(height: 4),
              Text(
                place.vicinity!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              decision.reasonZh,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (place.isDemo) ...[
              const SizedBox(height: 12),
              Text(
                '示範店家',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
