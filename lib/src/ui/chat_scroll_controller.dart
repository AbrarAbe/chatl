import 'package:nocterm/nocterm.dart';

/// Auto-scroll that releases on **any** user-initiated upward scroll, not
/// just past the framework's near-bottom threshold (ADR 0003: nocterm's
/// default 1-row threshold re-engages the anchor before a single-line
/// scroll can escape mid-stream).
class ChatScrollController extends AutoScrollController {
  @override
  void scrollBy(double delta) {
    if (delta < 0) disableAutoScroll();
    super.scrollBy(delta);
    if (delta < 0) disableAutoScroll(); // post-threshold re-check
  }

  @override
  void scrollUp([double lines = 1.0]) {
    disableAutoScroll(); // release before jumpTo's threshold check re-enables
    super.scrollUp(lines);
    disableAutoScroll();
  }
}
