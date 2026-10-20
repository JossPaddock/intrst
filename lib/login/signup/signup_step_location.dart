import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intrst/login/signup/signup_location_service.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/login/signup/signup_wizard_theme.dart';
import 'package:intrst/main/map_style.dart';

/// Part three of the wizard: where the user's marker goes.
///
/// Placement is **IP-based only** — the map opens on a city-level estimate and
/// the user drags the pin from there. No OS location permission is requested
/// here: the prompt was the slowest, least reliable part of the flow, and the
/// pin has to be dragged to a sharing-appropriate spot anyway. The app still
/// asks for precise location later, on the real map, for users who want it.
///
/// Either way a position is resolved *before* the account is created, so the
/// marker exists the moment they reach the map screen.
class SignupStepLocation extends StatefulWidget {
  const SignupStepLocation({
    super.key,
    required this.onFinish,
    required this.onBack,
    this.initial,
    this.locationService,
    this.submitting = false,
  });

  final ValueChanged<SignupLocationDraft> onFinish;
  final VoidCallback onBack;
  final SignupLocationDraft? initial;

  /// Injectable so tests can drive the step without touching the OS or the
  /// network.
  final SignupLocationService? locationService;

  /// True while the account is being created — locks the controls so the user
  /// can't submit twice or navigate away mid-write.
  final bool submitting;

  @override
  State<SignupStepLocation> createState() => _SignupStepLocationState();
}

class _SignupStepLocationState extends State<SignupStepLocation> {
  late final SignupLocationService _service =
      widget.locationService ?? SignupLocationService();

  SignupLocationDraft? _draft;
  bool _resolving = true;
  bool _seedStarted = false;
  GoogleMapController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeding reads MediaQuery for the viewport size, which is illegal in
    // initState — doing it there threw before the first await, leaving the
    // "finding your area" spinner up forever. didChangeDependencies is the
    // earliest point an inherited widget may be read; the flag keeps it to one
    // lookup despite this being called again on every dependency change.
    if (_seedStarted) return;
    _seedStarted = true;
    _seedInitialPosition();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Picks the position the map opens at. A draft carried back from a previous
  /// visit to this part wins, so stepping backwards and forwards doesn't throw
  /// away a pin the user already placed.
  ///
  /// This must always finish. Every failure — no network, a provider that hangs,
  /// an unexpected throw — resolves to [SignupLocationService.randomFallback]
  /// so the user gets a draggable pin instead of an endless spinner.
  Future<void> _seedInitialPosition({bool retry = false}) async {
    if (widget.initial != null && !retry) {
      setState(() {
        _draft = widget.initial;
        _resolving = false;
      });
      return;
    }

    if (retry) setState(() => _resolving = true);

    final double viewport = MediaQuery.of(context).size.shortestSide;
    SignupLocationDraft resolved;
    try {
      resolved = await _service.estimateFromIp(viewportPixels: viewport) ??
          _service.randomFallback();
    } catch (e) {
      print('Signup location seeding failed: $e');
      resolved = _service.randomFallback();
    }

    if (!mounted) return;
    setState(() {
      _draft = resolved;
      _resolving = false;
    });
    if (retry) await _moveCameraTo(resolved);
  }

