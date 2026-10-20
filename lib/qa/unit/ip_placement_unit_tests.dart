import 'dart:math' as math;

import '../../main/map_zoom.dart';
import '../../utility/IpLocationLookup.dart';
import 'unit_test.dart';

/// Unit coverage for the **decline-to-share** placement path: parsing a free
/// IP-geolocation provider's response ([IpLocationLookup.parseResponse]) and
/// turning its uncertainty into a camera zoom ([MapZoom.forRadius]).
///
/// Both are pure, and both sit on a path the user cannot retry easily — a new
/// sign-up who declines location sharing gets placed once, from whatever these
/// two return. A parser that accepted a provider's error body would drop the
/// user's marker at a garbage coordinate; a zoom that came out too tight would
/// hide their real surroundings behind the estimate.
List<UnitTest> ipPlacementUnitTests() {
  UnitTest parsing(String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'IpLocationLookup.parseResponse',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  UnitTest zooming(String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'MapZoom.forRadius',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  return <UnitTest>[
    parsing(
      'reads the ipwho.is response shape',
      'A successful ipwho.is body yields the estimate.',
      '''
## What it checks
`{"success": true, "latitude": .., "longitude": .., "city": ".."}` parses into
an `IpLocationEstimate` with the default accuracy radius.

## Why it matters
This is the first provider tried when a user declines to share location. If it
did not parse, every declining user would fall through to the second provider
and, failing that, to a random world coordinate.

## Expected
Seattle body → 47.6062, -122.3321, city "Seattle"''',
      (t) {
        final estimate = IpLocationLookup.parseResponse(
          '{"success":true,"latitude":47.6062,"longitude":-122.3321,'
          '"city":"Seattle"}',
          source: 'ipwho.is',
        );
        t.expectTrue(estimate != null, reason: 'expected an estimate');
        t.expectClose(estimate!.latitude, 47.6062, 1e-9);
        t.expectClose(estimate.longitude, -122.3321, 1e-9);
        t.expectEqual(estimate.city, 'Seattle');
        t.expectClose(estimate.accuracyRadiusMeters,
            IpLocationLookup.defaultAccuracyRadiusMeters, 1e-9);
      },
    ),
    parsing(
      'reads the ipapi.co response shape',
      'A successful ipapi.co body yields the estimate through the same parser.',
      '''
## What it checks
An ipapi.co body — no `success` field, coordinates at the top level — parses
identically to the ipwho.is one.

## Why it matters
The two providers are a fallback chain, so one parser serves both. This test is
what keeps that consolidation honest: if the shapes ever diverge, this fails
rather than the fallback silently never working.

## Expected
`{"latitude": 51.5074, "longitude": -0.1278, "city": "London"}` → estimate''',
      (t) {
        final estimate = IpLocationLookup.parseResponse(
          '{"latitude":51.5074,"longitude":-0.1278,"city":"London"}',
          source: 'ipapi.co',
        );
        t.expectTrue(estimate != null);
        t.expectClose(estimate!.latitude, 51.5074, 1e-9);
        t.expectEqual(estimate.city, 'London');
      },
    ),
    parsing(
      'rejects provider error bodies',
      'A rate-limit or failure response never becomes a location.',
      '''
## What it checks
`{"success": false, ...}` (ipwho.is) and `{"error": true, ...}` (ipapi.co) both
return `null`, as does an `error` object.

## Why it matters
These endpoints return HTTP 200 with an error payload when they rate-limit.
Both providers ship coordinates of `0` in that payload, so a parser that only
looked at latitude/longitude would place the user in the Gulf of Guinea and
call it a success — skipping the fallback provider entirely.

## Expected
every error body → `null`''',
      (t) {
        t.expectTrue(IpLocationLookup.parseResponse(
                '{"success":false,"message":"rate limited"}') ==
            null);
        t.expectTrue(IpLocationLookup.parseResponse(
                '{"error":true,"reason":"RateLimited"}') ==
            null);
        t.expectTrue(IpLocationLookup.parseResponse(
                '{"error":{"code":104},"latitude":1,"longitude":2}') ==
            null);
      },
    ),
    parsing(
      'rejects null island, out-of-range and malformed bodies',
      'Unusable coordinates fall through to the next provider.',
      '''
## What it checks
`0, 0`, coordinates outside ±90/±180, missing fields, non-JSON text and a JSON
array all return `null`.

## Why it matters
Providers return `0, 0` for reserved and unroutable addresses — a real answer
shaped like a valid coordinate. Treating it as a location would place the
marker in the ocean. The rest guard against a truncated or unexpected body.

## Expected
`{lat: 0, lng: 0}`, `{lat: 91, ...}`, `{}`, `not json`, `[]` → `null`''',
      (t) {
        t.expectTrue(
            IpLocationLookup.parseResponse('{"latitude":0,"longitude":0}') ==
                null);
        t.expectTrue(
            IpLocationLookup.parseResponse('{"latitude":91,"longitude":0}') ==
                null);
        t.expectTrue(
            IpLocationLookup.parseResponse('{"latitude":0,"longitude":181}') ==
                null);
        t.expectTrue(IpLocationLookup.parseResponse('{}') == null);
        t.expectTrue(IpLocationLookup.parseResponse('not json') == null);
        t.expectTrue(IpLocationLookup.parseResponse('[]') == null);
      },
    ),
    parsing(
      'accepts coordinates sent as strings',
      'A provider quoting its numbers still yields an estimate.',
      '''
## What it checks
`{"latitude": "40.7128", "longitude": "-74.0060"}` parses, while
`{"latitude": "unknown"}` does not.

## Why it matters
These are third-party JSON APIs we do not control; some quote numeric fields.
Being lenient about the representation while staying strict about the value
means a formatting choice on their side does not cost a user their placement.

## Expected
quoted numbers → estimate · non-numeric string → `null`''',
      (t) {
        final estimate = IpLocationLookup.parseResponse(
            '{"latitude":"40.7128","longitude":"-74.0060"}');
        t.expectTrue(estimate != null);
        t.expectClose(estimate!.latitude, 40.7128, 1e-9);

        t.expectTrue(IpLocationLookup.parseResponse(
                '{"latitude":"unknown","longitude":"-74.0"}') ==
            null);
      },
    ),
    zooming(
      'fits the uncertainty radius on screen',
      'The chosen zoom keeps the whole accuracy circle inside the viewport.',
      '''
## What it checks
For the returned zoom, the ground distance covered by half the viewport is at
least the accuracy radius.

## Why it matters
This is the actual requirement for a declined placement: the marker we guessed
and the place the user really is must both be visible, so they can drag the
marker a short way instead of hunting for it. The assertion re-derives ground
resolution from the zoom (`156543.03392 * cos(lat) / 2^zoom`) rather than
trusting the function's own arithmetic.

## Expected
50 km radius at latitude 47 on a 400 px screen → half-viewport span ≥ 50 km''',
      (t) {
        const double radius = 50000;
        const double latitude = 47.0;
        const double viewport = 400;

        final double zoom = MapZoom.forRadius(
          radiusMeters: radius,
          latitude: latitude,
          viewportPixels: viewport,
        );

        // Ground resolution at this zoom, metres per pixel.
        final double cosLat = math.cos(latitude * math.pi / 180.0);
        final double metersPerPixel = MapZoom.metersPerPixelAtZoomZero *
            cosLat /
            math.pow(2, zoom).toDouble();
        final double halfViewportMeters = (viewport / 2) * metersPerPixel;

        t.note('zoom $zoom covers ${(halfViewportMeters / 1000).round()}km '
            'across half the viewport');
        t.expectTrue(halfViewportMeters >= radius,
            reason: 'half the viewport ($halfViewportMeters m) must cover the '
                'accuracy radius ($radius m)');
      },
    ),
    zooming(
      'zooms out further for a larger radius',
      'A vaguer estimate produces a wider view, never a tighter one.',
      '''
## What it checks
Zoom decreases monotonically as the radius grows: 10 km ≥ 50 km ≥ 200 km.

## Why it matters
The direction of the relationship is the part that is easy to invert in the
arithmetic, and inverting it would be worst exactly when the estimate is
weakest — zooming *in* on a position we are least sure about.

## Expected
zoom(10 km) ≥ zoom(50 km) ≥ zoom(200 km)''',
      (t) {
        double zoomFor(double radius) => MapZoom.forRadius(
              radiusMeters: radius,
              latitude: 40,
              viewportPixels: 400,
            );

        final tight = zoomFor(10000);
        final medium = zoomFor(50000);
        final wide = zoomFor(200000);
        t.note('10km -> $tight, 50km -> $medium, 200km -> $wide');
        t.expectTrue(tight >= medium);
        t.expectTrue(medium >= wide);
        t.expectTrue(tight > wide, reason: 'the range must actually differ');
      },
    ),
    zooming(
      'zooms out nearer the poles for the same radius',
      'Mercator distortion is accounted for, so a high-latitude view is wider.',
      '''
## What it checks
The same radius at latitude 65 yields a zoom no greater than at latitude 0.

## Why it matters
In Web Mercator a pixel covers less ground as latitude rises
(`cos(latitude)`). Ignoring that term would under-zoom northern users and crop
the uncertainty circle they were meant to see.

## Expected
zoom(lat 65) ≤ zoom(lat 0)''',
      (t) {
        final equator = MapZoom.forRadius(
            radiusMeters: 50000, latitude: 0, viewportPixels: 400);
        final north = MapZoom.forRadius(
            radiusMeters: 50000, latitude: 65, viewportPixels: 400);
        t.note('equator -> $equator, lat 65 -> $north');
        t.expectTrue(north <= equator);
      },
    ),
    zooming(
      'stays within the map\'s zoom limits',
      'A tiny or absurd radius still produces a usable zoom.',
      '''
## What it checks
A very small radius clamps to `maxEstimatedZoom`, a planet-sized one clamps to
`minZoom`, and non-finite or non-positive inputs return a valid zoom instead of
throwing.

## Why it matters
This value goes straight into the map's `initialCameraPosition` during
start-up. A NaN or an out-of-range zoom there would break the map on the one
launch the user cannot skip. `maxEstimatedZoom` also caps how far in we imply
we can see: an IP estimate never justifies a street-level view, however small
the provider's claimed radius.

## Expected
1 m → `maxEstimatedZoom` · 20 000 km → `minZoom` · NaN/0/negative → in range''',
      (t) {
        final tiny = MapZoom.forRadius(
            radiusMeters: 1, latitude: 40, viewportPixels: 400);
        t.expectClose(tiny, MapZoom.maxEstimatedZoom, 1e-9);

        final huge = MapZoom.forRadius(
            radiusMeters: 20000000, latitude: 40, viewportPixels: 400);
        t.expectClose(huge, MapZoom.minZoom, 1e-9);

        for (final double bad in <double>[0, -5, double.nan, double.infinity]) {
          final z = MapZoom.forRadius(
              radiusMeters: bad, latitude: 40, viewportPixels: 400);
          t.expectTrue(z.isFinite, reason: 'radius $bad gave a non-finite zoom');
          t.expectTrue(z >= MapZoom.minZoom && z <= MapZoom.maxEstimatedZoom,
              reason: 'radius $bad gave out-of-range zoom $z');
        }

        final noViewport = MapZoom.forRadius(
            radiusMeters: 50000, latitude: 40, viewportPixels: 0);
        t.expectClose(noViewport, MapZoom.minZoom, 1e-9);
      },
    ),
  ];
}
