import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_prefs.dart';
import '../providers/app_state.dart';

class ColdStartScreen extends StatefulWidget {
  const ColdStartScreen({super.key, this.editing = false});
  final bool editing;
  @override
  State<ColdStartScreen> createState() => _ColdStartScreenState();
}

class _ColdStartScreenState extends State<ColdStartScreen> {
  int _index = 0;
  bool _started = false;
  final Map<String, bool> _answers = {};
  String? _error;

  Future<void> _finish({bool skip = false}) async {
    final app = context.read<AppState>();
    try {
      if (skip) {
        await app.skipColdStart();
      } else {
        await app.completeColdStart(_answers);
      }
      if (mounted && widget.editing) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '儲存失敗，請再試一次');
    }
  }

  void _choose(bool choseA) {
    _answers[coldStartQuestions[_index].id] = choseA;
    if (_index < coldStartQuestions.length - 1) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppState>().isBusy;
    final welcome = !_started && !widget.editing;
    final q = coldStartQuestions[_index];
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('調整口味偏好')) : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (welcome) ...[
                    Icon(
                      Icons.restaurant_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '吃定了',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '少想一點，好好吃一餐。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '一次推薦一家。先試試看，口味與價格之後都能調整。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    FilledButton(
                      onPressed: busy ? null : () => _finish(skip: true),
                      child: const Text('直接幫我決定'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => _started = true),
                      child: const Text('先選口味 · 3 個小問題'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '免註冊 · 需要時再開定位\n目前可先體驗示範店家',
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Text(
                      '第 ${_index + 1}／${coldStartQuestions.length} 題',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_index + 1) / coldStartQuestions.length,
                    ),
                    const SizedBox(height: 36),
                    Text(
                      q.prompt,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : () => _choose(true),
                      child: Text(q.optionA),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy ? null : () => _choose(false),
                      child: Text(q.optionB),
                    ),
                    const SizedBox(height: 24),
                    if (!widget.editing)
                      TextButton(
                        onPressed: busy ? null : () => _finish(skip: true),
                        child: const Text('先用預設，直接決定'),
                      ),
                  ],
                  if (_error != null) Text(_error!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
