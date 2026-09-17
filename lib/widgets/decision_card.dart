import 'package:flutter/material.dart';

import '../models/place.dart';

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.decision,
    this.showRealDistance = true,
  });

  final Decision decision;

  /// false：未定位／錨點距離不可信 → 顯示「示範距離」或隱藏公尺數。
  final bool showRealDistance;

  @override
  Widget build(BuildContext context) {
    final place = decision.place;
    final scheme = Theme.of(context).colorScheme;
    final distanceText = _distanceText(place);

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (decision.isBalanceNudge)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.secondary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.eco_outlined, size: 22, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '均衡小提醒 · 本週偏重，這餐建議清爽一點',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
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
                Text(distanceText),
                if (place.rating > 0) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.star_rounded, size: 18, color: scheme.secondary),
                  const SizedBox(width: 2),
                  Text(place.rating.toStringAsFixed(1)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text(
              decision.reasonZh,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (place.isDemo) ...[
              const SizedBox(height: 12),
              Text(
                '示範',
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

  String _distanceText(Place place) {
    if (!showRealDistance) {
      return place.isDemo ? '示範距離' : '距離未知';
    }
    return place.distanceLabel;
  }
}
