import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../main/marker_visibility.dart';
import '../qa_scenario.dart';

/// Coverage for how zoom drives name labels on the map, in six suites:
///
///  * **Marker label zoom boundary** — the gate at
///    [MarkerVisibility.minLabelZoom] (2.0): at 2.0 labels become eligible, a
///    hair below it (1.9) only POI dots are shown.
///  * **Marker label zoom round-trips** — the "swap to labels and back"
///    regression guard: zooming in so crowded dots gain labels and then zooming
///    back out must leave the marker set exactly as it was.
///  * **Marker search filtering** — the search branch of `buildVisibleMarkers`:
///    which markers survive a search term, how search overrides the
///    relationship filter, and how labels recompute against the filtered set.
///  * **Marker relationship filtering** — the relationship branch: an allow-set
///    keeps only its own uids, `null` means "show everyone", and an empty set
///    means "show nobody" rather than collapsing back onto `null`.
///  * **Marker move mode** — the `soloUid` branch: while the signed-in user is
///    repositioning their own marker from their preview, the map shows their
///    POI dot and nothing else.
///  * **Marker POI/label invariants** — the structural rules the marker set must
///    satisfy at *every* zoom: layered mode keeps a POI dot under each label,
///    original mode never emits both forms of a uid, no label is ever emitted
///    without a POI marker behind it, and the 1000 km isolation rule.
///
/// These assert on logic, not UI, so there is nothing to watch — they still run
/// and report in the dashboard.

const String _suite = 'Marker label zoom boundary';
const String _roundTripSuite = 'Marker label zoom round-trips';
const String _searchSuite = 'Marker search filtering';
const String _relationshipSuite = 'Marker relationship filtering';
const String _invariantSuite = 'Marker POI/label invariants';
const String _moveModeSuite = 'Marker move mode';

/// Three well-separated markers so proximity never suppresses a label; whether a
/// label shows then depends only on the zoom boundary.
Set<Marker> _poi() => {
      const Marker(markerId: MarkerId('a'), position: LatLng(0, 0)),
      const Marker(markerId: MarkerId('b'), position: LatLng(40, 40)),
      const Marker(markerId: MarkerId('c'), position: LatLng(-40, -40)),
    };

Set<Marker> _labels() => {
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('a')),
          position: const LatLng(0, 0)),
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('b')),
          position: const LatLng(40, 40)),
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('c')),
          position: const LatLng(-40, -40)),
    };

Set<Marker> _build({required double zoom, required bool useOriginal}) =>
    MarkerVisibility.buildVisibleMarkers(
      poiMarkers: _poi(),
      labelMarkers: _labels(),
      zoom: zoom,
      searchTerm: '',
      searchFilteredResults: const [],
      useOriginalMarkerBehavior: useOriginal,
    );

bool _hasAnyLabel(Set<Marker> markers) => markers
    .any((m) => m.markerId.value.endsWith(MarkerVisibility.labelIdSuffix));

/// Round-trip fixture: a crowded pair 110 m apart plus an isolated marker, so
/// zoom 1, zoom 10 and zoom 18 each produce a genuinely different marker set.
Set<Marker> _roundTripPoi() => {
      const Marker(markerId: MarkerId('a'), position: LatLng(0, 0)),
      const Marker(markerId: MarkerId('b'), position: LatLng(0.001, 0)),
      const Marker(markerId: MarkerId('c'), position: LatLng(40, 40)),
    };

Set<Marker> _roundTripLabels() => {
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('a')),
          position: const LatLng(0, 0)),
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('b')),
          position: const LatLng(0.001, 0)),
      Marker(
          markerId: MarkerId(MarkerVisibility.labelMarkerId('c')),
          position: const LatLng(40, 40)),
    };

/// Walks [zooms] through the marker-set builder in order — the same sequence of
/// calls `_onCameraMove` makes as the user pinches the map — and returns the
/// marker ids at each step.
List<Set<String>> _zoomSweep(List<double> zooms, {required bool useOriginal}) {
  final poi = _roundTripPoi();
  final labels = _roundTripLabels();
  return zooms
      .map((zoom) => MarkerVisibility.buildVisibleMarkers(
            poiMarkers: poi,
            labelMarkers: labels,
            zoom: zoom,
            searchTerm: '',
            searchFilteredResults: const [],
            useOriginalMarkerBehavior: useOriginal,
          ).map((m) => m.markerId.value).toSet())
      .toList();
}

/// True when [zooms] ends on exactly the marker ids it started with **and** the
/// midpoint genuinely differed, so the guard cannot pass vacuously.
bool _roundTrips(List<double> zooms, {required bool useOriginal}) {
  final steps = _zoomSweep(zooms, useOriginal: useOriginal);
  bool same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
  return same(steps.last, steps.first) && !same(steps[1], steps.first);
}


