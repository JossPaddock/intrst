import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../main/map_camera_memory.dart';
import '../../main/map_zoom.dart';
import '../../main/marker_visibility.dart';
import '../../widgets/Preview.dart';
import '../e2e/qa_app_harness.dart';
import '../e2e/qa_seed.dart';
import '../qa_scenario.dart';

/// Live coverage of the **map's marker pipeline, driven through the real app**.
///
/// Everything else that tests marker selection does it at the
/// [MarkerVisibility] layer, where the inputs are hand-built sets. These
/// scenarios close the loop: they seed a real user, let the real app load it,
/// then drive the real search field, the real relationship filters and the real
/// `_onCameraMove`, and assert on the marker ids the app actually handed the
/// map ([QaAppHarness.visibleMarkerIds]).
///
/// **Why they go through the harness.** A `GoogleMap` is a platform view: its
/// markers are not in the element tree, so the live driver can neither see nor
/// tap them. The harness is the only honest way to read the map's state and to
/// deliver a marker tap — and every one of its methods delegates to the app's
/// own code path, so what is asserted is production behaviour.
///
/// Each scenario also carries a headless `body` that pins the same rule at the
/// pure-logic layer, so `flutter test` (the source of truth) still gates on it
/// with no app, no Firebase and no network.

const String _searchSuite = 'Live map — search';
const String _filterSuite = 'Live map — relationship filters';
const String _previewSuite = 'Live map — marker tap';
const String _cameraSuite = 'Live map — camera and zoom';

/// Where the seeded fixture user is placed: a point in the South Atlantic well
/// away from any real user, so its marker is isolated at every zoom and its
/// label is decided by the zoom gate rather than by a crowded neighbour.
const double _fixtureLat = -42.5;
const double _fixtureLng = -25.5;

/// A name distinctive enough that a live search for it matches the fixture and
/// (essentially) nothing else in the real user collection.
const String _fixtureFirstName = 'Qazephyr';
const String _fixtureLastName = 'Fixturemark';
const String _fixtureName = '$_fixtureFirstName $_fixtureLastName';
const String _fixtureUid = '${QaSeeder.prefix}mapfixture';

/// The zoom used by the live scenarios that need labels to be eligible: well
/// above [MarkerVisibility.minLabelZoom], and inside the map's own range.
const double _labelZoom = 12.0;

// ---------------------------------------------------------------------------
// Headless fixtures. Three markers: a crowded pair 110 m apart (`a`, `b`) and
// one isolated marker (`c`), so search/filter changes are visible in the ids.
// ---------------------------------------------------------------------------

Set<Marker> _poi() => {
      const Marker(markerId: MarkerId('a'), position: LatLng(0, 0)),
      const Marker(markerId: MarkerId('b'), position: LatLng(0, 0.001)),
      const Marker(markerId: MarkerId('c'), position: LatLng(20, 20)),
    };

/// The label marker for each POI marker, exactly as `loadMarkers` builds them:
/// a second marker for the same position under the `<uid>_label` id.
Set<Marker> _labelsFor(Set<Marker> poiMarkers) => poiMarkers
    .map((marker) => Marker(
          markerId:
              MarkerId(MarkerVisibility.labelMarkerId(marker.markerId.value)),
          position: marker.position,
        ))
    .toSet();

