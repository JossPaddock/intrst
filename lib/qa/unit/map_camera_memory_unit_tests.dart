import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../main/map_camera_memory.dart';
import 'unit_test.dart';

/// Unit coverage for [MapCameraSnapshot] — the value the map's "remember where
/// I was" behaviour is built on: validation of coordinates, the JSON round
/// trip, tolerance of corrupt stored preferences, zoom clamping, and the
/// "same view" comparison that keeps camera-idle events from turning into a
/// stream of writes.
///
/// These matter because the snapshot decides the map's `initialCameraPosition`
/// on every launch. A snapshot that decodes bad data into a real position would
/// open the map somewhere the user has never been; one that rejects good data
/// would silently drop the memory and replay the old world-view-then-fly-in.
List<UnitTest> mapCameraMemoryUnitTests() {
  UnitTest camera(String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'MapCameraSnapshot',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  return <UnitTest>[
    camera(
      'round-trips a camera through encode/decode',
      'A remembered camera survives being written to and read back from storage.',
      '''
## What it checks
`encode()` followed by `decode(...)` returns the same latitude, longitude and
zoom.

## Why it matters
This is the entire "remember where I was" path: the camera is encoded on
`onCameraIdle` and decoded at launch to become `initialCameraPosition`. If the
round trip lost precision or fields, the map would reopen somewhere other than
where the user left it.

## Expected
`(47.6062, -122.3321, z 13.5)` → same values back''',
      (t) {
        const original = MapCameraSnapshot(
          latitude: 47.6062,
          longitude: -122.3321,
          zoom: 13.5,
        );
        final restored = MapCameraSnapshot.decode(original.encode());
        t.expectTrue(restored != null, reason: 'decode returned null');
        t.expectClose(restored!.latitude, 47.6062, 1e-9);
        t.expectClose(restored.longitude, -122.3321, 1e-9);
        t.expectClose(restored.zoom, 13.5, 1e-9);
      },
    ),
    camera(
      'decodes null, empty and malformed strings to null',
      'A missing or corrupt preference yields no snapshot instead of throwing.',
      '''
## What it checks
`decode(null)`, `decode('')`, non-JSON text, and JSON that is not an object all
return `null`.

## Why it matters
The stored value comes from device preferences, which can be absent (fresh
install), truncated, or left over from an older format. Any of those must fall
through to the app's default starting position — never crash the map's
bootstrap, which runs before the first frame of the map is drawn.

## Expected
every malformed input → `null`''',
      (t) {
        t.expectTrue(MapCameraSnapshot.decode(null) == null);
        t.expectTrue(MapCameraSnapshot.decode('') == null);
        t.expectTrue(MapCameraSnapshot.decode('not json at all') == null);
        t.expectTrue(MapCameraSnapshot.decode('[1,2,3]') == null);
        t.expectTrue(MapCameraSnapshot.decode('{"lat":1}') == null,
            reason: 'a partial object must not decode');
      },
    ),
    camera(
      'rejects out-of-range and non-finite coordinates',
      'Impossible coordinates never become a camera position.',
      '''
## What it checks
`create(...)` returns `null` for a latitude outside ±90, a longitude outside
±180, and for NaN / infinite values.

## Why it matters
A stored value that is numerically valid JSON but geographically impossible
would be handed straight to `CameraPosition`. Rejecting it here means the map
falls back to a sane default rather than opening on a broken camera.

## Expected
lat 91, lng 181, NaN, infinity → `null`''',
      (t) {
        t.expectTrue(
            MapCameraSnapshot.create(latitude: 91, longitude: 0, zoom: 10) ==
                null);
        t.expectTrue(
            MapCameraSnapshot.create(latitude: -91, longitude: 0, zoom: 10) ==
                null);
        t.expectTrue(
            MapCameraSnapshot.create(latitude: 0, longitude: 181, zoom: 10) ==
                null);
        t.expectTrue(
            MapCameraSnapshot.create(latitude: 0, longitude: -181, zoom: 10) ==
                null);
        t.expectTrue(MapCameraSnapshot.create(
                latitude: double.nan, longitude: 0, zoom: 10) ==
            null);
        t.expectTrue(MapCameraSnapshot.create(
                latitude: 0, longitude: 0, zoom: double.infinity) ==
            null);
      },
    ),
    camera(
      'accepts the coordinate extremes',
      'The poles and the antimeridian are valid, not off-by-one rejections.',
      '''
## What it checks
±90 latitude and ±180 longitude produce a snapshot.

## Why it matters
The range check is inclusive; treating the boundary as invalid would drop
legitimate positions near the poles or the date line.

## Expected
(90, 180) and (-90, -180) → snapshots''',
      (t) {
        t.expectTrue(
            MapCameraSnapshot.create(latitude: 90, longitude: 180, zoom: 10) !=
                null);
        t.expectTrue(MapCameraSnapshot.create(
                latitude: -90, longitude: -180, zoom: 10) !=
            null);
      },
    ),
    camera(
      'clamps zoom into the map\'s supported range',
      'A stored zoom outside the map limits is clamped, not discarded.',
      '''
## What it checks
A zoom below `minZoom` or above `maxZoom` is clamped into range while the
location is kept.

## Why it matters
The map declares `MinMaxZoomPreference(3, 900)`. A zoom outside it (from an
older build, or a different device) still carries a perfectly good location —
clamping preserves the place the user was looking at instead of throwing the
whole memory away.

## Expected
zoom 0 → 3 · zoom 5000 → 900 · latitude/longitude untouched''',
      (t) {
        final low =
            MapCameraSnapshot.create(latitude: 10, longitude: 20, zoom: 0);
        t.expectTrue(low != null);
        t.expectClose(low!.zoom, MapCameraSnapshot.minZoom, 1e-9);
        t.expectClose(low.latitude, 10, 1e-9);

        final high =
            MapCameraSnapshot.create(latitude: 10, longitude: 20, zoom: 5000);
        t.expectTrue(high != null);
        t.expectClose(high!.zoom, MapCameraSnapshot.maxZoom, 1e-9);
      },
    ),
    camera(
      'converts to and from a CameraPosition',
      'The snapshot and the map\'s own camera type describe the same view.',
      '''
## What it checks
`fromCameraPosition` then `toCameraPosition` preserves target and zoom.

## Why it matters
These two conversions are the seam between the map widget and the memory: the
map reports a `CameraPosition` on move, and hands one back as
`initialCameraPosition` at launch.

## Expected
`CameraPosition(51.5074, -0.1278, z 11)` → same values back''',
      (t) {
        const position = CameraPosition(
          target: LatLng(51.5074, -0.1278),
          zoom: 11,
        );
        final snapshot = MapCameraSnapshot.fromCameraPosition(position);
        t.expectTrue(snapshot != null);
        final restored = snapshot!.toCameraPosition();
        t.expectClose(restored.target.latitude, 51.5074, 1e-9);
        t.expectClose(restored.target.longitude, -0.1278, 1e-9);
        t.expectClose(restored.zoom, 11, 1e-9);
      },
    ),
    camera(
      'treats a sub-metre nudge as the same view',
      'Tiny camera drift does not trigger a redundant write.',
      '''
## What it checks
`isSameViewAs` is true for a position that differs by less than ~1e-5 degrees
and less than 0.01 zoom, and false once either exceeds that.

## Why it matters
`onCameraIdle` fires after every gesture, including ones that barely move the
map. Without this comparison each idle event would write to preferences.
Comparing against `null` must also be false, so the very first camera of a
session is always persisted.

## Expected
+0.000001° → same · +0.001° → different · +0.5 zoom → different · null →
different''',
      (t) {
        const base =
            MapCameraSnapshot(latitude: 40.0, longitude: -74.0, zoom: 12.0);

        t.expectTrue(base.isSameViewAs(const MapCameraSnapshot(
          latitude: 40.000001,
          longitude: -74.000001,
          zoom: 12.001,
        )));
        t.expectFalse(base.isSameViewAs(const MapCameraSnapshot(
          latitude: 40.001,
          longitude: -74.0,
          zoom: 12.0,
        )));
        t.expectFalse(base.isSameViewAs(const MapCameraSnapshot(
          latitude: 40.0,
          longitude: -74.0,
          zoom: 12.5,
        )));
        t.expectFalse(base.isSameViewAs(null),
            reason: 'no stored camera must always count as a change');
      },
    ),
    camera(
      'decodes numeric strings and integers',
      'Values stored as ints or strings still restore the camera.',
      '''
## What it checks
`fromJson` accepts `int` and numeric `String` values for lat/lng/zoom, and
rejects non-numeric strings.

## Why it matters
JSON round-trips can turn `12.0` into `12`, and older or hand-edited
preferences may hold strings. Being lenient about the representation — while
still strict about the value — keeps a real camera memory from being thrown
away over a type detail.

## Expected
`{lat: 1, lng: 2, zoom: "9.5"}` → snapshot · `{lat: "north", ...}` → null''',
      (t) {
        final fromMixed = MapCameraSnapshot.fromJson(
            <String, Object?>{'lat': 1, 'lng': 2, 'zoom': '9.5'});
        t.expectTrue(fromMixed != null);
        t.expectClose(fromMixed!.latitude, 1, 1e-9);
        t.expectClose(fromMixed.zoom, 9.5, 1e-9);

        t.expectTrue(
            MapCameraSnapshot.fromJson(<String, Object?>{
                  'lat': 'north',
                  'lng': 2,
                  'zoom': 9.5,
                }) ==
                null);
      },
    ),
  ];
}
