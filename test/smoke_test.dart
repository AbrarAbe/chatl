import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/ui/app.dart';
import 'package:nocterm/nocterm_test.dart';
import 'package:test/test.dart';

void main() {
  test('app shell renders', () async {
    final config = await Config.load(path: '/nonexistent/chatl.yaml', environment: const {});
    await testNocterm('smoke', (tester) async {
      await tester.pumpComponent(ChatlApp(config: config));
      await tester.pump();
      expect(tester.terminalState.containsText('❯'), isTrue);
    });
  });
}
