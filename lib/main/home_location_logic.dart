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
