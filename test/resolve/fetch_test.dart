import 'package:chatl/src/resolve/fetch.dart';
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
