import 'package:chatl/src/ui/app.dart';
import 'package:nocterm/nocterm_test.dart';
import 'package:test/test.dart';

void main() {
  test('app shell renders', () async {
    await testNocterm('smoke', (tester) async {
      await tester.pumpComponent(const ChatlApp());
      await tester.pump();
      expect(tester.terminalState.containsText('chatl'), isTrue);
    });
  });
}
