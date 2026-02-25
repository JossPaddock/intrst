part of 'package:intrst/main.dart';

extension _HomeLocationLogic on _MyHomePageState {
  Future<void> _showLocationDisclaimer(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Location Disclaimer"),
          content: const Text(
            "We respect your privacy. Your location data is used one time only "
            "to place your marker on the map. We do not store, share, or track "
            "your location, and we do not use your precise location — only an "
            "approximate position is used to improve your experience.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _getLocationServiceAndPermission(
      Completer<GoogleMapController> controllerCompleter) async {
    print('getLocationServiceAndPermission is running');

    CollectionReference users = FirebaseFirestore.instance.collection('users');
    final GoogleMapController controller = await controllerCompleter.future;

    // Ensure location services are enabled
    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        print('location service is not enabled');
        return;
      }
    }

    // Check current permission status
    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      // Request permission
      setState(() {
        _markersLoadingSignedInBannerText =
            'share location to place your marker...';
      });
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted == PermissionStatus.granted) {
        setState(() {
          _markersLoadingSignedInBannerText = 'placing your marker...';
        });
      }
      print('1st check permission granted: $_permissionGranted');
      // Poll for permission status to give iOS (mobile) time to update
      int tries = 0;
      while (_permissionGranted != PermissionStatus.granted && tries < 5) {
        print('polling for permission try#:$tries');
        await Future.delayed(const Duration(milliseconds: 500));
        _permissionGranted = await location.hasPermission();
        tries++;
      }
      print('after polling permission granted: $_permissionGranted');

      if (_permissionGranted != PermissionStatus.granted) {
        print('Permission not granted after request');
        /*Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (BuildContext context) => ChangeNotifierProvider(
              create: (context) => UserModel(),
              child: const MyApp(),
            ),
          ),
        ); */
        setState(() {
          _markersLoadingSignedIn = false;
          _markersLoadingSignedOut = false;
        });
      }
    }

    // Retrieve user location from Firestore
    final userLocation = await fu.retrieveUserLocation(
        users, FirebaseAuth.instance.currentUser!.uid);

    if (userLocation == GeoPoint(0, 0)) {
      print('user location was 0,0');
      // Update user location in Firestore and move map camera
      bool movedUser = await _gotoCurrentUserLocation(true, _signedIn);
      if (!movedUser) {
        // Move map camera to stored location with a small random offset
        Random random = Random();
        double lat = generateRandomNumber(-50, 50, random);
        double long = generateRandomNumber(-180, 180, random);
        _newPosition = CameraPosition(
          target: LatLng(
            lat,
            long,
          ),
          zoom: 3,
        );
        CollectionReference users =
            FirebaseFirestore.instance.collection('users');
        String localUid = FirebaseAuth.instance.currentUser!.uid;
        print(
            'updating user with user_uid: $localUid location to lat: ${lat}; long: ${long} in Firebase');
        fu.updateUserLocation(users, localUid, GeoPoint(lat, long));
        await loadMarkers(true);
        await controller
            .animateCamera(CameraUpdate.newCameraPosition(_newPosition));
        setState(() {
          _markersLoadingSignedIn = true;
          _markersLoadingSignedInBannerText =
              'click on the marker button (bottom right) then toggle to move your marker';
        });
      }
    } else {
      // Move map camera to stored location with a small random offset
      Random random = Random();
      double randomNumber1 = generateRandomNumber(-0.015, 0.015, random);
      double randomNumber2 = generateRandomNumber(-0.015, 0.015, random);
      _newPosition = CameraPosition(
        target: LatLng(
          userLocation.latitude + randomNumber1,
          userLocation.longitude + randomNumber2,
        ),
        zoom: 12,
      );
      await controller
          .animateCamera(CameraUpdate.newCameraPosition(_newPosition));
    }
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
        zoom: 12,
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

  Future<bool> _gotoCurrentUserLocation(
      bool updateUserLocation, bool loadUserMarker) async {
    print('running _gotoCurrentUserLocation method');
    Random random = Random();
    double randomNumber1 = generateRandomNumber(-0.015, 0.015, random);
    double randomNumber2 = generateRandomNumber(-0.015, 0.015, random);
    final GoogleMapController controller = await _controller.future;
    print('about to call location.getLocation');
    LocationData? locationData;
    try {
      locationData = await location.getLocation().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print("Timeout getting location. Took more than 5 seconds.");
          throw TimeoutException("location.getLocation() timed out");
        },
      );

      if (locationData.latitude == null || locationData.longitude == null) {
        print("Received null coordinates, retrying...");
        await Future.delayed(const Duration(seconds: 1));
        locationData = await location.getLocation();
      }

      print(
          "Got location: ${locationData.latitude}, ${locationData.longitude}");
    } catch (e) {
      print("Error getting location: $e");
      // Optionally show error to user or fallback
      return false;
    }
    print('locationData: ${locationData.latitude}');
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    String localUid = FirebaseAuth.instance.currentUser!.uid;
    if (updateUserLocation) {
      print(
          'updating user with user_uid: $localUid location to lat: ${locationData.latitude}; long: ${locationData.longitude} in Firebase');
      fu.updateUserLocation(
          users,
          localUid,
          GeoPoint(locationData.latitude! + randomNumber1,
              locationData.longitude! + randomNumber2));
    }
    _newPosition = CameraPosition(
        target: LatLng(locationData.latitude! + randomNumber1,
            locationData.longitude! + randomNumber2),
        zoom: 12);
    await loadMarkers(loadUserMarker);
    await controller
        .animateCamera(CameraUpdate.newCameraPosition(_newPosition));
    setState(() {
      _markersLoadingSignedIn = false;
    });
    return true;
  }

  double generateRandomNumber(double min, double max, Random random) {
    return min + random.nextDouble() * (max - min);
  }

  Future<void> _goToInitialPosition(
      Completer<GoogleMapController> completerController) async {
    final GoogleMapController controller = await completerController.future;
    await controller
        .animateCamera(CameraUpdate.newCameraPosition(_MyHomePageState._kLake));
  }

  Future<void> moveCameraToUserLocation({
    double zoom = 12,
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
    double zoom = 12,
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

      fu.updateUserLocation(
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
            zoom: 12,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error moving user marker: $e');
    }
  }
}
