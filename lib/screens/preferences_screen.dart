import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/dining_filters.dart';
import 'cold_start_screen.dart';
import 'history_screen.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prefs = state.prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('我的偏好')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('讓下一餐更合口味', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('不用帳號也能使用。偏好、收藏與紀錄保存在這台裝置。'),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ramen_dining),
                  title: const Text('口味偏好'),
                  subtitle: Text(
                    '${prefs.prefersNoodles == null
                        ? '麵飯都可以'
                        : prefs.prefersNoodles!
                        ? '偏好麵食'
                        : '偏好米飯'} · ${prefs.prefersLight == null
                        ? '口味不拘'
                        : prefs.prefersLight!
                        ? '偏好清淡'
                        : '偏好重口味'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: state.isBusy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const ColdStartScreen(editing: true),
                          ),
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DiningFiltersButton(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('管理永久排除'),
            subtitle: Text(
              '${prefs.excludedPlaceIds.length} 家店 · ${prefs.excludedCategories.length} 個類別',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const HistoryScreen(showExclusions: true),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('更新定位與店家'),
            subtitle: const Text('需要時再允許定位，隨時可以調整系統權限'),
            onTap: state.isBusy
                ? null
                : () => context.read<AppState>().enableLocation(),
          ),
          const Divider(height: 36),
          const Text('你的回饋怎麼使用', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            '在紀錄標記吃過和感受後，推薦會依回饋調整。「沒有去吃」不會被當作用餐；不合口味會降低推薦分數，永久排除則完全不推薦。',
          ),
          const SizedBox(height: 24),
          const Text('目前所有已開放功能皆可免費使用。'),
        ],
      ),
    );
  }
}
