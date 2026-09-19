import 'package:flutter/material.dart';

import '../models/place.dart';
import '../screens/place_details_sheet.dart';
import 'open_status_text.dart';
import 'place_photo_gallery.dart';

class DecisionCard extends StatelessWidget {
  const DecisionCard({
    super.key,
    required this.decision,
    this.showRealDistance = true,
    this.isFavorite = false,
    this.onFavorite,
    this.homePresentation = false,
    this.offline = false,
  });

  final Decision decision;

  /// false：未定位／錨點距離不可信 → 顯示評分，不顯示公尺數。
  final bool showRealDistance;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final bool homePresentation;

  /// The app knows there is no connection; the photo stays quiet about it.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final place = decision.place;
    final scheme = Theme.of(context).colorScheme;
    final address = place.vicinity?.trim();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlacePhotoGallery(place: place, compact: true, offline: offline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                        Icon(
                          Icons.eco_outlined,
                          size: 22,
                          color: scheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '均衡小提醒 · 本週偏重，這餐建議清爽一點',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
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
                    if (homePresentation && onFavorite != null)
                      IconButton(
                        tooltip: isFavorite ? '取消收藏' : '收藏',
                        onPressed: onFavorite,
                        icon: Icon(
                          isFavorite ? Icons.bookmark : Icons.bookmark_outline,
                        ),
                      ),
                  ],
                ),
                if (place.typeLabel != null && !place.needsRefresh)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      place.typeLabel!,
                      key: const Key('place_type'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  place.needsRefresh ? '店家資訊待更新，確認前會重新查詢。' : decision.reasonZh,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (!place.needsRefresh) ...[
                  _DecisionMeta(
                    place: place,
                    showRealDistance: showRealDistance,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${place.isDemo ? '示範價格：' : ''}${place.priceLabel}',
                    key: const Key('place_price'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  OpenStatusText(place: place),
                ],
                if (!homePresentation)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => showPlaceDetails(context, place),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('查看位置'),
                      ),
                      if (onFavorite != null)
                        TextButton.icon(
                          onPressed: onFavorite,
                          icon: Icon(
                            isFavorite
                                ? Icons.bookmark
                                : Icons.bookmark_outline,
                          ),
                          label: Text(isFavorite ? '已收藏' : '收藏'),
                        ),
                    ],
                  ),
                if (!homePresentation &&
                    address != null &&
                    address.isNotEmpty) ...[
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.star_rounded, size: 18, color: scheme.secondary),
        Text(place.rating > 0 ? place.rating.toStringAsFixed(1) : '尚無評分'),
        Text(
          place.userRatingsTotal > 0
              ? '（${place.userRatingsTotal} 則評論）'
              : '評論數未知',
        ),
        if (showRealDistance) Text(_distanceText(place)),
      ],
    );
  }

  String _distanceText(Place place) => place.distanceMeters == null
      ? place.distanceLabel
      : '直線距離${place.distanceLabel}';
}
