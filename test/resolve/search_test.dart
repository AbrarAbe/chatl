import 'package:chatl/src/resolve/search.dart';
import 'package:test/test.dart';

void main() {
  group('@search resolver (Task 1.1)', () {
    test('missing backend fails visibly', () async {
      final resolver = SearchResolver(backend: null);
      final result = await resolver.resolve('test query');
      expect(result.failures, hasLength(1));
      expect(result.failures.first.source, 'search');
      expect(result.requestContent, contains('[CONTEXT ERROR source=search'));
    });

    test('returns snippets with query', () async {
      final resolver = SearchResolver(
        backend: FakeSearchBackend(
          results: [
            SearchResult(
              title: 'Result 1',
              url: 'https://example.com/1',
              snippet: 'Snippet 1 text',
            ),
            SearchResult(
              title: 'Result 2',
              url: 'https://example.com/2',
              snippet: 'Snippet 2 text',
            ),
          ],
        ),
      );
      final result = await resolver.resolve('test query');
      expect(result.requestContent, contains('[CONTEXT source="search"'));
      expect(result.requestContent, contains('Result 1'));
      expect(result.requestContent, contains('Result 2'));
      expect(result.requestContent, contains('[/CONTEXT]'));
    });
  });
}

class FakeSearchBackend implements SearchBackend {
  final List<SearchResult> results;

  FakeSearchBackend({required this.results});

  @override
  Future<List<SearchResult>> search(String query) async {
    return results;
  }
}
