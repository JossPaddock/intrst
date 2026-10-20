import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A remembered map camera: where the user was last exploring, and how far in.
///
/// The map restores this on every launch so the app never replays the
/// "whole world, then fly to you" sequence. A snapshot is only ever produced
/// from values that pass [isValidLatitude]/[isValidLongitude]/[isValidZoom],
/// so a corrupt or truncated preference can never position the camera
/// somewhere nonsensical — decoding simply yields null and the caller falls
/// back to its own default.
class MapCameraSnapshot {
  const MapCameraSnapshot({
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  final double latitude;
  final double longitude;
  final double zoom;

  /// Mirrors the map's `minMaxZoomPreference`; a stored zoom outside this
  /// range is clamped rather than discarded (the location is still useful).
  static const double minZoom = 3.0;
  static const double maxZoom = 900.0;

  /// Camera moves smaller than these are treated as "the same view" and do not
  /// trigger a write. ~1e-5 degrees is roughly a metre.
  static const double _latLngEpsilon = 1e-5;
  static const double _zoomEpsilon = 0.01;

  static bool isValidLatitude(double value) =>
      value.isFinite && value >= -90.0 && value <= 90.0;

  static bool isValidLongitude(double value) =>
      value.isFinite && value >= -180.0 && value <= 180.0;

  static bool isValidZoom(double value) => value.isFinite;

  CameraPosition toCameraPosition() => CameraPosition(
        target: LatLng(latitude, longitude),
        zoom: zoom,
      );

  static MapCameraSnapshot? fromCameraPosition(CameraPosition position) =>
      create(
        latitude: position.target.latitude,
        longitude: position.target.longitude,
        zoom: position.zoom,
      );

  /// Builds a snapshot, or null when the coordinates are unusable. Zoom is
  /// clamped into [minZoom]..[maxZoom].
  static MapCameraSnapshot? create({
    required double latitude,
    required double longitude,
    required double zoom,
  }) {
    if (!isValidLatitude(latitude)) return null;
    if (!isValidLongitude(longitude)) return null;
    if (!isValidZoom(zoom)) return null;
    return MapCameraSnapshot(
      latitude: latitude,
      longitude: longitude,
      zoom: zoom.clamp(minZoom, maxZoom).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': latitude,
        'lng': longitude,
        'zoom': zoom,
      };

  String encode() => jsonEncode(toJson());

  /// Rebuilds a snapshot from [json], or null when anything is missing,
  /// non-numeric, or out of range.
  static MapCameraSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final double? lat = _asDouble(json['lat']);
    final double? lng = _asDouble(json['lng']);
    final double? zoom = _asDouble(json['zoom']);
    if (lat == null || lng == null || zoom == null) return null;
    return create(latitude: lat, longitude: lng, zoom: zoom);
  }

  /// Decodes the stored JSON string. Malformed input yields null.
  static MapCameraSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// True when [other] shows essentially the same view, i.e. re-persisting
  /// would be a wasted write.
  bool isSameViewAs(MapCameraSnapshot? other) {
    if (other == null) return false;
    return (latitude - other.latitude).abs() < _latLngEpsilon &&
        (longitude - other.longitude).abs() < _latLngEpsilon &&
        (zoom - other.zoom).abs() < _zoomEpsilon;
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      final double result = value.toDouble();
      return result.isFinite ? result : null;
    }
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  String toString() =>
      'MapCameraSnapshot(lat: $latitude, lng: $longitude, zoom: $zoom)';
}

/// Persists the last map camera across app launches.
///
/// Every operation is best-effort: if the platform has no preference store
/// (tests, web privacy modes) the map simply falls back to its default
/// starting position instead of failing.
class MapCameraMemory {
  const MapCameraMemory();

  static const String storageKey = 'intrst_map_last_camera_v1';

  Future<MapCameraSnapshot?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return MapCameraSnapshot.decode(prefs.getString(storageKey));
    } catch (e) {
      print('Failed to load remembered map camera: $e');
      return null;
    }
  }

  Future<void> save(MapCameraSnapshot snapshot) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, snapshot.encode());
    } catch (e) {
      print('Failed to persist map camera: $e');
    }
  }

  Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (e) {
      print('Failed to clear remembered map camera: $e');
    }
  }
}
