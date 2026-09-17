import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_prefs.dart';
import '../providers/app_state.dart';

/// Cold start：多輪二選一；可「先用預設，直接決定」跳過。
class ColdStartScreen extends StatefulWidget {
  const ColdStartScreen({super.key});

  @override
  State<ColdStartScreen> createState() => _ColdStartScreenState();
}

class _ColdStartScreenState extends State<ColdStartScreen> {
  int _index = 0;
  final Map<String, bool> _answers = {};

  void _choose(bool choseA) {
    final q = coldStartQuestions[_index];
    _answers[q.id] = choseA;
    if (_index < coldStartQuestions.length - 1) {
      setState(() => _index++);
    } else {
      context.read<AppState>().completeColdStart(_answers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = coldStartQuestions[_index];
    final progress = (_index + 1) / coldStartQuestions.length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '吃定了',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.read<AppState>().skipColdStart(),
                    child: const Text('先用預設，直接決定'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '先快速了解口味，之後一鍵決定這一餐',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                '第 ${_index + 1}／${coldStartQuestions.length} 題',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              Text(
                q.prompt,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _choose(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(q.optionA, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _choose(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(q.optionB, style: const TextStyle(fontSize: 20)),
              ),
              const Spacer(flex: 2),
              Text(
                '之後仍可在首頁微調心情與排除店家',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