/// Marker ids produced by a filtered build, at zoom 10 (well above the label
/// gate) — the same call `_onCameraMove` makes while a search or a relationship
/// filter is active. Pass `searchTerm: ''` to exercise the relationship branch
/// on its own, which is how the map behaves whenever the search box is empty.
Set<String> _visibleIds({
  required String searchTerm,
  required List<String> searchFilteredResults,
  Set<String>? relationshipUids,
  required bool useOriginal,
  Set<Marker>? poi,
  Set<Marker>? labels,
}) =>
    MarkerVisibility.buildVisibleMarkers(
      poiMarkers: poi ?? _poi(),
      labelMarkers: labels ?? _labels(),
      zoom: 10,
      searchTerm: searchTerm,
      searchFilteredResults: searchFilteredResults,
      relationshipUids: relationshipUids,
      useOriginalMarkerBehavior: useOriginal,
    ).map((m) => m.markerId.value).toSet();

/// The people represented by [ids], collapsing `uid_label` back onto `uid`, so
/// a check can talk about "who is on the map" independently of whether a given
/// person is currently drawn as a dot, a label, or both.
Set<String> _peopleIn(Set<String> ids) =>
    ids.map(MarkerVisibility.uidFromLabelMarkerId).toSet();

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Runs [check] against both marker behaviours, so a search rule can never be
/// pinned in the layered mode while silently regressing in the original one.
bool _inBothModes(bool Function(bool useOriginal) check) =>
    check(false) && check(true);

/// Every half-zoom step across the map's usable range, the sweep the invariant
/// checks walk so a rule can't hold at the handful of zooms other suites pick.
List<double> _fullZoomSweep() =>
    List<double>.generate(41, (i) => 1.0 + i * 0.5);

/// The marker ids produced at each zoom in [_fullZoomSweep], for one filter
/// configuration.
List<Set<String>> _sweepIds({
  required bool useOriginal,
  Set<Marker>? poi,
  Set<Marker>? labels,
  String searchTerm = '',
  List<String> searchFilteredResults = const [],
  Set<String>? relationshipUids,
}) =>
    _fullZoomSweep()
        .map((zoom) => MarkerVisibility.buildVisibleMarkers(
              poiMarkers: poi ?? _roundTripPoi(),
              labelMarkers: labels ?? _roundTripLabels(),
              zoom: zoom,
              searchTerm: searchTerm,
              searchFilteredResults: searchFilteredResults,
              relationshipUids: relationshipUids,
              useOriginalMarkerBehavior: useOriginal,
            ).map((m) => m.markerId.value).toSet())
        .toList();

bool _isLabelId(String id) => id.endsWith(MarkerVisibility.labelIdSuffix);

Set<String> _labelIdsIn(Set<String> ids) => ids.where(_isLabelId).toSet();

/// A label marker for a uid with **no** POI marker behind it — the stale entry a
/// real `_labelMarkers` set accumulates when someone leaves the map, since the
/// two sets are rebuilt from different streams.
Marker _ghostLabel() => Marker(
      markerId: MarkerId(MarkerVisibility.labelMarkerId('ghost')),
      position: const LatLng(70, 70),
    );

/// The four filter configurations the orphan-label check runs under: unfiltered,
/// search only, relationship only, and both at once.
List<Map<String, Object?>> _filterMatrix() => <Map<String, Object?>>[
      {'searchTerm': '', 'results': const <String>[], 'rel': null},
      {'searchTerm': 'a', 'results': const <String>['a'], 'rel': null},
      {
        'searchTerm': '',
        'results': const <String>[],
        'rel': const <String>{'a', 'c'}
      },
      {
        'searchTerm': 'a',
        'results': const <String>['a'],
        'rel': const <String>{'a', 'c'}
      },
    ];

/// Two markers 1056 km apart — comfortably past
/// [MarkerVisibility.alwaysLabelDistance] (1000 km) while staying inside the
/// 10-degree window that `markersToShowAsLabels` measures across at all, so the
/// isolation branch is reached by a real distance rather than by the skip.
Set<Marker> _isolatedPoi() => {
      const Marker(markerId: MarkerId('a'), position: LatLng(0, 0)),
      const Marker(markerId: MarkerId('b'), position: LatLng(9.5, 0)),
    };

/// The same pair, 890 km apart: still the widest spacing the sub-zoom-3
/// proximity threshold (701 km) calls isolated, but under the 1000 km rule.
Set<Marker> _nearlyIsolatedPoi() => {
      const Marker(markerId: MarkerId('a'), position: LatLng(0, 0)),
      const Marker(markerId: MarkerId('b'), position: LatLng(8, 0)),
    };

Set<Marker> _isolatedLabels(Set<Marker> poi) => poi
    .map((m) => Marker(
        markerId: MarkerId(MarkerVisibility.labelMarkerId(m.markerId.value)),
        position: m.position))
    .toSet();

