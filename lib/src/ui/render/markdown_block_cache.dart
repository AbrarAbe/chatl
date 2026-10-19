import 'block_splitter.dart';
import 'markdown_lines.dart';

/// Incremental render cache for streaming markdown (ADR 0003).
///
/// Completed blocks are rendered once and kept; only the open block is
/// re-rendered when [update] is called with new text. Pure Dart so the
/// incrementality contract is unit-testable without a widget tree.
class MarkdownBlockCache {
  final List<List<RenderedLine>> _completed = [];
  List<RenderedLine> _open = const [];

  /// Lines for every completed block, oldest first.
  List<List<RenderedLine>> get completedLines => _completed;

  /// Lines for the still-streaming block.
  List<RenderedLine> get openLines => _open;

  /// Every visible line, blocks in order.
  List<RenderedLine> get allLines => [for (final block in _completed) ...block, ..._open];

  /// Re-splits [text]; renders only newly completed blocks plus the open one.
  ///
  /// [onRender] fires once per completed-block render and once per open-block
  /// render — the hook that proves frozen blocks are not re-parsed.
  void update(String text, {void Function({required bool completed})? onRender}) {
    final split = BlockSplitter.split(text);
    for (var i = _completed.length; i < split.completed.length; i++) {
      _completed.add(renderMarkdown(split.completed[i]));
      onRender?.call(completed: true);
    }
    if (split.open.isEmpty) {
      _open = const [];
    } else {
      _open = renderMarkdown(split.open);
      onRender?.call(completed: false);
    }
  }
}