/// The marker ids `_onCameraMove` would hand the map for these inputs.
Set<String> _build({
  required double zoom,
  String searchTerm = '',
  List<String> searchFilteredResults = const <String>[],
  Set<String>? relationshipUids,
  Set<Marker>? poiMarkers,
}) {
  final Set<Marker> poi = poiMarkers ?? _poi();
  return MarkerVisibility.buildVisibleMarkers(
    poiMarkers: poi,
    labelMarkers: _labelsFor(poi),
    zoom: zoom,
    searchTerm: searchTerm,
    searchFilteredResults: searchFilteredResults,
    relationshipUids: relationshipUids,
  ).map((marker) => marker.markerId.value).toSet();
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// The uids behind [ids], collapsing `uid_label` back onto `uid`, so a check
/// can talk about *who* is on the map regardless of how they are drawn.
Set<String> _people(Iterable<String> ids) =>
    ids.map(MarkerVisibility.uidFromLabelMarkerId).toSet();

List<QaScenario> liveMapScenarios() {
  final search = _LiveSearchFixture();
  final filters = _LiveFilterFixture();
  final preview = _LiveLabelPreviewFixture();
  final camera = _LiveCameraFixture();
  final estimate = _LiveEstimatedPlacementFixture();

  return <QaScenario>[
    QaScenario(
      suite: _searchSuite,
      name: 'searching narrows the visible marker set on the real map',
      summary:
          'Typing a name into the real search box removes everyone who does '
          'not match from the map, leaving the person you searched for.',
      doc: '''
## What it checks
With a seeded user on the real map, typing their name into the **real** search
field leaves a marker set that is:

- **strictly smaller** than the unfiltered set,
- a **subset** of it (search never invents markers), and
- still **containing the person searched for**.

## Why it matters
Search is the map's main way of finding someone, and it is the one input that
feeds `buildVisibleMarkers` from a *live Firestore query* rather than from local
state. The pure-logic suites pin what the builder does with a result list; only
this one pins that the real autocomplete → search → `_onCameraMove` chain
actually reaches it.

## How it runs
- **Headless (`flutter test`):** the same rule against `buildVisibleMarkers`
  with a hand-built result list.
- **Live (dashboard ▶):** seeds `$_fixtureName` at a remote point, reloads the
  real markers, then writes into the app's own search controller — which is what
  a keystroke does — and reads back `QaAppHarness.visibleMarkerIds()`.

## Expected
`searched ⊂ unfiltered`, `searched.length < unfiltered.length`, and the fixture
uid is among the people still on the map.
''',
      body: (d) async {
        await d.check('search narrows the marker set to the match', () {
          final Set<String> unfiltered = _people(_build(zoom: 10));
          final Set<String> searched = _people(_build(
            zoom: 10,
            searchTerm: 'a',
            searchFilteredResults: const <String>['a'],
          ));
          return searched.length < unfiltered.length &&
              unfiltered.containsAll(searched) &&
              searched.contains('a');
        });
      },
      liveSetUp: search.setUp,
      liveBody: search.body,
      liveTearDown: search.cleanup,
    ),
    QaScenario(
      suite: _searchSuite,
      name: 'clearing the search restores the full marker set',
      summary:
          'Emptying the search box puts every marker back on the map — exactly '
          'the set that was there before the search.',
      doc: '''
## What it checks
Emptying the **real** search field restores *exactly* the marker set that was on
the map before the search — same ids, nothing dropped, nothing duplicated.

## Why it matters
This is the state users hit constantly: search, look, clear, search again. The
clear path is a separate branch of the production `optionsBuilder` (it resets
`searchTerm`, `searchFilteredResults` and `searchFilteredMarkers` and re-runs
`_onCameraMove`), and a stale result list surviving the clear would leave the map
permanently narrowed with an empty search box — a state the user cannot argue
with.

## How it runs
- **Headless:** builds with a search active, then with an empty term while the
  **previous result list is still in state**, and compares against the
  unfiltered set.
- **Live:** unfiltered → search → clear, comparing the first and last
  `visibleMarkerIds()`.

## Expected
`cleared == unfiltered` as a set, and the search really did narrow in between —
so the check cannot pass vacuously.
''',
      body: (d) async {
        await d.check('clearing the search restores every marker', () {
          final Set<String> unfiltered = _build(zoom: 10);
          final Set<String> searched = _build(
            zoom: 10,
            searchTerm: 'a',
            searchFilteredResults: const <String>['a'],
          );
          // Empty term, stale result list still in state — the clear path.
          final Set<String> cleared = _build(
            zoom: 10,
            searchTerm: '',
            searchFilteredResults: const <String>['a'],
          );
          return searched.length < unfiltered.length &&
              _sameSet(cleared, unfiltered);
        });
      },
      liveSetUp: search.setUp,
      liveBody: search.restoreBody,
      liveTearDown: search.cleanup,
    ),
    QaScenario(
      suite: _filterSuite,
      name: 'toggling the Friends filter updates the markers live and flips back',
      summary:
          'Turning on the Friends filter narrows the map to your friends, and '
          'turning it off puts everyone back.',
      doc: '''
## What it checks
Flipping the **Friends** relationship filter on the real map:

- narrows the marker set to the allow-set (friends plus your own marker), so a
  seeded non-friend disappears, and
- flipping it back off restores exactly the set that was there before.

## Why it matters
`_relationshipFilterUids()` is tri-state — `null` (no toggle: show everyone), a
populated allow-set, or an **empty** allow-set — and the filter chips are the
only thing that moves it between those states. The logic suites pin the three
states; this pins that the real chip handler (`_onMarkerFilterChanged`, which
re-reads the friend/follower/following uids and rebuilds the markers) moves
between them and back without stranding the map.

## How it runs
- **Headless:** allow-set `{a}` vs `null` against `buildVisibleMarkers`.
- **Live:** signs in (the filter is meaningless signed out), seeds a non-friend,
  then drives the app's own filter handler and reads `visibleMarkerIds()` at each
  step.

## Expected
Filtered set is a strict subset that excludes the seeded non-friend; unfiltered
set after flipping back equals the one before.
''',
      body: (d) async {
        await d.check('the relationship filter narrows and restores', () {
          final Set<String> everyone = _build(zoom: 10);
          final Set<String> friendsOnly =
              _build(zoom: 10, relationshipUids: <String>{'a'});
          final Set<String> flippedBack = _build(zoom: 10);
          return _people(friendsOnly).length < _people(everyone).length &&
              _people(everyone).containsAll(_people(friendsOnly)) &&
              !_people(friendsOnly).contains('c') &&
              _sameSet(flippedBack, everyone);
        });
      },
      liveSetUp: filters.setUp,
      liveBody: filters.body,
      liveTearDown: filters.cleanup,
    ),
    QaScenario(
      suite: _previewSuite,
      name: 'a label-rendered marker opens the Preview for the user behind it',
      summary:
          'Tapping someone whose name label is showing opens their Preview — '
          'the label id is resolved back to the user, not passed through.',
      doc: '''
## What it checks
When a marker is currently drawn as its **name label** (`<uid>_label`), tapping
it opens the real `Preview` **for that user**. The id that reaches the tap
handler is the label id; it has to be resolved through
`MarkerVisibility.uidFromLabelMarkerId` before it is used as a uid.

## Why it matters
The label and the dot are two markers for one person, with two different ids,
and above `minLabelZoom` the label is the one on top — so at any useful zoom the
label is what a user taps. Pass the raw `<uid>_label` through and the Preview
queries for a user that does not exist: a blank dialog, no name, no interests,
for the marker people tap the most. The existing Preview scenario only covers
the bare-uid path, so nothing else pins this.

## How it runs
- **Headless:** asserts that every label id in a real build resolves to a uid
  that actually has a POI marker — i.e. the resolution is what makes a label
  tappable — and that resolution is a no-op on a bare uid.
- **Live:** seeds `$_fixtureName` somewhere isolated, zooms to $_labelZoom (well
  above the gate) so their label is genuinely in `visibleMarkerIds()`, then hands
  that **label id** to the app's real marker-tap path and asserts their Preview
  opens with their name on it.

## Expected
`Preview` on screen showing **$_fixtureName** after tapping `<uid>_label`.
''',
      body: (d) async {
        await d.check('label ids resolve to the user behind them', () {
          final Set<String> ids = _build(zoom: 18);
          final Iterable<String> labelIds = ids.where(
              (id) => id.endsWith(MarkerVisibility.labelIdSuffix));
          if (labelIds.isEmpty) return false; // never pass vacuously
          final Set<String> poiUids =
              _poi().map((marker) => marker.markerId.value).toSet();
          final bool resolves = labelIds.every((id) =>
              poiUids.contains(MarkerVisibility.uidFromLabelMarkerId(id)));
          // Resolution must leave a bare uid alone: the dot path still works.
          final bool bareUidUntouched =
              MarkerVisibility.uidFromLabelMarkerId('a') == 'a';
          return resolves && bareUidUntouched;
        });
      },
      liveSetUp: preview.setUp,
      liveBody: preview.body,
      liveTearDown: preview.cleanup,
    ),
    QaScenario(
      suite: _cameraSuite,
      name: 'the restored camera zoom produces the same markers as zooming to it by hand',
      summary:
          'The zoom the map reopens at builds the same markers as pinching to '
          'that zoom yourself — the remembered camera is not a special case.',
      doc: '''
## What it checks
The zoom [`MapCameraMemory`](../../lib/main/map_camera_memory.dart) restores on
launch feeds `_onCameraMove` to exactly the same effect as the user pinching to
that zoom: the marker set at the restored zoom equals the marker set after
zooming out to the world view and back to it.

It also checks the restored zoom **survives a snapshot round-trip unchanged** —
`MapCameraSnapshot.create` clamps to `minZoom`..`maxZoom`, so a zoom that came
out of storage must already be inside the range it is about to be re-persisted
into.

## Why it matters
Camera restoration and marker selection are written as independent features:
`map_camera_memory.dart` decides *where* the map opens, `marker_visibility.dart`
decides *what is on it*. The only thing tying them together is the zoom value
handed across. If restoration produced a zoom the marker pipeline treats
differently — an unclamped value, a zoom below `minLabelZoom` — the user would
reopen the app to a map that looks nothing like the one they left, and no
existing test would notice.

## How it runs
- **Headless:** round-trips a snapshot through `encode`/`decode` and asserts the
  builder is order-independent at the restored zoom (same set via a detour).
- **Live:** reads the remembered zoom through the harness, applies it via the
  app's real `_onCameraMove`, records the ids, detours to the world view and
  back, and compares.

## Expected
Same marker ids both ways, a non-empty set, and `create(zoom).zoom == zoom`.
''',
      body: (d) async {
        await d.check('a restored zoom builds the same markers as a manual one',
            () {
          final MapCameraSnapshot? restored = MapCameraSnapshot.decode(
            MapCameraSnapshot.create(
              latitude: _fixtureLat,
              longitude: _fixtureLng,
              zoom: 12.0,
            )!.encode(),
          );
          if (restored == null) return false;
          // The restored zoom must already be inside the clamp range.
          if (MapCameraSnapshot.create(
                latitude: restored.latitude,
                longitude: restored.longitude,
                zoom: restored.zoom,
              )!.zoom !=
              restored.zoom) {
            return false;
          }
          final Set<String> onRestore = _build(zoom: restored.zoom);
          // Detour to the world view and back — what a manual zoom does.
          _build(zoom: MapCameraSnapshot.minZoom);
          final Set<String> manual = _build(zoom: restored.zoom);
          return onRestore.isNotEmpty && _sameSet(onRestore, manual);
        });
      },
      liveSetUp: camera.setUp,
      liveBody: camera.body,
      liveTearDown: camera.cleanup,
    ),
    QaScenario(
      suite: _cameraSuite,
      name: 'an IP-estimated placement lands at a zoom where its own marker is labelled',
      summary:
          'When we place you from your IP address, the map opens at a zoom '
          'where your own marker is named — not swallowed as an anonymous dot.',
      doc: '''
## What it checks
The zoom `MapZoom.forRadius` picks for an IP-estimated placement, fed into the
real marker pipeline, leaves the estimated marker **labelled**: both `<uid>` and
`<uid>_label` are on the map.

## Why it matters
IP placement is the fallback for someone who declined location sharing, and the
whole point of the widened zoom is that they can *see* the marker we chose for
them and drag it. `forRadius` is derived from the uncertainty radius and knows
nothing about `MarkerVisibility`: it could legitimately return a zoom below
`minLabelZoom`, where the builder emits no labels at all, and the user would
open the app to an unnamed dot they have to guess at. That is exactly the
crossover the two files never talk about, and this is the only check on it.

## How it runs
- **Headless:** `MapZoom.forRadius` for a typical city-level estimate, fed
  straight into `buildVisibleMarkers` for one isolated marker.
- **Live:** seeds the fixture at the estimate's coordinates, reloads the real
  markers, applies the computed zoom through the app's `_onCameraMove`, and
  reads `visibleMarkerIds()`.

## Expected
The computed zoom is at or above `minLabelZoom` (2.0), and the estimated
marker's uid **and** its label id are both in the marker set.
''',
      body: (d) async {
        await d.check('the estimated placement zoom labels its own marker', () {
          final double zoom = MapZoom.forRadius(
            radiusMeters: _estimateRadiusMeters,
            latitude: _fixtureLat,
            viewportPixels: _estimateViewportPixels,
          );
          if (zoom < MarkerVisibility.minLabelZoom) return false;
          final Set<Marker> poi = <Marker>{
            const Marker(
              markerId: MarkerId('estimated'),
              position: LatLng(_fixtureLat, _fixtureLng),
            ),
          };
          final Set<String> ids = _build(zoom: zoom, poiMarkers: poi);
          return ids.contains('estimated') &&
              ids.contains(MarkerVisibility.labelMarkerId('estimated'));
        });
      },
      liveSetUp: estimate.setUp,
      liveBody: estimate.body,
      liveTearDown: estimate.cleanup,
    ),
  ];
}

/// A typical city-level IP estimate, and the shorter screen edge the app
/// measures the radius against (`_ipEstimatedPlacement`).
const double _estimateRadiusMeters = 25000;
const double _estimateViewportPixels = 400;

/// Seeds one namespaced user onto the real map and takes it away again.
///
/// The live scenarios below all need the same thing: a user they own, far
/// enough from everyone else that proximity never decides their label, plus a
/// map that has actually loaded them. Cleanup clears the search first, because
/// the app's `loadMarkers` deliberately no-ops while a search is active.
class _SeededMapUser {
  final QaSeeder seeder = QaSeeder();

  Future<void> seedFixture(QaAppHarness harness) async {
    await seeder.seedUser(
      uid: _fixtureUid,
      firstName: _fixtureFirstName,
      lastName: _fixtureLastName,
      location: const GeoPoint(_fixtureLat, _fixtureLng),
    );
    await harness.goHome();
    await harness.reloadMarkers();
  }

  Future<void> cleanup(QaAppHarness harness) async {
    try {
      await harness.clearSearch();
    } catch (_) {
      // The search field may not be mounted; the seeded data still has to go.
    }
    await seeder.cleanup();
    try {
      await harness.reloadMarkers();
    } catch (_) {
      // Best-effort: the deleted user disappears on the next load regardless.
    }
  }
}

/// #15 and #16: the real search field narrowing, and restoring, the real map.
class _LiveSearchFixture extends _SeededMapUser {
  Future<void> setUp(QaAppHarness harness) => seedFixture(harness);

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    late Set<String> unfiltered;
    late Set<String> searched;

    await d.phase('the seeded user is on the unfiltered map', () async {
      await harness.applyMapZoom(_labelZoom);
      // Compared as *people*, not raw ids: narrowing the map also re-decides
      // which of the survivors are drawn as labels, so `a` can legitimately
      // become `a_label` on the way.
      unfiltered = _people(harness.visibleMarkerIds());
      await d.check('the map shows the seeded user before searching',
          () => unfiltered.contains(_fixtureUid));
    });

    await d.phase('search the real field for the seeded user', () async {
      await harness.enterSearch(_fixtureName);
      searched = _people(harness.visibleMarkerIds());
      await d.check('fewer people are on the map',
          () => searched.length < unfiltered.length);
      await d.check('everyone still shown was already on the map',
          () => unfiltered.containsAll(searched));
      await d.check('the searched-for user is still on the map',
          () => searched.contains(_fixtureUid));
    });
  }

  Future<void> restoreBody(QaDriver d, QaAppHarness harness) async {
    late Set<String> unfiltered;
    late Set<String> searched;

    await d.phase('record the unfiltered map', () async {
      await harness.applyMapZoom(_labelZoom);
      unfiltered = harness.visibleMarkerIds().toSet();
      await d.check('the unfiltered map is not empty', () => unfiltered.isNotEmpty);
    });

    await d.phase('search, then clear the real search field', () async {
      await harness.enterSearch(_fixtureName);
      searched = _people(harness.visibleMarkerIds());
      await d.check('the search really narrowed the map',
          () => searched.length < _people(unfiltered).length);

      await harness.clearSearch();
      final Set<String> cleared = harness.visibleMarkerIds().toSet();
      await d.check('clearing restored exactly the previous marker set',
          () => _sameSet(cleared, unfiltered));
    });
  }
}

