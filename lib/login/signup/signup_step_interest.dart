import 'package:flutter/material.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/login/signup/signup_wizard_theme.dart';

/// Part two of the wizard: the first interest, seeded into the account so the
/// user's list is never empty the first time they open it.
class SignupStepInterest extends StatefulWidget {
  const SignupStepInterest({
    super.key,
    required this.onContinue,
    required this.onBack,
    this.initial,
  });

  final ValueChanged<SignupInterestDraft> onContinue;
  final VoidCallback onBack;
  final SignupInterestDraft? initial;

  /// The prompt shown above the fields. Kept as a constant so the copy has one
  /// home rather than being buried in the layout.
  static const String prompt =
      'What has inspired you lately or alternately, what is a lifelong passion '
      'you want to share, with select friends or potential new friends?';

  @override
  State<SignupStepInterest> createState() => _SignupStepInterestState();
}

class _SignupStepInterestState extends State<SignupStepInterest> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _description =
        TextEditingController(text: widget.initial?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onContinue(SignupInterestDraft(
      name: _name.text.trim(),
      description: _description.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Text('Your first interest', style: SignupWizardTheme.title),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SignupWizardTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.format_quote,
                    color: SignupWizardTheme.accent, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    SignupStepInterest.prompt,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.45,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const Key('signup_interest_name'),
            controller: _name,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: SignupWizardTheme.inputDecoration(
              label: 'Interest name',
              hint: 'Rock climbing, Baking sourdough, Astronomy…',
            ),
            validator: validateSignupInterestName,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('signup_interest_description'),
            controller: _description,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: SignupWizardTheme.inputDecoration(
              label: 'Description',
              hint: 'Tell people what draws you to it…',
              helper: 'Optional — you can add or change this any time.',
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            key: const Key('signup_interest_continue'),
            style: SignupWizardTheme.primaryButton,
            onPressed: _submit,
            child: const Text('Continue'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: SignupWizardTheme.secondaryButton,
            onPressed: widget.onBack,
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}
