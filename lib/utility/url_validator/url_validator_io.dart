import 'dart:io';

Future<bool> isUrlResolvable(String url) async {
  HttpClient? client;
  try {
    final uri = Uri.parse(url);

    client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    HttpClientResponse response;

    try {
      final request = await client.openUrl('HEAD', uri);
      response = await request.close();
    } catch (_) {
      final request = await client.getUrl(uri);
      response = await request.close();
    }

    return response.statusCode >= 200 && response.statusCode < 400;
  } catch (_) {
    return false;
  } finally {
    client?.close();
  }
}
