import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../main/map_fly_path.dart';
import 'unit_test.dart';

/// Unit coverage for [MapFlyPath], the curve the web map flies along when a
/// search narrows down to one person.
///
/// The web maps plugin turns `animateCamera` into a jump, so on web the app
/// moves the camera one frame at a time along this path. If the path is wrong,
/// the camera lands in the wrong place, goes the long way round the planet,
/// or comes out as NaN, which the map silently ignores. In every one of those
/// cases the user sees a snap or nothing at all rather than a flight.
List<UnitTest> mapFlyPathUnitTests() {
  UnitTest fly(String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'MapFlyPath',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  const LatLng sanFrancisco = LatLng(37.7749, -122.4194);
  const LatLng newYork = LatLng(40.7128, -74.0060);

  return <UnitTest>[
    fly(
      'starts and ends exactly on the requested cameras',
      'The flight begins where the camera is and lands exactly on the target.',
      '''
## What it checks
`at(0)` returns the start camera and `at(1)` returns the target camera
unchanged, and out-of-range `t` is clamped to those ends.

## Why it matters
The last frame of a web flight is `at(1)`. Any drift there and the person the
search found would end up off-centre, with the camera never quite settling.

## Expected
SF z10 → NYC z13.5: `at(0)` = SF z10, `at(1)` = NYC z13.5''',
      (t) {
        final path = MapFlyPath(
          from: sanFrancisco,
          fromZoom: 10,
          to: newYork,
          toZoom: 13.5,
        );
        final start = path.at(0);
        final end = path.at(1);
        t.expectEqual(start.target, sanFrancisco);
        t.expectClose(start.zoom, 10, 1e-9);
        t.expectEqual(end.target, newYork);
        t.expectClose(end.zoom, 13.5, 1e-9);
        t.expectEqual(path.at(-1).target, sanFrancisco);
        t.expectEqual(path.at(2).target, newYork);
      },
    ),
    fly(
      'zooms out to cross a long distance, then back in',
      'A cross-country hop pulls back mid-flight instead of smearing tiles.',
      '''
## What it checks
Flying SF → NYC at city zoom, the midpoint is far more zoomed out than either
end, and every sample moves the camera closer to New York than the one before.

## Why it matters
Panning 4,000 km at zoom 13.5 would scroll thousands of screens of tiles
past in about a second. The path is meant to rise, cross, and descend.

## Expected
midpoint zoom < 8, distance to NYC strictly decreasing''',
      (t) {
        final path = MapFlyPath(
          from: sanFrancisco,
          fromZoom: 13.5,
          to: newYork,
          toZoom: 13.5,
        );
        final mid = path.at(0.5);
        t.note('midpoint: ${mid.target} z${mid.zoom.toStringAsFixed(2)}');
        t.expectLessOrEqual(mid.zoom, 8, reason: 'expected a zoom-out');

        double previous = double.infinity;
        for (var i = 0; i <= 20; i++) {
          final target = path.at(i / 20).target;
          final double remaining =
              (target.latitude - newYork.latitude).abs() +
                  (target.longitude - newYork.longitude).abs();
          t.expectTrue(remaining < previous || remaining == 0,
              reason: 'sample $i moved away from the target');
          previous = remaining;
        }
      },
    ),
    fly(
      'glides across a short hop without zooming out',
      'A hop across town barely changes zoom and takes the minimum time.',
      '''
## What it checks
Two points a couple of kilometres apart at zoom 13 keep the zoom within half a
level all the way, and the flight lasts `MapFlyPath.minDuration`.

## Why it matters
A search that finds someone nearby should feel like a nudge. Zooming out and
back in for that would look like a glitch.

## Expected
every sample's zoom ≥ 12.5, duration = 600 ms''',
      (t) {
        final path = MapFlyPath(
          from: sanFrancisco,
          fromZoom: 13,
          to: const LatLng(37.7900, -122.4000),
          toZoom: 13,
          viewportPixels: 800,
        );
        for (var i = 0; i <= 10; i++) {
          t.expectTrue(path.at(i / 10).zoom >= 12.5,
              reason: 'sample $i zoomed out to ${path.at(i / 10).zoom}');
        }
        t.expectEqual(path.duration, MapFlyPath.minDuration);
      },
    ),
    fly(
      'takes the short way across the antimeridian',
      'Tokyo → Honolulu crosses the Pacific, not Europe and the Atlantic.',
      '''
## What it checks
Halfway from Tokyo (139.7°E) to Honolulu (157.9°W), the camera's longitude is
out over the Pacific (east of 150°E or west of 150°W).

## Why it matters
Naively interpolating longitude goes from +139 to −157 through 0, which is the
other way round the planet. The path unwraps longitude so the hop takes the
short way.

## Expected
`|midpoint longitude| > 150`''',
      (t) {
        final path = MapFlyPath(
          from: const LatLng(35.6762, 139.6503),
          fromZoom: 10,
          to: const LatLng(21.3069, -157.8583),
          toZoom: 10,
        );
        final mid = path.at(0.5).target;
        t.note('midpoint longitude: ${mid.longitude}');
        t.expectTrue(mid.longitude.abs() > 150,
            reason: 'went the long way round (lng ${mid.longitude})');
      },
    ),
    fly(
      'scales duration with distance, within its bounds',
      'Staying put is instant; a far hop is slower but capped.',
      '''
## What it checks
- Same spot, same zoom → `isEmpty` and a zero duration.
- A world-spanning hop at street zoom → `MapFlyPath.maxDuration`.
- SF → NYC at city zoom → strictly between the two bounds.

## Why it matters
The duration is what makes the flight readable. Too short and it reads as a
snap; uncapped, a round-the-world search would keep the user waiting.

## Expected
0 / 2400 ms / between 600 and 2400 ms''',
      (t) {
        final still = MapFlyPath(
          from: newYork,
          fromZoom: 12,
          to: newYork,
          toZoom: 12,
        );
        t.expectTrue(still.isEmpty);
        t.expectEqual(still.duration, Duration.zero);

        final far = MapFlyPath(
          from: sanFrancisco,
          fromZoom: 19,
          to: const LatLng(-33.8688, 151.2093),
          toZoom: 19,
        );
        t.expectEqual(far.duration, MapFlyPath.maxDuration);

        final crossCountry = MapFlyPath(
          from: sanFrancisco,
          fromZoom: 10,
          to: newYork,
          toZoom: 10,
        );
        t.note('SF → NYC: ${crossCountry.duration.inMilliseconds} ms');
        t.expectTrue(crossCountry.duration > MapFlyPath.minDuration);
        t.expectTrue(crossCountry.duration < MapFlyPath.maxDuration);
      },
    ),
    fly(
      'zooms in place when the target is already centred',
      'Same centre, different zoom: the camera only zooms.',
      '''
## What it checks
From NYC z5 to NYC z13.5, the centre never moves and the zoom climbs steadily
from 5 to 13.5.

## Why it matters
This is the special case of the curve, where there is no pan to share the work.
It has its own formula, so it gets its own check.

## Expected
target constant, zoom monotonic 5 → 13.5''',
      (t) {
        final path = MapFlyPath(
          from: newYork,
          fromZoom: 5,
          to: newYork,
          toZoom: 13.5,
        );
        double previous = 5;
        for (var i = 1; i <= 10; i++) {
          final camera = path.at(i / 10);
          t.expectClose(camera.target.latitude, newYork.latitude, 1e-6);
          t.expectClose(camera.target.longitude, newYork.longitude, 1e-6);
          t.expectTrue(camera.zoom >= previous,
              reason: 'zoom went backwards at sample $i');
          previous = camera.zoom;
        }
        t.expectClose(previous, 13.5, 1e-9);
      },
    ),
    fly(
      'stays finite at extreme zooms and distances',
      'No NaN or infinite camera, even from max zoom to the far side of the world.',
      '''
## What it checks
Sampling 100 points from London at z21 to Auckland at z21, every latitude,
longitude and zoom is finite.

## Why it matters
The map silently ignores a NaN camera, so the flight would freeze. A far hop
from a close zoom used to be the case where `log(sqrt(b² + 1) − b)` cancels
to `log(0)`.

## Expected
all 101 samples finite''',
      (t) {
        final path = MapFlyPath(
          from: const LatLng(51.5074, -0.1278),
          fromZoom: 21,
          to: const LatLng(-36.8485, 174.7633),
          toZoom: 21,
        );
        for (var i = 0; i <= 100; i++) {
          final camera = path.at(i / 100);
          t.expectTrue(
            camera.zoom.isFinite &&
                camera.target.latitude.isFinite &&
                camera.target.longitude.isFinite,
            reason: 'sample $i is not finite: $camera',
          );
        }
      },
    ),
  ];
}
