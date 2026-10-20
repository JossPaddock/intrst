part of 'package:intrst/main.dart';

class _MyHomePageState extends State<MyHomePage> implements QaAppHarness {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late CameraPosition _newPosition;
  Location location = Location();
  late PermissionStatus _permissionGranted;
  late bool _serviceEnabled;
  double _currentZoom = 10;
  // Marker display mode toggle:
  //   true  -> original behavior: POI and label are mutually exclusive
  //            (the POI dot is replaced by the label when zoomed/spaced).
  //   false -> new behavior: the POI dot is always shown and the label is
  //            layered on top using the same zoom + proximity logic.
  bool _useOriginalMarkerBehavior = false;
  bool _markersLoadingSignedIn = true;
  String _markersLoadingSignedInBannerText = 'loading markers...';
  bool _markersLoadingSignedOut = false;
  bool _signedIn = false;
  String _name = '';
  String _uid = '';

  // True while the user is authenticated but has not yet verified their email.
  // The app shows a dedicated "verify your email" screen and polls until they
  // verify, at which point they are logged in automatically (no re-login).
  bool _awaitingEmailVerification = false;
  Timer? _emailVerificationPoll;

  // Monotonic counter used to discard stale `authStateChanges` continuations.
  // Each auth event bumps this; an event that awaits and then finds the
  // counter has moved on knows a newer event superseded it and must not
  // commit its (now stale) state. See [initializeFirebase].
  int _authStateGeneration = 0;
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

  /// The person the map last flew to because a search matched only them, so
  /// further keystrokes that still match just them don't restart the flight.
  String? _searchFocusedUid;

  /// Bumped by every camera flight; a running web flight stops as soon as it
  /// sees a newer one (see [flyCameraTo]).
  int _cameraFlightGeneration = 0;
  BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarker;
  late bool lastKnownDraggabilityState;
  bool _isLoading = false;
  bool mapOptionsVisibility = false;

  /// True while the user is repositioning their own marker from their preview.
  /// Every other marker is hidden and the map shows only a Done button; see
  /// _enterMarkerMoveMode / _exitMarkerMoveMode.
  bool _markerMoveMode = false;

  // Map marker relationship filters. When all are false, every marker is shown.
  // When one or more are enabled, only markers matching the enabled
  // relationship(s) — plus the user's own marker — are shown.
  bool _filterFriends = false;
  bool _filterFollowers = false;
  bool _filterFollowing = false;

  // Uid sets backing the relationship filters above; refreshed in loadMarkers.
  Set<String> _friendUids = {};
  Set<String> _followerUids = {};
  Set<String> _followingUids = {};
  bool hasNotification = false;
  int notificationCount = 0;
  Timer? _notificationLoading;
  String? _openMessagesWithUserUid;
  String? _pendingMapFocusUserUid;
  bool _hasPerformedInitialSignedInMapSetup = false;

  // ---------------------------------------------------------------------------
  // Map start-up. The map is never built until we know (a) whether the user is
  // signed in, and (b) where the camera should start and which markers belong
  // on it. Until then the body shows a single loading indicator, which is what
  // removes the old "world view -> fly to you -> markers pop in" sequence.
  // ---------------------------------------------------------------------------

  /// False until the first `authStateChanges` event lands, so we never flash
  /// the signed-out map at a user who turns out to be signed in.
  bool _authResolved = false;

  /// Safety net: if Firebase never reports an auth state we stop waiting and
  /// treat the session as signed out rather than showing a loader forever.
  Timer? _authResolutionTimeout;
  static const Duration _authResolutionGrace = Duration(seconds: 8);

  /// True once [_initialCameraPosition] is resolved and the markers for it are
  /// loaded; gates the GoogleMap widget.
  bool _mapReady = false;

  /// Identifies the session the current bootstrap ran for ("out", "in:<uid>"),
  /// so a sign-in/sign-out re-resolves the map exactly once.
  String? _mapBootstrapKey;

  /// Where the map starts. Read once by GoogleMap at construction time, which
  /// is why the widget must not be built before this is settled.
  CameraPosition _initialCameraPosition = _kLake;

  /// Set during bootstrap when the signed-in user has no stored location yet.
  /// Normally handled by the sign-up onboarding screen below; the in-map
  /// fallback (_placeUserMarkerAndCenter) only runs when that screen was not
  /// shown, e.g. an account that completed onboarding but lost its marker.
  bool _needsMarkerPlacement = false;

  /// True while the just-signed-up user is on the location onboarding screen.
  /// The map is not built until this clears, so it can open already centred on
  /// them with their markers loaded — no camera animation, no pop-in.
  bool _showLocationOnboarding = false;

  /// True while the onboarding screen is requesting permission / a fix.
  bool _locationOnboardingBusy = false;

  /// Set when the location request did not produce a position, so the screen
  /// can explain and offer to continue anyway rather than trapping the user.
  String? _locationOnboardingError;

