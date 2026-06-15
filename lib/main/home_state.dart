part of 'package:intrst/main.dart';

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
  BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarker;
  late bool lastKnownDraggabilityState;
  bool _isLoading = false;
  int toggleIndex = 0;
  bool mapOptionsVisibility = false;
  String _markerDraggabilityText = 'not moveable';
  bool hasNotification = false;
  int notificationCount = 0;
  Timer? _notificationLoading;
  String? _openMessagesWithUserUid;
  String? _pendingMapFocusUserUid;
  bool _hasPerformedInitialSignedInMapSetup = false;
  String _lastTrackedUsageDayKey = '';
  RemoteMessage? _pendingInitialMessage;
  bool _shouldCreateInterest = false;
  String _initialInterestName = '';

  final mapId = "bc8e2917cca03ad4";

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
    _goToInitialPosition(_controller);
    _goToInitialPosition(_controllerSignedOut);
    setState(() {
      lastKnownDraggabilityState = _retrieveDraggabilityUserModel();
      markers = poiMarkers;
    });
    loadFCMToken();
    _initNotifications();
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

  @override
  Widget build(BuildContext context) {
    return _buildHomePage(context);
  }
}