/// #17: the Friends chip narrowing the real map, and flipping back.
class _LiveFilterFixture extends _SeededMapUser {
  Future<void> setUp(QaAppHarness harness) async {
    if (!harness.signedIn) {
      // Throws QaHarnessUnavailable (shown in the PiP) when no test account is
      // configured — the relationship filter has no meaning signed out.
      await harness.signInTestUser();
    }
    await seedFixture(harness);
  }

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    late Set<String> everyone;

    await d.phase('no filter: the map shows everyone', () async {
      await harness.setRelationshipFilters(
          friends: false, followers: false, following: false);
      await harness.applyMapZoom(_labelZoom);
      everyone = harness.visibleMarkerIds().toSet();
      await d.check('the seeded non-friend is on the unfiltered map',
          () => _people(everyone).contains(_fixtureUid));
    });

    await d.phase('turn the Friends filter on', () async {
      await harness.setRelationshipFilters(friends: true);
      final Set<String> friendsOnly = harness.visibleMarkerIds().toSet();
      await d.check('the marker set changed',
          () => !_sameSet(friendsOnly, everyone));
      // As people, since filtering re-decides who gets a label.
      await d.check('everyone still shown was already on the map',
          () => _people(everyone).containsAll(_people(friendsOnly)));
      await d.check('the seeded non-friend is gone',
          () => !_people(friendsOnly).contains(_fixtureUid));
    });

