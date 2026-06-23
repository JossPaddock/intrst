import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  Shared helpers
// ─────────────────────────────────────────────

class _LegalSection {
  const _LegalSection({required this.heading, required this.body});
  final String heading;
  final String body;
}

/// Scrollable legal document layout shared by ToS and Privacy Policy.
class _LegalPage extends StatelessWidget {
  const _LegalPage({
    required this.title,
    required this.effectiveDate,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String effectiveDate;
  final String intro;
  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          children: [
            // Effective date badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Effective $effectiveDate',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Intro paragraph
            Text(
              intro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 28),

            // Sections
            ...sections.map((section) => _SectionBlock(section: section)),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // Footer contact nudge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mail_outline, size: 18, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Questions about this policy? Reach us at josspaddock@hotmail.com',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section});
  final _LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.heading,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Text(
              section.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Terms of Service
// ─────────────────────────────────────────────

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  static const _sections = <_LegalSection>[
    _LegalSection(
      heading: 'Acceptance of Terms',
      body:
          'By creating an account or using intrst, you agree to be bound by '
          'these Terms of Service and our Privacy Policy.'
          'We may update these terms from time to time; '
          'continued use after an update constitutes acceptance of the revised terms.',
    ),
    _LegalSection(
      heading: 'Eligibility',
      body:
          'You must be at least 13 years old to use intrst. By using the app '
          'you represent that you meet this age requirement and that any '
          'information you provide is accurate and complete.',
    ),
    _LegalSection(
      heading: 'Your Account',
      body:
          'You are responsible for keeping your account credentials secure and '
          'for all activity that occurs under your account. Notify us immediately '
          'at josspaddock@hotmail.com if you suspect unauthorised access. We reserve '
          'the right to suspend or terminate accounts that violate these terms.',
    ),
    _LegalSection(
      heading: 'User Content',
      body:
          'You retain ownership of any content (interests, messages, profile '
          'information) you post on intrst. By posting content you grant intrst '
          'a non-exclusive licence to display and distribute that '
          'content within the app. You must not post content that is unlawful, '
          'harmful, or infringes third-party rights.',
    ),
    _LegalSection(
      heading: 'Acceptable Use',
      body:
          'You agree not to: harass or harm other users; attempt to gain '
          'unauthorised access to any part of the service; use the app for '
          'spam or commercial solicitation without our consent; or reverse-engineer '
          'any part of the platform.',
    ),
    _LegalSection(
      heading: 'Messaging',
      body:
          'intrst provides in-app messaging as a convenience feature. '
          'You acknowledge that no transmission '
          'over the internet is 100% secure. Do not share sensitive personal or '
          'financial information via in-app messages.',
    ),
    _LegalSection(
      heading: 'Termination',
      body:
          'We may suspend or terminate your access at any time for conduct that '
          'we believe violates these terms or is harmful to other users, us, '
          'or third parties. You may delete your account at any time from the '
          'app settings.',
    ),
    _LegalSection(
      heading: 'Disclaimer of Warranties',
      body:
          'intrst is provided "as is" without warranties of any kind. We do not '
          'guarantee uninterrupted or error-free service. To the fullest extent '
          'permitted by law, we disclaim all implied warranties including '
          'merchantability and fitness for a particular purpose.',
    ),
    _LegalSection(
      heading: 'Limitation of Liability',
      body:
          'To the maximum extent permitted by applicable law, intrst and its '
          'developers shall not be liable for any indirect, incidental, or '
          'consequential damages arising from your use of the service.',
    ),
    _LegalSection(
      heading: 'Governing Law',
      body:
          'These terms are governed by the laws of the State of Washington, USA, '
          'without regard to conflict-of-law principles.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _LegalPage(
      title: 'Terms of Service',
      effectiveDate: 'June 2025',
      intro:
          'These Terms of Service ("Terms") govern your access to and use of '
          'the intrst mobile application ("app", "service") operated by the '
          'intrst development team. Please read them carefully.',
      sections: _sections,
    );
  }
}

// ─────────────────────────────────────────────
//  Privacy Policy
// ─────────────────────────────────────────────

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const _sections = <_LegalSection>[
    _LegalSection(
      heading: 'Information We Collect',
      body:
          'Account information: name, email address, and password (hashed) '
          'provided at sign-up.\n\n'
          'Profile content: interests, bio, and any photos you choose to upload.\n\n'
          'Usage data: interactions within the app (e.g. interests shared, '
          'people followed).\n\n'
          'Device & push tokens: FCM tokens used solely to deliver push '
          'notifications to your device.\n\n'
          'Location (optional): map-based features may request approximate '
          'location. This is never stored on our servers without your consent.',
    ),
    _LegalSection(
      heading: 'How We Use Your Information',
      body:
          'We use your information to:\n'
          '• Operate and personalise the app experience.\n'
          '• Deliver in-app and push notifications.\n'
          '• Enable messaging between users.\n'
          '• Maintain security and prevent abuse.\n'
          '• Respond to support requests.\n\n'
          'We do not sell your personal information to third parties.',
    ),
    _LegalSection(
      heading: 'Sharing of Information',
      body:
          'Your profile and interests are visible to other users according to '
          'the privacy settings you choose (public, friends & followers, or '
          'friends only). Messages are visible only to conversation participants. '
          'We share data with third-party service providers (Google Firebase, '
          'Google Maps) solely to operate the service, under agreements that '
          'protect your data.',
    ),
    _LegalSection(
      heading: 'Push Notifications',
      body:
          'We send push notifications '
          'such as new message alerts and activity updates. You can disable '
          'notifications at any time in your device settings. ',
    ),
    _LegalSection(
      heading: 'Data Retention',
      body:
          'We retain your data for as long as your account is active. When you '
          'delete your account, we initiate deletion of your personal data '
          'within 30 days, except where retention is required by law.',
    ),
    _LegalSection(
      heading: 'Children\'s Privacy',
      body:
          'intrst is not directed at children under 13. We do not knowingly '
          'collect personal information from children under 13. If you believe '
          'a child has provided us with personal data, please contact us and '
          'we will delete it promptly.',
    ),
    _LegalSection(
      heading: 'Security',
      body:
          'We use industry-standard measures and security rules to protect your '
          'data. No method of electronic storage is 100% secure, and we cannot '
          'guarantee absolute '
          'security.',
    ),
    _LegalSection(
      heading: 'Your Rights',
      body:
          'Depending on your location you may have rights to access, correct, '
          'or delete your personal data. To exercise these rights, contact us '
          'at josspaddock@hotmail.com. I will respond within 30 days.',
    ),
    _LegalSection(
      heading: 'Third-Party Services',
      body:
          'The app integrates Google services. Use of '
          'these services is subject to Google\'s Privacy Policy at '
          'policies.google.com/privacy. We are not responsible for third-party '
          'privacy practices.',
    ),
    _LegalSection(
      heading: 'Changes to This Policy',
      body:
          'We may update this Privacy Policy periodically. We will notify you '
          'of material changes via in-app notification or email. Continued use '
          'of intrst after changes take effect constitutes acceptance of the '
          'revised policy.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _LegalPage(
      title: 'Privacy Policy',
      effectiveDate: 'June 2025',
      intro:
          'Your privacy matters to us. This Privacy Policy explains what '
          'information intrst collects, how we use it, and the choices you '
          'have. By using intrst you agree to the practices described here.',
      sections: _sections,
    );
  }
}

// ─────────────────────────────────────────────
//  Support Page
// ─────────────────────────────────────────────

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'josspaddock@hotmail.com',
      queryParameters: {'subject': 'intrst Support Request'},
    );
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open mail app. '
              'Email us at josspaddock@hotmail.com',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Support'), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
          children: [
            // Header card
            Card(
              elevation: 0,
              color: colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: colorScheme.primary,
                      child: Icon(
                        Icons.support_agent,
                        color: colorScheme.onPrimary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'We\'re here to help',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Typically reply within 1–2 business days.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer.withOpacity(
                                0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Contact section
            Text(
              'Contact',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            _SupportTile(
              icon: Icons.mail_outline,
              title: 'Email support',
              subtitle: 'josspaddock@hotmail.com',
              onTap: () => _launchEmail(context),
            ),
            const SizedBox(height: 28),

            // FAQ section
            Text(
              'FAQ',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            const _FaqTile(
              question: 'How do I delete my account?',
              answer:
                  'Go to your profile settings and tap "Delete Account". '
                  'Your data will be removed within 30 days. This action '
                  'is permanent and cannot be undone.',
            ),
            const _FaqTile(
              question: 'Why am I not receiving notifications?',
              answer:
                  'Make sure notifications are enabled in your iPhone\'s '
                  'Settings → intrst → Notifications. If the issue persists, '
                  'try signing out and back in to refresh your push token.',
            ),
            const _FaqTile(
              question: 'How do I control who sees my interests?',
              answer:
                  'Each interest has a privacy setting: Public, '
                  'Friends & Followers, or Friends Only. You can change '
                  'this when creating or editing an interest.',
            ),
            const _FaqTile(
              question: 'I found a bug — what should I do?',
              answer:
                  'We\'d love to know. Email us at josspaddock@hotmail.com with '
                  'a short description of what happened and, if possible, '
                  'the steps to reproduce it. Screenshots always help!',
            ),
            const SizedBox(height: 28),

            // Legal links
            Text(
              'Legal',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            _SupportTile(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              subtitle: 'Review our terms',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
              ),
            ),
            _SupportTile(
              icon: Icons.lock_outline,
              title: 'Privacy Policy',
              subtitle: 'How we handle your data',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
              ),
            ),
            const SizedBox(height: 32),

            // App version footer
            Center(
              child: Text(
                'intrst · Version 1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Support tile (reusable row) ──────────────

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          child: Icon(icon, size: 20, color: colorScheme.onSecondaryContainer),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}

// ── FAQ accordion tile ───────────────────────

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  widget.answer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