List<QaScenario> markerVisibilityScenarios() {
  QaScenario logic(String suite, String name, String summary, String doc,
      bool Function() condition) {
    return QaScenario(
      suite: suite,
      name: name,
      summary: summary,
      doc: doc,
      body: (d) => d.check(name, condition),
    );
  }

  QaScenario boundary(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_suite, name, summary, doc, condition);

  QaScenario roundTrip(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_roundTripSuite, name, summary, doc, condition);

  QaScenario search(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_searchSuite, name, summary, doc, condition);

  QaScenario relationship(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_relationshipSuite, name, summary, doc, condition);

  QaScenario invariant(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_invariantSuite, name, summary, doc, condition);

  QaScenario moveMode(
          String name, String summary, String doc, bool Function() condition) =>
      logic(_moveModeSuite, name, summary, doc, condition);

  const boundaryAbout = '''
## About this suite
`MarkerVisibility.minLabelZoom` (2.0) is a hard gate: at or above it name labels
are eligible; below it the builder shows only POI dots. These logic checks pin the
gate from both sides (1.9 vs 2.0) in both marker behaviours, so an off-by-a-hair
change is caught. Nothing to watch — they run in place in the dashboard.
''';

  const roundTripAbout = '''
## About this suite
The map rebuilds its whole marker set on every camera move (`_onCameraMove` ->
`buildVisibleMarkers` -> `setState`). Zooming in swaps crowded POI dots for name
labels; zooming back out must swap them back. Each check walks a zoom sweep and
asserts the final marker ids equal the initial ones — **and** that the midpoint
differed, so it can't pass vacuously. `MarkerVisibility` is pure today, so this
holds by construction; the guard exists to catch the day someone adds caching or
accumulated state and a stale label survives the trip back.
''';


  const relationshipAbout = '''
## About this suite
Outside of a search, `relationshipUids` is the map's allow-set: `null` means
"show everyone", any set means "show exactly these uids". The three-way
distinction between `null`, a populated set and an **empty** set is the whole
contract, and the empty case is the one a refactor tends to collapse back onto
`null`. Nothing to watch — they run in place in the dashboard.
''';

  const invariantAbout = '''
## About this suite
The other suites pin *which* markers appear at a handful of chosen zooms. This
one pins the **structural rules the whole marker set has to satisfy at every
zoom** — walked as a 1.0 -> 21.0 sweep in half-zoom steps, so a rule cannot hold
at the sampled zooms and break in between. They are the properties the map's two
marker behaviours are actually defined by, and nothing else asserts them.
Nothing to watch — they run in place in the dashboard.
''';

  const moveModeAbout = '''
## About this suite
Tapping your own marker opens your preview, and "Move marker" puts the map into
**move mode**: `_onCameraMove` passes `soloUid: _uid`, which makes
`buildVisibleMarkers` return your POI dot alone. Everything else — other users'
dots, every name label including your own, the search term and the relationship
filters — is suppressed, so the only thing on the map is the dot you are
dragging and the Done button. These checks pin that short-circuit from both
sides. Nothing to watch — they run in place in the dashboard.
''';

  const searchAbout = '''
## About this suite
`buildVisibleMarkers` has a search branch the zoom suites never reach: an active
search term narrows the marker set to `searchFilteredResults`, **suppresses the
relationship filter** (`marker_visibility.dart:172` — deliberate, so results
behave as if no filters were applied), and narrows the input to the label
proximity computation (`marker_visibility.dart:178`), so labels are recomputed
against what is actually on screen. These checks pin all three, in both marker
behaviours. Nothing to watch — they run in place in the dashboard.
''';


  return <QaScenario>[
    boundary(
      'below the boundary (zoom 1.9) shows only POI dots — layered',
      'Just under the 2.0 label threshold, the map renders only POI dots and no '
          'name labels, in the default layered mode.',
      '''
## What it checks
At zoom 1.9 — just below the gate — the layered build produces no `_label`
markers.

## Expected
build(zoom: 1.9, layered) has **no** label markers.
$boundaryAbout''',
      () => !_hasAnyLabel(_build(zoom: 1.9, useOriginal: false)),
    ),
    boundary(
      'below the boundary (zoom 1.9) shows only POI dots — original',
      'Same rule in the original mutually-exclusive mode: at zoom 1.9 every '
          'marker is a POI dot and nothing is labelled.',
      '''
## What it checks
Same lower edge in original (mutually-exclusive) mode: at zoom 1.9 every marker
is a POI dot and nothing is labelled.

## Expected
build(zoom: 1.9, original) has **no** label markers.
$boundaryAbout''',
      () => !_hasAnyLabel(_build(zoom: 1.9, useOriginal: true)),
    ),
    boundary(
      'at the boundary (zoom 2.0) labels become eligible — layered',
      'The threshold is inclusive: at exactly zoom 2.0 the isolated markers gain '
          'their name labels in the default layered mode.',
      '''
## What it checks
The gate is **inclusive**: at exactly zoom 2.0 the isolated markers gain their
labels in layered mode.

## Expected
build(zoom: 2.0, layered) has **some** label marker.
$boundaryAbout''',
      () => _hasAnyLabel(_build(zoom: MarkerVisibility.minLabelZoom, useOriginal: false)),
    ),
    boundary(
      'at the boundary (zoom 2.0) labels become eligible — original',
      'The threshold is inclusive in the original mode too: at exactly zoom 2.0 '
          'the isolated markers flip from POI dots to name labels.',
      '''
## What it checks
Inclusive in original mode too: at exactly zoom 2.0 the isolated markers flip
from POI dots to name labels.

## Expected
build(zoom: 2.0, original) has **some** label marker.
$boundaryAbout''',
      () => _hasAnyLabel(_build(zoom: MarkerVisibility.minLabelZoom, useOriginal: true)),
    ),

    // Swap-to-labels-and-back regression guard. Zooming in swaps crowded POI
    // dots for name labels; zooming back out must swap them back, leaving the
    // map exactly as it was.
    roundTrip(
      'zoom 10 -> 18 -> 10 restores the original marker ids — layered',
      'Zooming in past the proximity threshold so crowded dots gain labels, '
          'then back out again, ends on exactly the marker ids it started with.',
      '''
## What it checks
The **proximity-threshold** sweep in layered mode: zoom 10 -> 18 -> 10. At zoom 10
the 110 m pair is crowded (threshold 5479 m); at zoom 18 it clears the threshold
(21 m) and both label; returning to zoom 10 must reproduce the zoom-10 set.

## Expected
ids(zoom 10 after) == ids(zoom 10 before), and the zoom-18 set differs.
$roundTripAbout''',
      () => _roundTrips([10, 18, 10], useOriginal: false),
    ),
    roundTrip(
      'zoom 10 -> 18 -> 10 restores the original marker ids — original',
      'The same in-and-out sweep in the mutually-exclusive mode, where markers '
          'change identity between POI dot and label rather than layering.',
      '''
## What it checks
The same 10 -> 18 -> 10 sweep in original mode, where a marker changes **identity**
between `uid` and `uid_label` rather than layering — a strictly harder round trip
for the id bookkeeping.

## Expected
ids(zoom 10 after) == ids(zoom 10 before), and the zoom-18 set differs.
$roundTripAbout''',
      () => _roundTrips([10, 18, 10], useOriginal: true),
    ),
    roundTrip(
      'zoom 10 -> 1 -> 10 restores the original marker ids — layered',
      'Crossing the 2.0 label boundary downwards and back up returns every '
          'label that was dropped, with no orphaned or duplicated markers.',
      '''
## What it checks
The **zoom-gate** sweep in layered mode: zoom 10 -> 1 -> 10, crossing
`minLabelZoom` (2.0) downwards and back up. Below the gate all labels drop; coming
back up they must all return.

## Why separately from 10 -> 18 -> 10
That sweep exercises the proximity threshold; this one exercises the zoom gate — a
different branch in `buildVisibleMarkers`. A bug that dropped labels permanently
after zooming out past the gate would be invisible to the proximity-only sweep.

## Expected
ids(zoom 10 after) == ids(zoom 10 before), and the zoom-1 set differs.
$roundTripAbout''',
      () => _roundTrips([10, 1, 10], useOriginal: false),
    ),
    roundTrip(
      'zoom 10 -> 1 -> 10 restores the original marker ids — original',
      'The boundary crossing in the mutually-exclusive mode, where every label '
          'becomes a POI dot below zoom 2.0 and must turn back on the way up.',
      '''
## What it checks
The zoom-gate sweep in original mode: below 2.0 every label becomes a POI dot, so
`c_label` at zoom 10 becomes `c` at zoom 1 and must turn back into `c_label` on the
way up — touching both `labelMarkerId` and `uidFromLabelMarkerId`.

## Expected
ids(zoom 10 after) == ids(zoom 10 before), and the zoom-1 set differs.
$roundTripAbout''',
      () => _roundTrips([10, 1, 10], useOriginal: true),
    ),
    // Search filtering. `_poi()` is three well-separated people (a, b, c); a
    // search for 'jo' resolves to just `a`.
    search(
      'search hides every non-matching marker',
      'With a search active, only the people in the search results are on the '
          'map — the other markers and their labels are gone.',
      '''
## What it checks
`searchTerm: 'jo'` with `searchFilteredResults: ['a']` against the three
well-separated markers a, b, c.

## Expected
The only person on the map is **a** (drawn as `a` + `a_label` layered, as
`a_label` alone in original mode). `b` and `c` are absent in both modes.
$searchAbout''',
      () => _inBothModes((useOriginal) => _sameSet(
            _peopleIn(_visibleIds(
              searchTerm: 'jo',
              searchFilteredResults: const ['a'],
              useOriginal: useOriginal,
            )),
            {'a'},
          )),
    ),
    search(
      'search suppresses the relationship filter',
      'A marker that the relationship filter would hide still shows while a '
          'search is active, because searching deliberately ignores filters.',
      '''
## What it checks
The same search (`'jo'` -> `['a']`) but with `relationshipUids: {'b'}` — a
relationship filter that excludes **a** entirely. `buildVisibleMarkers` drops the
relationship filter whenever a search is running:

```dart
final Set<String>? relUids = searchTerm.isEmpty ? relationshipUids : null;
```

## Expected
**a** is still on the map, and **b** — which passes the relationship filter but
not the search — is not. Search wins outright; it is not intersected with the
filter.

## Why it is worth pinning
That line is deliberate product behaviour ("search results behave as if no
filters are applied") with nothing else asserting it. Someone reading it as a bug
and "fixing" it to an intersection would silently make searching-while-filtered
return nothing.
$searchAbout''',
      () => _inBothModes((useOriginal) => _sameSet(
            _peopleIn(_visibleIds(
              searchTerm: 'jo',
              searchFilteredResults: const ['a'],
              relationshipUids: const {'b'},
              useOriginal: useOriginal,
            )),
            {'a'},
          )),
    ),
    search(
      'an empty search term ignores a stale result list',
      'Clearing the search box brings every marker back even if the previous '
          'result list is still hanging around in state.',
      '''
## What it checks
`searchTerm: ''` while `searchFilteredResults` still holds `['a']` from the
search the user just cleared — exactly the state the widget is in for the frame
after the search box is emptied.

## Expected
All three people (a, b, c) are on the map. `markerVisible` short-circuits on
`searchTerm.isNotEmpty &&`, so a stale result list is inert.

## Why it is worth pinning
The clear-search path is the one most likely to leave a stale list behind. Losing
that short-circuit would strand the map on the last search's results with an
empty search box — a confusing, hard-to-diagnose bug.
$searchAbout''',
      () => _inBothModes((useOriginal) => _sameSet(
            _peopleIn(_visibleIds(
              searchTerm: '',
              searchFilteredResults: const ['a'],
              useOriginal: useOriginal,
            )),
            {'a', 'b', 'c'},
          )),
    ),
    search(
      'a search that matches nobody yields an empty marker set',
      'A search with no results shows an empty map, not every marker — the '
          '"no matches" and "no filter" cases must not collapse together.',
      '''
## What it checks
A non-empty term with an **empty** result list: `searchTerm: 'zzzz'`,
`searchFilteredResults: []`.

## Expected
**Zero** markers, in both modes.

## Why it is worth pinning
Empty-list-means-no-filter is a real convention inside this very file —
`markersToShowAsLabels` treats `filteredUids.isEmpty` as "no filter, use every
marker". If that reading ever leaked into the visibility check, a search matching
nobody would show *everybody*: the opposite of the right answer, and the kind of
inversion that reads as plausible on screen.
$searchAbout''',
      () => _inBothModes((useOriginal) => _visibleIds(
            searchTerm: 'zzzz',
            searchFilteredResults: const [],
            useOriginal: useOriginal,
          ).isEmpty),
    ),
    search(
      'labels are recomputed against the filtered set',
      'Filtering away a crowded neighbour lets the surviving marker gain its '
          'name label, because label spacing is computed on visible markers only.',
      '''
## What it checks
The crowded fixture — **a** and **b** 110 m apart, **c** far away — at zoom 10,
where the proximity threshold is 5479 m. Unfiltered, a and b suppress each
other's labels. Searching down to just **a** removes b from the map, and
`buildVisibleMarkers` passes that narrowed set into the label computation:

```dart
markersToShowAsLabels(poiMarkers, zoom, filteredUids: visibleFilter);
```

## Expected
No `a_label` before the search; `a_label` present after it. Both modes.

## Why it is the subtlest branch here
It is the only place where filtering changes the *appearance* of a marker that
was already visible, rather than just which markers exist. Passing the unfiltered
set to the label computation still yields a plausible-looking map — every
surviving marker simply stays a bare dot — so the bug survives casual review, and
the payoff (search results are readable because they are named) is exactly what
is lost.
$searchAbout''',
      () => _inBothModes((useOriginal) {
        final before = _visibleIds(
          searchTerm: '',
          searchFilteredResults: const [],
          useOriginal: useOriginal,
          poi: _roundTripPoi(),
          labels: _roundTripLabels(),
        );
        final after = _visibleIds(
          searchTerm: 'a',
          searchFilteredResults: const ['a'],
          useOriginal: useOriginal,
          poi: _roundTripPoi(),
          labels: _roundTripLabels(),
        );
        final aLabel = MarkerVisibility.labelMarkerId('a');
        return !before.contains(aLabel) && after.contains(aLabel);
      }),
    ),
    // Relationship filtering. `_poi()` is three well-separated people (a, b, c),
    // so nothing here is confounded by label proximity.
    relationship(
      'the relationship filter shows only the allowed uids',
      'With a relationship toggle on, only the people it resolves to are on the '
          'map — everyone else and their labels are gone.',
      '''
## What it checks
`relationshipUids: {'a', 'c'}` with no search, against the three well-separated
markers a, b, c — the state the map is in when a filter toggle resolves to a
subset of the people on screen.

## Expected
**a** and **c** are on the map; **b** is absent. Both modes.

## Why both modes
Layered mode drops `b` and `b_label` from two different `where` clauses; original
mode drops it from the label branch or the POI branch depending on proximity. A
filter that leaked in one of those branches would leave a stray dot or a floating
name for someone the user has filtered away.
$relationshipAbout''',
      () => _inBothModes((useOriginal) => _sameSet(
            _peopleIn(_visibleIds(
              searchTerm: '',
              searchFilteredResults: const [],
              relationshipUids: const {'a', 'c'},
              useOriginal: useOriginal,
            )),
            {'a', 'c'},
          )),
    ),
    relationship(
      'a null relationship filter shows everyone',
      'With no relationship toggle on, every marker stays on the map — the '
          'unfiltered default the map opens in.',
      '''
## What it checks
`relationshipUids: null` — what `_relationshipFilterUids()`
(`home_map_logic.dart:101`) returns when none of the friends/followers/following
toggles is on:

```dart
if (!_filterFriends && !_filterFollowers && !_filterFollowing) return null;
```

## Expected
All three people (a, b, c) are on the map. `markerVisible` short-circuits on
`relationshipUids != null &&`, so no filtering happens at all.

## Why it is worth pinning
This is the app's default state — the map every user sees on open. It is also the
half of the tri-state that a "simplify the nullable to an empty set" refactor
would quietly merge with the empty case below, turning the default map blank.
$relationshipAbout''',
      () => _inBothModes((useOriginal) => _sameSet(
            _peopleIn(_visibleIds(
              searchTerm: '',
              searchFilteredResults: const [],
              relationshipUids: null,
              useOriginal: useOriginal,
            )),
            {'a', 'b', 'c'},
          )),
    ),
    relationship(
      'an empty relationship set hides every marker',
      'A toggle that matches nobody empties the map, rather than falling back to '
          'showing everyone.',
      '''
## What it checks
`relationshipUids: {}` — a toggle **is** on, but it resolved to zero uids (a user
with no friends yet, or whose relationship load failed). Distinct from `null`,
which is the scenario above.

## Expected
**Zero** markers, in both modes.

## Why it is worth pinning
Empty-means-no-filter is a real convention a few lines away:
`markersToShowAsLabels` treats `filteredUids.isEmpty` as "no filter, use every
marker", and `buildVisibleMarkers` genuinely does hand it an empty list here. The
visibility check must *not* read it the same way. If it ever did, turning on a
filter that matches nobody would show **everybody** — the exact inverse of what
the user asked for, and indistinguishable on screen from the filter simply not
working.
$relationshipAbout''',
      () => _inBothModes((useOriginal) => _visibleIds(
            searchTerm: '',
            searchFilteredResults: const [],
            relationshipUids: const <String>{},
            useOriginal: useOriginal,
          ).isEmpty),
    ),
    // Structural invariants of the marker set, walked across the whole
    // 1.0 -> 21.0 zoom range rather than at chosen zooms.
    invariant(
      'layered mode always keeps a POI dot under every label',
      'In the default layered mode every name label has its POI dot underneath '
          'it at every zoom — labels are layered on, never substituted.',
      '''
## What it checks
The **defining difference between the two marker behaviours**. Layered mode adds
every visible POI marker unconditionally and then layers labels on top:

```dart
result.addAll(poiMarkers.where((marker) => visible(marker.markerId.value)));
if (zoom >= minLabelZoom) { result.addAll(labelMarkers.where(...)); }
```

so for every `x_label` in the result, `x` must be in it too. The sweep walks zoom
1.0 -> 21.0 in half steps against the crowded fixture (a and b 110 m apart, c far
away), so the rule is checked either side of the 2.0 gate and either side of
every proximity-threshold step.

## Expected
At all 41 zooms, `{uid : uid_label in result}` is a subset of the result's plain
ids. Non-vacuous: at least one zoom in the sweep must actually emit a label.

## Why it is worth pinning
It is what "layered" *means*, and it was unasserted. If a refactor let a label
replace its dot here, the marker would lose its tap target and its POI icon while
still reading fine in a screenshot — the map would look right and stop working.
$invariantAbout''',
      () {
        final sweep = _sweepIds(useOriginal: false);
        final sawALabel = sweep.any((ids) => _labelIdsIn(ids).isNotEmpty);
        final holds = sweep.every((ids) => _labelIdsIn(ids)
            .map(MarkerVisibility.uidFromLabelMarkerId)
            .every(ids.contains));
        return sawALabel && holds;
      },
    ),
    invariant(
      'original mode never emits both forms of the same uid',
      'In the mutually-exclusive mode a person is drawn as a POI dot or as a '
          'name label, never as both, at every zoom from 1 to 21.',
      '''
## What it checks
The mirror-image rule for original mode, where POI and label are **mutually
exclusive**: the label branch takes the uids in `showAsLabels`, the POI branch
takes the complement.

```dart
result.addAll(labelMarkers.where((m) => visible(uid) && showAsLabels.contains(uid)));
result.addAll(poiMarkers.where((m) => visible(m.markerId.value)
    && !showAsLabels.contains(m.markerId.value)));
```

The two `where`s are guarded by opposite predicates over the same set, so no uid
may appear in both forms — at any zoom in the 1.0 -> 21.0 sweep.

## Expected
At all 41 zooms, no uid has both `x` and `x_label` in the result. Non-vacuous: the
sweep must contain at least one zoom emitting a label and at least one emitting a
plain dot.

## Why it is worth pinning
Both markers sit at the same coordinates, so a double emission draws the name
directly on top of its own icon — visually a slightly bolder marker, not an
obvious fault. The two `where` predicates are only complementary by construction;
nothing stops someone changing one and not the other.
$invariantAbout''',
      () {
        final sweep = _sweepIds(useOriginal: true);
        final sawALabel = sweep.any((ids) => _labelIdsIn(ids).isNotEmpty);
        final sawADot = sweep.any((ids) => ids.any((id) => !_isLabelId(id)));
        final holds = sweep.every((ids) => _labelIdsIn(ids)
            .map(MarkerVisibility.uidFromLabelMarkerId)
            .every((uid) => !ids.contains(uid)));
        return sawALabel && sawADot && holds;
      },
    ),
    invariant(
      'no label is emitted without a POI marker behind it',
      'A stale label with no matching POI marker never reaches the map, in '
          'either mode, at any zoom, and under search and relationship filters.',
      '''
## What it checks
No **orphan labels**. `_poiMarkers` and `_labelMarkers` are rebuilt from
different streams, so `_labelMarkers` can hold a `ghost_label` for someone who is
no longer a POI. The fixture adds exactly that — a label at (70, 70) with no POI
marker — and asserts every emitted label's uid is present in the **POI input
set**, across:

- both marker behaviours,
- the full 1.0 -> 21.0 zoom sweep,
- four filter configurations: unfiltered, search only, relationship only, and
  **search + relationship combined**.

## Expected
`ghost_label` never appears, and more strongly, every emitted `x_label` has an `x`
in `poiMarkers`. 328 marker sets checked.

## Why filters are part of it
The label branch is filtered by `visible(uid)`, which knows about the search and
relationship sets but knows nothing about which uids have POI markers — orphan
suppression is a side effect of `showAsLabels` being computed from `poiMarkers`.
That is load-bearing and implicit. A label with no dot behind it is a name
floating over empty map with no tap target, and under a relationship filter it
would be a name the user has explicitly filtered away.
$invariantAbout''',
      () {
        final poi = _roundTripPoi();
        final poiUids = poi.map((m) => m.markerId.value).toSet();
        final labels = {..._roundTripLabels(), _ghostLabel()};
        return _inBothModes((useOriginal) => _filterMatrix().every((filter) {
              final sweep = _sweepIds(
                useOriginal: useOriginal,
                poi: poi,
                labels: labels,
                searchTerm: filter['searchTerm']! as String,
                searchFilteredResults: filter['results']! as List<String>,
                relationshipUids: filter['rel'] as Set<String>?,
              );
              return sweep.every((ids) => _labelIdsIn(ids)
                  .map(MarkerVisibility.uidFromLabelMarkerId)
                  .every(poiUids.contains));
            }));
      },
    ),
    invariant(
      'the 1000 km isolation rule labels below the zoom gate',
      'A marker more than 1000 km from any neighbour is picked as a label even '
          'at zoom 1.5, below the 2.0 threshold — the isolation rule ignores zoom.',
      '''
## What it checks
The `alwaysLabelDistance` branch of `markersToShowAsLabels`
(`marker_visibility.dart:120`), the one selection rule with **no zoom term at
all**:

```dart
if (minDistanceToAnyMarker > alwaysLabelDistance) {
  showAsLabels.add(markerPositions[i].key);
} else if (currentZoom >= minLabelZoom && minDistanceToAnyMarker >= proximityThreshold) {
```

Fixture: two markers 9.5 degrees of latitude apart — **1056 km**, past the 1000 km
rule, and still inside the 10-degree window the loop measures across at all, so
the branch is reached by a real distance rather than by the `latDelta > 10` skip.
Control: the same pair at 8 degrees (**890 km**), which is over the sub-zoom-3
proximity threshold of 701 km but under the isolation rule.

## Expected
- `markersToShowAsLabels(1056 km pair, zoom: 1.5)` -> both uids.
- `markersToShowAsLabels(890 km pair, zoom: 1.5)` -> **empty** — the `else if`
  needs `zoom >= 2.0` and does not get it.

## Why it is worth pinning
It is the only branch that outranks the zoom gate, and it was uncovered. The
control half is what makes the check meaningful: without it, a build that ignored
zoom entirely would pass.
$invariantAbout''',
      () {
        final isolated =
            MarkerVisibility.markersToShowAsLabels(_isolatedPoi(), 1.5);
        final nearlyIsolated =
            MarkerVisibility.markersToShowAsLabels(_nearlyIsolatedPoi(), 1.5);
        return _sameSet(isolated, {'a', 'b'}) && nearlyIsolated.isEmpty;
      },
    ),
    invariant(
      'buildVisibleMarkers still withholds those labels below zoom 2.0',
      'End to end the zoom gate wins: the 1000 km isolation rule picks the '
          'labels, but the builder emits only POI dots below zoom 2.0.',
      '''
## What it checks
The other half of the isolation rule, and the more surprising one. Although
`markersToShowAsLabels` picks the 1056 km pair as labels at zoom 1.5, **neither
branch of `buildVisibleMarkers` acts on that below the gate**:

```dart
// layered
if (zoom >= minLabelZoom) { result.addAll(labelMarkers.where(...)); }
// original
if (zoom < minLabelZoom) { result.addAll(poiMarkers.where(...)); }  // labels never consulted
```

## Expected
`build(1056 km pair, zoom: 1.5)` -> `{a, b}`, no labels, in **both** modes — even
though `showAsLabels` at that zoom is `{a, b}`.

## Why it is worth pinning
The `alwaysLabelDistance` branch reads as "always label, whatever the zoom", and
at the `markersToShowAsLabels` level it is. End to end it is not: below zoom 2.0
its result is computed and then discarded. Pinning both halves says which layer
owns the gate, so the next person to touch either one can see the interaction
instead of rediscovering it. If the product intent is that a genuinely isolated
marker should be named at world zoom, this scenario is the one that will fail
when that is fixed — and it should be updated, not deleted.
$invariantAbout''',
      () => _inBothModes((useOriginal) {
        final poi = _isolatedPoi();
        final ids = MarkerVisibility.buildVisibleMarkers(
          poiMarkers: poi,
          labelMarkers: _isolatedLabels(poi),
          zoom: 1.5,
          searchTerm: '',
          searchFilteredResults: const [],
          useOriginalMarkerBehavior: useOriginal,
        ).map((m) => m.markerId.value).toSet();
        return _sameSet(ids, {'a', 'b'});
      }),
    ),

    // Move mode: the signed-in user is dragging their own marker, so the map is
    // reduced to that one dot.
    moveMode(
      'move mode shows the moving user\'s POI dot and nothing else',
      'While repositioning your own marker, the map hides every other marker so '
          'the only thing on it is the dot you are dragging.',
      '''
## What it checks
`buildVisibleMarkers(..., soloUid: 'b')` over three well-separated markers at a
zoom where all three would normally be labelled.

## Expected
The marker set is exactly `{b}` — no other uid, and no `b_label`.
$moveModeAbout''',
      () => _inBothModes((useOriginal) {
        final ids = MarkerVisibility.buildVisibleMarkers(
          poiMarkers: _poi(),
          labelMarkers: _labels(),
          zoom: 12,
          searchTerm: '',
          searchFilteredResults: const [],
          useOriginalMarkerBehavior: useOriginal,
          soloUid: 'b',
        ).map((m) => m.markerId.value).toSet();
        return _sameSet(ids, {'b'});
      }),
    ),
    moveMode(
      'move mode overrides the search term and the relationship filters',
      'Move mode wins over every other filter: a search term and a relationship '
          'allow-set that both exclude you cannot remove your own dot.',
      '''
## What it checks
The same build with a search term and a relationship allow-set that between them
exclude `b` entirely. Move mode short-circuits ahead of both.

## Expected
Still exactly `{b}`, not the empty set — you can always see the marker you are
moving.
$moveModeAbout''',
      () => _inBothModes((useOriginal) {
        final ids = MarkerVisibility.buildVisibleMarkers(
          poiMarkers: _poi(),
          labelMarkers: _labels(),
          zoom: 12,
          searchTerm: 'a',
          searchFilteredResults: const ['a'],
          relationshipUids: const {'a', 'c'},
          useOriginalMarkerBehavior: useOriginal,
          soloUid: 'b',
        ).map((m) => m.markerId.value).toSet();
        return _sameSet(ids, {'b'});
      }),
    ),
    moveMode(
      'leaving move mode restores the full marker set',
      'Dropping back to soloUid: null after a move rebuilds exactly the marker '
          'set the map had before move mode was entered.',
      '''
## What it checks
build(soloUid: null) before move mode and build(soloUid: null) after it produce
the same marker ids, while the move-mode build in between differs — so the check
cannot pass vacuously.

## Expected
ids(before) == ids(after), and ids(during) — just `{b}` — differs from both.
$moveModeAbout''',
      () => _inBothModes((useOriginal) {
        Set<String> build(String? soloUid) =>
            MarkerVisibility.buildVisibleMarkers(
              poiMarkers: _poi(),
              labelMarkers: _labels(),
              zoom: 12,
              searchTerm: '',
              searchFilteredResults: const [],
              useOriginalMarkerBehavior: useOriginal,
              soloUid: soloUid,
            ).map((m) => m.markerId.value).toSet();

        final before = build(null);
        final during = build('b');
        final after = build(null);
        return _sameSet(before, after) &&
            _sameSet(during, {'b'}) &&
            !_sameSet(during, before);
      }),
    ),
  ];
}
