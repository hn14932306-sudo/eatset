import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/cold_start_screen.dart';
import 'screens/home_screen.dart';
import 'theme/eatset_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const EatSetApp());
}

class EatSetApp extends StatelessWidget {
  const EatSetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..bootstrap(),
      child: MaterialApp(
        title: '吃定了',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'TW'),
        theme: EatSetTheme.light(),
        darkTheme: EatSetTheme.dark(),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.status == AppLoadStatus.error) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '吃定了',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  state.errorMessage ?? '載入失敗，請再試一次。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.read<AppState>().bootstrap(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.status != AppLoadStatus.ready) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '吃定了',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                '準備這一餐…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (!state.prefs.coldStartDone) {
      return const ColdStartScreen();
    }
    return const HomeScreen();
  }
}
