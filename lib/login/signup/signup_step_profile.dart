import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/login/signup/signup_wizard_theme.dart';

/// Part one of the wizard: first name, last name and age.
///
/// The age gate lives here rather than in the field validator so an underage
/// sign-up gets a proper explanation instead of a one-line form error — and
/// because this runs before the Firebase Auth account is created, no account
/// is ever produced for someone under [kMinimumSignupAge].
class SignupStepProfile extends StatefulWidget {
  const SignupStepProfile({
    super.key,
    required this.onContinue,
    this.initial,
  });

  final ValueChanged<SignupProfileDraft> onContinue;
  final SignupProfileDraft? initial;

  @override
  State<SignupStepProfile> createState() => _SignupStepProfileState();
}

class _SignupStepProfileState extends State<SignupStepProfile> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _birthday;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _firstName = TextEditingController(text: initial?.firstName ?? '');
    _lastName = TextEditingController(text: initial?.lastName ?? '');
    _birthday = TextEditingController(
        text: initial == null ? '' : _formatBirthday(initial.birthday));
    // Keeps the live age caption under the birthday field in sync as they type.
    _birthday.addListener(() => setState(() {}));
  }

  static String _formatBirthday(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/${date.year}';

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _birthday.dispose();
    super.dispose();
  }

  /// The age implied by whatever is currently typed, or null while the field
  /// isn't yet a valid date.
  int? get _typedAge {
    final birthday = parseSignupBirthday(_birthday.text);
    if (birthday == null || birthday.isAfter(DateTime.now())) return null;
    return calculateSignupAge(birthday);
  }

  Future<void> _pickBirthday() async {
    final DateTime now = DateTime.now();
    final DateTime initial =
        parseSignupBirthday(_birthday.text) ?? DateTime(now.year - 18, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: SignupWizardTheme.accent,
            onPrimary: SignupWizardTheme.background,
            surface: SignupWizardTheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _birthday.text = _formatBirthday(picked);
  }

  Future<void> _showUnderageDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Age Restriction'),
        content: const Text(
            'You must be at least $kMinimumSignupAge years of age to use the '
            'intrst app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final DateTime birthday = parseSignupBirthday(_birthday.text)!;
    final draft = SignupProfileDraft(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      birthday: birthday,
    );

    if (!draft.isOldEnough()) {
      await _showUnderageDialog();
      return;
    }

    widget.onContinue(draft);
  }

  @override
  Widget build(BuildContext context) {
    final int? age = _typedAge;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Text('About you', style: SignupWizardTheme.title),
          const SizedBox(height: 8),
          const Text(
            'This is the name other members will see on your marker and your '
            'profile.',
            style: SignupWizardTheme.body,
          ),
          const SizedBox(height: 28),
          TextFormField(
            key: const Key('signup_first_name'),
            controller: _firstName,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            decoration:
                SignupWizardTheme.inputDecoration(label: 'First name'),
            validator: (value) => validateSignupName(value, 'First Name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('signup_last_name'),
            controller: _lastName,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.familyName],
            decoration: SignupWizardTheme.inputDecoration(label: 'Last name'),
            validator: (value) => validateSignupName(value, 'Last Name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('signup_birthday'),
            controller: _birthday,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.datetime,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: SignupWizardTheme.inputDecoration(
              label: 'Date of birth (MM/DD/YYYY)',
              hint: '01/31/1990',
              helper: age == null
                  ? 'You must be at least $kMinimumSignupAge to use intrst.'
                  : "That makes you $age year${age == 1 ? '' : 's'} old.",
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white54),
                tooltip: 'Pick a date',
                onPressed: _pickBirthday,
              ),
            ),
            validator: validateSignupBirthdayField,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            key: const Key('signup_profile_continue'),
            style: SignupWizardTheme.primaryButton,
            onPressed: _submit,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
