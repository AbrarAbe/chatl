import 'dart:async';
import 'dart:convert';

/// Byte stream → string chunk stream for SSE (handles UTF-8 split across
/// chunks and CRLF normalization).
class SseDecoder extends StreamTransformerBase<List<int>, String> {
  const SseDecoder();

  @override
  Stream<String> bind(Stream<List<int>> stream) =>
      stream.transform(utf8.decoder).transform(const LineSplitter());
}

/// Line stream → SSE `data:` payloads.
///
/// Handles: comment lines (`:` keepalives), multi-line `data:` fields joined
/// with `\n`, blank-line event dispatch, and a trailing event without a
/// terminating blank line. `[DONE]` is passed through as a payload; the
/// caller interprets it.
class SseParser extends StreamTransformerBase<String, String> {
  const SseParser();

  @override
  Stream<String> bind(Stream<String> stream) {
    final buffer = StringBuffer();
    StreamController<String>? controller;

    void flush() {
      if (buffer.isEmpty) return;
      var text = buffer.toString();
      buffer.clear();
      // SSE: multiple data: lines join with '\n'; strip that joiner from the
      // trailing edge only if present.
      controller!.add(
        text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
      );
    }

    controller = StreamController<String>(
      onListen: () {
        stream.listen(
          (line) {
            if (line.startsWith(':')) return; // comment / keepalive
            if (line.isEmpty) {
              flush();
              return;
            }
            if (line.startsWith('data:')) {
              var value = line.substring(5);
              if (value.startsWith(' ')) value = value.substring(1);
              buffer.write(value);
              buffer.write('\n');
            }
            // Other fields (event:, id:, retry:) are ignored for chat SSE.
          },
          onDone: () {
            flush();
            controller!.close();
          },
          onError: controller!.addError,
        );
      },
    );
    return controller.stream;
  }
}
