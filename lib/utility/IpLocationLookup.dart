import 'dart:convert';

import 'package:http/http.dart' as http;

/// A coarse location inferred from the caller's IP address.
///
/// [accuracyRadiusMeters] is how far the real position might plausibly be from
/// [latitude]/[longitude]. IP geolocation resolves to a city or an ISP's
/// regional hub, not a street, so this is deliberately large — the map uses it
/// to pick a zoom that keeps both the placed marker and the user's actual
/// surroundings on screen.
class IpLocationEstimate {
  const IpLocationEstimate({
    required this.latitude,
    required this.longitude,
    required this.accuracyRadiusMeters,
    this.city,
    this.source = '',
  });

  final double latitude;
  final double longitude;
  final double accuracyRadiusMeters;
  final String? city;

  /// Which provider answered, for logging.
  final String source;

  @override
  String toString() => 'IpLocationEstimate(${city ?? 'unknown city'} '
      '$latitude, $longitude ±${(accuracyRadiusMeters / 1000).round()}km '
      'via $source)';
}

/// Looks up an approximate location from the caller's IP address.
///
/// Used when a user declines to share precise location: we still need to put
/// their marker somewhere meaningful, and a city-level estimate beats the
/// random world coordinate the app used to fall back to.
///
/// Providers are tried in order until one answers, because these are free,
/// unauthenticated endpoints — any single one can rate-limit, go down, or be
/// blocked by a network. Every failure mode (no network, timeout, rate limit,
/// malformed body, reserved-range IP) resolves to `null`, and the caller falls
/// back to its own default rather than surfacing an error.
class IpLocationLookup {
  IpLocationLookup({
    http.Client? client,
    List<Uri>? endpoints,
    this.requestTimeout = const Duration(seconds: 4),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        endpoints = endpoints ?? defaultEndpoints;

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final List<Uri> endpoints;

  /// HTTPS + CORS-enabled and usable without an API key, so the same call works
  /// from the web build and from mobile.
  static final List<Uri> defaultEndpoints = <Uri>[
    Uri.parse('https://ipwho.is/'),
    Uri.parse('https://ipapi.co/json/'),
  ];

  /// Assumed uncertainty when a provider does not report one. IP geolocation is
  /// typically city-accurate, with a long tail for mobile carriers and VPNs;
  /// 50 km keeps the map wide enough that the user's real surroundings are
  /// usually still in frame.
  static const double defaultAccuracyRadiusMeters = 50000;

  Future<IpLocationEstimate?> lookup() async {
    for (final Uri endpoint in endpoints) {
      try {
        final http.Response response = await _client
            .get(endpoint, headers: const {'Accept': 'application/json'})
            .timeout(requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          print('IP lookup ${endpoint.host} returned ${response.statusCode}');
          continue;
        }
        final IpLocationEstimate? estimate =
            parseResponse(response.body, source: endpoint.host);
        if (estimate != null) {
          print('IP lookup succeeded: $estimate');
          return estimate;
        }
        print('IP lookup ${endpoint.host} returned no usable location');
      } catch (e) {
        print('IP lookup ${endpoint.host} failed: $e');
      }
    }
    return null;
  }

  /// Parses a provider's JSON body, or returns null when it carries no usable
  /// location.
  ///
  /// One parser covers every supported provider: they all report `latitude` /
  /// `longitude` at the top level and flag failure with either `success: false`
  /// (ipwho.is) or `error: true` (ipapi.co). Coordinates may arrive as numbers
  /// or as strings, and `0, 0` is treated as "unknown" rather than a point in
  /// the Atlantic — providers use it for reserved and unroutable addresses.
  static IpLocationEstimate? parseResponse(String body, {String source = ''}) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      if (decoded['success'] == false) return null;
      if (decoded['error'] == true) return null;
      if (decoded['error'] is Map) return null;

      final double? latitude = _asDouble(decoded['latitude']);
      final double? longitude = _asDouble(decoded['longitude']);
      if (latitude == null || longitude == null) return null;
      if (latitude < -90 || latitude > 90) return null;
      if (longitude < -180 || longitude > 180) return null;
      if (latitude == 0 && longitude == 0) return null;

      final double radius = _asDouble(decoded['accuracy_radius_meters']) ??
          defaultAccuracyRadiusMeters;

      final Object? city = decoded['city'];
      return IpLocationEstimate(
        latitude: latitude,
        longitude: longitude,
        accuracyRadiusMeters: radius > 0 ? radius : defaultAccuracyRadiusMeters,
        city: city is String && city.isNotEmpty ? city : null,
        source: source,
      );
    } catch (_) {
      return null;
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      final double result = value.toDouble();
      return result.isFinite ? result : null;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value);
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
