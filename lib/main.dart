import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:name_app/models/UserModel.dart';
import 'package:name_app/utility/FirebaseUtility.dart';
import 'package:name_app/widgets/Interests.dart';
import 'package:provider/provider.dart';
import 'login/LoginScreen.dart';
import 'widgets/ButtonWidget.dart';
import 'widgets/InterestInputForm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:ui' as ui;
import 'package:label_marker/label_marker.dart';
import 'package:geolocator/geolocator.dart';
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

  static const appTitle = 'Drawer Demo';

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
  late List<Widget> _signedOutWidgetOptions;
  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        print('User is currently signed out!');
      } else {
        print('User is signed in!');
        _signedIn = true;
        _selectedIndex = 0;
        CollectionReference users =
            FirebaseFirestore.instance.collection('users');
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

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  void _onCameraMove(double zoom) {
    if (_currentZoom != zoom) {
      //print('$_currentZoom + $zoom');
      double level = 10.5;
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
    }
  }

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.423458, -110.310349),
    zoom: 14.4746,
  );

  static const CameraPosition _kLake = CameraPosition(
      bearing: 192.8334901395799,
      target: LatLng(37.43296265331129, -122.08832357078792),
      tilt: 59.440717697143555,
      zoom: 19.151926040649414);

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
    rootBundle.loadString('mapstyle.json').then((string) {
      _mapStyleString = string;
    });
    setState(() {
      markers = poiMarkers;
    });
    _signedOutWidgetOptions = <Widget>[
      Text(
        'Index 0: Replace this text widget with the google map widget',
        style: optionStyle,
      ),
      LoginScreen(
        signedIn: _signedIn,
        onSignInChanged: _handleSignInChanged,
        onSelectedIndexChanged: _onItemTapped,
        onNameChanged: _handleNameChanged,
        onUidChanged: _handleUidChanged,
      ),
    ];
    super.initState();
  }

  void addMarkers(Set<Marker> markers) {}

  void addMarker(String title, double lat, double lng, bool drag) {
    setState(() {
      poiMarkers.add(Marker(
          icon: poi,
          markerId: MarkerId(title),
          position: LatLng(lat, lng),
          draggable: drag,
          onDragEnd: (LatLng newPosition) {
            fu.updateUserLocation(
                FirebaseFirestore.instance.collection('users'),
                FirebaseAuth.instance.currentUser!.uid,
                GeoPoint(newPosition.latitude, newPosition.longitude));
            loadMarkers();
            print(markers);
            setState(() {
              /*
              for (var marker in markers) {
                if (marker.markerId.value == title) {
                  markers.remove(marker);
                  markers.add(marker.copyWith(positionParam: newPosition));
                }
              }*/
            });
          }));
    });

    labelMarkers
        .addLabelMarker(LabelMarker(
            icon: BitmapDescriptor.defaultMarker,
            label: title,
            markerId: MarkerId(title),
            position: LatLng(lat, lng),
            backgroundColor: const Color(0xFFFFFF),
            draggable: drag,
            onDragEnd: (LatLng newPosition) {
              fu.updateUserLocation(
                  FirebaseFirestore.instance.collection('users'),
                  FirebaseAuth.instance.currentUser!.uid,
                  GeoPoint(newPosition.latitude, newPosition.longitude));
              loadMarkers();
              print(markers);
              setState(() {
                /*
                for (var marker in markers) {
                  if (marker.markerId.value == title) {
                    markers.remove(marker);
                    markers.add(marker.copyWith(positionParam: newPosition));
                  }
                }*/
              });
            }))
        .then(
      (value) {
        setState(() {});
      },
    );
  }

  void loadMarkers() async {
    //markers = {};
    await Future.delayed(Duration(milliseconds: 1500));
    Uint8List imageData = await loadAssetAsByteData('assets/poi.png');
    poi = await BitmapDescriptor.bytes(imageData,
        width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    var signedInUserMarkerData =
        await fu.lookUpNameAndLocationByUserUid(users, _uid);
    //This is where we load the signed in users marker
    addMarker(signedInUserMarkerData[0], signedInUserMarkerData[1],
        signedInUserMarkerData[2], true);
    print('loadMarkers is working');
    var uids = await fu.retrieveAllUserUid(users);
    print(uids);
    uids.forEach((uid) async {
      var markerData = await fu.lookUpNameAndLocationByUserUid(users, uid);
      if (uid != _uid) {
        addMarker(markerData[0], markerData[1], markerData[2], false);
      }
    });
    setState(() {});
  }

  //Make marker loading more reliable (work on first load)
  //loading other users markers besides logged in user(start by testing firebase utility function that gets all user uids)

  Future<void> _getLocationServiceAndPermission() async {
    final GoogleMapController controller = await _controller.future;
    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }
    //do a soft check to determine if latlng is 0,0
    //if it is 0,0 update user location
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    final userLocation = await fu.retrieveUserLocation(
        users, FirebaseAuth.instance.currentUser!.uid);
    if (userLocation == GeoPoint(0, 0)) {
      print('user location was 0,0');
      _gotoCurrentUserLocation(true);
      _permissionGranted = await location.hasPermission();
      if (_permissionGranted == PermissionStatus.denied) {
        _permissionGranted = await location.requestPermission();
        if (_permissionGranted != PermissionStatus.granted) {
          return;
        } else {
          _gotoCurrentUserLocation(false);
        }
      } else {
        _newPosition = CameraPosition(
            target: LatLng(userLocation.latitude /*+ randomNumber1*/,
                userLocation.longitude /*+ randomNumber2*/),
            zoom: 12);
        controller.animateCamera(CameraUpdate.newCameraPosition(_newPosition));
      }
    }
  }

  Future<void> _gotoCurrentUserLocation(bool updateUserLocation) async {
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
          GeoPoint(locationData.latitude! /*+ randomNumber1*/,
              locationData.longitude! /*+ randomNumber2*/));
    }
    _newPosition = CameraPosition(
        target: LatLng(locationData.latitude! /*+ randomNumber1*/,
            locationData.longitude! /*+ randomNumber2*/),
        zoom: 12);
    loadMarkers();
    controller.animateCamera(CameraUpdate.newCameraPosition(_newPosition));
  }

  double generateRandomNumber(double min, double max, Random random) {
    return min + random.nextDouble() * (max - min);
  }

  Future<void> _goToTheLake() async {
    final GoogleMapController controller = await _controller.future;
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  static const TextStyle optionStyle =
      TextStyle(fontSize: 30, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              color: Colors.white,
              onPressed: () {
                Scaffold.of(context).openDrawer();
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
              width: 400.0,
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
                onChanged: (value) {
                  // Perform search based on the value
                  setState(() {
                    // Update search results based on the value
                  });
                },
              ),
            ),
          ),
          Spacer(),
          Builder(
            builder: (context) => IconButton(
              icon: Image.asset('assets/poi.png'),
              color: Colors.white,
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
          ),
        ],
      ),
      body: Center(
        child:
            _signedIn //todo: instead of dynamically loading all of the signed in widgets inject only the Google map widget into a list of late initialized _signedIn widgets(see _signedOut initialized objects as an example of late initialization)
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
                            initialCameraPosition: _kGooglePlex,
                            zoomControlsEnabled: false,
                            minMaxZoomPreference:
                                MinMaxZoomPreference(3.0, 900.0),
                            markers: markers,
                            onMapCreated: (GoogleMapController controller) {
                              print('onMapCreated is running');
                              _controller.future.then((value) {
                                value.setMapStyle(_mapStyleString);
                              });
                              print('mapStyle should be set');
                              _getLocationServiceAndPermission();
                              _gotoCurrentUserLocation(false);
                              print('callback is working');
                              setState(() {});
                              loadMarkers();
                              _controller.complete(controller);
                            },
                          ),
                          Text('name'),
                        ],
                      ),
                    ),
                    InterestInputForm(),
                    ButtonWidget(),
                    Text(
                      'Index 3: Replace this text widget with the Messages widget',
                      style: optionStyle,
                    ),
                    Text(
                      'Index 4: Replace this text widget with the Sign Out widget',
                      style: optionStyle,
                    ),
                  ][_selectedIndex]
                : _signedOutWidgetOptions[_selectedIndex],
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
                      _onItemTapped(0);
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
                      _onItemTapped(1);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
      ),
      endDrawer: SizedBox(
        width: MediaQuery.of(context).size.width * 1, //<-- SEE HERE
        child: Interests(name: _name, signedIn: _signedIn),
      ),
      onEndDrawerChanged: (state) {
        setState(() {
          _zoomEnabled = !state;
        });
      },
    );
  }
}
