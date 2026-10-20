import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/main/map_zoom.dart';
import 'package:intrst/utility/IpLocationLookup.dart';

/// Resolves a starting position for the wizard's location part.
///
/// Placement here is **IP-based only**: a city-level estimate, or a random
/// world point if even that fails. The OS location prompt is deliberately not
/// used during sign-up — it is slow, frequently returns nothing at all, and
/// blocks the flow while it does; the app still asks for precise location later
/// on the real map. The user drags the pin from wherever the estimate lands.
///
/// The ±0.015° jitter matches the rest of the app: markers are a social signal,
/// not a home address, and without it everyone behind one ISP would stack on a
/// single identical point.
class SignupLocationService {
  SignupLocationService({IpLocationLookup? ipLookup}) : _ipLookup = ipLookup;

  final IpLocationLookup? _ipLookup;

  static const double _jitterDegrees = 0.015;

  /// Hard ceiling on the whole estimate, on top of the per-provider timeouts
  /// inside [IpLocationLookup]. Nothing on this screen may run unbounded — a
  /// provider that accepts the connection and then never answers would
  /// otherwise leave the user watching a spinner with no way forward.
  static const Duration lookupBudget = Duration(seconds: 10);

  /// A city-level estimate from the caller's IP address. Needs no permission,
  /// which is the whole reason the wizard uses it: the map opens somewhere
  /// plausible with no dialog and no waiting on a GPS fix that may never come.
  ///
  /// [viewportPixels] is the shorter screen edge — the one that has to contain
  /// the accuracy radius — and widens the camera to match how wrong the
  /// estimate might be.
  Future<SignupLocationDraft?> estimateFromIp({
    double viewportPixels = 400,
  }) async {
    final IpLocationLookup lookup = _ipLookup ?? IpLocationLookup();
    try {
      final IpLocationEstimate? estimate =
          await lookup.lookup().timeout(lookupBudget, onTimeout: () => null);
      if (estimate == null) return null;

      final Random random = Random();
      return SignupLocationDraft(
        latitude: estimate.latitude + _jitter(random),
        longitude: estimate.longitude + _jitter(random),
        zoom: MapZoom.forRadius(
          radiusMeters: estimate.accuracyRadiusMeters,
          latitude: estimate.latitude,
          viewportPixels: viewportPixels,
        ),
        source: SignupLocationSource.ipEstimate,
      );
    } catch (e) {
      print('Signup IP placement failed: $e');
      return null;
    } finally {
      // Only dispose the client we created; an injected lookup belongs to the
      // caller and may be reused.
      if (_ipLookup == null) lookup.dispose();
    }
  }

  /// Last-resort placement: a random point at world zoom. The user is standing
  /// on the map screen with a draggable marker and a "try again" button, so an
  /// obviously-wrong position is recoverable in a way that a sign-up blocked on
  /// a location we cannot resolve would not be.
  SignupLocationDraft randomFallback() {
    final Random random = Random();
    return SignupLocationDraft(
      latitude: -50 + random.nextDouble() * 100,
      longitude: -180 + random.nextDouble() * 360,
      zoom: MapZoom.minZoom,
      source: SignupLocationSource.fallback,
    );
  }

  double _jitter(Random random) =>
      -_jitterDegrees + random.nextDouble() * (_jitterDegrees * 2);

  /// Converts a draft into the camera the map should open at.
  static CameraPosition cameraFor(SignupLocationDraft draft) => CameraPosition(
        target: LatLng(draft.latitude, draft.longitude),
        zoom: draft.zoom,
      );
}
