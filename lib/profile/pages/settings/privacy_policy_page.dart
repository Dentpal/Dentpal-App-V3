import 'package:flutter/material.dart';

import '../../services/platform_policies_service.dart';
import 'policy_document_page.dart';

/// The platform's privacy policy, as published from the admin dashboard.
///
/// The screen itself is [PolicyDocumentPage] — this page only names the
/// document and says where to fetch it.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

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
    );
  }
}
