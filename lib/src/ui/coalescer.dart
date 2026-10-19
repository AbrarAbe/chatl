import 'dart:async';

/// Time-based render coalescer (spec §Risk Module: never rebuild per token).
/// Schedules [flush] at most once per [interval].
class FrameCoalescer {
  FrameCoalescer({this.interval = const Duration(milliseconds: 33)});

  final Duration interval;
  bool _pending = false;
  Timer? _timer;

  void schedule(void Function() flush) {
    if (_pending) return;
    _pending = true;
    _timer = Timer(interval, () {
      _pending = false;
      _timer = null;
      flush();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
