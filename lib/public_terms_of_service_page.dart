import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'core/widgets/public_page_chrome.dart';
import 'profile/services/platform_policies_service.dart';
import 'profile/pages/settings/policy_document_page.dart';

/// The terms of service, served at `/terms-of-service` without an account.
///
/// The same screen the signed-in app shows under Settings → Terms & Conditions
/// — [PolicyDocumentPage] — with an address to write to at the end, which
/// someone who arrived from a store listing or a pasted link would otherwise
/// have no way to find.
class PublicTermsOfServicePage extends StatelessWidget {
  const PublicTermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PolicyDocumentPage(
      title: 'Terms of Service',
      summary: 'The agreement you accept by using DentPal',
      icon: Icons.description_outlined,
      loader: PlatformPoliciesService.getTermsAndConditions,
      unavailableMessage:
          'The Terms of Service have not been published yet. Please check back later.',
      failureMessage:
          'We couldn’t reach the Terms of Service. Check your connection and try again.',
      footer: const PublicContactCard(
        title: 'Questions about these terms?',
        message:
            'If anything here is unclear, or you need a copy for your records, '
            'get in touch and we will help.',
        email: AppConfig.contactEmail,
      ),
    );
  }
}