  /// The zoom used whenever the app opens the map on *the user* rather than on
  /// a remembered view — their stored marker, or a fresh device fix. One
  /// constant so every "go to where you are" path lands at the same scale.
  static const double _userLocationZoom = 12.0;

  /// The zoom a search flies in to when it finds a single person: close
  /// enough that their name label shows, matching the feed's "show on map".
  /// A user already zoomed in further keeps their own zoom.
  static const double _searchFocusZoom = 13.5;

  final MapCameraMemory _cameraMemory = const MapCameraMemory();

  /// Latest camera reported by the map, and the last one written to storage.
  MapCameraSnapshot? _lastCameraSnapshot;
  MapCameraSnapshot? _persistedCameraSnapshot;
  String _lastTrackedUsageDayKey = '';

  // Whether the signed-in user may open the admin dashboard. Owned by the
  // authStateChanges listener alongside _signedIn/_uid, so it is recomputed on
  // every sign-in and cleared on every sign-out rather than lingering from a
  // previous session. See [AdminAccess]; the dashboard re-checks independently.
  bool _isAdmin = false;
  RemoteMessage? _pendingInitialMessage;
  bool _shouldCreateInterest = false;
  String _initialInterestName = '';

  // Defined once in [IntrstMapStyle] so the sign-up wizard's placement maps
  // render with the same palette as the map the user is signing up to enter.
  final mapId = IntrstMapStyle.cloudMapId;

  Completer<GoogleMapController> _controller = Completer<GoogleMapController>();

  Completer<GoogleMapController> _controllerSignedOut =
      Completer<GoogleMapController>();

  static const CameraPosition _kLake = CameraPosition(
      bearing: 0.0,
      target: LatLng(37.43296265331129, -122.08832357078792),
      tilt: 0.0,
      zoom: 3);

  bool _zoomEnabled = true;

  BitmapDescriptor poi = BitmapDescriptor.defaultMarker;
  BitmapDescriptor poio = BitmapDescriptor.defaultMarker;

  static const TextStyle optionStyle =
      TextStyle(fontSize: 30, fontWeight: FontWeight.bold);

  @override
  void initState() {
    print('Build mode: ${kReleaseMode ? "Release" : "NOT Release"}');
    initializeFirebase();
    // Do NOT move the camera here: the map is not built until
    // _ensureMapBootstrapped resolves where it should start (see _mapReady).
    _authResolutionTimeout = Timer(_authResolutionGrace, () {
      if (!mounted || _authResolved) return;
      print('Auth state never resolved; continuing as signed out.');
      _markAuthResolved();
      _ensureMapBootstrapped();
    });
    setState(() {
      lastKnownDraggabilityState = _retrieveDraggabilityUserModel();
      markers = poiMarkers;
    });
    loadFCMToken();
    _initNotifications();
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    // Expose this running app to the live QA runner (admin dashboard). Web +
    // debug only, so release builds neither register nor drag in the runner.
    if (kIsWeb && kDebugMode) {
      QaAppController.instance.register(this);
    }
  }

  @override
  void dispose() {
    if (kIsWeb && kDebugMode) {
      QaAppController.instance.unregister(this);
    }
    _notificationLoading?.cancel();
    _emailVerificationPoll?.cancel();
    _authResolutionTimeout?.cancel();
    super.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildHomePage(context);
  }

  // ---------------------------------------------------------------------------
  // QaAppHarness — the control surface the admin dashboard's live QA runner
  // drives the real app through. Registered web + debug only (see initState).
  // Each method delegates to an existing production code path; the members must
  // live in the class body because `implements` is not satisfied by the
  // extension methods the other part files use.
  // ---------------------------------------------------------------------------

  @override
  String get currentUid => _uid;

  @override
  bool get signedIn => _signedIn;

