/// Splits a streaming markdown buffer into completed blocks and the open
/// (still-streaming) block. A boundary is a blank line **outside** a fenced
/// code block, so unclosed fences and half-streamed tables stay in the open
/// block (ADR 0003).
library;

class BlockSplit {
  const BlockSplit({required this.completed, required this.open});

  /// Blocks that can be rendered once and frozen.
  final List<String> completed;

  /// The tail currently being streamed; re-rendered on every update.
  final String open;
}

class BlockSplitter {
  const BlockSplitter._();

  static final _fence = RegExp(r'^\s*(```|~~~)');

  static BlockSplit split(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    if (normalized.isEmpty) return const BlockSplit(completed: [], open: '');

    final lines = normalized.split('\n');
    final completed = <String>[];
    final current = <String>[];
    var inFence = false;

    for (final line in lines) {
      if (_fence.hasMatch(line)) inFence = !inFence;

      if (!inFence && line.trim().isEmpty) {
        if (current.any((l) => l.trim().isNotEmpty)) {
          completed.add(current.join('\n').trimRight());
        }
        current.clear();
        continue;
      }
      current.add(line);
    }

    final open = current.join('\n');
    return BlockSplit(
      completed: completed,
      // a fully completed buffer leaves an empty open block
      open: open.trim().isEmpty ? '' : open,
    );
  }
}
