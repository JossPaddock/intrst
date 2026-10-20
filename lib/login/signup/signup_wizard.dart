import 'package:flutter/material.dart';
import 'package:intrst/login/signup/signup_location_service.dart';
import 'package:intrst/login/signup/signup_progress_header.dart';
import 'package:intrst/login/signup/signup_step_interest.dart';
import 'package:intrst/login/signup/signup_step_location.dart';
import 'package:intrst/login/signup/signup_step_profile.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/login/signup/signup_wizard_theme.dart';

/// Why a submission failed, and whether the wizard can recover from it.
///
/// [fatal] errors are ones the user can only fix back on the login screen —
/// an email already in use, for instance — so the wizard closes and hands the
/// message back. Everything else (a dropped connection mid-write) keeps them
/// on the last part with their answers intact so they can simply retry.
class SignupSubmitError {
  const SignupSubmitError(this.message, {this.fatal = false});

  final String message;
  final bool fatal;
}

/// Creates the account from the collected answers. Returns null on success.
typedef SignupWizardSubmit = Future<SignupSubmitError?> Function(
    SignupWizardResult result);

/// The multi-part sign-up wizard.
///
/// Runs *after* the user has entered an email and password but *before* the
/// Firebase Auth account is created: every answer is gathered first, then the
/// account, the profile document, the first interest and the marker location
/// are written together. That ordering is deliberate — it keeps the age gate
/// ahead of account creation, and it means a user who reaches the map already
/// has their interest in their list and their marker on the map, with nothing
/// deferred to a later screen.
class SignupWizard extends StatefulWidget {
  const SignupWizard({
    super.key,
    required this.email,
    required this.onSubmit,
    this.locationService,
  });

  /// Shown in the header so the user can see which account they are creating.
  final String email;

  final SignupWizardSubmit onSubmit;

  /// Injectable for tests; the location part builds a real one when null.
  final SignupLocationService? locationService;

  /// Pushes the wizard full-screen.
  ///
  /// Resolves to null when the account was created, or to a message to show on
  /// the login screen when the user backed out or hit a fatal error.
  static Future<String?> show(
    BuildContext context, {
    required String email,
    required SignupWizardSubmit onSubmit,
    SignupLocationService? locationService,
  }) async {
    final String? outcome = await Navigator.of(context, rootNavigator: true)
        .push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SignupWizard(
        email: email,
        onSubmit: onSubmit,
        locationService: locationService,
      ),
    ));
    if (outcome == successSentinel) return null;
    // A dismissal with no value (system back, swipe) is a cancellation.
    return outcome ?? 'Sign-up cancelled.';
  }

  /// Sentinel popped when the account was created successfully.
  static const String successSentinel = '';

  @override
  State<SignupWizard> createState() => _SignupWizardState();
}

class _SignupWizardState extends State<SignupWizard> {
  SignupWizardStep _step = SignupWizardStep.profile;

  SignupProfileDraft? _profile;
  SignupInterestDraft? _interest;
  SignupLocationDraft? _location;

  bool _submitting = false;

  void _goTo(SignupWizardStep step) {
    if (_submitting) return;
    setState(() => _step = step);
  }

  void _back() {
    switch (_step) {
      case SignupWizardStep.profile:
        _confirmDiscard();
      case SignupWizardStep.interest:
        _goTo(SignupWizardStep.profile);
      case SignupWizardStep.location:
        _goTo(SignupWizardStep.interest);
    }
  }

  Future<void> _confirmDiscard() async {
    if (_submitting) return;
    final bool discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Leave sign-up?'),
            content: const Text(
                'Your account has not been created yet, so anything you have '
                'entered will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep going'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _finish(SignupLocationDraft location) async {
    final profile = _profile;
    final interest = _interest;
    if (profile == null || interest == null || _submitting) return;

    setState(() {
      _location = location;
      _submitting = true;
    });

    final SignupSubmitError? error = await widget.onSubmit(SignupWizardResult(
      profile: profile,
      interest: interest,
      location: location,
    ));

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(SignupWizard.successSentinel);
      return;
    }

    setState(() => _submitting = false);
    if (error.fatal) {
      Navigator.of(context).pop(error.message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.message),
        backgroundColor: SignupWizardTheme.highlight,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case SignupWizardStep.profile:
        return SignupStepProfile(
          key: const ValueKey('signup_step_profile'),
          initial: _profile,
          onContinue: (draft) {
            _profile = draft;
            _goTo(SignupWizardStep.interest);
          },
        );
      case SignupWizardStep.interest:
        return SignupStepInterest(
          key: const ValueKey('signup_step_interest'),
          initial: _interest,
          onBack: _back,
          onContinue: (draft) {
            _interest = draft;
            _goTo(SignupWizardStep.location);
          },
        );
      case SignupWizardStep.location:
        return SignupStepLocation(
          key: const ValueKey('signup_step_location'),
          initial: _location,
          locationService: widget.locationService,
          submitting: _submitting,
          onBack: _back,
          onFinish: _finish,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The route only closes through _back/_finish so a stray system back
      // never strands a half-filled sign-up.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: SignupWizardTheme.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _step == SignupWizardStep.profile
                            ? Icons.close
                            : Icons.arrow_back,
                        color: Colors.white70,
                      ),
                      tooltip: _step == SignupWizardStep.profile
                          ? 'Leave sign-up'
                          : 'Back',
                      onPressed: _submitting ? null : _back,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SignupProgressHeader(
                  currentStep: _step,
                  onStepTapped: _submitting ? null : _goTo,
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildStep(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
