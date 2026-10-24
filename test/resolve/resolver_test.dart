import 'package:chatl/src/resolve/resolver.dart';
import 'package:test/test.dart';

/// A fake resolver: records invocations, returns a canned block or throws.
class _FakeResolver {
  _FakeResolver({this.takesArgument = true, this.result, this.throws = false});

  final bool takesArgument;
  final String? result;
  final bool throws;
  final calls = <String?>[];

  ResolverEntry get entry => ResolverEntry(
    name: 'fake',
    takesArgument: takesArgument,
    resolve: (argument) async {
      calls.add(argument);
      if (throws) throw Exception('backend down');
      return ContextBlock(source: 'fake:$argument', body: result ?? 'BODY');
    },
  );
}

void main() {
  group('MentionResolver (spec §The @ resolver layer)', () {
    test('with no resolvers, @ text passes through literally', () async {
      final resolver = MentionResolver(entries: const []);
      final result = await resolver.resolve(
        '@fetch https://x — is this a scam?',
      );

      expect(result.blocks, isEmpty);
      expect(result.failures, isEmpty);
      expect(result.requestContent, '@fetch https://x — is this a scam?');
    });

    test(
      'unknown @tokens pass through even when other resolvers exist',
      () async {
        final fake = _FakeResolver();
        final resolver = MentionResolver(entries: [fake.entry]);

        final result = await resolver.resolve('@other https://x');

        expect(fake.calls, isEmpty);
        expect(result.blocks, isEmpty);
        expect(result.requestContent, '@other https://x');
      },
    );

    test('email addresses are not mentions', () async {
      final fake = _FakeResolver();
      final resolver = MentionResolver(entries: [fake.entry]);

      final result = await resolver.resolve('mail me at a@fake.com please');

      expect(fake.calls, isEmpty);
      expect(result.requestContent, 'mail me at a@fake.com please');
    });

    test(
      'a registered mention expands into a context block plus the question',
      () async {
        final fake = _FakeResolver(result: 'extracted page text');
        final resolver = MentionResolver(entries: [fake.entry]);

        final result = await resolver.resolve(
          '@fake https://example.com — is this a scam?',
        );

        expect(fake.calls, ['https://example.com']);
        expect(result.blocks, hasLength(1));
        expect(result.blocks.single.source, 'fake:https://example.com');
        expect(
          result.requestContent,
          contains('[CONTEXT source="fake:https://example.com"'),
        );
        expect(result.requestContent, contains('extracted page text'));
        expect(result.requestContent, contains('[/CONTEXT]'));
        expect(
          result.requestContent.trim().endsWith('Q: is this a scam?'),
          isTrue,
        );
        // the syntax itself never survives into the request
        expect(result.requestContent.contains('@fake'), isFalse);
      },
    );

    test('argument-less resolvers do not swallow the next word', () async {
      final fake = _FakeResolver(takesArgument: false, result: '2026-09-27');
      final resolver = MentionResolver(entries: [fake.entry]);

      final result = await resolver.resolve('@fake what time is it?');

      expect(fake.calls, [null]);
      expect(result.requestContent.trim(), endsWith('Q: what time is it?'));
    });

    test('multiple mentions expand in appearance order', () async {
      final first = _FakeResolver(result: 'ONE');
      final second = ResolverEntry(
        name: 'second',
        takesArgument: true,
        resolve: (argument) async =>
            ContextBlock(source: 'second:$argument', body: 'TWO'),
      );
      final resolver = MentionResolver(entries: [first.entry, second]);

      final result = await resolver.resolve(
        '@fake a @second b — compare these',
      );

      expect(result.blocks.map((b) => b.body).toList(), ['ONE', 'TWO']);
    });

    test(
      'a failing resolver produces a visible error block, not a drop',
      () async {
        final broken = _FakeResolver(throws: true);
        final good = ResolverEntry(
          name: 'good',
          takesArgument: false,
          resolve: (_) async => const ContextBlock(source: 'good', body: 'OK'),
        );
        final resolver = MentionResolver(entries: [broken.entry, good]);

        final result = await resolver.resolve('@fake x @good — status?');

        expect(result.failures, hasLength(1));
        expect(result.failures.single.source, 'fake:x');
        expect(
          result.requestContent,
          contains('[CONTEXT ERROR source="fake:x"'),
        );
        expect(result.requestContent, contains('backend down'));
        expect(result.requestContent, contains('OK'));
      },
    );

    test('resolution is deterministic for the same input', () async {
      final fake = _FakeResolver();
      final resolver = MentionResolver(entries: [fake.entry]);

      final a = await resolver.resolve('@fake x — q');
      final b = await resolver.resolve('@fake x — q');

      expect(a.requestContent, b.requestContent);
    });

    test('bare @ and @ at line start with punctuation stay harmless', () async {
      final resolver = MentionResolver(entries: const []);
      for (final input in ['@', '@ ', 'ping @ then go', '(at)@']) {
        final result = await resolver.resolve(input);
        expect(result.requestContent, input, reason: 'input: $input');
      }
    });
  });
}
