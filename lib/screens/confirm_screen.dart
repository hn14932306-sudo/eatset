import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services/maps_launcher.dart';

/// S7 決定完成：短收束後再開地圖（設計 v1 P0）。
class ConfirmScreen extends StatelessWidget {
  const ConfirmScreen({
    super.key,
    required this.place,
    this.isDemo = false,
  });

  final Place place;
  final bool isDemo;

  Future<void> _openMaps(BuildContext context) async {
    final ok = await MapsLauncher.openPlace(place);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? '無法開啟地圖。請允許彈出式視窗，或改用 App 開啟地圖'
                : '無法開啟地圖，請確認裝置已安裝瀏覽器或 Google Maps',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.check_circle_rounded,
                size: 72,
                color: scheme.primary,
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
              if (isDemo) ...[
                const SizedBox(height: 12),
                Text(
                  '示範流程完成 · 開啟地圖可看位置',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                Text(
                  '網頁版可能受瀏覽器限制；地圖體驗建議用 App',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openMaps(context),
                icon: const Icon(Icons.map_outlined),
                label: const Text('開啟地圖'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
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
