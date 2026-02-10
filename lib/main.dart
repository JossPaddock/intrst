import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/utility/BackendIntegration.dart';
import 'package:intrst/widgets/Account.dart';
import 'package:intrst/widgets/Interests/Interests.dart';
//import 'package:intrst/widgets/Interests.dart';
import 'package:intrst/widgets/Messaging.dart';
import 'package:intrst/widgets/Preview.dart' as custom_preview;
import 'package:provider/provider.dart';
import 'login/LoginScreen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:label_marker/label_marker.dart';
import 'package:location/location.dart';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
//import 'package:flutter/rendering.dart';

//import is for google maps
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<void> main() async {
  //debugPaintSizeEnabled = false;
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
      //name: 'web-intrst',
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(
    ChangeNotifierProvider<UserModel>.value(
      value: UserModel(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const appTitle = 'intrst';

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      title: appTitle,
      home: MyHomePage(title: appTitle),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late CameraPosition _newPosition;
  Location location = Location();
  late PermissionStatus _permissionGranted;
  late bool _serviceEnabled;
  double _currentZoom = 10;
  bool _markersLoadingSignedIn = true;
  String _markersLoadingSignedInBannerText = 'loading markers...';
  bool _markersLoadingSignedOut = false;
  bool _signedIn = false;
  String _name = '';
  String _uid = '';
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  int _selectedIndex = 0;
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  Set<Marker> labelMarkers = {};
  Set<Marker> poiMarkers = {};
  Set<Marker> markers = {};
  Set<Marker> searchFilteredMarkers = {};
  List<String> searchFilteredResults = [];
  String searchTerm = '';
  BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarker;
  late bool lastKnownDraggabilityState;
  bool _isLoading = false;
  int toggleIndex = 0;
  bool mapOptionsVisibility = false;
  String _markerDraggabilityText = 'not movable';
  bool hasNotification = false;
  int notificationCount = 0;
  Timer? _notificationLoading;

  void loadFCMToken() async {
    // You may set the permission requests to "provisional" which allows the user to choose what type
    // of notifications they would like to receive once the user receives a notification.
    final notificationSettings =
    await FirebaseMessaging.instance.requestPermission(provisional: true);

    // For apple platforms, ensure the APNS token is available before making any FCM plugin API calls
    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken != null) {
      // APNS token is available, make FCM plugin API requests...
      print('APNs token is available: ${apnsToken}');
    } else {
      print('APNs token is NOT available');
    }
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('fcm token is available: ${fcmToken}');
      fu.addFcmTokenForUser(_uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }
  }

  Future<void> loadUserContext() async {
    _loadNotificationCount();
    _notificationLoading = Timer.periodic(Duration(seconds: 10), (timer) {
      print(
          'Attempting to load user notifications timestamp: ${DateTime.now()}');
      _loadNotificationCount();
    });
  }

  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      name: 'intrst',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        print('User is currently signed out!');
        _notificationLoading?.cancel();
      } else {
        CollectionReference users =
        FirebaseFirestore.instance.collection('users');
        print('User is signed in!');
        _signedIn = true;
        _selectedIndex = 0;
        String localUid = FirebaseAuth.instance.currentUser!.uid;
        setState(() {});
        String name = await fu.lookUpNameByUserUid(users, localUid);
        _name = name;
        _uid = localUid;
        _handleUserModel(localUid);
        setState(() {});
        loadUserContext();
      }
    });
  }

  final mapId = "bc8e2917cca03ad4";

  Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  Completer<GoogleMapController> _controllerSignedOut =
  Completer<GoogleMapController>();

  void _onCameraMove(double zoom) {
    double level = 10.5;
    if (_currentZoom != zoom) {
      //print('$_currentZoom + $zoom');
      if (zoom > level && _currentZoom < level) {
        print('load label markers');
        setState(() {
          if (searchTerm == '') {
            markers = labelMarkers;
          } else {
            markers = labelMarkers
                .where((value) =>
                searchFilteredResults.contains(value.markerId.value))
                .toSet();
            ;
          }
        });
        _currentZoom = zoom;
      } else if (zoom < level && _currentZoom > level) {
        print('load poi markers');
        setState(() {
          if (searchTerm == '') {
            markers = poiMarkers;
          } else {
            markers = poiMarkers
                .where((value) =>
                searchFilteredResults.contains(value.markerId.value))
                .toSet();
            ;
          }
        });
        _currentZoom = zoom;
      }
    } else {
      //the following conditions are critical for resetting after search updates
      if (_currentZoom > level) {
        setState(() {
          markers = {};
          if (searchTerm == '') {
            markers = labelMarkers;
          } else {
            markers = labelMarkers
                .where((value) =>
                searchFilteredResults.contains(value.markerId.value))
                .toSet();
            ;
          }
        });
      } else {
        setState(() {
          markers = {};
          if (searchTerm == '') {
            markers = poiMarkers;
          } else {
            markers = poiMarkers
                .where((value) =>
                searchFilteredResults.contains(value.markerId.value))
                .toSet();
            ;
          }
        });
      }
    }
  }

  static const CameraPosition _kLake = CameraPosition(
      bearing: 0.0,
      target: LatLng(37.43296265331129, -122.08832357078792),
      tilt: 0.0,
      zoom: 3);

  bool _zoomEnabled = true;

  BitmapDescriptor poi = BitmapDescriptor.defaultMarker;

  Future<Uint8List> loadAssetAsByteData(String path) async {
    ByteData data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  @override
  void initState() {
    print('Build mode: ${kReleaseMode ? "Release" : "NOT Release"}');
    initializeFirebase();
    _goToInitialPosition(_controller);
    _goToInitialPosition(_controllerSignedOut);
    setState(() {
      lastKnownDraggabilityState = _retrieveDraggabilityUserModel();
      markers = poiMarkers;
    });
    loadFCMToken();
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _notificationLoading?.cancel();
    super.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
  }

  void _loadNotificationCount() async {
    print('attempting to load notification count');
    await fu.updateUnreadNotificationCounts('users');
    int count = await fu.retrieveNotificationCount(
        FirebaseFirestore.instance.collection('users'), _uid);
    print('the notification count was $count');
    if (notificationCount != count) {
      setState(() {
        FlutterAppBadger.updateBadgeCount(count);
        if (count > 0) {
          hasNotification = true;
          notificationCount = count;
        } else {
          hasNotification = false;
          notificationCount = 0;
          FlutterAppBadger.removeBadge();
        }
      });
    }
  }

  Future<void>? handleMarkerTap(String title, String uid, bool isPoi) {
    if (_zoomEnabled) {
      _handleAlternateUserModel(uid, title);
      print(uid);
      if (uid == _uid) {
        //this is the case where you tapped on the signed in users marker
        _scaffoldKey.currentState?.openEndDrawer();
        //markers = isPoi ? poiMarkers : labelMarkers;
        return null;
      } else {
        return showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              _zoomEnabled = false;
              return custom_preview.Preview(
                uid: _uid,
                alternateUid: uid,
                scaffoldKey: _scaffoldKey,
                onItemTapped: _onItemTapped,
                signedIn: _signedIn,
                onDrawerOpened: () {
                  Navigator.of(context).pop(true);
                },
              );
            }).then((drawerOpened) {
          if (drawerOpened != true) {
            _zoomEnabled = true;
          }
          markers = isPoi ? poiMarkers : labelMarkers;
          setState(() {});
        });
      }
    }
  }

  void addMarkers(Set<Marker> markers) {}

  void addMarker(String title, double lat, double lng, bool drag,
      BitmapDescriptor poi, String uid, bool user) {
    setState(() {
      poiMarkers.add(Marker(
          icon: poi,
          markerId: MarkerId(uid),
          //maybe someday this offset below will work. It should!
          anchor: Offset(0.5, 0.5),
          position: LatLng(lat, lng),
          draggable: drag,
          zIndex: drag ? 10 : (user ? 5 : 1),
          onTap: () {
            markers = {};
            handleMarkerTap(title, uid, true);
            setState(() {});
          },
          onDragEnd: (LatLng newPosition) async {
            fu.updateUserLocation(
                FirebaseFirestore.instance.collection('users'),
                FirebaseAuth.instance.currentUser!.uid,
                GeoPoint(newPosition.latitude, newPosition.longitude));
            await loadMarkers(true);
            setState(() {
              _markersLoadingSignedIn = false;
              _markersLoadingSignedInBannerText = 'loading markers...';
            });
            //
          }));
    });

    var color = Colors.white;
    if (user) {
      color = Color(0xFFff673a);
    }

    labelMarkers
        .addLabelMarker(LabelMarker(
        icon: BitmapDescriptor.defaultMarker,
        label: title,
        textStyle: TextStyle(
          color: color,
          fontSize: 27.0,
          letterSpacing: 1.0,
          fontFamily: 'Roboto Bold',
        ),
        markerId: MarkerId(uid),
        //maybe someday this offset below will work. It should!
        anchor: Offset(0.5, 0.5),
        position: LatLng(lat, lng),
        backgroundColor: const Color(0x00000000),
        draggable: drag,
        zIndex: drag ? 10 : (user ? 5 : 1),
        onTap: () {
          markers = {};
          handleMarkerTap(title, uid, false);
          setState(() {});
        },
        onDragEnd: (LatLng newPosition) async {
          fu.updateUserLocation(
              FirebaseFirestore.instance.collection('users'),
              FirebaseAuth.instance.currentUser!.uid,
              GeoPoint(newPosition.latitude, newPosition.longitude));
          await loadMarkers(true);
          setState(() {
            _markersLoadingSignedIn = false;
            _markersLoadingSignedInBannerText = 'loading markers...';
          });
        }))
        .then(
          (value) {
        setState(() {});
      },
    );
  }

  Future<bool> loadMarkers(bool loadUserMarker) async {
    if (searchTerm == '') {
      //Call this if your are dragging the marker!!
      await Future.delayed(Duration(milliseconds: 1500));
      setState(() {
        //markers = {};
        labelMarkers = {};
        poiMarkers = {};
      });
      Uint8List imageData = await loadAssetAsByteData('assets/poi.png');
      poi = await BitmapDescriptor.bytes(imageData,
          width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
      CollectionReference users =
      FirebaseFirestore.instance.collection('users');
      //user
      if (loadUserMarker) {
        Uint8List userImageData = await loadAssetAsByteData('assets/poio.png');
        BitmapDescriptor poio = await BitmapDescriptor.bytes(userImageData,
            width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
        var signedInUserMarkerData =
        await fu.lookUpNameAndLocationByUserUid(users, _uid);
        //This is where we load the signed in users marker
        addMarker(
            signedInUserMarkerData[0],
            signedInUserMarkerData[1],
            signedInUserMarkerData[2],
            _retrieveDraggabilityUserModel(),
            poio,
            _uid,
            true);
      }
      print('loadMarkers is working');
      var uids = await fu.retrieveAllUserUid(users);
      uids.forEach((uid) async {
        var markerData = await fu.lookUpNameAndLocationByUserUid(users, uid);
        if (uid != _uid) {
          addMarker(markerData[0], markerData[1], markerData[2], false, poi,
              uid, false);
        }
      });
      setState(() {});
    } else {
      //any logic if search term is empty
      /*setState(() {
        markers = searchFilteredMarkers;
      }); */
    }
    setState(() {
      _markersLoadingSignedIn = false;
      _markersLoadingSignedOut = false;
    });
    return loadUserMarker;
  }

  //Make marker loading more reliable (work on first load)
  //loading other users markers besides logged in user(start by testing firebase utility function that gets all user uids)

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
    await controller.animateCamera(CameraUpdate.newCameraPosition(_kLake));
  }

  void _handleSignInChanged(bool newValue) {
    setState(() {
      _signedIn = newValue;
    });
    if (newValue) {
      loadUserContext();
    }
  }

  void _handleNameChanged(String newValue) {
    setState(() {
      _name = newValue;
    });
  }

  void _handleUidChanged(String newValue) {
    setState(() {
      _uid = newValue;
    });
    // this gets the global instance of usermodel and allows us to access methods
    _handleUserModel(newValue);
  }

  void _handleUserModel(String value) {
    UserModel().changeUid(value);
  }

  bool _retrieveDraggabilityUserModel() {
    return UserModel().draggability;
  }

  Future<void> _setDraggabilityUserModel(bool value) async {
    print('Changing draggability $value');
    UserModel().changeDraggability(value);
  }

  void _handleAlternateUserModel(String value, String name) {
    UserModel().changeAlternateUid(value);
    UserModel().changeAlternateName(name);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showLoadingIndicator() {
    setState(() {
      _isLoading = true;
    });
    Future.delayed(Duration(seconds: 5), () {
      setState(() {
        _isLoading = false;
      });
    });
  }

  static const TextStyle optionStyle =
  TextStyle(fontSize: 30, fontWeight: FontWeight.bold);

  Widget rollingIconBuilder(int? value, bool foreground) {
    return Icon(iconDataByValue(value));
  }

  Widget iconBuilder(int value) {
    return rollingIconBuilder(value, false);
  }

  IconData iconDataByValue(int? value) => switch (value) {
    0 => Icons.disabled_by_default,
    _ => Icons.swipe,
  };

  Widget sizeIconBuilder(BuildContext context,
      AnimatedToggleProperties<int> local, GlobalToggleProperties<int> global) {
    return iconBuilder(local.value);
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

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    //padding.top represents the height of the status bar which varies by device
    double mapHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;
    double toolbarHeight = 56;
    // Updated bottom bar height - doubled from 80 to 160
    double bottomBarHeight = 164;

    return Scaffold(
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: toolbarHeight,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: Badge.count(
                  isLabelVisible: hasNotification,
                  count: notificationCount,
                  child: const Icon(Icons.menu)),
              color: Colors.white,
              onPressed: () {
                Scaffold.of(context).openDrawer();
                print(markers.length);
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        title: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            height: 48.0,
            width: screenWidth * 0.4 >= 225 ? screenWidth * 0.4 : 225,
            child: RawAutocomplete<String>(
              textEditingController: _searchController,
              focusNode: _searchFocusNode,
              optionsBuilder: (TextEditingValue textEditingValue) async {
                final value = textEditingValue.text;
                if (value.isEmpty) {
                  setState(() {
                    searchTerm = '';
                    searchFilteredResults = [];
                    searchFilteredMarkers = {};
                    _onCameraMove(_currentZoom); // reapply full marker set
                  });

                  return const Iterable<String>.empty();
                }

                if (value.isEmpty) {
                  return const Iterable<String>.empty();
                }

                var diff = value.length - searchTerm.length;
                var charDeleted = (diff == -1);
                if (charDeleted) {
                  print('user deleted a character from searchbar');
                }

                setState(() {
                  searchTerm = value;
                });

                CollectionReference users =
                FirebaseFirestore.instance.collection('users');

                List<String> uid_results = await fu
                    .searchForPeopleAndInterestsReturnUIDs(users, value, true);

                List<String> results =
                await fu.searchForPeopleAndInterests(users, value, true);
                List<String> interests = await fu.listInterests();
                print("interests: $interests");

                setState(() {
                  searchFilteredMarkers = markers;
                  searchFilteredResults = uid_results;
                  _onCameraMove(_currentZoom);
                });
                var input = value;
                var options = interests;

                if (results.isEmpty) {
                  print('No results! Calling LLM for more options');

                  // 1. Initialize the new client
                  BackendIntegration gptclient = BackendIntegration();

                  try {
                    // 2. Call the new generateResponse method and await it directly
                    final response = await gptclient.createResponse(
                      model: "gpt-4o",
                      input:
                      "You are an autocomplete semantic gap-filler.\n\nYour task is to map a user's search query to the most relevant existing autocomplete entries, even when the query does not exactly match any entry.\n\nRules:\n- You MUST return only items that appear EXACTLY in the provided list.\n- Do NOT invent, modify, or paraphrase entries.\n- Use semantic similarity such as shared activity type, environment, or user intent.\n- Prefer broader or closely related categories over loosely associated topics.\n- Rank results from most relevant to least relevant.\n- Return a maximum of 5 results.\n- Output must be a valid JSON stringified array.\n- Do NOT include explanations, comments, or additional text.\n\nNegative rules:\n- Do NOT add new concepts.\n- Do NOT include items with weak or indirect relevance.\n- If nothing is relevant, return an empty array: [].\n\nExample:\nInput:\nQuery: \"painting\"\nOptions: [\"art\", \"skiing\", \"podcasts\"]\n\nOutput:\n[\"art\"]\n\nNow process the following input:\n\nQuery: \"$input\"\nOptions: $options",
                    );

                    // 3. Use the new helper which now returns List<String> instead of a String
                    // We no longer need jsonDecode(answer) because the helper does it for us.
                    results = gptclient.extractAutocompleteEntries(response);

                    print("LLM results: $results");
                  } catch (e) {
                    print('Error calling backend: $e');
                  } finally {
                    // 4. Always close the client to prevent memory leaks
                    gptclient.dispose();
                  }
                }
                return results;
              },
              fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                  ) {
                return TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    hintText: 'find interests and people',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width - 32,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            title: Text(option),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: (selection) {
                setState(() {
                  searchTerm = selection;
                });
                print('Selected: $selection');
              },
            ),
          ),
        ),
        backgroundColor: Color(0xFF082D38),
        actions: [
          // Add the TextField wrapped in a StatefulBuilder
          Builder(
            builder: (context) => IconButton(
              icon: _signedIn
                  ? Image.asset('assets/poio.png')
                  : Image.asset('assets/poi.png'),
              //color: Colors.red,
              onPressed: () {
                _handleAlternateUserModel(_uid, _name);
                Scaffold.of(context).openEndDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(
                  height: 10,
                ),
                Text(
                  'Changing draggability',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                )
              ],
            ),
          ),
        )
            : _signedIn // _signedInGoogleMap
            ? <Widget>[
          Scaffold(
            body: Container(
              color: Color(0xFF082D38),
              //child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  Container(
                    height: mapOptionsVisibility
                        ? mapHeight - toolbarHeight - bottomBarHeight
                        : mapHeight - toolbarHeight,
                    child: Stack(
                      children: [
                        GoogleMap(
                          /*onTap: (LatLng position) {
                                      if (mapOptionsVisibility) {
                                        mapOptionsVisibility = false;
                                      }
                                    },*/
                          onCameraMove:
                              (CameraPosition cameraPosition) {
                            _onCameraMove(cameraPosition.zoom);
                          },
                          cloudMapId:
                          mapId, // Set the map style ID here
                          mapToolbarEnabled: false,
                          zoomGesturesEnabled: _zoomEnabled,
                          gestureRecognizers: _zoomEnabled
                              ? <Factory<
                              OneSequenceGestureRecognizer>>{
                            Factory<PanGestureRecognizer>(
                                    () => PanGestureRecognizer()),
                            Factory<ScaleGestureRecognizer>(
                                    () => ScaleGestureRecognizer()),
                            Factory<TapGestureRecognizer>(
                                    () => TapGestureRecognizer()),
                            Factory<VerticalDragGestureRecognizer>(
                                    () =>
                                    VerticalDragGestureRecognizer()),
                          }
                              : <Factory<
                              OneSequenceGestureRecognizer>>{}
                              .toSet(),
                          initialCameraPosition: _kLake,
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: true,
                          minMaxZoomPreference:
                          MinMaxZoomPreference(3.0, 900.0),
                          markers: markers,
                          onMapCreated:
                              (GoogleMapController controller) async {
                            loadFCMToken();
                            double zoom =
                            await controller.getZoomLevel();
                            _currentZoom = zoom;
                            print('onMapCreated signedIn is running');
                            if (_controller.isCompleted) {
                              _controller = Completer();
                            }
                            await _showLocationDisclaimer(context);
                            _getLocationServiceAndPermission(
                                _controller);
                            _gotoCurrentUserLocation(
                                false, _signedIn);
                            print('callback is working');
                            setState(() {});
                            if (markers.isEmpty) {
                              print(
                                  'markers is empty attempting to load markers now');
                              await loadMarkers(true);
                            }
                            _onCameraMove(_currentZoom);
                            _controller.complete(controller);
                          },
                        ),
                        Positioned(
                          bottom: kIsWeb? 130 : 70,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.white,
                            onPressed: () {
                              _gotoCurrentUserLocationFast(
                                  true, _signedIn);
                            },
                            child: Icon(Icons.my_location,
                                color: Colors.blue),
                          ),
                        ),
                        Positioned(
                          bottom: kIsWeb? 75 : 15,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            onPressed: () async {
                              setState(() {
                                //_zoomEnabled = false;
                                mapOptionsVisibility =
                                !mapOptionsVisibility;
                              });
                              if (mapOptionsVisibility) {
                                moveCameraToUserLocation();
                              }
                            },
                            child: Icon(Icons.location_on),
                            backgroundColor: Colors.blue,
                          ),
                        ),
                        if (_markersLoadingSignedIn)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 250,
                            child: Container(
                              color: Colors.black54,
                              padding: EdgeInsets.all(12),
                              child: Text(
                                _markersLoadingSignedInBannerText,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Updated bottom bar with title and larger height
                  Visibility(
                    visible: mapOptionsVisibility,
                    child: Container(
                      height: bottomBarHeight,
                      width: double.infinity,
                      color: Color(0xFF082D38),
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title at the top
                          Text(
                            'Marker Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),
                          // Toggle switch and status text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Toggle switch
                              SizedBox(
                                height: 40,
                                width: 100,
                                child: AnimatedToggleSwitch<int>.rolling(
                                  current: toggleIndex,
                                  values: [0, 1],
                                  onChanged: (i) async {
                                    print(toggleIndex);
                                    setState(() => toggleIndex = i);
                                    bool choice = (i == 1);
                                    _setDraggabilityUserModel(choice);
                                    await loadMarkers(true);
                                    _onCameraMove(_currentZoom);
                                    setState(() => toggleIndex = i);
                                    print(toggleIndex);
                                    setState(() {
                                      _zoomEnabled = true;
                                      if (!choice) {
                                        mapOptionsVisibility = false;
                                        _markerDraggabilityText = 'not movable';
                                      } else {
                                        _markerDraggabilityText = 'movable';
                                        setState(() {
                                          _markersLoadingSignedIn = true;
                                          if (kIsWeb) {
                                            _markersLoadingSignedInBannerText =
                                            'drag your marker to a new location...';
                                          } else {
                                            _markersLoadingSignedInBannerText =
                                            'long press to drag your marker to a new location...';
                                          }
                                        });
                                      }
                                    });
                                  },
                                  iconBuilder: rollingIconBuilder,
                                  style: ToggleStyle(),
                                  height: 50,
                                ),
                              ),
                              SizedBox(width: 16),
                              // Text label
                              Text(
                                _markerDraggabilityText,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          // Button on its own row, centered
                          ElevatedButton(
                            onPressed: () {
                              moveUserMarkerToCurrentLocation();
                            },
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: Text(
                              "move to my exact location",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                //),
              ),
            ),
          ),
          Text('New Feature coming in the future'),
          Account(uid: _uid),
          Messaging(user_uid: _uid),
          Text(
            'Index 4: Replace this text widget with the Sign Out widget',
            style: optionStyle,
          ),
        ][_selectedIndex]
            : <Widget>[
          Stack(children: [
            GoogleMap(
              onCameraMove: (CameraPosition cameraPosition) {
                _onCameraMove(cameraPosition.zoom);
              },
              cloudMapId: mapId, // Set the map style ID here
              zoomGesturesEnabled: _zoomEnabled,
              initialCameraPosition: _kLake,
              zoomControlsEnabled: false,
              minMaxZoomPreference: MinMaxZoomPreference(3.0, 900.0),
              markers: markers,
              onMapCreated: (GoogleMapController controller) async {
                setState(() {
                  _markersLoadingSignedOut = true;
                });
                double zoom = await controller.getZoomLevel();
                _currentZoom = zoom;
                print('onMapCreated signedOut is running');
                if (_controllerSignedOut.isCompleted) {
                  _controllerSignedOut = Completer();
                }
                print('mapStyle should be set');
                print('callback is working');
                setState(() {});
                print(markers.length);
                await loadMarkers(false);
                //await Future.delayed(Duration(milliseconds: 1000));
                print(markers.length);
                _controllerSignedOut.complete(controller);
                _onCameraMove(_currentZoom);
                await Future.delayed(Duration(milliseconds: 250));
                setState(() {
                  _markersLoadingSignedOut = false;
                });
              },
            ),
            if (_markersLoadingSignedOut)
              Positioned(
                left: 0,
                right: 0,
                bottom: 250,
                child: Container(
                  color: Colors.black54,
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'loading markers...',
                    style:
                    TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ]),
          LoginScreen(
            signedIn: _signedIn,
            onSignInChanged: _handleSignInChanged,
            onSelectedIndexChanged: _onItemTapped,
            onNameChanged: _handleNameChanged,
            onUidChanged: _handleUidChanged,
          ),
        ][_selectedIndex],
      ),
      drawer: Drawer(
        child: _signedIn
            ? ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: kDebugMode ? Text("$_name : $_uid") : Text("$_name"),
            ),
            ListTile(
              title: const Text('Map'),
              selected: _selectedIndex == 0,
              onTap: () {
                _onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Friends'),
              selected: _selectedIndex == 1,
              onTap: () {
                _onItemTapped(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Account'),
              selected: _selectedIndex == 2,
              onTap: () {
                _onItemTapped(2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Messages'),
              trailing: Badge.count(
                isLabelVisible: hasNotification,
                count: notificationCount,
              ),
              selected: _selectedIndex == 3,
              onTap: () {
                _onItemTapped(3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Sign Out'),
              selected: _selectedIndex == 0,
              onTap: () {
                markers = {};
                setState(() {});
                _onItemTapped(0);
                FirebaseAuth.instance.signOut();
                _handleSignInChanged(false);
                _handleNameChanged('');
                _handleUidChanged('');
                setState(() {
                  hasNotification = false;
                  notificationCount = 0;
                });
                Navigator.pop(context);
              },
            ),
          ],
        )
            : ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 75,
              child: DrawerHeader(
                decoration: BoxDecoration(
                  color: Color(0xFF082D38),
                ),
                child: Text(
                  "$_name : $_uid",
                  style: TextStyle(
                      color: Colors.white), // Set your desired color),
                ),
              ),
            ),
            ListTile(
              title: const Text('Map'),
              selected: _selectedIndex == 0,
              onTap: () {
                _onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Sign In'),
              selected: _selectedIndex == 1,
              onTap: () {
                markers = {};
                setState(() {});
                _onItemTapped(1);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      endDrawer: SizedBox(
        width: MediaQuery.of(context).size.width * 1,
        child: Container(
          alignment: Alignment.center,
          child: Interests(
            name: _name,
            scaffoldKey: _scaffoldKey,
            signedIn: _signedIn,
            onItemTapped: _onItemTapped,
          ),
        ),
      ),
      drawerEdgeDragWidth: 200,
      onEndDrawerChanged: (state) async {
        print('endDrawer is $state');
        if (state) {
          markers = {};
        } else {
          //await loadMarkers(true);
          if (_retrieveDraggabilityUserModel() != lastKnownDraggabilityState) {
            //await loadMarkers(true);
            lastKnownDraggabilityState = _retrieveDraggabilityUserModel();
          }
          _onCameraMove(_currentZoom);
        }
        setState(() {
          _zoomEnabled = !state;
        });
      },
    );
  }
}