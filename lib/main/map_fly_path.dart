import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A smooth "fly to" camera path between two map views.
///
/// This is van Wijk & Nuij's smooth zoom-and-pan path, the same curve as
/// d3's `interpolateZoom` and Mapbox's `flyTo`. A short hop just glides across.
/// A long one zooms out, crosses at a height where the ground moves at a
/// comfortable speed, then zooms back in, so the ride never turns into a
/// smear of tiles.
///
/// It exists because the web maps plugin implements `animateCamera` as a plain
/// `moveCamera`, which jumps. On web the app drives the camera itself, sampling
/// [at] once per frame. Everything here is pure math, with no map or widget
/// involved.
class MapFlyPath {
  MapFlyPath._(this._from, this._to, this._sample, this._length);

  /// Builds the path from ([from], [fromZoom]) to ([to], [toZoom]).
  ///
  /// [viewportPixels] is the size of the map on screen. It decides how far
  /// apart two points "feel": the same hop is a short glide on a big screen
  /// and a zoom-out on a small one.
  factory MapFlyPath({
    required LatLng from,
    required double fromZoom,
    required LatLng to,
    required double toZoom,
    double viewportPixels = 400,
  }) {
    final CameraPosition start = CameraPosition(target: from, zoom: fromZoom);
    final CameraPosition end = CameraPosition(target: to, zoom: toZoom);
    final double viewport =
        viewportPixels.isFinite && viewportPixels > 0 ? viewportPixels : 400;

    final math.Point<double> p0 = _project(from);
    final math.Point<double> p1raw = _project(to);
    // Cross the antimeridian when that is the shorter way round, e.g. Tokyo to
    // Honolulu. The overshooting longitude is wrapped back by LatLng.
    double x1 = p1raw.x;
    if (x1 - p0.x > _worldSize / 2) x1 -= _worldSize;
    if (p0.x - x1 > _worldSize / 2) x1 += _worldSize;

    final double ux0 = p0.x, uy0 = p0.y, ux1 = x1, uy1 = p1raw.y;
    // Width of the viewport in world units at each end.
    final double w0 = viewport / math.pow(2, fromZoom);
    final double w1 = viewport / math.pow(2, toZoom);
    final double dx = ux1 - ux0, dy = uy1 - uy0;
    final double d2 = dx * dx + dy * dy;

    CameraPosition fromWorld(double x, double y, double w) => CameraPosition(
          target: _unproject(x, y),
          zoom: math.log(viewport / w) / math.ln2,
        );

    late final CameraPosition Function(double) sample;
    late final double length;

    if (d2 < _epsilon2) {
      // Same spot: a pure zoom (or nothing at all).
      final double signedLength = math.log(w1 / w0) / _rho;
      length = signedLength.abs();
      sample = (double t) => fromWorld(
            ux0 + t * dx,
            uy0 + t * dy,
            w0 * math.exp(_rho * t * signedLength),
          );
    } else {
      final double d1 = math.sqrt(d2);
      final double b0 =
          (w1 * w1 - w0 * w0 + _rho4 * d2) / (2 * w0 * _rho2 * d1);
      final double b1 =
          (w1 * w1 - w0 * w0 - _rho4 * d2) / (2 * w1 * _rho2 * d1);
      // log(sqrt(b^2 + 1) - b), written as -asinh(b) so a far hop from a
      // close zoom (huge b) doesn't cancel down to log(0).
      final double r0 = -_asinh(b0);
      final double r1 = -_asinh(b1);
      length = (r1 - r0) / _rho;
      sample = (double t) {
        final double s = t * length;
        final double u =
            w0 / (_rho2 * d1) * (_cosh(r0) * _tanh(_rho * s + r0) - _sinh(r0));
        return fromWorld(
          ux0 + u * dx,
          uy0 + u * dy,
          w0 * _cosh(r0) / _cosh(_rho * s + r0),
        );
      };
    }

    return MapFlyPath._(start, end, sample, length);
  }

  /// The curve's zoom-versus-pan trade-off: higher means it zooms out more
  /// on the way. sqrt(2) is the value the paper recommends and what d3 uses.
  static const double _rho = math.sqrt2;
  static const double _rho2 = 2;
  static const double _rho4 = 4;
  static const double _epsilon2 = 1e-12;

  /// How fast the camera moves along the path, in path-length units (about
  /// one screenful each) per second. Tuned so a hop across town takes
  /// [minDuration], a cross-country one about two seconds, and only the far
  /// side of the world reaches [maxDuration]. (Mapbox's flyTo default of 1.2
  /// would make that cross-country hop take about eight seconds.)
  static const double _speed = 4.5;

  /// A flight never takes less or more than this. Below the floor the camera
  /// would still look like it snapped, and above the ceiling a
  /// round-the-world hop would feel like waiting.
  static const Duration minDuration = Duration(milliseconds: 600);
  static const Duration maxDuration = Duration(milliseconds: 2400);

  /// Width of the Web Mercator world at zoom 0, in Google's 256px tiles.
  static const double _worldSize = 256;

  final CameraPosition _from;
  final CameraPosition _to;
  final CameraPosition Function(double) _sample;

  /// Length of the path in the curve's own units (roughly screenfuls).
  final double _length;

  /// True when the camera is already where it needs to be.
  bool get isEmpty => _length.abs() < 1e-6;

  /// How long the flight should take, scaled to how far it travels.
  Duration get duration {
    if (isEmpty) return Duration.zero;
    final int micros = (_length.abs() / _speed * 1e6).round();
    return Duration(
      microseconds:
          micros.clamp(minDuration.inMicroseconds, maxDuration.inMicroseconds),
    );
  }

  /// The camera at [t] along the path, where 0 is the start and 1 is the end.
  /// [t] is clamped, and both ends return the exact requested positions.
  CameraPosition at(double t) {
    if (t <= 0) return _from;
    if (t >= 1 || isEmpty) return _to;
    return _sample(t);
  }

  static math.Point<double> _project(LatLng point) {
    final double siny =
        math.sin(point.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
    return math.Point<double>(
      (point.longitude + 180) / 360 * _worldSize,
      (0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi)) * _worldSize,
    );
  }

  static LatLng _unproject(double x, double y) {
    final double n = math.pi * (1 - 2 * y / _worldSize);
    final double latitude =
        (2 * math.atan(math.exp(n)) - math.pi / 2) * 180 / math.pi;
    return LatLng(latitude, x / _worldSize * 360 - 180);
  }

  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _tanh(double x) {
    // exp(2x) overflows long before tanh stops being exactly ±1.
    if (x > 20) return 1;
    if (x < -20) return -1;
    final double e2 = math.exp(2 * x);
    return (e2 - 1) / (e2 + 1);
  }

  static double _asinh(double x) =>
      x < 0 ? -_asinh(-x) : math.log(x + math.sqrt(x * x + 1));
}
