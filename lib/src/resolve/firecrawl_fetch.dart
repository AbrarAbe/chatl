/// Firecrawl-backed `@fetch` resolver backend.
///
/// Uses the Firecrawl `/scrape` API to extract markdown from a URL without
/// requiring a shell reader binary. Configure `fetch.type: firecrawl` and
/// `fetch.api_key` (or `$FIRECRAWL_API_KEY`) in config.
///
/// Firecrawl API: POST https://api.firecrawl.dev/v0/scrape
///   Headers: Authorization: Bearer \`api-key\`, Content-Type: application/json
///   Body:    {"url": "`url`", "formats": ["markdown"]}
///   Response: {"success": true, "data": {"markdown": "...", ...}}
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fetch.dart';

/// A `FetchBackend` that uses the Firecrawl scrape API to extract markdown
/// from a URL.
class FirecrawlFetchBackend implements FetchBackend {
  /// Creates a Firecrawl-backed fetch backend.
  ///
  /// [apiKey] is the Firecrawl API key. [baseUrl] overrides the API origin
  /// (defaults to `https://api.firecrawl.dev`). [client] is the HTTP client
  /// used for requests (defaults to a real `http.Client`).
  FirecrawlFetchBackend({required this.apiKey, this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final String? baseUrl;
  final http.Client _client;

  @override
  Future<FetchResult> fetch(String url) async {
    final uri = Uri.parse('${baseUrl ?? 'https://api.firecrawl.dev'}/v0/scrape');
    final request = http.Request('POST', uri)
      ..headers['content-type'] = 'application/json'
      ..headers['authorization'] = 'Bearer $apiKey'
      ..body = jsonEncode({
        'url': url,
        'formats': ['markdown'],
      });

    final response = await _client.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      throw Exception('Firecrawl scrape failed (${response.statusCode}): $body');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw Exception('Firecrawl scrape failed: ${decoded['error'] ?? body}');
    }

    final data = decoded['data'] as Map<String, dynamic>;
    final markdown = data['markdown'] as String?;

    if (markdown == null || markdown.isEmpty) {
      throw Exception('Firecrawl returned no markdown for $url');
    }

    return FetchResult(url: url, body: markdown);
  }
}
