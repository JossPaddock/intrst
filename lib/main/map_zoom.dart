import 'dart:math' as math;

/// Web Mercator zoom arithmetic.
///
/// Used when the app places a marker it is not certain about — currently an
/// IP-derived position, where the user's real surroundings may be tens of
/// kilometres away. Rather than guessing a zoom, we pick the one that puts the
/// whole uncertainty radius on screen, so the marker *and* wherever the user
/// actually is are both visible without them having to pinch out.
class MapZoom {
  const MapZoom._();

  /// Ground resolution at zoom 0 on the equator, in metres per pixel, for the
  /// 256-pixel tiles Google Maps uses: earth circumference / 256.
  static const double metersPerPixelAtZoomZero = 156543.03392;

  /// Never zoom further out than the map itself allows.
  static const double minZoom = 3.0;

  /// Never zoom *in* past a city view on an estimated position, however small
  /// the radius claims to be — precision we don't have would be misleading.
  static const double maxEstimatedZoom = 12.0;

  /// The zoom at which a circle of [radiusMeters] around a point at
  /// [latitude] fits within a viewport of [viewportPixels] on its shorter side.
  ///
  /// Derivation: at zoom z the ground resolution is
  /// `metersPerPixelAtZoomZero * cos(latitude) / 2^z`. Fitting the radius into
  /// half the viewport gives
  /// `2^z <= viewportPixels * metersPerPixelAtZoomZero * cos(latitude) /
  /// (2 * radiusMeters)`.
  ///
  /// The `cos(latitude)` term matters: a degree of longitude covers far less
  /// ground near the poles, so the same radius needs a wider zoom there.
  ///
  /// The result is clamped to [minZoom]..[maxEstimatedZoom]. Non-finite or
  /// non-positive inputs fall back to [minZoom] rather than throwing, since
  /// this feeds a camera position during start-up.
  static double forRadius({
    required double radiusMeters,
    required double latitude,
    required double viewportPixels,
  }) {
    if (!radiusMeters.isFinite || radiusMeters <= 0) return maxEstimatedZoom;
    if (!viewportPixels.isFinite || viewportPixels <= 0) return minZoom;
    if (!latitude.isFinite || latitude.abs() > 90) return minZoom;

    final double cosLatitude = math.cos(latitude * math.pi / 180.0);
    if (cosLatitude <= 0) return minZoom;

    final double ratio = (viewportPixels * metersPerPixelAtZoomZero *
            cosLatitude) /
        (2 * radiusMeters);
    if (ratio <= 0) return minZoom;

    final double zoom = math.log(ratio) / math.ln2;
    if (!zoom.isFinite) return minZoom;
    return zoom.clamp(minZoom, maxEstimatedZoom).toDouble();
  }
}
