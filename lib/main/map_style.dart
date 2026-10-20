import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_camera_memory.dart';

/// The single definition of how an intrst map looks and behaves.
///
/// Every `GoogleMap` in the app — the signed-in map, the signed-out map, and
/// the marker-placement maps in the sign-up wizard — must render with the same
/// palette, or the wizard's map reads as a different product than the one the
/// user is about to enter.
class IntrstMapStyle {
  const IntrstMapStyle._();

  /// The Google Cloud–hosted map style applied to every map in the app.
  ///
  /// The styling lives in the Google Cloud console against this id rather than
  /// in a local JSON blob, so changing the palette does not need an app
  /// release. A map built without it falls back to Google's default styling,
  /// which is why this is passed everywhere rather than only on the main map.
  static const String cloudMapId = 'bc8e2917cca03ad4';

  /// The zoom range every map is held to, matching the bounds
  /// [MapCameraSnapshot] clamps remembered cameras into — so a camera saved on
  /// one map is always reachable on another.
  static MinMaxZoomPreference get zoomRange => const MinMaxZoomPreference(
        MapCameraSnapshot.minZoom,
        MapCameraSnapshot.maxZoom,
      );
}
