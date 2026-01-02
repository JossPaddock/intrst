import 'dart:html';

Future<bool> isUrlResolvable(String url) async {
  try {
    final request = await HttpRequest.request(
      url,
      method: 'HEAD',
      requestHeaders: {
        'Accept': '*/*',
      },
    );

    return request.status != null &&
        request.status! >= 200 &&
        request.status! < 400;
  } catch (_) {
    return false;
  }
}
