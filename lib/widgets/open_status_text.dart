import 'dart:async';

import 'package:flutter/material.dart';

import '../models/place.dart';

/// Open state with a live countdown ("還有 2 小時 15 分鐘打烊"). The time is
/// computed from the closing time Google already returned, so it stays correct
/// without any new request; a light timer only repaints it.
class OpenStatusText extends StatefulWidget {
  const OpenStatusText({super.key, required this.place, this.style, this.now});

  final Place place;
  final TextStyle? style;

  /// Overridable clock for tests.
  final DateTime Function()? now;

  @override
  State<OpenStatusText> createState() => _OpenStatusTextState();
}

class _OpenStatusTextState extends State<OpenStatusText> {
  Timer? _timer;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant OpenStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  /// Only places with a known closing time need repainting.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final place = widget.place;
    if (place.isDemo || place.openNow != true || place.closesAt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final scheme = Theme.of(context).colorScheme;
    final at = _now;
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    final open = !place.isDemo && place.isOpenAt(at) == true;
    final left = place.timeUntilClose(at);
    // Closing within half an hour is worth a warning colour.
    final soon = left != null && left <= const Duration(minutes: 30);
    return Text(
      place.openStatusLabel(at),
      key: const Key('place_open_status'),
      style: open
          ? base?.copyWith(
              color: soon ? scheme.error : scheme.primary,
              fontWeight: FontWeight.w600,
            )
          : base,
    );
  }
}
