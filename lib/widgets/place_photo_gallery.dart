import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';
import '../models/place_photo.dart';
import '../services/place_photos_service.dart';

/// Loads only the displayed restaurant and one photo at a time. A generation
/// guard prevents a slow response from showing another restaurant's photo.
class PlacePhotoGallery extends StatefulWidget {
  const PlacePhotoGallery({
    super.key,
    required this.place,
    this.service,
    this.openLink,
    this.compact = false,
    this.thumbnail = false,
    this.autoLoad = true,
    this.autoLoadDelay = const Duration(milliseconds: 350),
    this.cachedOnly = false,
    this.offline = false,
  });
  final Place place;
  final PlacePhotosService? service;
  final Future<bool> Function(Uri)? openLink;
  final bool compact;
  final bool thumbnail;
  final bool autoLoad;

  /// Auto-loading waits until the card has been on screen this long, so rapid
  /// rerolls do not pay for photos nobody looked at. Cache hits, taps, and
  /// retries are immediate.
  final Duration autoLoadDelay;

  /// Render nothing unless a photo is already in memory: for places where a
  /// photo is a bonus and must never trigger a paid request or a placeholder.
  final bool cachedOnly;

  /// The app already knows there is no connection (its banner says so). Photos
  /// that are not in memory then show one quiet line instead of each trying,
  /// failing and reporting on their own; they load by themselves once the
  /// connection is back.
  final bool offline;
  @override
  State<PlacePhotoGallery> createState() => _PlacePhotoGalleryState();
}

class _PlacePhotoGalleryState extends State<PlacePhotoGallery> {
  late PlacePhotosService _service;
  List<PlacePhoto> _photos = [];
  Uint8List? _bytes;
  int _index = 0;
  int _generation = 0;
  bool _loading = false;
  bool _failed = false;
  bool _requested = false;
  PhotoLoadException _error = const PhotoLoadException();
  bool get _demo => widget.place.isDemo || widget.place.id.startsWith('demo_');
  PhotoSize get _size => widget.thumbnail ? PhotoSize.thumb : PhotoSize.card;

