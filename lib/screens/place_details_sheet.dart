import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

import '../models/place.dart';
import '../services/maps_launcher.dart';
import '../widgets/open_status_text.dart';
import '../widgets/place_photo_gallery.dart';
import '../widgets/place_links.dart';

Future<void> showPlaceDetails(
  BuildContext context,
  Place place,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PlaceDetailsSheet(
    place: place,
    // Fresh data needs no round trip; skipping it also avoids a blank flash.
    refreshPlace: place.isDemo || !place.needsRefresh
        ? null
        : () => context.read<AppState>().refreshPlace(place.id),
  ),
);

class PlaceDetailsSheet extends StatefulWidget {
  const PlaceDetailsSheet({
    super.key,
    required this.place,
    this.openMaps,
    this.refreshPlace,
    this.offline = false,
  });
  final Place place;
  final Future<Place> Function()? refreshPlace;
  final Future<bool> Function(Place)? openMaps;

  /// Whether the app knew there was no connection when this opened.
  final bool offline;
  @override
  State<PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<PlaceDetailsSheet> {
  late Place _place = widget.place;
  late bool _refreshing = widget.refreshPlace != null;
  bool _refreshFailed = false;
  @override
  void initState() {
    super.initState();
    if (widget.refreshPlace != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshFailed = false;
    });
    try {
      final place = await widget.refreshPlace!();
      if (mounted) setState(() => _place = place);
    } catch (_) {
      if (mounted) {
        setState(() {
          _refreshFailed = true;
          _place = Place.reference(widget.place.id);
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  bool _opening = false;
  String? _note;
  @override
  Widget build(BuildContext context) {
    final place = _place;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(place.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (_refreshing) const LinearProgressIndicator(),
            if (!_refreshing && (_refreshFailed || place.needsRefresh)) ...[
              const Text('最新店家資訊暫時無法取得，原本的收藏與紀錄仍保留。'),
              if (widget.refreshPlace != null)
                TextButton(
                  onPressed: _refreshing ? null : _refresh,
                  child: const Text('重試更新店家資訊'),
                ),
            ] else if (!_refreshing)
              PlacePhotoGallery(
                place: place,
                autoLoad: false,
                offline: widget.offline,
              ),
            const SizedBox(height: 12),
            Text(
              place.vicinity?.trim().isNotEmpty == true
                  ? place.vicinity!
                  : '尚無地址資料',
            ),
            const SizedBox(height: 8),
            if (!_refreshing && !place.needsRefresh) ...[
              Text(place.priceLabel),
              OpenStatusText(place: place),
            ],
            const SizedBox(height: 12),
            Text(
              place.isDemo
                  ? '這是示範店家；地圖連結僅用於示範位置流程。'
                  : '先確認位置，再決定要不要去。查看地圖不會記為已決定。',
            ),
            if (!_refreshing && !_refreshFailed) ...[
              const SizedBox(height: 8),
              PlaceLinks(place: place, showMaps: false),
            ],
            if (_note != null) ...[const SizedBox(height: 12), Text(_note!)],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _opening ? null : _open,
              icon: const Icon(Icons.map_outlined),
              label: Text(_opening ? '開啟中…' : '在 Google Maps 查看'),
            ),
            if (!place.isDemo) const Text('更多照片與評論可在 Google Maps 瀏覽。'),
            TextButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(
                    ClipboardData(
                      text: MapsLauncher.mapsSearchUri(place).toString(),
                    ),
                  );
                  if (mounted) setState(() => _note = '已複製地圖連結');
                } catch (_) {
                  if (mounted) setState(() => _note = '複製失敗，請再試一次');
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('複製地圖連結'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _note = null;
    });
    try {
      final ok = await (widget.openMaps ?? MapsLauncher.openPlace)(_place);
      if (mounted) {
        setState(
          () => _note = !ok
              ? '地圖沒有開啟，請重試或複製連結。'
              : kIsWeb
              ? '若未出現新分頁，可複製連結到瀏覽器開啟。'
              : null,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _note = '地圖開啟失敗，請重試或複製連結。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
