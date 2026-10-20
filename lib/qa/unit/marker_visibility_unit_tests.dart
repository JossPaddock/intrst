import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../main/marker_visibility.dart';
import 'unit_test.dart';

/// Unit coverage for [MarkerVisibility]: label-id round-tripping, great-circle
/// distance, the per-zoom proximity thresholds, the "which markers label"
/// proximity logic, search/relationship visibility, and the full
/// [MarkerVisibility.buildVisibleMarkers] set in both marker behaviours —
/// including the zoom-2.0 label boundary and the "swap to labels and back"
/// zoom round-trips.
///
/// These are the same assertions the admin dashboard's **Patrol tests** tab
/// exercises at the scenario level via `markerVisibilityScenarios()`; here they
/// run as fine-grained unit tests.

/// A POI marker as the map logic sees it: markerId == uid.
Marker _poi(String uid, double lat, double lng) =>
    Marker(markerId: MarkerId(uid), position: LatLng(lat, lng));

/// A label marker: markerId == "<uid>_label", same position as its POI.
Marker _label(String uid, double lat, double lng) => Marker(
      markerId: MarkerId(MarkerVisibility.labelMarkerId(uid)),
      position: LatLng(lat, lng),
    );

Set<String> _idsOf(Set<Marker> markers) =>
    markers.map((m) => m.markerId.value).toSet();

bool _hasNoLabelMarkers(Set<Marker> markers) => markers
    .every((m) => !m.markerId.value.endsWith(MarkerVisibility.labelIdSuffix));

bool _deepSetEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Runs [zooms] through [MarkerVisibility.buildVisibleMarkers] in order, one
/// call per zoom, and returns the resulting marker-id set at each step — the
/// same sequence of calls `_onCameraMove` makes as the user pinches the map.
List<Set<String>> _zoomSweep(
  Set<Marker> poiMarkers,
  Set<Marker> labelMarkers,
  List<double> zooms, {
  bool useOriginal = false,
}) =>
    zooms
        .map((zoom) => _idsOf(MarkerVisibility.buildVisibleMarkers(
              poiMarkers: poiMarkers,
              labelMarkers: labelMarkers,
              zoom: zoom,
              searchTerm: '',
              searchFilteredResults: const [],
              useOriginalMarkerBehavior: useOriginal,
            )))
        .toList();

