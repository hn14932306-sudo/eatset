import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/place.dart';
import '../services/maps_launcher.dart';

/// S7 決定完成：短收束後再開地圖（設計 v1 P0／P1-1 失敗態）。
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.place,
    this.isDemo = false,
    this.openMapsOverride,
    this.forceWebCopyLink = false,
  });

  final Place place;
  final bool isDemo;

  /// 測試用：覆寫開啟地圖結果。
  final Future<bool> Function(Place place)? openMapsOverride;

  /// 測試用：在非 web 也顯示「複製地圖連結」。
  final bool forceWebCopyLink;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  bool _mapsFailed = false;
  bool _opening = false;
  String? _failureMessage;

  bool get _showCopyLink => kIsWeb || widget.forceWebCopyLink;

  Future<void> _openMaps() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failureMessage = null;
    });
    final opener = widget.openMapsOverride ?? MapsLauncher.openPlace;
    final ok = await opener(widget.place);
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (ok) {
        _mapsFailed = false;
        _failureMessage = null;
      } else {
        _mapsFailed = true;
        _failureMessage = _showCopyLink
            ? '無法開啟地圖。請允許彈出式視窗，或複製連結到瀏覽器開啟'
            : '無法開啟地圖，請確認裝置已安裝瀏覽器或 Google Maps';
      }
    });
  }

  Future<void> _copyMapsLink() async {
    final uri = MapsLauncher.mapsSearchUri(widget.place);
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製地圖連結')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final place = widget.place;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                _mapsFailed
                    ? Icons.map_outlined
                    : Icons.check_circle_rounded,
                size: 72,
                color: _mapsFailed ? scheme.error : scheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                '就這家了',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                place.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.isDemo) ...[
                const SizedBox(height: 12),
                Text(
                  '示範流程完成 · 開啟地圖可看位置',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (_showCopyLink && !_mapsFailed) ...[
                const SizedBox(height: 8),
                Text(
                  '網頁版可能受瀏覽器限制；地圖體驗建議用 App',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (_mapsFailed && _failureMessage != null) ...[
                const SizedBox(height: 20),
                Material(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      _failureMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: _opening ? null : _openMaps,
                icon: _opening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _mapsFailed ? Icons.refresh : Icons.map_outlined,
                      ),
                label: Text(_mapsFailed ? '再試一次' : '開啟地圖'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              if (_mapsFailed && _showCopyLink) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _copyMapsLink,
                  icon: const Icon(Icons.link),
                  label: const Text('複製地圖連結'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍後再說'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
