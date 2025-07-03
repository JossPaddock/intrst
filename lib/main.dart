import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/widgets/Interests.dart';
import 'package:intrst/widgets/Messaging.dart';
import 'package:intrst/widgets/Preview.dart' as custom_preview;
import 'package:provider/provider.dart';
import 'login/LoginScreen.dart';
import 'widgets/InterestInputForm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:label_marker/label_marker.dart';
import 'package:location/location.dart';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';

//import is for google maps
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
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
  bool _signedIn = false;
  String _name = '';
  String _uid = '';
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
  String _markerDraggabilityText = 'Your marker is not movable';
  bool hasNotification = false;
  int notificationCount = 0;
  Timer? _notificationLoading;

  Future<void> loadUserContext() async {
    _loadNotificationCount();
    _notificationLoading = Timer.periodic(Duration(seconds: 30), (timer) {
      print(
          'Attempting to load user notifications timestamp: ${DateTime.now()}');
      _loadNotificationCount();
    });
  }

  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      //name: 'intrst',
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
    super.initState();
  }

  @override
  void dispose() {
    _notificationLoading?.cancel();
    super.dispose();
  }

  void _loadNotificationCount() async {
    print('attempting to load notification count');
    await fu.updateUnreadNotificationCounts('users');
    int count = await fu.retrieveNotificationCount(
        FirebaseFirestore.instance.collection('users'), _uid);
    print('the notification count was $count');
    if (notificationCount != count) {
      setState(() {
        if (count > 0) {
          hasNotification = true;
          notificationCount = count;
        } else {
          hasNotification = false;
          notificationCount = 0;
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
    return loadUserMarker;
  }

  //Make marker loading more reliable (work on first load)
  //loading other users markers besides logged in user(start by testing firebase utility function that gets all user uids)

  Future<void> _getLocationServiceAndPermission(
      Completer<GoogleMapController> controllerCompleter) async {
    print('getLocationServiceAndPermission is running');
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    final GoogleMapController controller = await controllerCompleter.future;
    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        print('location service is not enabled');
        return;
      }
    }
    //do a soft check to determine if latlng is 0,0
    //if it is 0,0 update user location
    final userLocation = await fu.retrieveUserLocation(
        users, FirebaseAuth.instance.currentUser!.uid);
    if (userLocation == GeoPoint(0, 0)) {
      print('user location was 0,0');
      _gotoCurrentUserLocation(true, true);
      _permissionGranted = await location.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _permissionGranted = await location.requestPermission();
        if (_permissionGranted != PermissionStatus.granted) {
          //todo: markers are not loading for some reason
          //setState(() {});
          //print('trying to reload page');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (BuildContext context) => ChangeNotifierProvider(
                create: (context) => UserModel(),
                child: const MyApp(),
              ),
            ),
          );
          setState(() {});
        } else {
          setState(() {});
          _gotoCurrentUserLocation(false, _signedIn);
        }
      } else {
        Random random = Random();
        double randomNumber1 = generateRandomNumber(-0.015, 0.015, random);
        double randomNumber2 = generateRandomNumber(-0.015, 0.015, random);
        _newPosition = CameraPosition(
            target: LatLng(userLocation.latitude + randomNumber1,
                userLocation.longitude + randomNumber2),
            zoom: 12);
        controller.animateCamera(CameraUpdate.newCameraPosition(_newPosition));
      }
    }
  }

  Future<void> _gotoCurrentUserLocation(
      bool updateUserLocation, bool loadUserMarker) async {
    Random random = Random();
    double randomNumber1 = generateRandomNumber(-0.015, 0.015, random);
    double randomNumber2 = generateRandomNumber(-0.015, 0.015, random);
    final GoogleMapController controller = await _controller.future;
    final locationData = await location.getLocation();
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    String localUid = FirebaseAuth.instance.currentUser!.uid;
    if (updateUserLocation) {
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
    controller.animateCamera(CameraUpdate.newCameraPosition(_newPosition));
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

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    //padding.top represents the height of the status bar which varies by device
    double mapHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;
    double toolbarHeight = 56;
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
        //title: Text(widget.title),
        backgroundColor: Color(0xFF082D38),
        actions: [
          // Add the TextField wrapped in a StatefulBuilder
          Spacer(),
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: 48.0,
              width: screenWidth * 0.5,
              child: TextField(
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  hintText: 'find interests and people',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12.0), // Adjust as needed
                  ),
                ),
                onChanged: (value) async {
                  //we calculated this difference to determine if a user has deleted a character.
                  var diff = value.length - searchTerm.length ;
                  var charDeleted = (diff == -1);
                  if(charDeleted) {
                    print('user deleted a character from searchbar');
                  }
                  _onCameraMove(_currentZoom);
                  setState(() {
                    searchTerm = value;
                  });
                  // Perform search based on the value
                  CollectionReference users =
                      FirebaseFirestore.instance.collection('users');
                  List<String> results =
                      await fu.searchForPeopleAndInterests(users, value, true);
                  //_onCameraMove(_currentZoom);
                  print('these are the results of the search $results');
                  setState(() {
                    // Update search results based on the value
                    print('before values');
                    for (var item in markers) {
                      print(item.markerId);
                    }
                    searchFilteredMarkers = markers;
                    searchFilteredResults = results;
                    print('after values');
                    for (var item in markers) {
                      print(item.markerId);
                    }
                      _onCameraMove(_currentZoom);
                  });

                },
              ),
            ),
          ),
          Spacer(),
          Builder(
            builder: (context) => IconButton(
              icon: Image.asset('assets/poio.png'),
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
                                  ? mapHeight - toolbarHeight - 80
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
                                    myLocationButtonEnabled: true,
                                    compassEnabled: true,
                                    minMaxZoomPreference:
                                        MinMaxZoomPreference(3.0, 900.0),
                                    markers: markers,
                                    onMapCreated:
                                        (GoogleMapController controller) async {
                                      double zoom =
                                          await controller.getZoomLevel();
                                      _currentZoom = zoom;
                                      print('onMapCreated is running');
                                      if (_controller.isCompleted) {
                                        _controller = Completer();
                                      }
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
                                      _controller.complete(controller);
                                    },
                                  ),
                                  Positioned(
                                    bottom: 75,
                                    right: 10,
                                    child: FloatingActionButton(
                                      mini: true,
                                      onPressed: () async {
                                        setState(() {
                                          //_zoomEnabled = false;
                                          mapOptionsVisibility =
                                              !mapOptionsVisibility;
                                        });
                                      },
                                      child: Icon(Icons.location_on),
                                      backgroundColor: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            //Visibility(
                            //visible: mapOptionsVisibility,
                            //child:
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: 10,
                                ),
                                child: Visibility(
                                  visible: mapOptionsVisibility,
                                  child: Column(children: [
                                    SizedBox(height: 10),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            _markerDraggabilityText,
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                          SizedBox(
                                            width: 40,
                                          ),
                                          Container(
                                            padding: EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                                color: Colors.blue,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: SizedBox(
                                              height: 40,
                                              width: 100,
                                              child: AnimatedToggleSwitch<
                                                  int>.rolling(
                                                current: toggleIndex,
                                                values: [0, 1],
                                                onChanged: (i) async {
                                                  print(toggleIndex);
                                                  setState(
                                                      () => toggleIndex = i);
                                                  bool choice = (i == 1);
                                                  _setDraggabilityUserModel(
                                                      choice);
                                                  await loadMarkers(true);
                                                  _onCameraMove(_currentZoom);
                                                  setState(
                                                      () => toggleIndex = i);
                                                  print(toggleIndex);
                                                  setState(() {
                                                    _zoomEnabled = true;
                                                    if (!choice) {
                                                      mapOptionsVisibility =
                                                          false;
                                                      _markerDraggabilityText =
                                                          'Your marker is not movable';
                                                    } else {
                                                      _markerDraggabilityText =
                                                          'Your marker is movable';
                                                    }
                                                  });
                                                },
                                                //loading: false, // for deactivating loading animation
                                                iconBuilder: rollingIconBuilder,
                                                style: ToggleStyle(),
                                                height: 50,
                                              ),
                                            ),
                                          ),
                                        ]),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                          //),
                        ),
                      ),
                    ),
                    Interests(
                      name: _name,
                      scaffoldKey: _scaffoldKey,
                      signedIn: _signedIn,
                    ),
                    custom_preview.Preview(
                      uid: _uid,
                      alternateUid: _uid,
                      scaffoldKey: _scaffoldKey,
                      onItemTapped: _onItemTapped,
                      signedIn: _signedIn,
                      onDrawerOpened: () {},
                    ),
                    Messaging(user_uid: _uid),
                    Text(
                      'Index 4: Replace this text widget with the Sign Out widget',
                      style: optionStyle,
                    ),
                  ][_selectedIndex]
                : <Widget>[
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
                        double zoom = await controller.getZoomLevel();
                        _currentZoom = zoom;
                        print('onMapCreated is running');
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
                        setState(() {});
                      },
                    ),
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
                    child: Text("$_name : $_uid"),
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
                    title: const Text('My Interests'),
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
        width: MediaQuery.of(context).size.width * 1, //<-- SEE HERE
        child: Container(
          alignment: Alignment.topCenter,
          child: Interests(
            name: _name,
            scaffoldKey: _scaffoldKey,
            signedIn: _signedIn,
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
