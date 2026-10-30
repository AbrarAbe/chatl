import 'dart:async';
import 'dart:convert';

import 'package:chatl/src/resolve/fetch.dart';
import 'package:chatl/src/resolve/firecrawl_fetch.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('@fetch resolver (Task 1.2)', () {
    test('missing backend fails visibly', () async {
      final resolver = FetchResolver(backend: null);
      final result = await resolver.resolve('https://example.com');
      expect(result.failures, hasLength(1));
      expect(result.failures.first.source, 'fetch');
      expect(result.requestContent, contains('[CONTEXT ERROR source=fetch'));
    });

    test('returns extracted content with URL', () async {
      final resolver = FetchResolver(
        backend: FakeFetchBackend(
          result: FetchResult(url: 'https://example.com', body: 'Extracted page text content.'),
        ),
      );
      final result = await resolver.resolve('https://example.com');
      expect(result.requestContent, contains('[CONTEXT source="https://example.com"'));
      expect(result.requestContent, contains('Extracted page text content'));
      expect(result.requestContent, contains('[/CONTEXT]'));
      expect(result.requestContent, contains('Q: https://example.com'));
    });

    test('backend failure produces visible error block', () async {
      final resolver = FetchResolver(backend: _FailingFetchBackend());
      final result = await resolver.resolve('https://example.com');
      expect(result.failures, hasLength(1));
      expect(result.requestContent, contains('[CONTEXT ERROR source=fetch'));
      expect(result.requestContent, contains('reader crashed'));
    });

    test('truncates oversized content with visible notice', () async {
      final longBody = 'y' * 200_000;
      final resolver = FetchResolver(
        backend: FakeFetchBackend(
          result: FetchResult(url: 'https://example.com', body: longBody),
        ),
        maxBytes: 100,
      );
      final result = await resolver.resolve('https://example.com');
      expect(result.requestContent, contains('[... truncated:'));
      expect(result.requestContent, contains('bytes over cap'));
      expect(result.requestContent, isNot(contains(longBody)));
    });
  });

  group('FirecrawlFetchBackend', () {
    test('extracts markdown from successful scrape response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v0/scrape');
        expect(request.headers['authorization'], 'Bearer test-key');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'markdown': '# Example\n\nSome content here.'},
          }),
          200,
        );
      });

      final backend = FirecrawlFetchBackend(apiKey: 'test-key', client: client);
      final result = await backend.fetch('https://example.com');

      expect(result.url, 'https://example.com');
      expect(result.body, '# Example\n\nSome content here.');
    });

    test('throws on non-2xx response', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'success': false, 'error': 'rate limited'}), 429);
      });

      final backend = FirecrawlFetchBackend(apiKey: 'test-key', client: client);
      expect(
        () async => backend.fetch('https://example.com'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Firecrawl scrape failed'),
          ),
        ),
      );
    });

    test('throws when success is false', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'success': false, 'error': 'invalid URL'}), 200);
      });

      final backend = FirecrawlFetchBackend(apiKey: 'test-key', client: client);
      expect(
        () async => backend.fetch('https://example.com'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Firecrawl scrape failed'),
          ),
        ),
      );
    });

    test('throws when no markdown returned', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'success': true, 'data': {}}), 200);
      });

      final backend = FirecrawlFetchBackend(apiKey: 'test-key', client: client);
      expect(
        () async => backend.fetch('https://example.com'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('no markdown'))),
      );
    });

    test('times out when the scrape hangs', () async {
      final client = MockClient((request) async {
        // Never completes — simulates a hanging Firecrawl API.
        await Future<void>.delayed(const Duration(hours: 1));
        return http.Response('{}', 200);
      });

      final backend = FirecrawlFetchBackend(apiKey: 'test-key', client: client);
      expect(
        () async => backend.fetch('https://example.com'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('timed out'))),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

class FakeFetchBackend implements FetchBackend {
  final FetchResult result;

  FakeFetchBackend({required this.result});

  @override
  Future<FetchResult> fetch(String url) async {
    return result;
  }
}

class _FailingFetchBackend implements FetchBackend {
  @override
  Future<FetchResult> fetch(String url) async {
    throw Exception('reader crashed');
  }
}
