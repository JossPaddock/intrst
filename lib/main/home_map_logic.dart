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

  Set<String> _getMarkersToShowAsLabels(double currentZoom, {List<String>? filteredUids}) {
    const double minLabelZoom = 2.0;
    const double alwaysLabelDistance = 1000000; // 1000km for always label markers distances

    Set<String> showAsLabels = {};

    double proximityThreshold = _getVisualProximityThreshold(currentZoom);

    List<MapEntry<String, LatLng>> markerPositions = [];
    for (var marker in poiMarkers) {
      if (filteredUids == null || filteredUids.isEmpty || filteredUids.contains(marker.markerId.value)) {
        markerPositions.add(MapEntry(marker.markerId.value, marker.position));
      }
    }

    int n = markerPositions.length;
    
    for (int i = 0; i < n; i++) {
      double minDistanceToAnyMarker = double.infinity;
      LatLng p1 = markerPositions[i].value;

      for (int j = 0; j < n; j++) {
        if (i == j) continue;
        
        LatLng p2 = markerPositions[j].value;
        
      
        double latDelta = (p1.latitude - p2.latitude).abs();
        double lngDelta = (p1.longitude - p2.longitude).abs();
        
        if (latDelta > 10 || lngDelta > 10) {
           continue; 
        }

        double distance = _calculateDistance(p1, p2);

        if (distance < minDistanceToAnyMarker) {
          minDistanceToAnyMarker = distance;
          if (currentZoom >= minLabelZoom && distance < proximityThreshold) {
            break; 
          }
        }
      }

      if (minDistanceToAnyMarker > alwaysLabelDistance) {
        showAsLabels.add(markerPositions[i].key);
      } else if (currentZoom >= minLabelZoom && minDistanceToAnyMarker >= proximityThreshold) {
        showAsLabels.add(markerPositions[i].key);
      }
    }

    print('At zoom $currentZoom: ${showAsLabels.length} markers shown as labels, ${markerPositions.length - showAsLabels.length} as POI');
    return showAsLabels;
  }

  // Label markers carry this suffix on their MarkerId so they can be shown on
  // top of the always-visible POI marker (which uses the bare uid) instead of
  // replacing it.
  static const String _labelIdSuffix = '_label';

  String _labelMarkerId(String uid) => '$uid$_labelIdSuffix';

  String _uidFromLabelMarkerId(String labelMarkerId) =>
      labelMarkerId.endsWith(_labelIdSuffix)
          ? labelMarkerId.substring(
              0, labelMarkerId.length - _labelIdSuffix.length)
          : labelMarkerId;

  // The label_marker package paints the text near the top of the bitmap and
  // leaves a fixed block of dead space (arrow + padding) at the bottom: the
  // bitmap height is textHeight + 50, with the text drawn at y = 10. A centered
  // anchor (0.5, 0.5) therefore lands the geo-point on the bitmap's center,
  // which sits ~15px below the text center, making the label float above the
  // POI dot. This returns the anchor whose y aligns the *text* center with the
  // point so the label sits directly on the dot.
  Offset _labelAnchor(String text, TextStyle textStyle) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final double bitmapHeight = painter.height + 50;
    final double textCenter = 10 + painter.height / 2;
    return Offset(0.5, textCenter / bitmapHeight);
  }

  void _onCameraMove(double zoom) {
    const double minLabelZoom = 2.0;

    Set<String> showAsLabels = _getMarkersToShowAsLabels(zoom,
        filteredUids: searchTerm.isEmpty ? null : searchFilteredResults);

    setState(() {
      markers = {};

      if (_useOriginalMarkerBehavior) {
        // Original behavior: POI and label are mutually exclusive — a marker
        // shows as a label when in `showAsLabels`, otherwise as a POI dot.
        if (searchTerm == '') {
          if (zoom < minLabelZoom) {
            markers.addAll(poiMarkers);
          } else {
            markers.addAll(labelMarkers.where((marker) =>
                showAsLabels.contains(_uidFromLabelMarkerId(marker.markerId.value))));
            markers.addAll(poiMarkers
                .where((marker) => !showAsLabels.contains(marker.markerId.value)));
          }
        } else {
          if (zoom < minLabelZoom) {
            markers.addAll(poiMarkers.where(
                (marker) => searchFilteredResults.contains(marker.markerId.value)));
          } else {
            markers.addAll(labelMarkers.where((marker) {
              final String uid = _uidFromLabelMarkerId(marker.markerId.value);
              return searchFilteredResults.contains(uid) &&
                  showAsLabels.contains(uid);
            }));
            markers.addAll(poiMarkers.where((marker) =>
                searchFilteredResults.contains(marker.markerId.value) &&
                !showAsLabels.contains(marker.markerId.value)));
          }
        }
      } else {
        // New behavior: POI markers are always shown (respecting the active
        // search filter)...
        markers.addAll(
          poiMarkers.where((marker) =>
              searchTerm == '' ||
              searchFilteredResults.contains(marker.markerId.value)),
        );

        // ...and label markers are layered on top, shown/hidden by the same
        // zoom + proximity logic as before.
        if (zoom >= minLabelZoom) {
          markers.addAll(
            labelMarkers.where((marker) {
              final String uid = _uidFromLabelMarkerId(marker.markerId.value);
              if (!showAsLabels.contains(uid)) return false;
              if (searchTerm != '' && !searchFilteredResults.contains(uid)) {
                return false;
              }
              return true;
            }),
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

    final TextStyle labelTextStyle = TextStyle(
      color: color,
      fontSize: 27.0,
      letterSpacing: 1.0,
      fontFamily: 'Roboto Bold',
    );

    await labelMarkers
        .addLabelMarker(LabelMarker(
        icon: BitmapDescriptor.defaultMarker,
        label: title,
        textStyle: labelTextStyle,
        // Distinct id so the label can coexist with the always-shown POI
        // marker (which uses the bare uid).
        markerId: MarkerId(_labelMarkerId(uid)),
        // Anchor so the label text centers on the POI dot instead of floating
        // above it.
        anchor: _labelAnchor(title, labelTextStyle),
        position: LatLng(lat, lng),
        backgroundColor: const Color(0x00000000),
        // The POI marker (always visible) handles dragging; the label sits on
        // top of it and renders above all POI dots.
        draggable: false,
        zIndex: (drag ? 10 : (user ? 5 : 1)) + 1000,
        onTap: () {
          markers = {};
          handleMarkerTap(title, uid, false);
          setState(() {});
        }));
    setState(() {});
  }

  Future<bool> loadMarkers(bool loadUserMarker) async {
    if (searchTerm == '') {
      setState(() {
        labelMarkers = {};
        poiMarkers = {};
      });

      if (poi == BitmapDescriptor.defaultMarker) {
        Uint8List imageData = await loadAssetAsByteData('assets/poi.png');
        poi = await BitmapDescriptor.bytes(imageData,
            width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
      }
      if (poio == BitmapDescriptor.defaultMarker) {
        Uint8List userImageData = await loadAssetAsByteData('assets/poio.png');
        poio = await BitmapDescriptor.bytes(userImageData,
            width: 50.0, height: 50.0, bitmapScaling: MapBitmapScaling.auto);
      }

      CollectionReference users =
      FirebaseFirestore.instance.collection('users');

      print('loadMarkers is starting batched fetch');

      // i made this batched fetch of all users' marker data
      List<Map<String, dynamic>> allUserData = await fu.retrieveAllUserMarkerData(users);

      // these sets represent the batches
      Set<Marker> newPoiMarkers = {};
      Set<LabelMarker> newLabelMarkers = {};

      List<Future<void>> markerCreationFutures = [];

      for (var userData in allUserData) {
        String uid = userData['uid'];
        String name = userData['name'];
        double lat = userData['lat'];
        double lng = userData['lng'];
        bool isCurrentUser = (uid == _uid);

        if (isCurrentUser && !loadUserMarker) continue;

        // Common onTap logic
        void Function() handleTap(bool isPoi) {
          return () {
            setState(() {
              markers = {};
            });
            handleMarkerTap(name, uid, isPoi);
          };
        }

        Future<void> handleDragEnd(LatLng newPosition) async {
          fu.updateUserLocation(
              FirebaseFirestore.instance.collection('users'),
              FirebaseAuth.instance.currentUser!.uid,
              GeoPoint(newPosition.latitude, newPosition.longitude));
          await loadMarkers(true);
          setState(() {
            _markersLoadingSignedIn = false;
            _markersLoadingSignedInBannerText = 'loading markers...';
          });
        }

        bool draggable = isCurrentUser ? _retrieveDraggabilityUserModel() : false;
        BitmapDescriptor icon = isCurrentUser ? poio : poi;
        int zIndex = draggable ? 10 : (isCurrentUser ? 5 : 1);
        Color labelColor = isCurrentUser ? const Color(0xFFff673a) : Colors.white;

        newPoiMarkers.add(Marker(
          icon: icon,
          markerId: MarkerId(uid),
          anchor: const Offset(0.5, 0.5),
          position: LatLng(lat, lng),
          draggable: draggable,
          zIndex: zIndex.toDouble(),
          onTap: handleTap(true),
          onDragEnd: isCurrentUser ? handleDragEnd : null,
        ));

// Determine platform-specific label styles
        final double labelFontSize = kIsWeb ? 15.0 : 45.0;
        final List<Shadow> labelShadows = [
          // White glow (existing)
          Shadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 0.0,
            offset: Offset.zero,
          ),
          Shadow(
            color: Colors.white.withOpacity(0.6),
            blurRadius: 0.0,
            offset: Offset.zero,
          ),
          // Dark outline
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(-0.65, -0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(0.65, -0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(-0.65, 0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(0.65, 0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(0, -0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(0, 0.65)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(-0.65, 0)),
          Shadow(color: Colors.black87, blurRadius: 0.0, offset: const Offset(0.65, 0)),
        ];

        final TextStyle labelTextStyle = TextStyle(
          color: labelColor,
          fontSize: labelFontSize,
          letterSpacing: 1.0,
          fontFamily: 'Roboto Bold',
          shadows: labelShadows,
        );

        newLabelMarkers.add(LabelMarker(
          icon: BitmapDescriptor.defaultMarker,
          label: name,
          textStyle: labelTextStyle,
          // Distinct id so the label can coexist with the always-shown POI
          // marker (which uses the bare uid).
          markerId: MarkerId(_labelMarkerId(uid)),
          // Anchor so the label text centers on the POI dot instead of
          // floating above it.
          anchor: _labelAnchor(name, labelTextStyle),
          position: LatLng(lat, lng),
          backgroundColor: const Color(0x00000000),
          // The POI marker (always visible) handles dragging; the label sits
          // on top of it and renders above all POI dots.
          draggable: false,
          zIndex: zIndex.toDouble() + 1000,
          onTap: handleTap(false),
        ));
      }

      setState(() {
        poiMarkers = newPoiMarkers;
      });

      for (var lm in newLabelMarkers) {
        await labelMarkers.addLabelMarker(lm);
      }

      _onCameraMove(_currentZoom);
    }
    setState(() {
      _markersLoadingSignedIn = false;
      _markersLoadingSignedOut = false;
    });
    return loadUserMarker;
  }
}