  Future<void> _moveCameraTo(SignupLocationDraft draft) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(SignupLocationService.cameraFor(draft)),
    );
  }

  void _movePin(LatLng target) {
    final current = _draft;
    if (current == null) return;
    setState(() {
      _draft = current.copyWith(
        latitude: target.latitude,
        longitude: target.longitude,
        source: SignupLocationSource.manual,
      );
    });
  }

  Future<void> _expandMap() async {
    final SignupLocationDraft? current = _draft;
    if (current == null) return;
    final SignupLocationDraft? updated =
        await Navigator.of(context).push<SignupLocationDraft>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenMarkerMap(initial: current),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _draft = updated);
    await _moveCameraTo(updated);
  }

  String get _statusText {
    switch (_draft?.source) {
      case SignupLocationSource.ipEstimate:
        return 'We estimated your area from your connection. Drag the pin to '
            'where you would like your marker to sit.';
      case SignupLocationSource.manual:
        return "Your marker will sit exactly here. Drag it again if you'd like "
            'to move it.';
      case SignupLocationSource.fallback:
      case null:
        return "We couldn't guess your area. Drag the pin to where you would "
            'like your marker to sit.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final SignupLocationDraft? draft = _draft;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Text('Where are you?', style: SignupWizardTheme.title),
        const SizedBox(height: 8),
        const Text(
          'Your marker is how people find you on the map. It never has to be '
          'your exact address — drag the pin wherever you are happy to be '
          'found.',
          style: SignupWizardTheme.body,
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: Stack(
              children: [
                if (_resolving || draft == null)
                  Container(
                    color: SignupWizardTheme.surface,
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: SignupWizardTheme.accent),
                        SizedBox(height: 12),
                        Text('Finding your area…',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  )
                else
                  GoogleMap(
                    initialCameraPosition:
                        SignupLocationService.cameraFor(draft),
                    // The same cloud style and zoom bounds as the app's main
                    // map, so the pin is placed on the map the user is about
                    // to be handed.
                    cloudMapId: IntrstMapStyle.cloudMapId,
                    minMaxZoomPreference: IntrstMapStyle.zoomRange,
                    markers: {_pinFor(draft, onDragEnd: _movePin)},
                    onTap: _movePin,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: true,
                    onMapCreated: (controller) => _controller = controller,
                    onCameraMove: (position) {
                      // Remember the zoom the user settled on so the app opens
                      // the real map at the same scale they chose here.
                      final current = _draft;
                      if (current != null) {
                        _draft = current.copyWith(zoom: position.zoom);
                      }
                    },
                  ),
                if (draft != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _MapIconButton(
                      icon: Icons.open_in_full,
                      tooltip: 'Expand map',
                      onPressed: widget.submitting ? null : _expandMap,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(_statusText, style: SignupWizardTheme.body),
        // Offered only when the estimate failed outright: the pin is then
        // somewhere arbitrary, and a second attempt is worth having before the
        // user resorts to dragging across the whole world.
        if (draft?.source == SignupLocationSource.fallback && !_resolving)
          TextButton.icon(
            onPressed: widget.submitting
                ? null
                : () => _seedInitialPosition(retry: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try finding my area again'),
            style: TextButton.styleFrom(
                foregroundColor: SignupWizardTheme.accent),
          ),
        const SizedBox(height: 24),
        ElevatedButton(
          key: const Key('signup_location_finish'),
          style: SignupWizardTheme.primaryButton,
          onPressed: draft == null || widget.submitting
              ? null
              : () => widget.onFinish(draft),
          child: widget.submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: SignupWizardTheme.background),
                )
              : const Text('Create my account'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: SignupWizardTheme.secondaryButton,
          onPressed: widget.submitting ? null : widget.onBack,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

/// The single draggable pin shared by the inline and full-screen maps.
Marker _pinFor(SignupLocationDraft draft,
    {required ValueChanged<LatLng> onDragEnd}) {
  return Marker(
    markerId: const MarkerId('signup_marker'),
    position: LatLng(draft.latitude, draft.longitude),
    draggable: true,
    onDragEnd: onDragEnd,
    infoWindow: const InfoWindow(title: 'Your marker'),
  );
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SignupWizardTheme.background.withOpacity(0.85),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Full-screen version of the placement map, pushed by the expand button.
///
/// It owns its own copy of the draft and only hands it back when the user
/// confirms, so backing out of the full-screen view leaves the inline map's
/// pin exactly where it was.
class _FullScreenMarkerMap extends StatefulWidget {
  const _FullScreenMarkerMap({required this.initial});

  final SignupLocationDraft initial;

  @override
  State<_FullScreenMarkerMap> createState() => _FullScreenMarkerMapState();
}

class _FullScreenMarkerMapState extends State<_FullScreenMarkerMap> {
  late SignupLocationDraft _draft = widget.initial;

  void _movePin(LatLng target) {
    setState(() {
      _draft = _draft.copyWith(
        latitude: target.latitude,
        longitude: target.longitude,
        source: SignupLocationSource.manual,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SignupWizardTheme.background,
      appBar: AppBar(
        backgroundColor: SignupWizardTheme.background,
        foregroundColor: Colors.white,
        title: const Text('Place your marker'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: SignupLocationService.cameraFor(_draft),
            cloudMapId: IntrstMapStyle.cloudMapId,
            minMaxZoomPreference: IntrstMapStyle.zoomRange,
            markers: {_pinFor(_draft, onDragEnd: _movePin)},
            onTap: _movePin,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: true,
            onCameraMove: (position) => _draft =
                _draft.copyWith(zoom: position.zoom),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: SignupWizardTheme.background.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Drag the pin, or tap anywhere, to place your marker.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                // Compact (and therefore centred) so the button hugs its
                // label instead of spanning the map and sitting on top of the
                // zoom controls in the bottom-right corner.
                ElevatedButton(
                  style: SignupWizardTheme.primaryButtonCompact,
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: const Text('Use this spot'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
