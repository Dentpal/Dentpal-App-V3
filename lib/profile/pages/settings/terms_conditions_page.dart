import 'package:flutter/material.dart';

import '../../services/platform_policies_service.dart';
import 'policy_document_page.dart';

/// The platform's terms of service, as published from the admin dashboard.
///
/// The screen itself is [PolicyDocumentPage] — this page only names the
/// document and says where to fetch it.
class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PolicyDocumentPage(
      title: 'Terms & Conditions',
      summary: 'The agreement you accept by using DentPal',
      icon: Icons.description_outlined,
      loader: PlatformPoliciesService.getTermsAndConditions,
      unavailableMessage:
          'Terms and Conditions have not been published yet. Please check back later.',
      failureMessage:
          'We couldn’t reach the Terms and Conditions. Check your connection and try again.',
    );
  }
}
