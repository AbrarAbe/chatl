import 'package:chatl/src/config/config.dart';
import 'package:chatl/src/ui/app.dart';
import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  final config = await Config.load();
  await runApp(ChatlApp(config: config));
}
