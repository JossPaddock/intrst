part of 'package:intrst/main.dart';

extension _HomeMapLogic on _MyHomePageState {
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000;

    double lat1Rad = point1.latitude * pi / 180;
    double lat2Rad = point2.latitude * pi / 180;
    double deltaLat = (point2.latitude - point1.latitude) * pi / 180;
    double deltaLng = (point2.longitude - point1.longitude) * pi / 180;

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
            sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /*double _getVisualProximityThreshold(double zoom) {
    // examples of how the formula works according to ai:
    // zoom level 3, markers ~1000km apart considered "close"
    // zoom level 10, markers ~10km apart considered "close"
    // zoom level 15, markers ~300m apart considered "close"
    // zoom level 20, markers ~10m apart considered "close"
    const double labelAggressiveness = 0.07;
    // This formula creates an exponential relationship
    // don't do it with out Shubh!! You can adjust the base value (40075000) and exponent to tune behavior (don't do it with out Shubh!!)
    double threshold = (40075000 * labelAggressiveness) / pow(2, zoom - 1); // Earth's circumference / 2^(zoom-1)

    const double minThreshold = 10; // in meters
    const double maxThreshold = 10000000; // 100km

    threshold = threshold.clamp(minThreshold, maxThreshold);

    print('At zoom $zoom, proximity threshold is ${threshold} meters');
    return threshold;
  }*/

