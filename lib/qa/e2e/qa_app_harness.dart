/// The control surface the live QA runner uses to drive the **real running
/// intrst app** — as opposed to the sandbox widget trees `flutter test` mounts.
///
/// The running `_MyHomePageState` implements this and registers itself into
/// [QaAppController] (web + debug only). The runner then drives production
/// screens through these methods — each one delegates to a real app code path
/// (`handleMarkerTap`, `_openMessagesForUserFromFeed`, Firebase auth) — instead
/// of reaching into private state. Keeping the surface this small is what lets
/// the scenarios stay readable and the app coupling stay auditable.
abstract class QaAppHarness {
  /// The signed-in user's uid, or '' when signed out.
  String get currentUid;

  /// Whether a user is currently signed in.
  bool get signedIn;

  /// Signs in the dedicated QA test account (see [QaTestCredentials]). Resolves
  /// once the app has observed the sign-in and updated its own state. Throws
  /// [QaHarnessUnavailable] when no credentials are configured.
  Future<void> signInTestUser();

  /// Signs the current user out and resolves once the app is signed out.
  Future<void> signOutTestUser();

  /// Opens the **real** `Preview` dialog for [uid] by invoking the app's own
  /// marker-tap handler (the Google Maps marker itself can't be tapped, so this
  /// is the one simulated step; everything the Preview then does is real). When
  /// [uid] is the signed-in user's own uid the app opens the end drawer instead
  /// and no Preview appears — matching production.
  Future<void> openPreviewFor(String uid, String displayName);

  /// Navigates to the real Messaging screen and opens the 1:1 conversation with
  /// [uid], mounting the production `CollapsibleChatScreen`.
  Future<void> openConversationWith(String uid, String displayName);

  /// Returns the app to the map/home surface (nav index 0).
  Future<void> goHome();

  /// Opens the **real** multi-part sign-up wizard, using [email] as the address
  /// the header shows.
  ///
  /// The wizard normally opens from `LoginScreen`'s sign-up submit, after the
  /// user has typed an email and password. Driving `FlutterLogin`'s own form
  /// live would be asserting on a third-party widget's internals, so this
  /// mounts the production wizard directly — every screen the scenario then
  /// walks is the real one.
  ///
  /// Account creation is **disabled** for the pushed wizard: its submit
  /// callback always refuses, so a live run against prod can walk all three
  /// parts, and even press "Create my account", without ever creating an
  /// account. Live scenarios therefore cover the parts and the gates between
  /// them; the write itself is covered by the `Signup submission` scenarios.
  Future<void> openSignupWizard({String email = 'qa-signup@example.com'});

  // ---------------------------------------------------------------------------
  // Map surface. A `GoogleMap` is a platform view: its markers cannot be tapped
  // by the live driver, and nothing about them is visible to an element walk.
  // These give a live scenario the same view of the map the app itself has —
  // which markers are on it, at what zoom — and let it drive the map through
  // the app's own code paths (`_onCameraMove`, `loadMarkers`, the real search
  // field, the real relationship-filter handler) rather than reaching into
  // widget state.
  // ---------------------------------------------------------------------------

  /// The `MarkerId`s currently handed to the map, exactly as the app built
  /// them — so a label-rendered marker appears here as `<uid>_label`.
  List<String> visibleMarkerIds();

  /// The zoom the current marker set was built for.
  double get currentMapZoom;

  /// The zoom the map opened at this launch: the zoom restored from
  /// [MapCameraMemory], or the default the app fell back to.
  double get initialMapZoom;

  /// The zoom stored in the app's camera memory — the one a launch right now
  /// would restore — or null when nothing has been remembered yet.
  Future<double?> rememberedCameraZoom();

  /// Rebuilds the marker set at [zoom] through the app's real `_onCameraMove`,
  /// the same call the map makes as the user pinches.
  Future<void> applyMapZoom(double zoom);

  /// Re-runs the app's real `loadMarkers`, so markers seeded during
  /// [QaLiveSetUp] reach the map.
  Future<void> reloadMarkers();

  /// Puts [term] in the **real** search field, which drives the production
  /// autocomplete → Firestore search → `_onCameraMove` chain. Resolves once the
  /// app has applied the term (or throws [QaHarnessUnavailable] on timeout).
  Future<void> enterSearch(String term);

  /// Empties the real search field, taking the app's own "search cleared" path.
  Future<void> clearSearch();

  /// Flips the relationship filter toggles (null leaves one unchanged) and runs
  /// the app's real filter-changed handler, refreshing the uid sets and
  /// rebuilding the markers.
  Future<void> setRelationshipFilters({
    bool? friends,
    bool? followers,
    bool? following,
  });

  /// Opens the real Preview for a marker taken straight out of
  /// [visibleMarkerIds] — including a `<uid>_label` id, which must be resolved
  /// back to its uid the way the map's own label `onTap` does.
  Future<void> openPreviewForMarkerId(String markerId, String displayName);

  /// Resets the app to a known baseline so a scenario never inherits UI state a
  /// previous one left behind (an open `Preview` dialog, an open drawer, a
  /// different tab). Dismisses any dialog/pushed page, closes drawers, and
  /// returns to the map. The runner calls this before every live scenario, so
  /// "Run all" is order-independent.
  Future<void> resetToBaseline();
}

/// Credentials for the throwaway QA test account, supplied at build/run time via
/// `--dart-define` and never committed:
///
/// ```
/// flutter run -d chrome \
///   --dart-define=QA_E2E_EMAIL=qa@example.com \
///   --dart-define=QA_E2E_PASSWORD=•••••••
/// ```
///
/// Scenarios that need an authenticated (or explicitly signed-out) session read
/// [isConfigured] first and surface a clear message in the PiP when it is false,
/// rather than failing obscurely.
class QaTestCredentials {
  const QaTestCredentials._();

  static const String email = String.fromEnvironment('QA_E2E_EMAIL');
  static const String password = String.fromEnvironment('QA_E2E_PASSWORD');

  static bool get isConfigured => email.isNotEmpty && password.isNotEmpty;

  static const String missingMessage =
      'No QA test account configured. Re-run with '
      '--dart-define=QA_E2E_EMAIL=… --dart-define=QA_E2E_PASSWORD=… to run the '
      'sign-in scenarios.';
}

/// Thrown when the live runner cannot proceed: the app harness has not
/// registered yet, or a prerequisite (such as test credentials) is missing. The
/// runner catches it and paints the failing step red in the PiP.
class QaHarnessUnavailable implements Exception {
  QaHarnessUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
