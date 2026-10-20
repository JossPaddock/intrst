part of 'package:intrst/main.dart';

/// Map start-up and camera memory.
///
/// The rule this implements: **the map always returns to where the user was
/// last exploring.** The only time we choose a position for them is when there
/// is no remembered camera at all — a genuinely fresh install (or a cleared
/// preference store), where we fall back to their stored marker location, and
/// failing that to the first-run placement flow.
///
/// The second rule: **nothing is shown until it is ready.** `GoogleMap` reads
/// `initialCameraPosition` exactly once, at construction, so the widget is not
/// built until the camera is resolved *and* the markers for it are loaded.
/// Until then the body renders a single loading indicator. That is what
/// removes the old multi-step sequence (world view -> animate to your marker ->
/// animate again to GPS -> markers pop in).
/// A marker position the app inferred rather than measured, paired with the
/// zoom that keeps its uncertainty on screen.
class _EstimatedPlacement {
  const _EstimatedPlacement({required this.target, required this.zoom});

  final LatLng target;
  final double zoom;
}

extension _HomeMapBootstrap on _MyHomePageState {
  /// Records that Firebase has reported an auth state at least once. Until
  /// this happens the UI shows the loading indicator rather than guessing.
  void _markAuthResolved() {
    _authResolutionTimeout?.cancel();
    _authResolutionTimeout = null;
    if (_authResolved) return;
    if (!mounted) {
      _authResolved = true;
      return;
    }
    setState(() {
      _authResolved = true;
    });
  }

  /// Bootstraps the map for the current session, exactly once per session.
  /// Signing in or out changes the key and re-runs it.
  Future<void> _ensureMapBootstrapped() async {
    if (!_authResolved) return;
    final String key = _signedIn && _uid.isNotEmpty ? 'in:$_uid' : 'out';
    if (_mapBootstrapKey == key) return;
    _mapBootstrapKey = key;

    if (mounted) {
      setState(() {
        _mapReady = false;
      });
    }

    try {
      // Bounded so a slow marker fetch can never strand the user on the
      // loading screen; the camera is already resolved by then, and
      // loadMarkers keeps running and refreshes the map when it lands.
      await _bootstrapMap(key).timeout(const Duration(seconds: 15));
    } catch (e) {
      // A failed bootstrap must never strand the user on a loading screen; we
      // show the map at whatever position we managed to resolve.
      print('Map bootstrap failed: $e');
    }

    // A newer session superseded us while we were awaiting — it owns the UI.
    if (!mounted || _mapBootstrapKey != key) return;
    setState(() {
      _mapReady = true;
      _markersLoadingSignedIn = false;
      _markersLoadingSignedOut = false;
    });
  }

  /// Resolves the starting camera, then loads the markers for it, so both are
  /// in place before the map appears. [key] guards against a session change
  /// landing mid-flight.
  Future<void> _bootstrapMap(String key) async {
    _needsMarkerPlacement = false;
    _showLocationOnboarding = false;
    _locationOnboardingError = null;

    final CameraPosition initial = await _resolveInitialCameraPosition();
    if (!mounted || _mapBootstrapKey != key) return;

    _initialCameraPosition = initial;
    _currentZoom = initial.zoom;
    _lastCameraSnapshot = MapCameraSnapshot.fromCameraPosition(initial);

    _showLocationOnboarding = await _shouldShowLocationOnboarding();
    if (!mounted || _mapBootstrapKey != key) return;

    // A new sign-up goes to the onboarding screen first, and their marker does
    // not exist yet — _completeLocationOnboarding loads the markers once, after
    // placing it. Loading here as well would just be a discarded fetch.
    if (_showLocationOnboarding) return;

    // Markers are loaded *before* the map is shown so they are already on it
    // the first frame it renders, rather than appearing a beat later.
    await loadMarkers(_signedIn);
  }