  @override
  Future<void> signInTestUser() async {
    if (!QaTestCredentials.isConfigured) {
      throw QaHarnessUnavailable(QaTestCredentials.missingMessage);
    }
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: QaTestCredentials.email,
      password: QaTestCredentials.password,
    );
    // The app's own authStateChanges listener updates _signedIn/_uid; wait for
    // it rather than assuming the write is immediately visible.
    final ok = await _qaWaitUntil(() => _signedIn && _uid.isNotEmpty);
    if (!ok) {
      throw QaHarnessUnavailable(
        'Signed in, but the app did not reach a signed-in state in time.',
      );
    }
    await _qaSettle();
  }

  @override
  Future<void> signOutTestUser() async {
    await FirebaseAuth.instance.signOut();
    await _qaWaitUntil(() => !_signedIn);
    await _qaSettle();
  }

  @override
  Future<void> openPreviewFor(String uid, String displayName) async {
    await goHome();
    // The camera-zoom guard gates marker taps; open it so the real handler runs.
    _zoomEnabled = true;
    // Fire the real marker-tap handler. Do NOT await its future — it only
    // completes when the Preview is dismissed.
    handleMarkerTap(displayName, uid, false);
    await _qaSettle();
  }

  @override
  Future<void> openConversationWith(String uid, String displayName) async {
    _openMessagesForUserFromFeed(uid, displayName);
    await _qaSettle();
  }

  @override
  Future<void> goHome() async {
    _onItemTapped(0);
    await _qaSettle();
  }

  @override
  Future<void> openSignupWizard(
      {String email = 'qa-signup@example.com'}) async {
    await goHome();
    // Not awaited: `show` only completes when the wizard is popped, which is
    // what the scenario's teardown does.
    //
    // The submit callback always refuses, so a live run can walk every part of
    // the real wizard — and press "Create my account" — without a QA run ever
    // creating an account in prod. Everything else the scenario touches is the
    // production widget.
    unawaited(SignupWizard.show(
      context,
      email: email,
      onSubmit: (_) async => const SignupSubmitError(
        'QA run: account creation is disabled for the live wizard.',
        fatal: true,
      ),
    ));
    await _qaSettle();
  }

  // --- Map surface -----------------------------------------------------------
  // Everything below goes through the same code the map itself uses, so a live
  // scenario asserts on what production built, not on a parallel computation.

  @override
  List<String> visibleMarkerIds() =>
      markers.map((marker) => marker.markerId.value).toList(growable: false);

  @override
  double get currentMapZoom => _currentZoom;

  @override
  double get initialMapZoom => _initialCameraPosition.zoom;

  @override
  Future<double?> rememberedCameraZoom() async =>
      (await _cameraMemory.load())?.zoom;

  @override
  Future<void> applyMapZoom(double zoom) async {
    _onCameraMove(zoom);
    await _qaSettle();
  }

  @override
  Future<void> reloadMarkers() async {
    await loadMarkers(_signedIn);
    await _qaSettle();
  }

  @override
  Future<void> enterSearch(String term) async {
    if (term.isEmpty) return clearSearch();
    // Writing to the controller is what a keystroke does: RawAutocomplete
    // listens to it and runs the real `optionsBuilder`, which performs the
    // Firestore search and calls `_onCameraMove` with the results.
    _searchController.text = term;
    await _qaSettle();
    final ok = await _qaWaitUntil(() => searchTerm == term,
        timeout: const Duration(seconds: 15));
    if (!ok) {
      throw QaHarnessUnavailable(
        'The app never applied the search term "$term" (the search field may '
        'not be mounted — the map tab has to be open).',
      );
    }
    await _qaSettle();
  }

  @override
  Future<void> clearSearch() async {
    _searchController.clear();
    await _qaSettle();
    final ok = await _qaWaitUntil(() => searchTerm.isEmpty);
    if (!ok) {
      throw QaHarnessUnavailable(
        'The app never cleared its search term.',
      );
    }
    await _qaSettle();
  }

  @override
  Future<void> setRelationshipFilters({
    bool? friends,
    bool? followers,
    bool? following,
  }) async {
    setState(() {
      if (friends != null) _filterFriends = friends;
      if (followers != null) _filterFollowers = followers;
      if (following != null) _filterFollowing = following;
    });
    // The same handler the filter chips call.
    await _onMarkerFilterChanged();
    await _qaSettle();
  }

  @override
  Future<void> openPreviewForMarkerId(String markerId, String displayName) =>
      openPreviewFor(
        MarkerVisibility.uidFromLabelMarkerId(markerId),
        displayName,
      );

  @override
  Future<void> resetToBaseline() async {
    // Dismiss any dialog / pushed page so we're back on the home page. The
    // home page is the first route (the dashboard was already popped to start
    // the run), so popping to it never removes the app itself.
    final navigator = Navigator.maybeOf(context);
    navigator?.popUntil((route) => route.isFirst);

    // Close either drawer if a previous scenario left one open.
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null) {
      if (scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
      if (scaffold.isDrawerOpen) scaffold.closeDrawer();
    }

    // Re-arm marker taps (a Preview open sets this false) and return to the map.
    _zoomEnabled = true;
    await goHome();
  }

  /// Live-app equivalent of `pumpAndSettle`: a few real frames plus a short
  /// grace period for async work (auth, Firestore reads) to land.
  Future<void> _qaSettle() async {
    final binding = WidgetsBinding.instance;
    for (var i = 0; i < 3; i++) {
      await binding.endOfFrame;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await binding.endOfFrame;
  }

  /// Polls [predicate] until it holds or [timeout] elapses.
  Future<bool> _qaWaitUntil(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    const step = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    while (!predicate()) {
      if (elapsed >= timeout) return false;
      await Future<void>.delayed(step);
      elapsed += step;
    }
    return true;
  }
}
