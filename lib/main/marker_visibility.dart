import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pure marker visibility/label logic, lifted out of `_HomeMapLogic` so it can
/// be exercised without a widget tree. Everything here takes its inputs as
/// parameters and returns a value — no `State`, no `setState`.
class MarkerVisibility {
  MarkerVisibility._();

  /// Zoom at or above which labels are considered at all.
  static const double minLabelZoom = 2.0;

  /// Markers further than this from any neighbour are always labelled,
  /// regardless of zoom.
  static const double alwaysLabelDistance = 1000000; // 1000km

  // Label markers carry this suffix on their MarkerId so they can be shown on
  // top of the always-visible POI marker (which uses the bare uid) instead of
  // replacing it.
  static const String labelIdSuffix = '_label';

  static String labelMarkerId(String uid) => '$uid$labelIdSuffix';

  static String uidFromLabelMarkerId(String labelMarkerId) =>
      labelMarkerId.endsWith(labelIdSuffix)
          ? labelMarkerId.substring(
              0, labelMarkerId.length - labelIdSuffix.length)
          : labelMarkerId;

  /// Great-circle distance between two points, in meters.
  static double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000;

    double lat1Rad = point1.latitude * pi / 180;
    double lat2Rad = point2.latitude * pi / 180;
    double deltaLat = (point2.latitude - point1.latitude) * pi / 180;
    double deltaLng = (point2.longitude - point1.longitude) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Distance (meters) below which two markers read as visually overlapping at
  /// [zoom]. Hand-tuned per zoom level rather than computed.
  static double visualProximityThreshold(double zoom) {
    switch (zoom.floor()) {
      case 3: return 900000;
      case 4: return 350000;
      case 5: return 90000;
      case 6: return 87664.062;
      case 7: return 43832.031;
      case 8: return 21916.016;
      case 9: return 10958;
      case 10: return 5479;
      case 11: return 2739;
      case 12: return 1369;
      case 13: return 684;
      case 14: return 342;
      case 15: return 171;
      case 16: return 85;
      case 17: return 42;
      case 18: return 21;
      case 19: return 10;
      case 20: return 10;
      case 21: return 10;
      default:
        if (zoom < 3) return 701312.5;
        return 10;
    }
  }

  /// Uids of the POI markers that are isolated enough at [currentZoom] to be
  /// drawn with their name label. [filteredUids] (when non-null and non-empty)
  /// restricts the computation to the currently visible markers.
  static Set<String> markersToShowAsLabels(
    Set<Marker> poiMarkers,
    double currentZoom, {
    List<String>? filteredUids,
  }) {
    Set<String> showAsLabels = {};

    double proximityThreshold = visualProximityThreshold(currentZoom);

    List<MapEntry<String, LatLng>> markerPositions = [];
    for (var marker in poiMarkers) {
      if (filteredUids == null ||
          filteredUids.isEmpty ||
          filteredUids.contains(marker.markerId.value)) {
        markerPositions.add(MapEntry(marker.markerId.value, marker.position));
      }
    }

    int n = markerPositions.length;

    for (int i = 0; i < n; i++) {
      double minDistanceToAnyMarker = double.infinity;
      LatLng p1 = markerPositions[i].value;

      for (int j = 0; j < n; j++) {
        if (i == j) continue;

        LatLng p2 = markerPositions[j].value;

        double latDelta = (p1.latitude - p2.latitude).abs();
        double lngDelta = (p1.longitude - p2.longitude).abs();

        if (latDelta > 10 || lngDelta > 10) {
          continue;
        }

        double distance = calculateDistance(p1, p2);

        if (distance < minDistanceToAnyMarker) {
          minDistanceToAnyMarker = distance;
          if (currentZoom >= minLabelZoom && distance < proximityThreshold) {
            break;
          }
        }
      }

      if (minDistanceToAnyMarker > alwaysLabelDistance) {
        showAsLabels.add(markerPositions[i].key);
      } else if (currentZoom >= minLabelZoom &&
          minDistanceToAnyMarker >= proximityThreshold) {
        showAsLabels.add(markerPositions[i].key);
      }
    }

    print(
        'At zoom $currentZoom: ${showAsLabels.length} markers shown as labels, ${markerPositions.length - showAsLabels.length} as POI');
    return showAsLabels;
  }