  /// Decides where the map opens, in priority order:
  ///  1. a pending "show me this user" request from the feed,
  ///  2. the remembered camera from the user's last session,
  ///  3. (signed in) their stored marker location,
  ///  4. a fresh device fix, when we can get one without prompting,
  ///  5. the default world view.
  ///
  /// 3 and 4 both open at [_MyHomePageState._userLocationZoom]: on a fresh load
  /// with no memory, if we know where the user is at all we start zoomed in on
  /// them, never on the whole world.
  ///
  /// Whether the user still needs a marker placed is decided *separately* from
  /// where the camera opens: someone who browsed signed out has a remembered
  /// camera but, on their first sign-in, still has no marker.
  Future<CameraPosition> _resolveInitialCameraPosition() async {
    final String? pendingFocusUid = _pendingMapFocusUserUid;
    if (pendingFocusUid != null && pendingFocusUid.isNotEmpty) {
      final CameraPosition? focus =
          await _cameraPositionForUser(pendingFocusUid, zoom: 13.5);
      if (focus != null) return focus;
    }

    final MapCameraSnapshot? remembered = await _cameraMemory.load();

    CameraPosition? ownMarker;
    if (_signedIn && _uid.isNotEmpty) {
      ownMarker = await _cameraPositionForUser(
        _uid,
        zoom: _MyHomePageState._userLocationZoom,
      );
      // No usable stored location means this account has never placed a
      // marker, regardless of what the camera memory says.
      _needsMarkerPlacement = ownMarker == null;
    }

    if (remembered != null) {
      print('Restoring remembered map camera: $remembered');
      _persistedCameraSnapshot = remembered;
      return remembered.toCameraPosition();
    }

    if (ownMarker != null) {
      print('No remembered camera; opening at the signed-in user marker.');
      return ownMarker;
    }

    final CameraPosition? deviceFix = await _deviceLocationCamera();
    if (deviceFix != null) {
      print('No remembered camera or marker; opening at the device location.');
      return deviceFix;
    }

    return _MyHomePageState._kLake;
  }

  /// The device's current position, at the same zoom as the user's marker —
  /// but **only** when location is already available. This runs while the
  /// loading indicator is up, so it must never trigger a service or permission
  /// prompt (that belongs to [_placeUserMarkerAndCenter], which runs over a
  /// visible map) and must never block start-up for long.
  Future<CameraPosition?> _deviceLocationCamera() async {
    try {
      if (!await location.serviceEnabled()) return null;
      if (await location.hasPermission() != PermissionStatus.granted) {
        return null;
      }
      final LocationData data =
          await location.getLocation().timeout(const Duration(seconds: 3));
      if (data.latitude == null || data.longitude == null) return null;
      final MapCameraSnapshot? snapshot = MapCameraSnapshot.create(
        latitude: data.latitude!,
        longitude: data.longitude!,
        zoom: _MyHomePageState._userLocationZoom,
      );
      return snapshot?.toCameraPosition();
    } catch (e) {
      print('No device location available for the initial camera: $e');
      return null;
    }
  }

  /// Whether this is a brand-new sign-up that should meet the location
  /// onboarding screen.
  ///
  /// Requires **both** that the account has no marker yet and that it has not
  /// completed the first-run experience. Two conditions rather than one because
  /// each covers the other's failure mode: `getFirstRunExperience` returns
  /// false when the read fails, which alone would re-show onboarding after a
  /// network blip; and an account can only lack a marker before it has ever
  /// finished this flow.
  Future<bool> _shouldShowLocationOnboarding() async {
    if (!_signedIn || _uid.isEmpty) return false;
    if (!_needsMarkerPlacement) return false;
    final bool alreadyCompleted = await fu.getFirstRunExperience(
        FirebaseFirestore.instance.collection('users'), _uid);
    return !alreadyCompleted;
  }

