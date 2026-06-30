part of 'package:intrst/main.dart';

extension _HomeUiLogic on _MyHomePageState {
  Widget rollingIconBuilder(int? value, bool foreground) {
    return Icon(iconDataByValue(value));
  }

  Widget iconBuilder(int value) {
    return rollingIconBuilder(value, false);
  }

  // A single relationship-filter chip for the Marker Settings menu.
  Widget _buildMarkerFilterChip(
      String label, bool selected, ValueChanged<bool> onSelected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
      checkmarkColor: Colors.white,
      backgroundColor: const Color(0xFF0E3D4A),
      selectedColor: const Color(0xFFff673a),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? const Color(0xFFff673a) : Colors.white24,
        ),
      ),
    );
  }

  // Refreshes the relationship uid sets and re-applies the marker filter after
  // a filter chip is toggled.
  Future<void> _onMarkerFilterChanged() async {
    await _loadRelationshipFilterUids(
        FirebaseFirestore.instance.collection('users'));
    _onCameraMove(_currentZoom);
  }

  IconData iconDataByValue(int? value) => switch (value) {
        0 => Icons.disabled_by_default,
        _ => Icons.swipe,
      };

  Widget sizeIconBuilder(BuildContext context,
      AnimatedToggleProperties<int> local, GlobalToggleProperties<int> global) {
    return iconBuilder(local.value);
  }

  /// Full-screen state shown while an account exists but its email is not yet
  /// verified. The app polls in the background (see _startEmailVerification
  /// Polling); the moment verification is detected the user is logged straight
  /// in, so they never have to come back and sign in a second time.
  Widget _buildVerifyEmailScreen() {
    final String email =
        FirebaseAuth.instance.currentUser?.email ?? 'your email address';
    return Container(
      color: const Color(0xFF082D38),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SafeArea(
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_unread_outlined,
              color: Colors.amber, size: 72),
          const SizedBox(height: 24),
          const Text(
            'Verify your email',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            "We sent a verification link to $email.\n\n"
            'Open it to finish setting up your account — please check your '
            'junk/spam folder too. This screen will continue automatically '
            'once you verify.',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.amber),
              ),
              SizedBox(width: 12),
              Text('Waiting for verification…',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _resendVerificationEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: const Color(0xFF082D38),
            ),
            child: const Text('Resend email'),
          ),
          TextButton(
            onPressed: () {
              // Bail out of sign-up: signing out routes through
              // _enterSignedOutState (cancels polling, clears pending state).
              FirebaseAuth.instance.signOut();
            },
            child: const Text('Use a different account',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    //padding.top represents the height of the status bar which varies by device
    double mapHeight =
        MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top;
    double toolbarHeight = 56;
    // Updated bottom bar height - doubled from 80 to 160
    // Raised to fit the relationship filter chips below the draggability toggle.
    double bottomBarHeight = 252;

    return Scaffold(
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      appBar: _awaitingEmailVerification
          ? null
          : AppBar(
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
          builder: (context, setState) => Row(
            children: [
              Expanded(
                child:SizedBox(
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

                CollectionReference users =
                    FirebaseFirestore.instance.collection('users');

                List<String> uid_results = await fu
                    .searchForPeopleAndInterestsReturnUIDs(users, value, true);

                List<String> results =
                    await fu.searchForPeopleAndInterests(users, value, true);
                List<String> interests = await fu.listInterests();
                print("interests: $interests");

                setState(() {
                  searchTerm = value;
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
              onSelected: (selection) async {
                CollectionReference users =
                    FirebaseFirestore.instance.collection('users');

                List<String> uid_results = await fu
                    .searchForPeopleAndInterestsReturnUIDs(users, selection, true);

                setState(() {
                  searchTerm = selection;
                  searchFilteredResults = uid_results;
                  _onCameraMove(_currentZoom);
                });
                print('Selected: $selection');
              },
            ),
          ),
        ),
          const SizedBox(width: 0),
          if (_searchController.text.isNotEmpty)
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF082D38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(32, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
        onPressed: () {
          final searchText = _searchController.text;
          _handleAlternateUserModel(_uid, _name);
          setState(() {
            _shouldCreateInterest = true;
            _initialInterestName = searchText;
          });
          _scaffoldKey.currentState?.openEndDrawer();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add),
          ],
        ),
      ),
    ),
    ],
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
            : _awaitingEmailVerification
                ? _buildVerifyEmailScreen()
                : _signedIn // _signedInGoogleMap
                ? IndexedStack( index: _selectedIndex, children: <Widget>[
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
                                      _trackSignedInUsageAction();
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
                                    initialCameraPosition:
                                        _MyHomePageState._kLake,
                                    zoomControlsEnabled: false,
                                    myLocationButtonEnabled: false,
                                    compassEnabled: true,
                                    minMaxZoomPreference:
                                        MinMaxZoomPreference(3.0, 900.0),
                                    markers: markers,
                                    onMapCreated:
                                        (GoogleMapController controller) async {
                                      final pendingFeedMapFocusUid =
                                          _pendingMapFocusUserUid;
                                      final hasPendingFeedMapFocus =
                                          (pendingFeedMapFocusUid?.isNotEmpty ??
                                              false);
                                      loadFCMToken();
                                      double zoom =
                                          await controller.getZoomLevel();
                                      _currentZoom = zoom;
                                      print('onMapCreated signedIn is running');
                                      if (_controller.isCompleted) {
                                        _controller = Completer();
                                      }
                                      _controller.complete(controller);
                                      if (!hasPendingFeedMapFocus &&
                                          !_hasPerformedInitialSignedInMapSetup) {
                                        _hasPerformedInitialSignedInMapSetup =
                                            true;
                                        await _showLocationDisclaimer(context);
                                        _getLocationServiceAndPermission(
                                          _controller,
                                          suppressWhenPendingFocus: true,
                                        );
                                        _gotoCurrentUserLocation(
                                          false,
                                          _signedIn,
                                          suppressWhenPendingFocus: true,
                                        );
                                      }
                                      print('callback is working');
                                      setState(() {});
                                      if (markers.isEmpty) {
                                        print(
                                            'markers is empty attempting to load markers now');
                                        await loadMarkers(true);
                                      }
                                      _onCameraMove(_currentZoom);
                                      if (hasPendingFeedMapFocus &&
                                          pendingFeedMapFocusUid != null &&
                                          pendingFeedMapFocusUid.isNotEmpty) {
                                        await moveCameraToSpecificUser(
                                          pendingFeedMapFocusUid,
                                          zoom: 13.5,
                                        );
                                        if (mounted) {
                                          setState(() {
                                            if (_pendingMapFocusUserUid ==
                                                pendingFeedMapFocusUid) {
                                              _pendingMapFocusUserUid = null;
                                            }
                                          });
                                        }
                                      }
                                    },
                                  ),
                                  Positioned(
                                    bottom: kIsWeb ? 185 : 125,
                                    right: 10,
                                    child: FloatingActionButton(
                                      mini: true,
                                      backgroundColor: Colors.white,
                                      onPressed: () {
                                        _showTemporaryBottomMessage(
                                          "Taking you to your Marker's location",
                                        );
                                        moveCameraToUserLocation();
                                      },
                                      child:
                                          Icon(Icons.place, color: Colors.blue),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: kIsWeb ? 130 : 70,
                                    right: 10,
                                    child: FloatingActionButton(
                                      mini: true,
                                      backgroundColor: Colors.white,
                                      onPressed: () {
                                        _showTemporaryBottomMessage(
                                          'Taking you to your current location',
                                        );
                                        _gotoCurrentUserLocationFast(
                                            true, _signedIn);
                                      },
                                      child: Icon(Icons.my_location,
                                          color: Colors.blue),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: kIsWeb ? 75 : 15,
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
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Toggle switch
                                        SizedBox(
                                          height: 40,
                                          width: 100,
                                          child:
                                              AnimatedToggleSwitch<int>.rolling(
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
                                                  _markerDraggabilityText =
                                                      'not movable';
                                                } else {
                                                  _markerDraggabilityText =
                                                      'movable';
                                                  setState(() {
                                                    _markersLoadingSignedIn =
                                                        true;
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
                                    // Relationship filters
                                    Text(
                                      'Show on map',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        _buildMarkerFilterChip(
                                          'Friends',
                                          _filterFriends,
                                          (v) async {
                                            setState(() => _filterFriends = v);
                                            await _onMarkerFilterChanged();
                                          },
                                        ),
                                        _buildMarkerFilterChip(
                                          'Followers',
                                          _filterFollowers,
                                          (v) async {
                                            setState(() => _filterFollowers = v);
                                            await _onMarkerFilterChanged();
                                          },
                                        ),
                                        _buildMarkerFilterChip(
                                          'Following',
                                          _filterFollowing,
                                          (v) async {
                                            setState(() => _filterFollowing = v);
                                            await _onMarkerFilterChanged();
                                          },
                                        ),
                                      ],
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
                    FollowingFeed(
                      userUid: _uid,
                      onOpenInterests: _openInterestsForUserFromFeed,
                      onOpenMessages: _openMessagesForUserFromFeed,
                      onOpenUserOnMap: _openUserOnMapFromFeed,
                    ),
                    Account(
                      uid: _uid,
                      onNameChanged: _handleNameChanged,
                    ),
                    Messaging(
                      user_uid: _uid,
                      openWithUserUid: _openMessagesWithUserUid,
                    ),
          FriendsManagerWidget(currentUserUid: _uid)
                  ])
                : <Widget>[
                    Stack(children: [
                      GoogleMap(
                        onCameraMove: (CameraPosition cameraPosition) {
                          _onCameraMove(cameraPosition.zoom);
                        },
                        cloudMapId: mapId, // Set the map style ID here
                        zoomGesturesEnabled: _zoomEnabled,
                        initialCameraPosition: _MyHomePageState._kLake,
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
                      onSelectedIndexChanged: _onItemTapped,
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
                    title: const Text('Friends'),
                    selected: _selectedIndex == 4,
                    onTap: () {
                      _onItemTapped(4);
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    title: const Text('Feed'),
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
                        _openMessagesWithUserUid = null;
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
                      // Signed-out drawer: never render identity here. In
                      // debug we keep it visible to aid troubleshooting.
                      child: Text(
                        kDebugMode ? "$_name : $_uid" : "Welcome to intrst",
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
            shouldCreateInterest: _shouldCreateInterest,
            initialInterestName: _initialInterestName,
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
          _shouldCreateInterest = false;
          _initialInterestName = '';
        }
        setState(() {
          _zoomEnabled = !state;
        });
      },
    );
  }
}
