import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/place.dart';
import '../models/place_photo.dart';
import '../services/maps_launcher.dart';

/// Opens the official page directly; does not fetch menu images through Places.
class PlaceLinks extends StatefulWidget {
  const PlaceLinks({
    super.key,
    required this.place,
    this.showMaps = true,
    this.openLink,
  });
  final Place place;
  final bool showMaps;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<PlaceLinks> createState() => _PlaceLinksState();
}

class _PlaceLinksState extends State<PlaceLinks> {
  bool _opening = false;
  String? _error;

  @override
  void didUpdateWidget(covariant PlaceLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) _error = null;
  }

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    final id = widget.place.id;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final ok =
          await (widget.openLink?.call(uri) ??
              launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
      if (!ok) throw StateError('link not opened');
    } catch (_) {
      if (mounted && widget.place.id == id) {
        setState(() => _error = '連結開啟失敗，請再試一次。');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    if (place.isDemo || place.isReference) return const SizedBox.shrink();
    final menu = !place.needsRefresh
        ? safePhotoLink(place.menuUri?.toString())
        : null;
    final website = !place.needsRefresh
        ? safePhotoLink(place.websiteUri?.toString())
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            if (menu != null)
              TextButton.icon(
                onPressed: _opening ? null : () => _open(menu),
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('看菜單'),
              )
            else if (website != null)
              TextButton.icon(
                onPressed: _opening ? null : () => _open(website),
                icon: const Icon(Icons.language),
                label: const Text('店家官網'),
              ),
            if (widget.showMaps)
              TextButton.icon(
                onPressed: _opening
                    ? null
                    : () => _open(MapsLauncher.mapsSearchUri(place)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('更多照片與評論'),
              ),
          ],
        ),
        if (menu != null && place.menuNote != null)
          Text(place.menuNote!, style: Theme.of(context).textTheme.bodySmall),
        if (!widget.showMaps && menu == null)
          Text(
            website != null
                ? '菜單可至店家官網查找；是否提供以店家為準。'
                : '尚無已確認的菜單連結，可至 Google Maps 查看店家資訊。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