  /// The camera for [uid]'s stored marker, or null when they have no usable
  /// location yet (missing document, or the 0,0 "unset" sentinel).
  Future<CameraPosition?> _cameraPositionForUser(
    String uid, {
    required double zoom,
  }) async {
    if (uid.isEmpty) return null;
    try {
      final GeoPoint point = await fu.retrieveUserLocation(
          FirebaseFirestore.instance.collection('users'), uid);
      if (point.latitude == 0 && point.longitude == 0) return null;
      final MapCameraSnapshot? snapshot = MapCameraSnapshot.create(
        latitude: point.latitude,
        longitude: point.longitude,
        zoom: zoom,
      );
      return snapshot?.toCameraPosition();
    } catch (e) {
      print('Could not read stored location for $uid: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera memory
  // ---------------------------------------------------------------------------

  /// Every camera movement, from either map. Keeps the marker set in sync and
  /// remembers the position so [_persistCameraPosition] can store it when the
  /// gesture settles.
  void _handleCameraMove(CameraPosition position) {
    final MapCameraSnapshot? snapshot =
        MapCameraSnapshot.fromCameraPosition(position);
    if (snapshot != null) {
      _lastCameraSnapshot = snapshot;
    }
    _onCameraMove(position.zoom);
  }

  /// Persists the current camera once the map comes to rest. Called from
  /// `onCameraIdle`, and skipped when the view has not meaningfully changed so
  /// idle events do not turn into a stream of writes.
  Future<void> _persistCameraPosition() async {
    if (!_mapReady) return;
    final MapCameraSnapshot? snapshot = _lastCameraSnapshot;
    if (snapshot == null) return;
    if (snapshot.isSameViewAs(_persistedCameraSnapshot)) return;
    _persistedCameraSnapshot = snapshot;
    await _cameraMemory.save(snapshot);
  }

  /// Immediately remembers [position] — used when the app itself moves the
  /// camera (first-run placement) rather than the user.
  Future<void> _rememberCameraPosition(CameraPosition position) async {
    final MapCameraSnapshot? snapshot =
        MapCameraSnapshot.fromCameraPosition(position);
    if (snapshot == null) return;
    _lastCameraSnapshot = snapshot;
    _persistedCameraSnapshot = snapshot;
    await _cameraMemory.save(snapshot);
  }

  // ---------------------------------------------------------------------------
  // Sign-up location onboarding
  // ---------------------------------------------------------------------------

  /// Requests location, places the new user's marker, and hands the map a
  /// camera already centred on them.
  ///
  /// Everything happens while the onboarding screen is still up: the marker is
  /// written, the markers are reloaded, and [_initialCameraPosition] is set
  /// before [_showLocationOnboarding] clears. Because the `GoogleMap` widget is
  /// not built until then, it opens directly at their location with every
  /// marker already on it — there is no camera animation to see and nothing
  /// pops in afterwards.
  ///
  /// When [shareLocation] is false — the user declined — we place them from
  /// their IP address instead and open the map zoomed out far enough that both
  /// the estimated marker and wherever they really are should be on screen.
  /// If even that fails we keep the historical fallback: a random spot in the
  /// world at world zoom, with the banner telling them how to move the marker.
  Future<void> _completeLocationOnboarding({required bool shareLocation}) async {
    if (_locationOnboardingBusy) return;
    if (!_signedIn || _uid.isEmpty) return;

    setState(() {
      _locationOnboardingBusy = true;
      _locationOnboardingError = null;
    });

    LatLng? gpsTarget;
    if (shareLocation) {
      gpsTarget = await _requestLocationForOnboarding();
      if (!mounted) return;
      if (gpsTarget == null) {
        // Don't trap them on this screen: explain, and let them decline
        // instead — the decline path still places them by IP.
        setState(() {
          _locationOnboardingBusy = false;
          _locationOnboardingError =
              "We couldn't get your location. Check that location access is "
              'enabled for intrst, or continue without sharing and we\'ll '
              'estimate your area instead.';
        });
        return;
      }
    }

    final CollectionReference users =
        FirebaseFirestore.instance.collection('users');

    LatLng? target = gpsTarget;
    double zoom = _MyHomePageState._userLocationZoom;

    if (target == null) {
      // Declined: estimate from the IP address and widen the camera to cover
      // how wrong that estimate might be.
      final _EstimatedPlacement? estimate = await _ipEstimatedPlacement();
      if (!mounted) return;
      if (estimate != null) {
        target = estimate.target;
        zoom = estimate.zoom;
      }
    }

    if (target == null) {
      final Random random = Random();
      target = LatLng(
        generateRandomNumber(-50, 50, random),
        generateRandomNumber(-180, 180, random),
      );
      zoom = MapCameraSnapshot.minZoom;
    }

    final bool placedMeaningfully =
        gpsTarget != null || zoom != MapCameraSnapshot.minZoom;

    print('Onboarding: placing marker for $_uid at '
        '${target.latitude}, ${target.longitude}');
    await fu.updateUserLocation(
        users, _uid, GeoPoint(target.latitude, target.longitude));
    await fu.setFirstRunExperienceComplete(users, _uid);

    // Markers before the map, so the first frame is the finished picture.
    final CameraPosition placed = CameraPosition(target: target, zoom: zoom);
    _initialCameraPosition = placed;
    _currentZoom = zoom;
    await _rememberCameraPosition(placed);
    await loadMarkers(true);
    if (!mounted) return;

    setState(() {
      _showLocationOnboarding = false;
      _locationOnboardingBusy = false;
      _needsMarkerPlacement = false;
      // The in-map placement fallback must not also run for this session.
      _hasPerformedInitialSignedInMapSetup = true;
      if (gpsTarget != null) {
        _markersLoadingSignedIn = false;
        _markersLoadingSignedInBannerText = 'loading markers...';
      } else {
        // Both estimate paths leave the marker somewhere approximate, so the
        // banner points at the control that moves it.
        _markersLoadingSignedIn = true;
        _markersLoadingSignedInBannerText = placedMeaningfully
            ? 'we estimated your area — use the marker button (bottom right) to move your marker'
            : 'click on the marker button (bottom right) then toggle to move your marker';
      }
    });
  }

  /// Places a user who declined location sharing, using their IP address.
  ///
  /// Returns the marker position and the zoom that fits the estimate's
  /// uncertainty on screen, so the user opens the map able to see both the
  /// marker we chose and the area they are actually in — the point being that
  /// they can drag it the short distance to where they want it, instead of
  /// hunting for it from a world view.
  ///
  /// The position carries the same small jitter as every other placement. Here
  /// it does double duty: IP lookups return a city or ISP centroid, so without
  /// it everyone on the same network would stack on one identical point.
  Future<_EstimatedPlacement?> _ipEstimatedPlacement() async {
    final IpLocationLookup lookup = IpLocationLookup();
    try {
      final IpLocationEstimate? estimate = await lookup.lookup();
      if (estimate == null) return null;

      final Random random = Random();
      final LatLng target = LatLng(
        estimate.latitude + generateRandomNumber(-0.015, 0.015, random),
        estimate.longitude + generateRandomNumber(-0.015, 0.015, random),
      );

      // The shorter screen edge is what has to contain the radius; using the
      // longer one would let the circle overflow in portrait.
      final double viewportPixels =
          mounted ? MediaQuery.of(context).size.shortestSide : 400;

      final double zoom = MapZoom.forRadius(
        radiusMeters: estimate.accuracyRadiusMeters,
        latitude: estimate.latitude,
        viewportPixels: viewportPixels,
      );

      print('Placing by IP at zoom $zoom: $estimate');
      return _EstimatedPlacement(target: target, zoom: zoom);
    } catch (e) {
      print('IP-based placement failed: $e');
      return null;
    } finally {
      lookup.dispose();
    }
  }

  /// Drives the OS location prompts for the onboarding screen. Returns the
  /// position to place the marker at, or null if the user declined or no fix
  /// arrived.
  Future<LatLng?> _requestLocationForOnboarding() async {
    try {
      _serviceEnabled = await location.serviceEnabled();
      if (!_serviceEnabled) {
        _serviceEnabled = await location.requestService();
      }
      if (!_serviceEnabled) return null;

      _permissionGranted = await location.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _permissionGranted = await location.requestPermission();
        // Poll briefly: iOS updates the status a moment after the dialog.
        int tries = 0;
        while (_permissionGranted != PermissionStatus.granted && tries < 5) {
          await Future.delayed(const Duration(milliseconds: 500));
          _permissionGranted = await location.hasPermission();
          tries++;
        }
      }
      if (_permissionGranted != PermissionStatus.granted) return null;

      return await _readCurrentLocationWithJitter();
    } catch (e) {
      print('Onboarding location request failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // First-run marker placement
  // ---------------------------------------------------------------------------

  /// First-run only: asks for location access, writes the user's marker, and
  /// centres on it. Runs after the map is visible so the permission dialog
  /// appears over a real map instead of a loading screen. Returning users
  /// never reach this — their camera is restored from memory instead, which is
  /// why the app no longer requests GPS on every launch.
  Future<void> _placeUserMarkerAndCenter() async {
    if (!_signedIn || _uid.isEmpty) return;

    final CollectionReference users =
        FirebaseFirestore.instance.collection('users');
    final GoogleMapController controller = await _controller.future;

    LatLng? gpsTarget;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
    }

    if (_serviceEnabled) {
      _permissionGranted = await location.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _setMarkerPlacementBanner('share location to place your marker...');
        _permissionGranted = await location.requestPermission();
        // Poll briefly: iOS updates the status a moment after the dialog.
        int tries = 0;
        while (_permissionGranted != PermissionStatus.granted && tries < 5) {
          await Future.delayed(const Duration(milliseconds: 500));
          _permissionGranted = await location.hasPermission();
          tries++;
        }
      }

      if (_permissionGranted == PermissionStatus.granted) {
        _setMarkerPlacementBanner('placing your marker...');
        gpsTarget = await _readCurrentLocationWithJitter();
      }
    }

    if (!mounted) return;

    // Same ladder as the onboarding screen: a real fix, else an IP estimate at
    // a zoom that covers its error, else a random spot at world zoom.
    LatLng? target = gpsTarget;
    double zoom = _MyHomePageState._userLocationZoom;
    if (target == null) {
      final _EstimatedPlacement? estimate = await _ipEstimatedPlacement();
      if (!mounted) return;
      if (estimate != null) {
        target = estimate.target;
        zoom = estimate.zoom;
      }
    }
    if (target == null) {
      final Random random = Random();
      target = LatLng(
        generateRandomNumber(-50, 50, random),
        generateRandomNumber(-180, 180, random),
      );
      zoom = MapCameraSnapshot.minZoom;
    }

    print('Placing first-run marker for $_uid at '
        '${target.latitude}, ${target.longitude}');
    await fu.updateUserLocation(
        users, _uid, GeoPoint(target.latitude, target.longitude));

    await loadMarkers(true);
    if (!mounted) return;

    final CameraPosition placed = CameraPosition(target: target, zoom: zoom);
    if (!_shouldSuppressAutoCenter(true)) {
      _currentZoom = zoom;
      await controller.animateCamera(CameraUpdate.newCameraPosition(placed));
      await _rememberCameraPosition(placed);
    }

    if (!mounted) return;
    final bool placedMeaningfully =
        gpsTarget != null || zoom != MapCameraSnapshot.minZoom;
    setState(() {
      if (gpsTarget != null) {
        _markersLoadingSignedIn = false;
        _markersLoadingSignedInBannerText = 'loading markers...';
      } else {
        _markersLoadingSignedIn = true;
        _markersLoadingSignedInBannerText = placedMeaningfully
            ? 'we estimated your area — use the marker button (bottom right) to move your marker'
            : 'click on the marker button (bottom right) then toggle to move your marker';
      }
    });
  }

  /// The device location, offset slightly so a marker never sits exactly on the
  /// user's real position. Null when no fix is available in time.
  Future<LatLng?> _readCurrentLocationWithJitter() async {
    final Random random = Random();
    try {
      final LocationData data = await location.getLocation().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('location.getLocation() timed out'),
          );
      if (data.latitude == null || data.longitude == null) return null;
      return LatLng(
        data.latitude! + generateRandomNumber(-0.015, 0.015, random),
        data.longitude! + generateRandomNumber(-0.015, 0.015, random),
      );
    } catch (e) {
      print('Error getting location for first-run placement: $e');
      return null;
    }
  }

  void _setMarkerPlacementBanner(String text) {
    if (!mounted) return;
    setState(() {
      _markersLoadingSignedIn = true;
      _markersLoadingSignedInBannerText = text;
    });
  }

  /// The screen a brand-new sign-up meets before the map exists. It carries the
  /// marker disclaimer that used to be an OK-button dialog over the map, plus
  /// the location request itself — so the user reads why we want their location
  /// and grants it in one place, and the map that follows is already correct.
  Widget _buildLocationOnboardingScreen() {
    final bool failed = _locationOnboardingError != null;

    return Container(
      color: const Color(0xFF082D38),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.place_outlined,
                  color: Color(0xFFff673a), size: 72),
              const SizedBox(height: 24),
              const Text(
                'Welcome to intrst',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // The location disclaimer, verbatim from the dialog it replaces.
              const Text(
                'Please use marker settings in bottom right to move your '
                'marker wherever you want it. We initially place it in a '
                'random spot in your general vicinity.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'To start you off somewhere useful, intrst needs your '
                'location. We only use it to place your marker on the map, '
                'and you can move it whenever you like.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Says plainly what declining does. Declining still infers a
              // rough area, so the user should know that before choosing it.
              const Text(
                "If you'd rather not, we'll estimate your general area from "
                'your internet connection and place your marker there instead.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              if (failed) ...[
                const SizedBox(height: 20),
                Text(
                  _locationOnboardingError!,
                  style: const TextStyle(color: Colors.amber, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _locationOnboardingBusy
                      ? null
                      : () => _completeLocationOnboarding(shareLocation: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFff673a),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF8a3a20),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _locationOnboardingBusy
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text('Setting up your map…',
                                style: TextStyle(fontSize: 16)),
                          ],
                        )
                      : Text(
                          failed
                              ? 'Try sharing location again'
                              : 'Share Location with Intrst',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _locationOnboardingBusy
                      ? null
                      : () => _completeLocationOnboarding(shareLocation: false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    disabledForegroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Don't share my location",
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The loading state shown in place of the map until the session and the
  /// map's starting position + markers are known.
  Widget _buildMapLoadingIndicator() {
    return Container(
      color: const Color(0xFF082D38),
      width: double.infinity,
      height: double.infinity,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFff673a)),
            SizedBox(height: 16),
            Text(
              'loading your map...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
