import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'core/widgets/public_page_chrome.dart';
import 'profile/services/platform_policies_service.dart';
import 'profile/pages/settings/policy_document_page.dart';

/// The privacy policy, served at `/privacy-policy` without an account.
///
/// The document Google Play links to, and the one the web footer points at. It
/// is the same screen the signed-in app shows under Settings → Privacy Policy —
/// [PolicyDocumentPage] — so the text is set the same way in both places; this
/// page only names the document, says where to fetch it, and closes it with an
/// address to write to, which the in-app copy does not need.
class PublicPrivacyPolicyPage extends StatelessWidget {
  const PublicPrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PolicyDocumentPage(
      title: 'Privacy Policy',
      summary: 'What we collect, why, and what you can ask us to delete',
      icon: Icons.shield_outlined,
      loader: PlatformPoliciesService.getUserPrivacyPolicy,
      unavailableMessage:
          'The Privacy Policy has not been published yet. Please check back later.',
      failureMessage:
          'We couldn’t reach the Privacy Policy. Check your connection and try again.',
      footer: const PublicContactCard(
        title: 'Questions about your data?',
        message:
            'Write to us about anything in this policy — what we hold, how it '
            'is used, or a request to correct or delete it.',
        email: AppConfig.contactEmail,
      ),
    );
  }
}
