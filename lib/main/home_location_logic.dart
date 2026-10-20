part of 'package:intrst/main.dart';

extension _HomeLocationLogic on _MyHomePageState {
  bool _shouldSuppressAutoCenter(bool suppressWhenPendingFocus) {
    return suppressWhenPendingFocus &&
        (_pendingMapFocusUserUid?.isNotEmpty ?? false);
  }

  Future<bool> _gotoCurrentUserLocationFast(
      bool updateUserLocation, bool loadUserMarker) async {
    final GoogleMapController controller = await _controller.future;
    LocationData? locationData;

    try {
      locationData = await location.getLocation().timeout(
            const Duration(milliseconds: 500),
            //onTimeout: () => null,
          );

      if (locationData == null) {
        await location.changeSettings(accuracy: LocationAccuracy.balanced);
        locationData = await location.getLocation();
      }

      if (locationData.latitude == null) return false;

      _newPosition = CameraPosition(
        target: LatLng(locationData.latitude!, locationData.longitude!),
        zoom: _MyHomePageState._userLocationZoom,
      );

      await controller.animateCamera(
        CameraUpdate.newCameraPosition(_newPosition),
      );

      await loadMarkers(loadUserMarker);

      if (mounted) {
        setState(() => _markersLoadingSignedIn = false);
      }

      return true;
    } catch (e) {
      print("Error: $e");
      return false;
    }
  }

  double generateRandomNumber(double min, double max, Random random) {
    return min + random.nextDouble() * (max - min);
  }

  Future<void> moveCameraToUserLocation({
    double zoom = _MyHomePageState._userLocationZoom,
    bool animate = true,
  }) async {
    if (_uid.isEmpty) return;

    final users = FirebaseFirestore.instance.collection('users');

    final GeoPoint point = await fu.retrieveUserLocation(users, _uid);

    final LatLng target = LatLng(point.latitude, point.longitude);

    final GoogleMapController controller = await _controller.future;

    final CameraUpdate update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: target,
        zoom: zoom,
      ),
    );

    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  Future<void> moveCameraToSpecificUser(
    String targetUid, {
    double zoom = _MyHomePageState._userLocationZoom,
    bool animate = true,
  }) async {
    if (targetUid.isEmpty) return;

    final users = FirebaseFirestore.instance.collection('users');
    final GeoPoint point = await fu.retrieveUserLocation(users, targetUid);
    final LatLng target = LatLng(point.latitude, point.longitude);
    final GoogleMapController controller = await _controller.future;

    final CameraUpdate update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: target,
        zoom: zoom,
      ),
    );

    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  /// Smoothly moves the map camera to [target] at [zoom].
  ///
  /// On Android and iOS this is the SDK's own `animateCamera`. The web plugin
  /// implements `animateCamera` as a plain `moveCamera`, which jumps, so on
  /// web the camera is stepped once per frame along a [MapFlyPath] instead.
  /// Starting another flight stops this one where it is.
  Future<void> flyCameraTo(LatLng target, {required double zoom}) async {
    final Completer<GoogleMapController> mapController =
        _signedIn ? _controller : _controllerSignedOut;
    if (!_mapReady || !mapController.isCompleted) return;
    final GoogleMapController controller = await mapController.future;
    final int flight = ++_cameraFlightGeneration;
    final CameraPosition end = CameraPosition(target: target, zoom: zoom);

    try {
      if (!kIsWeb) {
        await controller.animateCamera(CameraUpdate.newCameraPosition(end));
        return;
      }

      final CameraPosition start =
          _lastCameraSnapshot?.toCameraPosition() ?? _initialCameraPosition;
      final MapFlyPath path = MapFlyPath(
        from: start.target,
        fromZoom: start.zoom,
        to: target,
        toZoom: zoom,
        viewportPixels: MediaQuery.sizeOf(context).shortestSide,
      );
      final int durationMicros = path.duration.inMicroseconds;
      final Stopwatch clock = Stopwatch()..start();

      while (true) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || flight != _cameraFlightGeneration) return;
        final double t = durationMicros == 0
            ? 1.0
            : (clock.elapsedMicroseconds / durationMicros).clamp(0.0, 1.0);
        final CameraPosition frame =
            path.at(Curves.easeInOutCubic.transform(t));
        // The zoom-out on a long hop can dip below what the map allows.
        final CameraPosition clamped = CameraPosition(
          target: frame.target,
          zoom: max(frame.zoom, MapZoom.minZoom),
        );
        await controller.moveCamera(CameraUpdate.newCameraPosition(clamped));
        if (t >= 1.0) return;
      }
    } catch (e) {
      // The map can be torn down mid-flight (sign-out, or leaving the
      // signed-out map's tab disposes it).
      print('Camera flight stopped: $e');
    }
  }

  /// When a search matches exactly one person, flies the map to their marker.
  /// Called with every fresh set of search results; anything other than a
  /// single match just forgets the last flight, so narrowing back down to
  /// that person later flies there again.
  void _focusSoleSearchResult(List<String> uids) {
    if (uids.length != 1) {
      _searchFocusedUid = null;
      return;
    }
    final String uid = uids.single;
    if (uid == _searchFocusedUid) return;
    final Marker? marker =
        poiMarkers.where((m) => m.markerId.value == uid).firstOrNull;
    if (marker == null) return;
    _searchFocusedUid = uid;
    flyCameraTo(
      marker.position,
      zoom: max(_currentZoom, _MyHomePageState._searchFocusZoom),
    );
  }

  Future<void> moveUserMarkerToCurrentLocation() async {
    if (_uid.isEmpty) return;

    try {
      final LocationData locationData = await location.getLocation();

      if (locationData.latitude == null || locationData.longitude == null) {
        return;
      }

      final LatLng newLatLng = LatLng(
        locationData.latitude!,
        locationData.longitude!,
      );

      final users = FirebaseFirestore.instance.collection('users');

      // Awaited so the marker reload below reads the new location rather than
      // racing the write.
      await fu.updateUserLocation(
        users,
        _uid,
        GeoPoint(newLatLng.latitude, newLatLng.longitude),
      );

      await loadMarkers(true);

      final GoogleMapController controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newLatLng,
            zoom: _MyHomePageState._userLocationZoom,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error moving user marker: $e');
    }
  }
}
