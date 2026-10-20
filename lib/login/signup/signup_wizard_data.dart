/// Pure data + validation for the multi-part sign-up wizard.
///
/// Everything in this file is deliberately free of Flutter widgets and
/// Firebase so the rules that decide whether a sign-up may proceed (name
/// present, birthday parseable, age gate, interest named) can be exercised
/// directly by unit tests and by the admin dashboard's test runner.
library;

/// Minimum age required to hold an intrst account.
///
/// The gate is enforced in the wizard's first part, which runs *before* the
/// Firebase Auth account is created, so no account ever exists for an
/// underage sign-up attempt.
const int kMinimumSignupAge = 13;

/// The three parts of the wizard, in order. The progress header renders one
/// segment per entry and the shell drives navigation off the index.
enum SignupWizardStep {
  profile('About you'),
  interest('Your interest'),
  location('Your location');

  const SignupWizardStep(this.label);

  /// Short caption shown under the step's dot in the progress header.
  final String label;

  static int get count => SignupWizardStep.values.length;
}

/// Parses a birthday entered as `MM/DD/YYYY`.
///
/// Returns null when the string isn't a valid calendar date in that format.
/// `DateTime` normalizes out-of-range values (month 13 rolls into the next
/// year) instead of throwing, so the parts are round-tripped to reject dates
/// that only *look* valid.
DateTime? parseSignupBirthday(String input) {
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(input.trim());
  if (match == null) return null;

  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);

  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Whole years elapsed since [birthday]. [now] is injectable so tests don't
/// depend on the wall clock.
int calculateSignupAge(DateTime birthday, {DateTime? now}) {
  final today = now ?? DateTime.now();
  int age = today.year - birthday.year;
  if (today.month < birthday.month ||
      (today.month == birthday.month && today.day < birthday.day)) {
    age--;
  }
  return age;
}

/// Field validator for the first/last name inputs. [label] is interpolated
/// into the message so one function serves both fields.
String? validateSignupName(String? value, String label) {
  if (value == null || value.trim().isEmpty) return 'Please enter a $label';
  return null;
}

/// Field validator for the birthday input. Checks format and that the date is
/// not in the future; the age gate itself is deliberately *not* enforced here
/// so it can raise the explanatory dialog rather than a terse field error.
String? validateSignupBirthdayField(String? value, {DateTime? now}) {
  if (value == null || value.trim().isEmpty) return 'Please enter your birthday';
  final birthday = parseSignupBirthday(value);
  if (birthday == null) return 'Please enter a valid date as MM/DD/YYYY';
  if (birthday.isAfter(now ?? DateTime.now())) {
    return 'Birthday cannot be in the future';
  }
  return null;
}

/// Field validator for the interest's name. The description is optional — a
/// user with a name-only interest still lands on the map with a populated
/// list, which is the point of collecting it during sign-up.
String? validateSignupInterestName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please name your interest';
  }
  return null;
}

/// Part one: who the user is.
class SignupProfileDraft {
  const SignupProfileDraft({
    required this.firstName,
    required this.lastName,
    required this.birthday,
  });

  final String firstName;
  final String lastName;
  final DateTime birthday;

  int ageAt(DateTime now) => calculateSignupAge(birthday, now: now);

  bool isOldEnough({DateTime? now}) =>
      calculateSignupAge(birthday, now: now) >= kMinimumSignupAge;
}

/// Part two: the interest seeded into the account.
class SignupInterestDraft {
  const SignupInterestDraft({required this.name, this.description = ''});

  final String name;
  final String description;
}

/// Part three: where the user's marker is dropped.
///
/// [zoom] travels with the position because the ways of arriving at one carry
/// very different confidence: an IP estimate is city-level and wants a wider
/// camera, while a marker the user dragged themselves is exactly where they
/// meant it to be.
class SignupLocationDraft {
  const SignupLocationDraft({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    this.source = SignupLocationSource.manual,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final SignupLocationSource source;

  SignupLocationDraft copyWith({
    double? latitude,
    double? longitude,
    double? zoom,
    SignupLocationSource? source,
  }) {
    return SignupLocationDraft(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      zoom: zoom ?? this.zoom,
      source: source ?? this.source,
    );
  }
}

/// How a [SignupLocationDraft] was arrived at.
///
/// There is no device-GPS source: sign-up places the marker from the IP
/// estimate alone and lets the user drag it, rather than blocking the flow on
/// an OS location prompt.
enum SignupLocationSource { ipEstimate, manual, fallback }

/// The completed wizard, handed back to the login screen so it can create the
/// account and write all three parts in one go.
class SignupWizardResult {
  const SignupWizardResult({
    required this.profile,
    required this.interest,
    required this.location,
  });

  final SignupProfileDraft profile;
  final SignupInterestDraft interest;
  final SignupLocationDraft location;
}