  /// Whether a marker (by uid) should be visible given the active search term
  /// and relationship filter. [relationshipUids] is the resolved relationship
  /// filter (null means "show everyone").
  static bool markerVisible(
    String uid, {
    required String searchTerm,
    required List<String> searchFilteredResults,
    Set<String>? relationshipUids,
  }) {
    if (searchTerm.isNotEmpty && !searchFilteredResults.contains(uid)) {
      return false;
    }
    if (relationshipUids != null && !relationshipUids.contains(uid)) {
      return false;
    }
    return true;
  }

  /// The full marker set to hand the map at [zoom].
  ///
  /// [relationshipUids] is the relationship-filter set (null = show everyone);
  /// it is ignored while a search is active so search results behave as if no
  /// filters are applied.
  ///
  /// With [useOriginalMarkerBehavior], POI and label are mutually exclusive —
  /// a marker shows as a label when it is isolated enough, otherwise as a POI
  /// dot. Otherwise POI markers are always shown and labels are layered on top.
  ///
  /// [soloUid] is "marker move mode": while the user is repositioning their own
  /// marker every other marker is hidden, and their label is dropped too so
  /// nothing sits on top of the dot they are dragging.
  static Set<Marker> buildVisibleMarkers({
    required Set<Marker> poiMarkers,
    required Set<Marker> labelMarkers,
    required double zoom,
    required String searchTerm,
    required List<String> searchFilteredResults,
    Set<String>? relationshipUids,
    bool useOriginalMarkerBehavior = false,
    String? soloUid,
  }) {
    if (soloUid != null && soloUid.isNotEmpty) {
      return poiMarkers
          .where((marker) => marker.markerId.value == soloUid)
          .toSet();
    }

    // While searching, ignore the relationship filters.
    final Set<String>? relUids = searchTerm.isEmpty ? relationshipUids : null;

    bool visible(String uid) => markerVisible(
          uid,
          searchTerm: searchTerm,
          searchFilteredResults: searchFilteredResults,
          relationshipUids: relUids,
        );

    // Effective visible-uid filter (search ∩ relationship) used by the label
    // proximity computation. Null means no filtering is active.
    List<String>? visibleFilter;
    if (searchTerm.isNotEmpty || relUids != null) {
      visibleFilter = poiMarkers
          .map((marker) => marker.markerId.value)
          .where(visible)
          .toList();
    }

    final Set<String> showAsLabels =
        markersToShowAsLabels(poiMarkers, zoom, filteredUids: visibleFilter);

    final Set<Marker> result = {};

    if (useOriginalMarkerBehavior) {
      if (zoom < minLabelZoom) {
        result.addAll(
            poiMarkers.where((marker) => visible(marker.markerId.value)));
      } else {
        result.addAll(labelMarkers.where((marker) {
          final String uid = uidFromLabelMarkerId(marker.markerId.value);
          return visible(uid) && showAsLabels.contains(uid);
        }));
        result.addAll(poiMarkers.where((marker) =>
            visible(marker.markerId.value) &&
            !showAsLabels.contains(marker.markerId.value)));
      }
    } else {
      // POI markers are always shown (within the active filter)...
      result
          .addAll(poiMarkers.where((marker) => visible(marker.markerId.value)));

      // ...and label markers are layered on top, shown/hidden by the same
      // zoom + proximity logic as before.
      if (zoom >= minLabelZoom) {
        result.addAll(labelMarkers.where((marker) {
          final String uid = uidFromLabelMarkerId(marker.markerId.value);
          return visible(uid) && showAsLabels.contains(uid);
        }));
      }
    }

    return result;
  }
}
