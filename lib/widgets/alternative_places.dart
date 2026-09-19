import 'package:flutter/material.dart';
import '../models/place.dart';
import 'open_status_text.dart';
import 'place_photo_gallery.dart';

class AlternativePlaces extends StatelessWidget {
  const AlternativePlaces({
    super.key,
    required this.places,
    required this.showRealDistance,
    required this.onSelect,
    this.busy = false,
    this.offline = false,
  });
  final List<Place> places;
  final bool showRealDistance;
  final ValueChanged<Place> onSelect;
  final bool busy;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(
          '想換口味？',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('點選店家，換成這餐推薦', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 21;
            final cards = places.map((p) => _card(context, p)).toList();
            if (singleColumn) {
              return Column(
                children: [
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: card,
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
                if (cards.length == 1) const Expanded(child: SizedBox()),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Place p) => Card(
    key: ValueKey('alternative-${p.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: busy ? null : () => onSelect(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlacePhotoGallery(
            key: ValueKey(p.id),
            place: p,
            thumbnail: true,
            autoLoad: false,
            offline: offline,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.rating > 0 ? '★ ${p.rating.toStringAsFixed(1)}' : '尚無評分'} · ${p.priceLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (showRealDistance) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.distanceMeters == null
                        ? p.distanceLabel
                        : '直線距離${p.distanceLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                p.isDemo
                    ? Text('示範店家', style: Theme.of(context).textTheme.bodySmall)
                    : OpenStatusText(
                        place: p,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