List<UnitTest> markerVisibilityUnitTests() {
  UnitTest t(String suite, String name, String summary, UnitTestBody body,
          {String? doc}) =>
      UnitTest(
          suite: suite, name: name, summary: summary, doc: doc, body: body);

  const ids = 'MarkerVisibility.labelMarkerId / uidFromLabelMarkerId';
  const dist = 'MarkerVisibility.calculateDistance';
  const thresh = 'MarkerVisibility.visualProximityThreshold';
  const labels = 'MarkerVisibility.markersToShowAsLabels';
  const visible = 'MarkerVisibility.markerVisible';
  const layered = 'MarkerVisibility.buildVisibleMarkers — layered';
  const original = 'MarkerVisibility.buildVisibleMarkers — original';
  const roundTrip = 'MarkerVisibility.buildVisibleMarkers — zoom round-trips';

  // Isolated markers so labels are never suppressed by proximity.
  final layeredPoi = {_poi('a', 0, 0), _poi('b', 40, 40), _poi('c', -40, -40)};
  final layeredLabels = {
    _label('a', 0, 0),
    _label('b', 40, 40),
    _label('c', -40, -40),
  };

  Set<Marker> buildLayered({
    double zoom = 12,
    String searchTerm = '',
    List<String> searchFilteredResults = const [],
    Set<String>? relationshipUids,
  }) =>
      MarkerVisibility.buildVisibleMarkers(
        poiMarkers: layeredPoi,
        labelMarkers: layeredLabels,
        zoom: zoom,
        searchTerm: searchTerm,
        searchFilteredResults: searchFilteredResults,
        relationshipUids: relationshipUids,
      );

  // 'a'/'b' crowd each other; 'c' is isolated.
  final originalPoi = {_poi('a', 0, 0), _poi('b', 0.001, 0), _poi('c', 40, 40)};
  final originalLabels = {
    _label('a', 0, 0),
    _label('b', 0.001, 0),
    _label('c', 40, 40),
  };

  Set<Marker> buildOriginal({double zoom = 12}) =>
      MarkerVisibility.buildVisibleMarkers(
        poiMarkers: originalPoi,
        labelMarkers: originalLabels,
        zoom: zoom,
        searchTerm: '',
        searchFilteredResults: const [],
        useOriginalMarkerBehavior: true,
      );

  // Round-trip fixture: a crowded pair ('a'/'b', ~110 m apart) plus an isolated
  // marker ('c'). Chosen so every waypoint of the sweeps below is genuinely a
  // different marker set — otherwise a "returns to where it started" assertion
  // would pass without anything having changed in between.
  //
  //            zoom 1          zoom 10               zoom 18
  //   layered  a,b,c           a,b,c,c_label         a,b,c + all three labels
  //   original a,b,c           a,b,c_label           all three as labels
  final roundTripPoi = {_poi('a', 0, 0), _poi('b', 0.001, 0), _poi('c', 40, 40)};
  final roundTripLabels = {
    _label('a', 0, 0),
    _label('b', 0.001, 0),
    _label('c', 40, 40),
  };

  List<Set<String>> sweep(List<double> zooms, {bool useOriginal = false}) =>
      _zoomSweep(roundTripPoi, roundTripLabels, zooms,
          useOriginal: useOriginal);

  /// Asserts a zoom sweep returns to exactly the marker ids it started with,
  /// and that the midpoint really did differ (so the guard cannot pass vacuously).
  void expectRoundTrip(UnitTestContext t, List<double> zooms,
      {bool useOriginal = false}) {
    final steps = sweep(zooms, useOriginal: useOriginal);
    for (var i = 0; i < zooms.length; i++) {
      t.note('zoom ${zooms[i]} -> ${(steps[i].toList()..sort()).join(', ')}');
    }
    t.expectEqual(steps.last, steps.first,
        reason: 'zoom sweep ${zooms.join(" -> ")} did not restore the '
            'original marker ids: started with ${steps.first}, ended with '
            '${steps.last}');
    t.expectFalse(_deepSetEquals(steps[1], steps.first),
        reason: 'zoom ${zooms[1]} produced the same markers as zoom '
            '${zooms.first}, so this round-trip proves nothing');
  }

  return <UnitTest>[
    // ── label id round-tripping ──────────────────────────────────────────
    t(ids, 'round-trips a uid',
        'labelMarkerId adds the suffix and uidFromLabelMarkerId removes it.',
        doc: '''
## What it checks
`labelMarkerId(uid)` appends the `_label` suffix, and `uidFromLabelMarkerId`
recovers the original uid.

## Why it matters
A label marker and its POI dot share one uid but need distinct `MarkerId`s so
both can sit on the map at once. The suffix is that distinction, and the round
trip is how a tapped label maps back to the person it names.

## Expected
`abc123` -> `abc123_label` -> `abc123`
''',
        (t) {
      const uid = 'abc123';
      t.expectEqual(MarkerVisibility.labelMarkerId(uid), 'abc123_label');
      t.expectEqual(
        MarkerVisibility.uidFromLabelMarkerId(
            MarkerVisibility.labelMarkerId(uid)),
        uid,
      );
    }),
    t(ids, 'leaves a bare (POI) id untouched',
        'A bare POI id (no suffix) passes through unchanged.',
        doc: '''
## What it checks
`uidFromLabelMarkerId` on a bare POI id (no `_label` suffix) returns it
unchanged.

## Why it matters
The same helper runs for every tapped marker, POI or label. It must be a no-op
on POI ids rather than trimming real characters off a uid.

## Expected
`abc123` -> `abc123`
''',
        (t) => t.expectEqual(
            MarkerVisibility.uidFromLabelMarkerId('abc123'), 'abc123')),
    t(ids, 'strips only the trailing suffix',
        'A uid that itself contains "_label" keeps its inner occurrence.',
        doc: '''
## What it checks
Only the **trailing** `_label` is stripped; a uid that itself contains `_label`
keeps its inner occurrence.

## Why it matters
Firestore uids are arbitrary, so a naive `replaceAll('_label', '')` would corrupt
a uid that legitimately contains that substring. The helper removes exactly the
one suffix it added.

## Expected
`a_labelb_label` -> `a_labelb`
''',
        (t) => t.expectEqual(
            MarkerVisibility.uidFromLabelMarkerId('a_labelb_label'),
            'a_labelb')),

    // ── distance ─────────────────────────────────────────────────────────
    t(dist, 'is zero for identical points',
        'Two identical coordinates are zero metres apart.',
        doc: '''
## What it checks
The great-circle distance between a point and itself is exactly `0.0`.

## Why it matters
Two markers at the same spot must read as maximally crowded (distance 0), never
a tiny non-zero value from floating-point drift that could flip a threshold
comparison.

## Expected
d((37,-122), (37,-122)) = `0.0`
''',
        (t) => t.expectEqual(
            MarkerVisibility.calculateDistance(
                const LatLng(37.0, -122.0), const LatLng(37.0, -122.0)),
            0.0)),
    t(dist, 'one degree of latitude is ~111km',
        'One degree of latitude is about 111 km.', doc: '''
## What it checks
One degree of latitude measures ~111 km (within 50 m).

## Why it matters
This is the reference calibration for the haversine implementation — one degree
of latitude is a known, constant ~111.195 km everywhere on Earth, so it anchors
the formula's correctness.

## Expected
d((0,0), (1,0)) ≈ `111195 m` (±50)
''', (t) {
      final d = MarkerVisibility.calculateDistance(
          const LatLng(0, 0), const LatLng(1, 0));
      t.expectClose(d, 111195, 50);
    }),
    t(dist, 'is symmetric', 'Distance A→B equals distance B→A.', doc: '''
## What it checks
`distance(A, B)` equals `distance(B, A)` within floating-point tolerance.

## Why it matters
The proximity logic compares each marker against its neighbours in both
iteration orders; an asymmetric distance could label one marker of a pair but
not the other.

## Expected
d(SF, LA) == d(LA, SF)
''', (t) {
      const a = LatLng(37.7749, -122.4194); // SF
      const b = LatLng(34.0522, -118.2437); // LA
      t.expectClose(MarkerVisibility.calculateDistance(a, b),
          MarkerVisibility.calculateDistance(b, a), 1e-6);
    }),
    t(dist, 'SF to LA is ~559km', 'A known city pair lands near 559 km.', doc: '''
## What it checks
A real-world city pair (San Francisco -> Los Angeles) computes to ~559 km
(within 5 km).

## Why it matters
A second, larger-scale calibration point beyond the 1-degree check, using
coordinates whose true distance is independently known.

## Expected
d(SF, LA) ≈ `559000 m` (±5000)
''', (t) {
      final d = MarkerVisibility.calculateDistance(
          const LatLng(37.7749, -122.4194), const LatLng(34.0522, -118.2437));
      t.expectClose(d, 559000, 5000);
    }),

    // ── proximity thresholds ─────────────────────────────────────────────
    t(thresh, 'returns the tuned value for each mapped zoom level',
        'Each mapped zoom returns its hand-tuned proximity threshold.', doc: '''
## What it checks
Several mapped zoom levels return their exact hand-tuned proximity threshold —
the distance under which two markers read as overlapping.

## Why it matters
These constants are the dial that sets how crowded the map looks at each zoom.
Pinning them guards against an accidental edit changing label density across the
whole app.

## Expected
z3 -> `900000`, z10 -> `5479`, z15 -> `171`, z21 -> `10`
''', (t) {
      t.expectEqual(MarkerVisibility.visualProximityThreshold(3), 900000);
      t.expectEqual(MarkerVisibility.visualProximityThreshold(10), 5479);
      t.expectEqual(MarkerVisibility.visualProximityThreshold(15), 171);
      t.expectEqual(MarkerVisibility.visualProximityThreshold(21), 10);
    }),
    t(thresh, 'floors fractional zooms into their bucket',
        'A fractional zoom uses the same threshold as its floor.',
        doc: '''
## What it checks
A fractional zoom uses the same threshold as its integer floor: `10.9` maps to
the same bucket as `10.0`.

## Why it matters
Google Maps reports continuous zoom values, but the thresholds are defined per
integer level. Flooring keeps the label set stable across a smooth pinch instead
of flickering between two buckets.

## Expected
threshold(10.9) == threshold(10.0)
''',
        (t) => t.expectEqual(MarkerVisibility.visualProximityThreshold(10.0),
            MarkerVisibility.visualProximityThreshold(10.9))),
    t(thresh, 'below zoom 3 uses the wide fallback',
        'Below zoom 3 the threshold is the wide fallback value.', doc: '''
## What it checks
Any zoom below 3 returns the single wide fallback threshold.

## Why it matters
When the whole world is in view, markers are so dense that a per-level table
would be pointless; one wide value suppresses nearly all labels down there.

## Expected
threshold(2.5) = threshold(0) = `701312.5`
''', (t) {
      t.expectEqual(MarkerVisibility.visualProximityThreshold(2.5), 701312.5);
      t.expectEqual(MarkerVisibility.visualProximityThreshold(0), 701312.5);
    }),
    t(thresh, 'above the mapped range clamps to 10m',
        'Beyond the mapped zooms the threshold clamps to 10 m.', doc: '''
## What it checks
Beyond the top of the mapped range the threshold clamps to the minimum, 10 m.

## Why it matters
At extreme zoom every marker is effectively isolated, so the threshold bottoms
out rather than reading off the end of the table.

## Expected
threshold(22) = threshold(30) = `10`
''', (t) {
      t.expectEqual(MarkerVisibility.visualProximityThreshold(22), 10);
      t.expectEqual(MarkerVisibility.visualProximityThreshold(30), 10);
    }),
    t(thresh, 'is monotonically non-increasing across the mapped range',
        'Thresholds never increase as zoom increases across 3–21.', doc: '''
## What it checks
Across zooms 3 -> 21 the threshold never increases from one level to the next.

## Why it matters
The whole model assumes "zoom in => more room => more labels". A single
out-of-order value would break that and could make labels *vanish* as you zoom
in. This property check catches any such table typo.

## Expected
For every z in 3..21: `threshold(z) <= threshold(z-1)`
''', (t) {
      double previous = MarkerVisibility.visualProximityThreshold(3);
      for (double z = 4; z <= 21; z++) {
        final value = MarkerVisibility.visualProximityThreshold(z);
        t.expectLessOrEqual(value, previous, reason: 'at zoom $z');
        previous = value;
      }
    }),

    // ── markersToShowAsLabels ────────────────────────────────────────────
    t(labels, 'an isolated marker always labels, even zoomed far out',
        'Markers beyond alwaysLabelDistance always label, regardless of zoom.',
        doc: '''
## What it checks
Two markers separated by more than `alwaysLabelDistance` both label even at a
far-out zoom (1).

## Why it matters
A marker with no near neighbour should always show its name — there is nothing
for it to collide with — regardless of the per-zoom threshold.

## Expected
{a(0,0), b(40,40)} at zoom 1 -> `{a, b}`
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('b', 40, 40)}, 1),
            {'a', 'b'})),
    t(labels, 'a lone marker labels (no neighbour at all)',
        'A single marker with no neighbour always labels.',
        doc: '''
## What it checks
A single marker, with no neighbour at all, always labels.

## Why it matters
The degenerate one-marker case must not fall through the neighbour-scan into "no
label"; a lone pin always shows its name.

## Expected
{a(0,0)} at zoom 12 -> `{a}`
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels({_poi('a', 0, 0)}, 12),
            {'a'})),
    t(labels, 'two very close markers are both suppressed when zoomed out',
        'A close pair inside the proximity threshold shows no labels.',
        doc: '''
## What it checks
Two markers ~110 m apart show **no** labels at zoom 12 (threshold 1369 m).

## Why it matters
When names would visually overlap, showing neither is cleaner than showing a
tangled pair — the core anti-clutter rule.

## Expected
{a(0,0), b(0.001,0)} at zoom 12 -> `{}`
''',
        (t) => t.expectEmpty(MarkerVisibility.markersToShowAsLabels(
            {_poi('a', 0, 0), _poi('b', 0.001, 0)}, 12))),
    t(labels, 'the same pair labels once zoomed in past the threshold',
        'Zooming past the threshold lets a close pair label again.',
        doc: '''
## What it checks
The same ~110 m pair **does** label at zoom 19 (threshold 10 m), because they are
now far enough apart on screen.

## Why it matters
Suppression is about on-screen overlap, not absolute distance: zooming in buys
the room to show both names. This is the reciprocal of the "suppressed when
zoomed out" test.

## Expected
{a(0,0), b(0.001,0)} at zoom 19 -> `{a, b}`
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('b', 0.001, 0)}, 19),
            {'a', 'b'})),
    t(labels, 'filteredUids restricts which markers participate',
        'Filtering to one of a crowded pair leaves it isolated, so it labels.',
        doc: '''
## What it checks
Passing `filteredUids: ['a']` for a crowded pair makes `a` label — with `b`
excluded from the computation, `a` has no neighbour.

## Why it matters
When a search or relationship filter is active, only visible markers should
crowd each other. A hidden neighbour must not suppress a visible marker's label.

## Expected
{a, b} crowded, filter `['a']`, zoom 12 -> `{a}`
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('b', 0.001, 0)}, 12,
                filteredUids: ['a']),
            {'a'})),
    t(labels, 'an empty filteredUids list means no filter (matches null)',
        'An empty filter behaves the same as passing no filter.',
        doc: '''
## What it checks
An empty `filteredUids` list behaves identically to passing no filter at all.

## Why it matters
Callers pass an empty list when no filter is active. That must mean "everyone
participates", not "nobody participates" (which would hide every label).

## Expected
result(filter: []) == result(no filter)
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('b', 0.001, 0)}, 12, filteredUids: []),
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('b', 0.001, 0)}, 12))),
    t(labels, 'markers more than 10 degrees apart are skipped as neighbours',
        'A marker >10° away never suppresses another\'s label.',
        doc: '''
## What it checks
A marker more than 10° away in longitude is skipped as a neighbour, so it never
suppresses another marker's label.

## Why it matters
This is a performance short-circuit: markers that far apart can't visually
collide at any usable zoom, so the code skips the expensive distance calc. The
test confirms the short-circuit doesn't change the outcome.

## Expected
{a(0,0), far(0,20)} at zoom 12 -> `{a, far}`
''',
        (t) => t.expectEqual(
            MarkerVisibility.markersToShowAsLabels(
                {_poi('a', 0, 0), _poi('far', 0, 20)}, 12),
            {'a', 'far'})),
    t(labels, 'crowded cluster suppresses all of its members',
        'A tight cluster shows no labels for any member.',
        doc: '''
## What it checks
Three markers packed into a tiny cluster show no labels for any member at
zoom 16.

## Why it matters
Extends the two-marker suppression rule to a real cluster: when everyone is
crowded, everyone's label is suppressed, not just some.

## Expected
tight {a, b, c} at zoom 16 -> `{}`
''',
        (t) => t.expectEmpty(MarkerVisibility.markersToShowAsLabels({
              _poi('a', 0, 0),
              _poi('b', 0.0001, 0),
              _poi('c', 0, 0.0001),
            }, 16))),
    t(labels, 'empty input yields no labels',
        'No markers in means no labels out.',
        doc: '''
## What it checks
An empty marker set yields an empty label set.

## Why it matters
The no-data path (map still loading, everything filtered out) must return
cleanly rather than error.

## Expected
{} at zoom 12 -> `{}`
''',
        (t) => t.expectEmpty(
            MarkerVisibility.markersToShowAsLabels(<Marker>{}, 12))),

    // ── markerVisible ────────────────────────────────────────────────────
    t(visible, 'everything is visible with no search and no filter',
        'With no search term and no relationship filter, every uid is visible.',
        doc: '''
## What it checks
With no search term and no relationship filter, every uid is visible.

## Why it matters
The default, unfiltered map shows everyone; visibility only narrows when a filter
is actually applied.

## Expected
markerVisible('a', search '', no filter) -> `true`
''',
        (t) => t.expectTrue(MarkerVisibility.markerVisible('a',
            searchTerm: '', searchFilteredResults: []))),
    t(visible, 'search hides uids outside the result set',
        'An active search hides uids that are not in its results.', doc: '''
## What it checks
With an active search, a uid **in** the results is visible and one **outside**
them is hidden.

## Why it matters
Search is a hard filter: the map should show only what matched, nothing else.

## Expected
search 'bo', results ['b']: `a` -> hidden, `b` -> visible
''', (t) {
      t.expectFalse(MarkerVisibility.markerVisible('a',
          searchTerm: 'bo', searchFilteredResults: ['b']));
      t.expectTrue(MarkerVisibility.markerVisible('b',
          searchTerm: 'bo', searchFilteredResults: ['b']));
    }),
    t(visible, 'relationship filter hides uids outside the set',
        'A relationship filter hides uids that are not in its set.', doc: '''
## What it checks
With a relationship filter set, a uid inside the set is visible and one outside
it is hidden.

## Why it matters
The relationship filter (e.g. "friends only") narrows the map the same way search
does, but via a resolved uid set instead of text.

## Expected
filter {b}: `a` -> hidden, `b` -> visible
''', (t) {
      t.expectFalse(MarkerVisibility.markerVisible('a',
          searchTerm: '', searchFilteredResults: [], relationshipUids: {'b'}));
      t.expectTrue(MarkerVisibility.markerVisible('b',
          searchTerm: '', searchFilteredResults: [], relationshipUids: {'b'}));
    }),
    t(visible, 'an empty relationship set hides everything',
        'An empty relationship set (filter on, no matches) hides every uid.',
        doc: '''
## What it checks
An empty (but non-null) relationship set hides every uid.

## Why it matters
`null` means "no filter — show everyone", but an empty **set** means "the filter
is on and nobody matched" — the opposite. Conflating the two would wrongly show
everyone when a filter legitimately excludes all.

## Expected
filter {} : `a` -> hidden
''',
        (t) => t.expectFalse(MarkerVisibility.markerVisible('a',
            searchTerm: '',
            searchFilteredResults: [],
            relationshipUids: <String>{}))),

    // ── buildVisibleMarkers — layered ────────────────────────────────────
    t(layered, 'POI markers are always shown, labels layered on top',
        'In layered mode both the POI dot and its label render when isolated.',
        doc: '''
## What it checks
In the default **layered** mode, isolated markers render both their POI dot and
their label on top.

## Why it matters
Layered mode keeps the tappable POI dot always present and treats the label as a
decoration over it — so the tap target never disappears when a name shows.

## Expected
3 isolated at zoom 12 -> `{a, b, c, a_label, b_label, c_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildLayered()),
            {'a', 'b', 'c', 'a_label', 'b_label', 'c_label'})),
    t(layered, 'below minLabelZoom only POI markers are shown',
        'Far out (zoom 1) only POI dots render, no labels.',
        doc: '''
## What it checks
Below `minLabelZoom` (at zoom 1) only POI dots render — no labels.

## Why it matters
Labels are meaningless when zoomed way out; the map shows plain dots until it is
worth naming them.

## Expected
zoom 1 -> `{a, b, c}`
''',
        (t) => t.expectEqual(_idsOf(buildLayered(zoom: 1)), {'a', 'b', 'c'})),
    t(layered, 'at zoom 1.9 (just below minLabelZoom) no labels are emitted',
        'A hair below the 2.0 boundary still shows only POI dots.', doc: '''
## What it checks
At zoom 1.9 — a hair below the 2.0 boundary — the result is POI-only and
contains no `_label` markers.

## Why it matters
Pins the exact lower edge of the label boundary rather than a coarse 1-vs-10
check, so an off-by-a-hair change to `minLabelZoom` is caught.

## Expected
zoom 1.9 -> `{a, b, c}` and no `_label` ids
''', (t) {
      final result = buildLayered(zoom: 1.9);
      t.expectEqual(_idsOf(result), {'a', 'b', 'c'});
      t.expectTrue(_hasNoLabelMarkers(result));
    }),
    t(layered, 'at zoom 2.0 exactly, labels become eligible again',
        'The 2.0 boundary is inclusive: labels appear for isolated markers.',
        doc: '''
## What it checks
At exactly `minLabelZoom` (2.0) the isolated markers gain their labels.

## Why it matters
The boundary is **inclusive** (`>=`), so 2.0 itself labels. Paired with the 1.9
test, this fixes the boundary from both sides.

## Expected
zoom 2.0 -> `{a, b, c, a_label, b_label, c_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildLayered(zoom: MarkerVisibility.minLabelZoom)),
            {'a', 'b', 'c', 'a_label', 'b_label', 'c_label'})),
    t(layered, 'search narrows both POI and label markers',
        'A search restricts both the POI and label sets to its results.',
        doc: '''
## What it checks
An active search restricts both the POI dots and the labels to the matching uid.

## Why it matters
The layered POI + label pair must filter as a unit — a search should never leave
an orphan dot or an orphan label for a hidden person.

## Expected
search 'a', results ['a'] -> `{a, a_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildLayered(searchTerm: 'a', searchFilteredResults: ['a'])),
            {'a', 'a_label'})),
    t(layered, 'relationship filter narrows both POI and label markers',
        'A relationship filter restricts both the POI and label sets.',
        doc: '''
## What it checks
A relationship filter restricts both the POI dots and the labels to the allowed
uid.

## Why it matters
The relationship filter must narrow the layered pair exactly as search does.

## Expected
filter {b} -> `{b, b_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildLayered(relationshipUids: {'b'})), {'b', 'b_label'})),
    t(layered, 'an active search overrides the relationship filter',
        'When both are set, search results win over the relationship filter.',
        doc: '''
## What it checks
When a search and a relationship filter are both active, the search results win —
even a uid outside the relationship set shows if it matched the search.

## Why it matters
Search is meant to reach the whole map, not just your filtered subset; otherwise
searching while a filter is on would silently drop matches.

## Expected
search 'a' (results ['a']) + filter {b} -> `{a, a_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildLayered(
                searchTerm: 'a',
                searchFilteredResults: ['a'],
                relationshipUids: {'b'})),
            {'a', 'a_label'})),
    t(layered, 'a search with no results shows nothing',
        'A search that matches nothing renders an empty map.',
        doc: '''
## What it checks
A search that matches nothing renders an empty marker set.

## Why it matters
"No results" must clear the map, not fall back to showing everyone.

## Expected
search 'zzz', results [] -> `{}`
''',
        (t) => t.expectEmpty(buildLayered(
            searchTerm: 'zzz', searchFilteredResults: const []))),
    t(layered, 'crowded markers keep their POI dot but lose their label',
        'Crowded markers keep their POI dot but drop the label in layered mode.',
        doc: '''
## What it checks
A crowded pair keeps both POI dots but shows neither label in layered mode.

## Why it matters
This is the defining difference of layered mode: proximity suppresses only the
**label**, never the tappable dot. Both people stay selectable even when their
names would collide.

## Expected
crowded {a, b} at zoom 12 -> `{a, b}` (no labels)
''',
        (t) {
      final result = MarkerVisibility.buildVisibleMarkers(
        poiMarkers: {_poi('a', 0, 0), _poi('b', 0.001, 0)},
        labelMarkers: {_label('a', 0, 0), _label('b', 0.001, 0)},
        zoom: 12,
        searchTerm: '',
        searchFilteredResults: const [],
      );
      t.expectEqual(_idsOf(result), {'a', 'b'});
    }),

    // ── buildVisibleMarkers — original (mutually exclusive) ───────────────
    t(original, 'a labelled marker shows only its label, not its POI dot',
        'Isolated markers show a label instead of a POI dot; crowded stay POI.',
        doc: '''
## What it checks
In **original** (mutually exclusive) mode an isolated marker shows its label
*instead of* its POI dot, while a crowded pair stays as POI dots.

## Why it matters
This is the legacy behaviour where POI and label are alternatives, not layers —
`c` (isolated) becomes `c_label`, while crowded `a`/`b` remain dots.

## Expected
{a,b crowded, c isolated} at zoom 12 -> `{a, b, c_label}`
''',
        (t) => t.expectEqual(_idsOf(buildOriginal()), {'a', 'b', 'c_label'})),
    t(original, 'below minLabelZoom only POI markers are shown',
        'Far out (zoom 1) only POI dots render.',
        doc: '''
## What it checks
Below `minLabelZoom` (zoom 1) original mode also shows only POI dots.

## Expected
zoom 1 -> `{a, b, c}`
''',
        (t) => t.expectEqual(_idsOf(buildOriginal(zoom: 1)), {'a', 'b', 'c'})),
    t(original, 'at zoom 1.9 (just below minLabelZoom) no labels are emitted',
        'A hair below the 2.0 boundary shows only POI dots in original mode.',
        doc: '''
## What it checks
At zoom 1.9 original mode is POI-only with no `_label` markers — the lower edge
of the boundary, verified for this behaviour too.

## Expected
zoom 1.9 -> `{a, b, c}` and no `_label` ids
''',
        (t) {
      final result = buildOriginal(zoom: 1.9);
      t.expectEqual(_idsOf(result), {'a', 'b', 'c'});
      t.expectTrue(_hasNoLabelMarkers(result));
    }),
    t(original, 'at zoom 2.0 exactly, labels become eligible again',
        'At the inclusive boundary the isolated marker flips to a label.',
        doc: '''
## What it checks
At exactly zoom 2.0 the isolated marker `c` flips from a POI dot to a label,
while crowded `a`/`b` stay dots.

## Why it matters
Confirms the inclusive boundary holds in original mode, where crossing it swaps
the dot for the label rather than adding a label on top.

## Expected
zoom 2.0 -> `{a, b, c_label}`
''',
        (t) => t.expectEqual(
            _idsOf(buildOriginal(zoom: MarkerVisibility.minLabelZoom)),
            {'a', 'b', 'c_label'})),
    t(original, 'never emits both the POI and the label for one uid',
        'No uid appears as both a POI dot and a label at once.', doc: '''
## What it checks
No uid is ever emitted as both its POI dot and its label at the same time.

## Why it matters
The whole point of original mode is mutual exclusivity: two markers for one
person would double-draw and double-tap. This asserts the invariant directly.

## Expected
for each uid: not (`uid` and `uid_label` both present)
''', (t) {
      final result = _idsOf(buildOriginal());
      for (final uid in ['a', 'b', 'c']) {
        t.expectFalse(
          result.contains(uid) && result.contains('${uid}_label'),
          reason: '$uid appeared as both POI and label',
        );
      }
    }),
    t(original, 'every uid is represented exactly once',
        'Each uid renders exactly once, as either a POI dot or a label.', doc: '''
## What it checks
Every uid is represented exactly once — as either a POI dot or a label — so the
three input markers yield three output markers covering `{a, b, c}`.

## Why it matters
The complement of the "never both" test: mutual exclusivity must not *drop* a
marker either. Each person appears once, never zero or twice.

## Expected
3 markers out; uids (suffix-stripped) = `{a, b, c}`
''', (t) {
      final result = _idsOf(buildOriginal());
      t.expectEqual(result.length, 3);
      t.expectEqual(
          result.map(MarkerVisibility.uidFromLabelMarkerId).toSet(),
          {'a', 'b', 'c'});
    }),

    // ── zoom round-trips (swap to labels and back) ───────────────────────
    t(
        roundTrip,
        'zoom 10 -> 18 -> 10 restores the original marker ids — layered',
        'Zooming in far enough to swap crowded dots for labels and back out '
            'again lands on exactly the marker set we started with.',
        doc: '''
## Swap to labels and back

The map rebuilds its whole marker set on every camera move: `_onCameraMove`
calls `MarkerVisibility.buildVisibleMarkers` and hands the result straight to
`setState`. Zooming in swaps crowded POI dots for name labels; zooming back out
must swap them back.

This walks the builder through **zoom 10 -> 18 -> 10** and asserts the final
`Set<Marker>` carries exactly the same `MarkerId`s as the initial one.

- At **zoom 10** the proximity threshold is 5479 m, so the pair 110 m apart is
  crowded and unlabelled; only the isolated marker labels.
- At **zoom 18** the threshold drops to 21 m, so the pair clears it and all
  three label.
- Returning to **zoom 10** must reproduce the zoom-10 set exactly.

The test also asserts the zoom-18 set **differs** from the zoom-10 set, so it
can never pass vacuously — a builder that returned the same thing at every zoom
would fail here rather than sail through.

## Why it is worth guarding

The builder is pure today, so the round trip is equality by construction. That
is exactly the property under guard: the moment anyone adds caching, memoisation
or accumulated state to the marker pipeline, a stale label or an orphaned dot
would survive the trip back and this test would catch it — including the
`_label` suffix bookkeeping that keeps a label marker distinct from its POI.
''', (t) => expectRoundTrip(t, [10, 18, 10])),
    t(
        roundTrip,
        'zoom 10 -> 18 -> 10 restores the original marker ids — original',
        'The same in/out sweep in the mutually-exclusive mode, where markers '
            'flip between POI dot and label rather than layering.',
        doc: '''
## Swap to labels and back (original mode)

Same **zoom 10 -> 18 -> 10** sweep as the layered case, but with
`useOriginalMarkerBehavior: true`, where a marker is drawn as *either* a POI dot
*or* a label — never both. That makes the round trip strictly harder: a marker
does not merely gain and lose a label, it changes identity between `uid` and
`uid_label`.

- **zoom 10** — the crowded pair renders as dots, the isolated marker as a label.
- **zoom 18** — all three render as labels; both dots disappear.
- **back to zoom 10** — the two dots must come back and the two labels must go.

As with the layered case, the midpoint is asserted to differ from the start.
''', (t) => expectRoundTrip(t, [10, 18, 10], useOriginal: true)),
    t(
        roundTrip,
        'zoom 10 -> 1 -> 10 restores the original marker ids — layered',
        'Crossing the minLabelZoom boundary downwards and back up leaves the '
            'marker set exactly as it was.',
        doc: '''
## Crossing minLabelZoom in both directions

`MarkerVisibility.minLabelZoom` (2.0) is a hard gate: below it the builder takes
a different branch entirely and emits **no label markers at all**, whatever the
proximity maths says. This sweep runs **zoom 10 -> 1 -> 10**, crossing that
boundary downwards and then upwards again, and asserts the final `MarkerId`s
match the initial ones.

- **zoom 10** — POI dots plus the isolated marker's label.
- **zoom 1** — below the gate: three bare POI dots, no labels.
- **back to zoom 10** — the label must return.

The zoom-1 set is asserted to differ from the zoom-10 set, so the crossing
really happened.

## Why this direction matters separately

The 10 -> 18 -> 10 sweep exercises the proximity threshold; this one exercises
the zoom gate, which is a different branch in `buildVisibleMarkers`. A bug that
dropped labels permanently after zooming out past the gate would leave the map
label-less for the rest of the session and would be invisible to the
proximity-only test.
''', (t) => expectRoundTrip(t, [10, 1, 10])),
    t(
        roundTrip,
        'zoom 10 -> 1 -> 10 restores the original marker ids — original',
        'The boundary crossing in the mutually-exclusive mode, where dropping '
            'below minLabelZoom turns every label back into a POI dot.',
        doc: '''
## Crossing minLabelZoom in both directions (original mode)

The **zoom 10 -> 1 -> 10** sweep with `useOriginalMarkerBehavior: true`. Below
`minLabelZoom` this mode falls back to POI dots for *every* marker, so the
isolated marker that was showing as `c_label` at zoom 10 must become a plain `c`
dot at zoom 1 — and must turn back into `c_label` on the way up.

That round trip touches both halves of the id bookkeeping: `labelMarkerId` on
the way in and `uidFromLabelMarkerId` on the way out. If either drifted, the
final set would contain the wrong id and this test would fail.
''', (t) => expectRoundTrip(t, [10, 1, 10], useOriginal: true)),
  ];
}