  /// A photo already in memory is free to show, so it counts as requested.
  bool get _autoRequested =>
      widget.autoLoad ||
      _service.hasCachedFirstPhoto(widget.place, size: _size);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PlacePhotosService();
    _requested = _autoRequested;
    _load();
  }

  @override
  void didUpdateWidget(covariant PlacePhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      if (oldWidget.service == null) _service.dispose();
      _service = widget.service ?? PlacePhotosService();
    }
    if (oldWidget.place.id != widget.place.id ||
        oldWidget.place.isDemo != widget.place.isDemo ||
        oldWidget.place.isReference != widget.place.isReference ||
        (oldWidget.place.needsRefresh && !widget.place.needsRefresh) ||
        oldWidget.service != widget.service) {
      _requested = _autoRequested;
      _load();
    } else if (oldWidget.offline &&
        !widget.offline &&
        _requested &&
        _bytes == null &&
        !_loading) {
      _load(immediate: true);
    }
  }

  void _releaseImage() {
    final old = _bytes;
    _bytes = null;
    if (old != null) MemoryImage(old).evict();
  }

  @override
  void dispose() {
    _generation++;
    _releaseImage();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false, bool immediate = false}) async {
    final generation = ++_generation;
    _releaseImage();
    final free = !refresh && _service.hasCachedFirstPhoto(widget.place);
    setState(() {
      _photos = [];
      _index = 0;
      _failed = false;
      _error = const PhotoLoadException();
      _loading =
          _requested &&
          !_demo &&
          !widget.place.needsRefresh &&
          _service.isConfigured &&
          (!widget.offline || free);
    });
    if (!_loading) return;
    final wait = refresh || immediate || free
        ? Duration.zero
        : widget.autoLoadDelay;
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
      if (!mounted || generation != _generation) return;
    }
    try {
      final photos = await (refresh
          ? _service.refreshPhotos(widget.place)
          : _service.fetchPhotos(widget.place));
      if (!mounted || generation != _generation) return;
      setState(() {
        _photos = photos.take(3).toList();
        _loading = false;
      });
      if (photos.isNotEmpty) await _showPhoto(0);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = error is PhotoLoadException
            ? error
            : const PhotoLoadException();
      });
    }
  }

  Future<void> _showPhoto(int index, {bool force = false}) async {
    if (_loading || index < 0 || index >= _photos.length) return;
    if (!force && index == _index && _bytes != null && !_failed) return;
    await _fetchPhoto(index);
  }

  Future<void> _fetchPhoto(int index, {bool tokensRefreshed = false}) async {
    final generation = ++_generation;
    final photo = _photos[index];
    _releaseImage();
    setState(() {
      _index = index;
      _loading = true;
      _failed = false;
      _error = const PhotoLoadException();
    });
    try {
      final bytes = await _service.fetchImage(photo, size: _size);
      if (!mounted || generation != _generation) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      final failure = error is PhotoLoadException
          ? error
          : const PhotoLoadException();
      // An expired token is not the user's problem: swap in fresh ones behind
      // the spinner, once, and try the same photo again.
      if (failure.code == 'INVALID_PHOTO' && !tokensRefreshed) {
        try {
          final fresh = (await _service.refreshPhotos(
            widget.place,
          )).take(3).toList();
          if (!mounted || generation != _generation) return;
          if (fresh.isNotEmpty) {
            setState(() => _photos = fresh);
            await _fetchPhoto(
              index < fresh.length ? index : 0,
              tokensRefreshed: true,
            );
            return;
          }
        } catch (_) {
          if (!mounted || generation != _generation) return;
        }
      }
      setState(() {
        _loading = false;
        _failed = true;
        _error = failure;
      });
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      final ok =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, webOnlyWindowName: '_blank'));
      if (!ok) throw const PhotoLoadException();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('連結開啟失敗，請再試一次')));
      }
    }
  }

  Widget _message(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        const Icon(Icons.photo_outlined, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );

  /// Retries only what failed. With the photo list already in hand that is
  /// just the image, so no extra metadata lookup is paid for; a bad picture
  /// (it arrived but would not decode) is dropped from memory first, otherwise
  /// the same bytes would come straight back.
  void _retry() {
    if (_loading) return;
    if (_photos.isEmpty) {
      _load(refresh: true);
      return;
    }
    if (_bytes != null) _service.evict(_photos[_index]);
    _fetchPhoto(_index);
  }

  Widget _loadButton() => FilledButton.tonalIcon(
    onPressed: () {
      if (_requested) return;
      _requested = true;
      _load(immediate: true);
    },
    icon: const Icon(Icons.photo_outlined),
    label: const Text('查看照片'),
  );

  // One fixed ratio per size across every state (loading, empty, error, photo),
  // so the card never jumps in height when the picture arrives.
  double get _aspect => widget.thumbnail ? 1.6 : (widget.compact ? 1.5 : 4 / 3);

  @override
  Widget build(BuildContext context) {
    if (widget.cachedOnly && (_bytes == null || _failed)) {
      return const SizedBox.shrink();
    }
    if (widget.compact || widget.thumbnail) return _compactGallery(context);
    if (_demo) return _message('示範店家沒有實景照片');
    if (widget.place.needsRefresh && _bytes == null) {
      return _message('更新店家資訊後可看照片');
    }
    if (!_service.isConfigured) return _message('店家照片尚未連線');
    if (widget.offline && _bytes == null && !_loading) {
      return _message('離線中 · 暫時看不到照片');
    }
    if (!_requested) return _loadButton();
    final photo = _photos.isEmpty ? null : _photos[_index];
    final showing = _bytes != null && !_failed && !_loading && photo != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('店家照片', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _stage(context),
        ),
        _limitNote(),
        if (showing) ...[
          const SizedBox(height: 8),
          const Text(
            'Google Maps',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
          ...photo.authors.map(
            (author) => author.uri == null
                ? Text('攝影：${author.name}')
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _open(author.uri!),
                      child: Text('攝影：${author.name}'),
                    ),
                  ),
          ),
          Wrap(
            spacing: 8,
            children: [
              if (photo.sourceUri != null)
                TextButton(
                  onPressed: () => _open(photo.sourceUri!),
                  child: const Text('查看照片來源'),
                ),
              if (photo.reportUri != null)
                TextButton(
                  onPressed: () => _open(photo.reportUri!),
                  child: const Text('回報照片'),
                ),
            ],
          ),
          Text('照片可能包含餐點、環境或菜單。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  /// One short line and a small icon; the whole area is the retry target, so
  /// there is no button to draw the eye. Thumbnails are too small for text.
  Widget _placeholder(
    String text, {
    required double minHeight,
    bool retry = false,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final small = widget.thumbnail;
    final canRetry = _failed || retry;
    final body = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minHeight,
        minWidth: double.infinity,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? (canRetry ? Icons.refresh : Icons.image_outlined),
                size: small ? 26 : 30,
                color: scheme.onSurfaceVariant,
              ),
              if (!(small && canRetry && icon == null)) ...[
                const SizedBox(height: 6),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!canRetry) return body;
    return Tooltip(
      message: '重試照片',
      child: InkWell(onTap: _retry, child: body),
    );
  }

  String get _failureLine => switch (_error.code) {
    'DAILY_LIMIT' => '今日照片額度已用完',
    'NETWORK_FAILED' => '沒有網路 · 點一下重試',
    _ => '照片暫時無法載入 · 點一下重試',
  };

  /// A message worth reading in full goes under the picture, not inside it.
  Widget _limitNote() {
    final code = _error.code;
    if (!_failed || widget.thumbnail) return const SizedBox.shrink();
    if (code != 'DAILY_LIMIT' && code != 'CLIENT_LIMIT') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(_error.message, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _navButton(String tooltip, IconData icon, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black12,
          disabledForegroundColor: Colors.white38,
        ),
      );

  /// The picture area: photo, spinner, or message at a fixed ratio, with paging
  /// controls laid over it. Swipe changes photo; a tap opens the full view.
  Widget _stage(
    BuildContext context, {
    String? staticMessage,
    IconData? staticIcon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final paging = !widget.thumbnail && _photos.length > 1;
    final canOpen =
        !widget.thumbnail && _bytes != null && !_failed && !_loading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxWidth / _aspect;
        // Explanations (demo, offline, no photos) stay compact: only states
        // that hold or await a picture reserve the full photo height.
        final message =
            staticMessage != null || (!_loading && !_failed && _bytes == null);
        final minHeight = message ? (widget.thumbnail ? 96.0 : 120.0) : height;
        final Widget content;
        if (staticMessage != null) {
          content = _placeholder(
            staticMessage,
            minHeight: minHeight,
            icon: staticIcon,
          );
        } else if (_loading) {
          content = SizedBox(
            height: height,
            child: const Center(
              child: CircularProgressIndicator(semanticsLabel: '正在載入店家照片'),
            ),
          );
        } else if (_failed) {
          content = _placeholder(
            _failureLine,
            minHeight: minHeight,
            retry: true,
          );
        } else if (_bytes == null) {
          content = _placeholder('店家尚未提供可顯示的照片', minHeight: minHeight);
        } else {
          content = SizedBox(
            height: height,
            child: Image.memory(
              _bytes!,
              // A new picture is a new Image. Without this, a retry that
              // finishes before the next frame reuses the failed one and keeps
              // showing its error even though the new bytes are fine.
              key: ObjectKey(_bytes),
              fit: BoxFit.cover,
              width: double.infinity,
              height: height,
              semanticLabel: '${widget.place.name}的店家照片，第 ${_index + 1} 張',
              // Fade in instead of popping in once decoded.
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: child,
                    ),
              errorBuilder: (_, _, _) => SingleChildScrollView(
                child: Center(
                  child: _placeholder(
                    '照片暫時無法載入 · 點一下重試',
                    minHeight: height,
                    retry: true,
                  ),
                ),
              ),
            ),
          );
        }
        final stack = Stack(
          children: [
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: minHeight,
                  minWidth: double.infinity,
                ),
                child: Center(child: content),
              ),
            ),
            if (paging)
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned(
                      left: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _navButton(
                          '上一張照片',
                          Icons.chevron_left,
                          !_loading && _index > 0
                              ? () => _showPhoto(_index - 1)
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _navButton(
                          '下一張照片',
                          Icons.chevron_right,
                          !_loading && _index < _photos.length - 1
                              ? () => _showPhoto(_index + 1)
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            '${_index + 1} / ${_photos.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        if (widget.thumbnail) return stack;
        return GestureDetector(
          onTap: canOpen ? _openViewer : null,
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (_loading) return;
            if (v < -300) _showPhoto(_index + 1);
            if (v > 300) _showPhoto(_index - 1);
          },
          child: stack,
        );
      },
    );
  }

  Widget _compactGallery(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_requested &&
        !_demo &&
        !widget.place.needsRefresh &&
        !widget.offline &&
        _service.isConfigured) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: _aspect,
          child: Center(child: _loadButton()),
        ),
      );
    }
    final photo = _photos.isEmpty ? null : _photos[_index];
    String? message;
    var offlineNote = false;
    if (_demo) {
      message = '示範店家沒有實景照片';
    } else if (widget.place.needsRefresh && _bytes == null) {
      message = '更新店家資訊後可看照片';
    } else if (!_service.isConfigured) {
      message = '店家照片尚未連線';
    } else if (widget.offline && _bytes == null && !_loading) {
      message = widget.thumbnail ? '離線中' : '離線中 · 暫時看不到照片';
      offlineNote = true;
    }
    final showing = _bytes != null && !_failed && !_loading && photo != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stage(
          context,
          staticMessage: message,
          staticIcon: offlineNote ? Icons.cloud_off_outlined : null,
        ),
        _limitNote(),
        if (showing)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 2, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      const Text('Google Maps', style: TextStyle(fontSize: 12)),
                      for (final author in photo.authors)
                        Text(
                          '攝影：${author.name}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '照片來源與回報',
                  onPressed: () => _photoInfo(photo),
                  icon: const Icon(Icons.info_outline, size: 18),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _openViewer() {
    final bytes = _bytes;
    final photo = _photos.isEmpty ? null : _photos[_index];
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    semanticLabel: '${widget.place.name}的店家照片，放大檢視',
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: '關閉',
                  color: Colors.white,
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            if (photo != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  child: Text(
                    [
                      'Google Maps',
                      for (final a in photo.authors) '攝影：${a.name}',
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _photoInfo(PlacePhoto photo) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Google Maps · 店家照片'),
              const SizedBox(height: 12),
              for (final author in photo.authors)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('攝影：${author.name}'),
                  trailing: author.uri == null
                      ? null
                      : const Icon(Icons.open_in_new),
                  onTap: author.uri == null ? null : () => _open(author.uri!),
                ),
              if (photo.sourceUri != null)
                TextButton(
                  onPressed: () => _open(photo.sourceUri!),
                  child: const Text('查看照片來源'),
                ),
              if (photo.reportUri != null)
                TextButton(
                  onPressed: () => _open(photo.reportUri!),
                  child: const Text('回報照片'),
                ),
              const Text('照片可能包含餐點、環境或菜單。'),
            ],
          ),
        ),
      ),
    );
  }
}