    await d.phase('turn it back off', () async {
      await harness.setRelationshipFilters(friends: false);
      final Set<String> restored = harness.visibleMarkerIds().toSet();
      await d.check('the full marker set came back',
          () => _sameSet(restored, everyone));
    });
  }

  @override
  Future<void> cleanup(QaAppHarness harness) async {
    try {
      await harness.setRelationshipFilters(
          friends: false, followers: false, following: false);
    } catch (_) {
      // Leave no filter on for the next scenario; failing here must not strand
      // the seeded data.
    }
    await super.cleanup(harness);
  }
}

/// #18: tapping a marker that is currently drawn as its name label.
class _LiveLabelPreviewFixture extends _SeededMapUser {
  Future<void> setUp(QaAppHarness harness) => seedFixture(harness);

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    late String labelId;

    await d.phase('zoom until the seeded marker is label-rendered', () async {
      await harness.applyMapZoom(_labelZoom);
      labelId = MarkerVisibility.labelMarkerId(_fixtureUid);
      await d.check('the marker is currently drawn as a label',
          () => harness.visibleMarkerIds().contains(labelId));
    });

    await d.phase('tap the label marker', () async {
      await d.expectAbsent(qaType(Preview));
      // The platform-view marker can't be tapped, so hand the app the very id
      // it put on the map — the label id, not the bare uid.
      await harness.openPreviewForMarkerId(labelId, _fixtureName);
      await d.expectVisible(qaType(Preview), count: 1);
      await d.expectVisible(qaText(_fixtureName));
    });
  }
}

