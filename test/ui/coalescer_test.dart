import 'package:chatl/src/ui/coalescer.dart';
import 'package:test/test.dart';

void main() {
  group('FrameCoalescer', () {
    test('many rapid schedules produce one flush per interval', () async {
      final coalescer = FrameCoalescer(interval: const Duration(milliseconds: 33));
      var flushes = 0;

      for (var i = 0; i < 50; i++) {
        coalescer.schedule(() => flushes++);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(flushes, 1);

      for (var i = 0; i < 50; i++) {
        coalescer.schedule(() => flushes++);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(flushes, 2);

      coalescer.dispose();
    });

    test('flush runs after the interval, not synchronously', () async {
      final coalescer = FrameCoalescer(interval: const Duration(milliseconds: 10));
      var flushed = false;
      coalescer.schedule(() => flushed = true);
      expect(flushed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(flushed, isTrue);
      coalescer.dispose();
    });
  });
}
