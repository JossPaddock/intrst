import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUtility.dart';
import 'package:intrst/widgets/Interests.dart';
import 'package:intrst/widgets/Preview.dart';
import 'package:provider/provider.dart';
import 'login/LoginScreen.dart';
import 'widgets/InterestInputForm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:label_marker/label_marker.dart';
import 'package:location/location.dart';

//import is for google maps
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => UserModel(),
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
  final FirebaseUtility fu = FirebaseUtility();
  Set<Marker> labelMarkers = {};
  Set<Marker> poiMarkers = {};
  Set<Marker> markers = {};
  BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarker;

  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        print('User is currently signed out!');
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
          markers = labelMarkers;
        });
        _currentZoom = zoom;
      } else if (zoom < level && _currentZoom > level) {
        print('load poi markers');
        setState(() {
          markers = poiMarkers;
        });
        _currentZoom = zoom;
      }
    } else {
      //the following conditions are critical for resetting after search updates
      if (_currentZoom > level) {
        setState(() {
          markers = {};
          markers = labelMarkers;
        });
      } else {
        setState(() {
          markers = {};
          markers = poiMarkers;
        });
      }
    }
    print('this is how many markers: ' + markers.length.toString());
    //print(markers);
  }

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.423458, -110.310349),
    zoom: 14.4746,
  );

  static const CameraPosition _kLake = CameraPosition(
      bearing: 192.8334901395799,
      target: LatLng(37.43296265331129, -122.08832357078792),
      tilt: 59.440717697143555,
      zoom: 3);

  bool _zoomEnabled = true;

  BitmapDescriptor poi = BitmapDescriptor.defaultMarker;

  Future<Uint8List> loadAssetAsByteData(String path) async {
    ByteData data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  late String _mapStyleString;
  @override
  void initState() {
    initializeFirebase();
    _goToInitialPosition(_controller);
    _goToInitialPosition(_controllerSignedOut);
    rootBundle.loadString('assets/mapstyle.json').then((string) {
      _mapStyleString = string;
    });
    setState(() {
      markers = poiMarkers;
    });
    super.initState();
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
              return Preview(
                uid: uid,
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
      BitmapDescriptor poi, String uid) {
    setState(() {
      poiMarkers.add(Marker(
          icon: poi,
          markerId: MarkerId(uid),
          //maybe someday this offset below will work. It should!
          anchor: Offset(0.5, 0.5),
          position: LatLng(lat, lng),
          draggable: drag,
          zIndex: drag ? 10 : 1,
          onTap: () {
            markers = {};
            handleMarkerTap(title, uid, true);
            setState(() {});
          },
          onDragEnd: (LatLng newPosition) {
            fu.updateUserLocation(
                FirebaseFirestore.instance.collection('users'),
                FirebaseAuth.instance.currentUser!.uid,
                GeoPoint(newPosition.latitude, newPosition.longitude));
            loadMarkers(true);
            //
            setState(() {});
          }));
    });

    var color = Colors.white;
    if (drag) {
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
            zIndex: drag ? 10 : 1,
            onTap: () {
              markers = {};
              handleMarkerTap(title, uid, false);
              setState(() {});
            },
            onDragEnd: (LatLng newPosition) {
              fu.updateUserLocation(
                  FirebaseFirestore.instance.collection('users'),
                  FirebaseAuth.instance.currentUser!.uid,
                  GeoPoint(newPosition.latitude, newPosition.longitude));
              loadMarkers(true);
              setState(() {
                updateMarkerDragState(uid, false);
              });
            }))
        .then(
      (value) {
        setState(() {});
      },
    );
  }

  void updateMarkerDragState(String uid, bool draggable) {
    poiMarkers = poiMarkers.map((marker) {
      if (marker.markerId.value == _uid && marker.markerId.value == uid) {
        marker.copyWith(draggableParam: draggable);
      }
      return marker;
    }).toSet();

    labelMarkers = labelMarkers.map((marker) {
      if (marker.markerId.value == _uid && marker.markerId.value == uid) {
        marker.copyWith(draggableParam: draggable);
      }
      return marker;
    }).toSet();
  }

  void loadMarkers(bool loadUserMarker) async {
    //Call this if your are dragging the marker!!
    await Future.delayed(Duration(milliseconds: 1500));
    Uint8List imageData = await loadAssetAsByteData('assets/poi.png');
    poi = await BitmapDescriptor.bytes(imageData,
        width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    //user
    if (loadUserMarker) {
      Uint8List userImageData = await loadAssetAsByteData('assets/poio.png');
      BitmapDescriptor poio = await BitmapDescriptor.bytes(userImageData,
          width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
      var signedInUserMarkerData =
          await fu.lookUpNameAndLocationByUserUid(users, _uid);
      //This is where we load the signed in users marker
      addMarker(signedInUserMarkerData[0], signedInUserMarkerData[1],
          signedInUserMarkerData[2], true, poio, _uid);
    }
    print('loadMarkers is working');
    var uids = await fu.retrieveAllUserUid(users);
    uids.forEach((uid) async {
      var markerData = await fu.lookUpNameAndLocationByUserUid(users, uid);
      if (uid != _uid) {
        addMarker(markerData[0], markerData[1], markerData[2], false, poi, uid);
      }
    });
    setState(() {});
  }

  //Make marker loading more reliable (work on first load)
  //loading other users markers besides logged in user(start by testing firebase utility function that gets all user uids)

  Future<void> _getLocationServiceAndPermission(
      Completer<GoogleMapController> controllerCompleter) async {
    print('getLocationServiceAndPermission is running');
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<String> results =
        await fu.searchForPeopleAndInterests(users, "oss Paddoc");
    print('these are the results of the search $results');
    print('hello world');
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
    /*final userLocation = await fu.retrieveUserLocation(
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
    } */
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
    loadMarkers(loadUserMarker);
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
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeUid(value);
  }

  void _handleAlternateUserModel(String value, String name) {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeAlternateUid(value);
    userModel.changeAlternateName(name);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  static const TextStyle optionStyle =
      TextStyle(fontSize: 30, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu),
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
                  // Perform search based on the value
                  _onCameraMove(_currentZoom);
                  CollectionReference users =
                      FirebaseFirestore.instance.collection('users');
                  List<String> results =
                      await fu.searchForPeopleAndInterests(users, value);
                  print('these are the results of the search $results');
                  setState(() {
                    // Update search results based on the value
                    print('before values');
                    for (var item in markers) {
                      print(item.markerId);
                    }
                    markers = markers
                        .where(
                            (value) => results.contains(value.markerId.value))
                        .toSet();
                    print('after values');
                    for (var item in markers) {
                      print(item.markerId);
                    }
                    loadMarkers(_signedIn);
                    if (value == "" || value == " ") {
                      _onCameraMove(_currentZoom);
                    }
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
        child: _signedIn // _signedInGoogleMap
            ? <Widget>[
                Scaffold(
                  body: Stack(
                    children: <Widget>[
                      GoogleMap(
                        onCameraMove: (CameraPosition cameraPosition) {
                          _onCameraMove(cameraPosition.zoom);
                        },
                        //cloudMapId: mapId, // Set the map style ID here
                        zoomGesturesEnabled: _zoomEnabled,
                        gestureRecognizers: _zoomEnabled
                            ? <Factory<OneSequenceGestureRecognizer>>{
                                Factory<PanGestureRecognizer>(
                                    () => PanGestureRecognizer()),
                                Factory<ScaleGestureRecognizer>(
                                    () => ScaleGestureRecognizer()),
                                Factory<TapGestureRecognizer>(
                                    () => TapGestureRecognizer()),
                                Factory<VerticalDragGestureRecognizer>(
                                    () => VerticalDragGestureRecognizer()),
                              }
                            : <Factory<OneSequenceGestureRecognizer>>{}.toSet(),
                        initialCameraPosition: _kGooglePlex,
                        zoomControlsEnabled: false,
                        minMaxZoomPreference: MinMaxZoomPreference(3.0, 900.0),
                        markers: markers,
                        onMapCreated: (GoogleMapController controller) async {
                          print('onMapCreated is running');
                          if (_controller.isCompleted) {
                            _controller = Completer();
                          }
                          //await Future.delayed(Duration(milliseconds: 10000));
                          _controller.future.then((value) {
                            value.setMapStyle(_mapStyleString);
                          });
                          print('mapStyle should be set');
                          _getLocationServiceAndPermission(_controller);
                          _gotoCurrentUserLocation(false, _signedIn);
                          print('callback is working');
                          setState(() {});
                          if (markers.isEmpty) {
                            loadMarkers(true);
                          }
                          _controller.complete(controller);
                        },
                      ),
                    ],
                  ),
                ),
                Interests(name: _name, signedIn: _signedIn),
                Preview(
                    uid: _uid,
                    scaffoldKey: _scaffoldKey,
                    onItemTapped: _onItemTapped,
                    signedIn: _signedIn, onDrawerOpened: () {  },),
                Text(
                  'Index 3: Replace this text widget with the Messages widget',
                  style: optionStyle,
                ),
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
                  //cloudMapId: mapId, // Set the map style ID here
                  zoomGesturesEnabled: _zoomEnabled,
                  initialCameraPosition: _kGooglePlex,
                  zoomControlsEnabled: false,
                  minMaxZoomPreference: MinMaxZoomPreference(3.0, 900.0),
                  markers: markers,
                  onMapCreated: (GoogleMapController controller) async {
                    print('onMapCreated is running');
                    if (_controllerSignedOut.isCompleted) {
                      _controllerSignedOut = Completer();
                    }

                    _controllerSignedOut.future.then((value) {
                      value.setMapStyle(_mapStyleString);
                    });
                    print('mapStyle should be set');
                    print('callback is working');
                    setState(() {});
                    print(markers.length);
                    loadMarkers(false);
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
          child: Interests(name: _name, signedIn: _signedIn),
          alignment: Alignment.topCenter,
        ),
      ),
      drawerEdgeDragWidth: 200,
      onEndDrawerChanged: (state) {
        print('endDrawer is $state');
        if (state) {
          markers = {};
        } else {
          _onCameraMove(_currentZoom);
        }
        setState(() {
          _zoomEnabled = !state;
        });
      },
    );
  }
}