/// #19: the remembered camera zoom vs. a manual zoom to the same value.
class _LiveCameraFixture extends _SeededMapUser {
  Future<void> setUp(QaAppHarness harness) => seedFixture(harness);

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    late double restoredZoom;
    late Set<String> onRestore;

    await d.phase('apply the zoom the app restores on launch', () async {
      final double? remembered = await harness.rememberedCameraZoom();
      restoredZoom = remembered ?? harness.initialMapZoom;
      await d.check('the restored zoom survives a snapshot round-trip', () {
        final MapCameraSnapshot? snapshot = MapCameraSnapshot.create(
          latitude: _fixtureLat,
          longitude: _fixtureLng,
          zoom: restoredZoom,
        );
        return snapshot != null && snapshot.zoom == restoredZoom;
      });

      await harness.applyMapZoom(restoredZoom);
      onRestore = harness.visibleMarkerIds().toSet();
      await d.check('the restored zoom produces markers',
          () => onRestore.isNotEmpty);
    });

    await d.phase('zoom away and back by hand', () async {
      await harness.applyMapZoom(MapCameraSnapshot.minZoom);
      await harness.applyMapZoom(restoredZoom);
      final Set<String> manual = harness.visibleMarkerIds().toSet();
      await d.check('the manual zoom builds the same marker set',
          () => _sameSet(manual, onRestore));
    });
  }
}

/// #20: the zoom an IP estimate picks, against the marker it placed.
class _LiveEstimatedPlacementFixture extends _SeededMapUser {
  Future<void> setUp(QaAppHarness harness) => seedFixture(harness);

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    // The same call `_ipEstimatedPlacement` makes, for a city-level estimate at
    // the fixture's latitude.
    final double zoom = MapZoom.forRadius(
      radiusMeters: _estimateRadiusMeters,
      latitude: _fixtureLat,
      viewportPixels: _estimateViewportPixels,
    );

    await d.phase('the estimated zoom is above the label gate', () async {
      await d.check('zoom $zoom >= MarkerVisibility.minLabelZoom',
          () => zoom >= MarkerVisibility.minLabelZoom);
    });

    await d.phase('the estimated marker is labelled at that zoom', () async {
      await harness.applyMapZoom(zoom);
      final List<String> ids = harness.visibleMarkerIds();
      await d.check('the estimated marker is on the map',
          () => ids.contains(_fixtureUid));
      await d.check('and it is drawn with its name label',
          () => ids.contains(MarkerVisibility.labelMarkerId(_fixtureUid)));
    });
  }
}
