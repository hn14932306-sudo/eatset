import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/cold_start_screen.dart';
import 'screens/app_shell.dart';
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
  const EatSetApp({super.key, this.createAppState});

  final AppState Function()? createAppState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (createAppState?.call() ?? AppState())..bootstrap(),
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

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> with WidgetsBindingObserver {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) unawaited(context.read<AppState>().syncTime());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      unawaited(_onResumed());
    } else {
      _clockTimer?.cancel();
    }
  }

  Future<void> _onResumed() async {
    final app = context.read<AppState>();
    await app.syncTime();
    if (!mounted) return;
    // A retry after a dropped connection is a full search, so it also covers
    // an outdated or moved-from list; do not attempt both.
    if (app.offline) {
      await app.retryAfterOffline();
    } else {
      await app.refreshIfOutdated(checkMoved: true);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

    if (state.status != AppLoadStatus.ready &&
        !(state.prefs.coldStartDone && state.nearby.isNotEmpty)) {
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
              Text('準備這一餐…', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (!state.prefs.coldStartDone) {
      return const ColdStartScreen();
    }
    return const AppShell();
  }
}
