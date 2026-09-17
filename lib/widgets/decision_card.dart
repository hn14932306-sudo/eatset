import 'package:flutter/material.dart';

import '../models/place.dart';

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.decision,
    this.showRealDistance = true,
  });

  final Decision decision;

  /// false：未定位／錨點距離不可信 → 顯示評分，不顯示公尺數。
  final bool showRealDistance;

  @override
  Widget build(BuildContext context) {
    final place = decision.place;
    final scheme = Theme.of(context).colorScheme;
    final address = place.vicinity?.trim();

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (decision.isBalanceNudge)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.secondary.withValues(alpha: 0.35),
                  ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (place.isDemo) ...[
                  const SizedBox(width: 8),
                  Text(
                    '示範',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              decision.reasonZh,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            _DecisionMeta(place: place, showRealDistance: showRealDistance),
            if (address != null && address.isNotEmpty) ...[
              const SizedBox(height: 4),
              ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 32, bottom: 4),
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(
                  '地址',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      address,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecisionMeta extends StatelessWidget {
  const _DecisionMeta({required this.place, required this.showRealDistance});

  final Place place;
  final bool showRealDistance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (showRealDistance) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 4),
          Text(_distanceText(place)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 18, color: scheme.secondary),
        const SizedBox(width: 4),
        Text(place.rating > 0 ? place.rating.toStringAsFixed(1) : '尚無評分'),
      ],
    );
  }

  String _distanceText(Place place) => place.distanceLabel;
}