  double _getVisualProximityThreshold(double zoom) {
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

  Set<String> _getMarkersToShowAsLabels(double currentZoom) {
    const double minLabelZoom = 2.0;
    const double alwaysLabelDistance = 1000000; // 10km for always label markers distances

    Set<String> showAsLabels = {};

    double proximityThreshold = _getVisualProximityThreshold(currentZoom);

    List<MapEntry<String, LatLng>> markerPositions = [];
    for (var marker in poiMarkers) {
      markerPositions.add(MapEntry(marker.markerId.value, marker.position));
    }

    for (int i = 0; i < markerPositions.length; i++) {
      double minDistanceToAnyMarker = double.infinity;

      for (int j = 0; j < markerPositions.length; j++) {
        if (i != j) {
          double distance = _calculateDistance(
            markerPositions[i].value,
            markerPositions[j].value,
          );

          if (distance < minDistanceToAnyMarker) {
            minDistanceToAnyMarker = distance;
          }
        }
      }

      if (minDistanceToAnyMarker > alwaysLabelDistance) {
        print('loner markers' + markerPositions[i].value.toString());
        showAsLabels.add(markerPositions[i].key);
      } else if (currentZoom >= minLabelZoom && minDistanceToAnyMarker >= proximityThreshold) {
        showAsLabels.add(markerPositions[i].key);
      }
    }

    print('At zoom $currentZoom: ${showAsLabels.length} markers shown as labels, ${markerPositions.length - showAsLabels.length} as POI');
    return showAsLabels;
  }

  void _onCameraMove(double zoom) {
    const double minLabelZoom = 2.0;

    Set<String> showAsLabels = _getMarkersToShowAsLabels(zoom);

    setState(() {
      markers = {};

      if (searchTerm == '') {
        if (zoom < minLabelZoom) {
          markers = poiMarkers;
        } else {
          markers.addAll(
              labelMarkers.where((marker) => showAsLabels.contains(marker.markerId.value))
          );
          markers.addAll(
              poiMarkers.where((marker) => !showAsLabels.contains(marker.markerId.value))
          );
        }
      } else {
        if (zoom < minLabelZoom) {
          markers = poiMarkers
              .where((marker) => searchFilteredResults.contains(marker.markerId.value))
              .toSet();
        } else {
          markers.addAll(
              labelMarkers.where((marker) =>
              searchFilteredResults.contains(marker.markerId.value) &&
                  showAsLabels.contains(marker.markerId.value))
          );
          markers.addAll(
              poiMarkers.where((marker) =>
              searchFilteredResults.contains(marker.markerId.value) &&
                  !showAsLabels.contains(marker.markerId.value))
          );
        }
      }
    });

    _currentZoom = zoom;
  }

/*
  Set<String> _getProximityRestrictedMarkers(double currentZoom) {
    const double proximityThreshold = 2000;
    const double baseZoomLevel = 10.5;
    const double proximityZoomLevel = 14.0;

    Set<String> restrictedMarkers = {};

    if (currentZoom <= baseZoomLevel || currentZoom >= proximityZoomLevel) {
      return restrictedMarkers;
    }

    List<MapEntry<String, LatLng>> markerPositions = [];
    for (var marker in poiMarkers) {
      markerPositions.add(MapEntry(marker.markerId.value, marker.position));
    }

    for (int i = 0; i < markerPositions.length; i++) {
      bool hasCloseNeighbor = false;

      for (int j = 0; j < markerPositions.length; j++) {
        if (i != j) {
          double distance = _calculateDistance(
            markerPositions[i].value,
            markerPositions[j].value,
          );

          if (distance < proximityThreshold) {
            hasCloseNeighbor = true;
            break;
          }
        }
      }

      if (hasCloseNeighbor) {
        restrictedMarkers.add(markerPositions[i].key);
      }
    }

    return restrictedMarkers;
  }

  void _onCameraMove(double zoom) {
    double baseLevel = 10.5;
    double proximityLevel = 13.0;

    if (_currentZoom != zoom) {
      Set<String> proximityRestricted = _getProximityRestrictedMarkers(zoom);

      if (zoom > baseLevel && _currentZoom < baseLevel) {
        setState(() {
          if (searchTerm == '') {
            markers = labelMarkers
                .where((marker) => !proximityRestricted.contains(marker.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((marker) => proximityRestricted.contains(marker.markerId.value))
            );
          } else {
            markers = labelMarkers
                .where((value) =>
            searchFilteredResults.contains(value.markerId.value) &&
                !proximityRestricted.contains(value.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((value) =>
                searchFilteredResults.contains(value.markerId.value) &&
                    proximityRestricted.contains(value.markerId.value))
            );
          }
        });
        _currentZoom = zoom;
      } else if (zoom > proximityLevel && _currentZoom < proximityLevel) {
        print('load all label markers (proximity threshold passed)');
        setState(() {
          if (searchTerm == '') {
            markers = labelMarkers;
          } else {
            markers = labelMarkers
                .where((value) => searchFilteredResults.contains(value.markerId.value))
                .toSet();
          }
        });
        _currentZoom = zoom;
      } else if (zoom < proximityLevel && _currentZoom > proximityLevel) {
        print('applying proximity check when zooming out');
        setState(() {
          Set<String> restricted = _getProximityRestrictedMarkers(zoom);
          if (searchTerm == '') {
            markers = labelMarkers
                .where((marker) => !restricted.contains(marker.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((marker) => restricted.contains(marker.markerId.value))
            );
          } else {
            markers = labelMarkers
                .where((value) =>
            searchFilteredResults.contains(value.markerId.value) &&
                !restricted.contains(value.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((value) =>
                searchFilteredResults.contains(value.markerId.value) &&
                    restricted.contains(value.markerId.value))
            );
          }
        });
        _currentZoom = zoom;
      } else if (zoom < baseLevel && _currentZoom > baseLevel) {
        print('load poi markers');
        setState(() {
          if (searchTerm == '') {
            markers = poiMarkers;
          } else {
            markers = poiMarkers
                .where((value) => searchFilteredResults.contains(value.markerId.value))
                .toSet();
          }
        });
        _currentZoom = zoom;
      }
    } else {
      Set<String> proximityRestricted = _getProximityRestrictedMarkers(_currentZoom);

      if (_currentZoom > proximityLevel) {
        setState(() {
          if (searchTerm == '') {
            markers = labelMarkers;
          } else {
            markers = labelMarkers
                .where((value) => searchFilteredResults.contains(value.markerId.value))
                .toSet();
          }
        });
      } else if (_currentZoom > baseLevel) {
        setState(() {
          if (searchTerm == '') {
            markers = labelMarkers
                .where((marker) => !proximityRestricted.contains(marker.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((marker) => proximityRestricted.contains(marker.markerId.value))
            );
          } else {
            markers = labelMarkers
                .where((value) =>
            searchFilteredResults.contains(value.markerId.value) &&
                !proximityRestricted.contains(value.markerId.value))
                .toSet();
            markers.addAll(
                poiMarkers.where((value) =>
                searchFilteredResults.contains(value.markerId.value) &&
                    proximityRestricted.contains(value.markerId.value))
            );
          }
        });
      } else {
        setState(() {
          if (searchTerm == '') {
            markers = poiMarkers;
          } else {
            markers = poiMarkers
                .where((value) => searchFilteredResults.contains(value.markerId.value))
                .toSet();
          }
        });
      }
    }
  }*/

  Future<Uint8List> loadAssetAsByteData(String path) async {
    ByteData data = await rootBundle.load(path);
    return data.buffer.asUint8List();
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
                onOpenMessages: _openMessagesForUserFromFeed,
              );
            }).then((drawerOpened) {
          if (drawerOpened != true) {
            _zoomEnabled = true;
          }
          _onCameraMove(_currentZoom);
        });
      }
    }
  }

  void addMarkers(Set<Marker> markers) {}

  Future<void> addMarker(String title, double lat, double lng, bool drag,
      BitmapDescriptor poi, String uid, bool user) async {
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

    await labelMarkers
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
        }));
    setState(() {});
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
        await addMarker(
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
      for (final uid in uids) {
        var markerData = await fu.lookUpNameAndLocationByUserUid(users, uid);
        if (uid != _uid) {
          await addMarker(
              markerData[0], markerData[1], markerData[2], false, poi,
              uid, false);
        }
      }
      _onCameraMove(_currentZoom);
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
}
