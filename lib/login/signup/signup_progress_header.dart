import 'package:flutter/material.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/login/signup/signup_wizard_theme.dart';

/// The visual progress indicator pinned to the top of every wizard part.
///
/// One numbered dot per [SignupWizardStep], joined by connector bars that fill
/// as the user advances. Completed parts show a tick, the current part is
/// ringed in the accent colour, and upcoming parts stay muted — so the user can
/// see at a glance both how far along they are and how much is left.
class SignupProgressHeader extends StatelessWidget {
  const SignupProgressHeader({
    super.key,
    required this.currentStep,
    this.onStepTapped,
  });

  final SignupWizardStep currentStep;

  /// Called when the user taps an already-completed dot to go back. Null while
  /// a submission is in flight, which disables backwards navigation.
  final ValueChanged<SignupWizardStep>? onStepTapped;

  @override
  Widget build(BuildContext context) {
    final steps = SignupWizardStep.values;
    return Semantics(
      label: 'Step ${currentStep.index + 1} of ${SignupWizardStep.count}: '
          '${currentStep.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${currentStep.index + 1} of ${SignupWizardStep.count}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Expanded(child: _Connector(filled: i <= currentStep.index)),
                _StepDot(
                  step: steps[i],
                  state: i < currentStep.index
                      ? _StepState.complete
                      : i == currentStep.index
                          ? _StepState.current
                          : _StepState.upcoming,
                  onTap: i < currentStep.index && onStepTapped != null
                      ? () => onStepTapped!(steps[i])
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _StepState { complete, current, upcoming }

class _Connector extends StatelessWidget {
  const _Connector({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 3,
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: filled ? SignupWizardTheme.accent : Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step, required this.state, this.onTap});

  final SignupWizardStep step;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool done = state == _StepState.complete;
    final bool current = state == _StepState.current;
    final Color fill = done
        ? SignupWizardTheme.accent
        : current
            ? SignupWizardTheme.background
            : Colors.transparent;
    final Color border =
        done || current ? SignupWizardTheme.accent : Colors.white30;
    final Color foreground = done
        ? SignupWizardTheme.background
        : current
            ? SignupWizardTheme.accent
            : Colors.white38;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 2),
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(Icons.check, size: 18, color: foreground)
                : Text(
                    '${step.index + 1}',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 84,
            child: Text(
              step.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: current ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: current ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
