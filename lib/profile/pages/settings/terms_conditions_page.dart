import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';

class TermsConditionsPage extends StatefulWidget {
  const TermsConditionsPage({super.key});

  @override
  State<TermsConditionsPage> createState() => _TermsConditionsPageState();
}

class _TermsConditionsPageState extends State<TermsConditionsPage> {
  String? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .get();

        if (userDoc.exists && mounted) {
          setState(() {
            _userRole = userDoc.data()?['role'] ?? 'buyer';
            _isLoading = false;
          });
        } else if (mounted) {
          setState(() {
            _userRole = 'buyer';
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _userRole = 'buyer';
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.d('Error loading user role: $e');
      if (mounted) {
        setState(() {
          _userRole = 'buyer';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Terms & Conditions',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWideWeb = kIsWeb && constraints.maxWidth > 900; // BREAKPOINT
                
                final content = SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.onSurface.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: _userRole == 'seller'
                          ? _buildSellerTerms()
                          : _buildBuyerTerms(),
                    ),
                  ),
                );

                if (isWideWeb) {
                  // Web wide: centered with max width
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200), // MAX_WIDTH
                      child: content,
                    ),
                  );
                }
                
                // Mobile and narrow web: full width
                return content;
              },
            ),
    );
  }

  Widget _buildBuyerTerms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('1. Introduction'),
        _buildSubSectionTitle('1.1 Welcome & Agreement'),
        _buildParagraph(
          'Welcome to DentPal, powered by R&R Newtech Dental Corporation ("DentPal," "we," "us," or "our"). By using DentPal or creating an account ("Account"), you agree to these Terms of Service. Continued use constitutes acceptance of updates.',
        ),
        _buildSubSectionTitle('1.2 Scope of Services'),
        _buildParagraph(
          'DentPal provides a mobile e-commerce platform connecting account users with merchants who sell dental products and equipment. DentPal\'s services include:',
        ),
        _buildBulletList([
          'The mobile application and related features',
          'Tools to browse, order, and pay for products',
          'Communication channels between account users and merchants',
          'Additional features or services made available in the app',
        ]),
        _buildParagraph(
          'Note: Contracts for purchases are between account users and merchants. DentPal is not a party to these contracts and assumes no responsibility for product quality, delivery, or disputes.',
        ),
        _buildSubSectionTitle('1.3 Account Agreement & Data Consent'),
        _buildParagraph(
          'By creating an account, you consent to the collection and processing of your data as described in the DentPal Privacy Policy, which is incorporated by reference. You are responsible for maintaining accurate account information and for all activity under your account.',
        ),
        _buildSubSectionTitle('1.4 Platform Rights & Modifications'),
        _buildParagraph(
          'DentPal reserves the right to change, modify, suspend, or discontinue all or any part of the DentPal mobile application or its services at any time, with or without notice, as permitted by Philippine law. DentPal may release certain features or services in a beta or trial version, which may not function in the same way as the final version. DentPal shall not be held liable for any errors, disruptions, or limitations in such cases.',
        ),
        _buildSubSectionTitle('1.5 Account Refusal, Acceptance, and Age Requirement'),
        _buildParagraph(
          'DentPal reserves the right to refuse access to the application or to deny the creation of an account for any reason. If you are under the minimum legal age required to enter into an agreement in the Philippines, you must obtain permission from a parent or legal guardian to create an account.',
        ),

        _buildSectionTitle('2. Privacy'),
        _buildSubSectionTitle('2.1 User Privacy and Consent'),
        _buildParagraph('Your privacy is important to us. By using DentPal, you:'),
        _buildBulletList([
          'Consent to collection, use, and sharing of your data as described in the Privacy Policy',
          'Acknowledge that User Information is jointly owned by you and DentPal',
          'Agree not to disclose User Information to third parties without DentPal\'s consent, except where required by law',
        ]),
        _buildSubSectionTitle('2.2 Sharing of Data with Third-Party Partners'),
        _buildParagraph('User Information may be shared with trusted third-party service providers for:'),
        _buildBulletList([
          'Payment processing',
          'Order fulfillment and delivery',
          'Platform support services',
          'Marketing, advertising, and promotional activities',
        ]),

        _buildSectionTitle('3. Limited License'),
        _buildSubSectionTitle('3.1 Access and Intellectual Property'),
        _buildParagraph(
          'DentPal grants you a limited and revocable license to access and use the Services, subject to these Terms of Service. All proprietary Content, trademarks, service marks, brand names, logos, and other intellectual property are the property of DentPal and, where applicable, third-party proprietors.',
        ),
        _buildSubSectionTitle('3.2 Linking to DentPal'),
        _buildParagraph(
          'You are welcome to link to the platform from your website, provided that your website does not imply any endorsement by or association with DentPal.',
        ),

        _buildSectionTitle('4. Software'),
        _buildParagraph(
          'Any software provided by DentPal to you as part of the Services is subject to these Terms of Service. DentPal reserves all rights to the software not expressly granted to you under these Terms.',
        ),

        _buildSectionTitle('5. Accounts and Security'),
        _buildSubSectionTitle('5.1 Account Registration'),
        _buildParagraph(
          'Some services require registration. You are responsible for accurate information, confidentiality of your credentials, and activities under your account.',
        ),
        _buildSubSectionTitle('5.2 Account Security Responsibilities'),
        _buildParagraph('You agree to:'),
        _buildBulletList([
          'Keep your password confidential and use only your User ID and password when logging in',
          'Log out from your Account at the end of each session',
          'Immediately notify DentPal of any unauthorized use of your Account',
          'Ensure that your Account information is accurate and up-to-date',
        ]),
        _buildSubSectionTitle('5.3 DentPal\'s Right to Suspend or Terminate Accounts'),
        _buildParagraph('Grounds for account suspension or termination may include:'),
        _buildBulletList([
          'Extended periods of inactivity',
          'Violation of these Terms of Service',
          'Illegal, fraudulent, harassing, defamatory, threatening, or abusive behavior',
          'Having multiple accounts',
          'Abnormal or excessive purchasing',
          'Voucher or promotion abuse',
          'Failure to make timely payments for transactions',
        ]),
        _buildSubSectionTitle('5.4 User-Initiated Account Termination'),
        _buildParagraph(
          'You may terminate your Account by sending a written request to support@dentpal.shop from your registered email address. Your Account will be terminated within 24 hours after DentPal receives the request.',
        ),
        _buildSubSectionTitle('5.5 Geographic Restrictions'),
        _buildParagraph(
          'You may use DentPal only where services are offered. DentPal works with logistics and delivery providers to determine coverage areas.',
        ),

        _buildSectionTitle('6. Term of Use and Prohibited Conduct'),
        _buildSubSectionTitle('6.1 Term of Use'),
        _buildParagraph(
          'The license to use DentPal Services is effective until terminated. DentPal may terminate this license for non-compliance with these Terms.',
        ),
        _buildSubSectionTitle('6.2 Prohibited Activities'),
        _buildParagraph('You agree not to:'),
        _buildBulletList([
          'Upload or transmit content that is unlawful, harmful, threatening, abusive, harassing, obscene, defamatory, or otherwise objectionable',
          'Harm minors or upload content involving unsupervised minors',
          'Impersonate others or submit false verification documents',
          'Post unsolicited advertising or spam',
          'Violate any laws, including export/import restrictions',
          'Act fraudulently or deceptively',
          'Reverse engineer, hack, or interfere with DentPal Services',
          'Collect unauthorized data on other users',
          'Transmit viruses, malware, or harmful software',
        ]),
        _buildSubSectionTitle('6.3 Responsibility for Content'),
        _buildParagraph(
          'You are solely responsible for all Content uploaded, transmitted, or shared. DentPal is not liable for offensive, indecent, or objectionable Content.',
        ),

        _buildSectionTitle('7. Violation of Our Terms of Service'),
        _buildSubSectionTitle('7.1 Violations and Consequences'),
        _buildParagraph('Violations may result in:'),
        _buildBulletList([
          'Limits placed on account privileges',
          'Account suspension and subsequent termination',
          'Criminal charges',
          'Civil actions, including claims for damages',
          'Cancellation or suspension of any transactions',
        ]),
        _buildSubSectionTitle('7.2 Reporting Violations'),
        _buildParagraph(
          'If you believe an account user is violating these Terms of Service, please contact support@dentpal.shop.',
        ),

        _buildSectionTitle('8. Reporting Intellectual Property Rights Infringement'),
        _buildParagraph(
          'DentPal does not allow account users to upload, submit, or share content that violates the intellectual property rights of brands or other IPR owners.',
        ),
        _buildSubSectionTitle('8.4 Complaints Requirements'),
        _buildParagraph('Complaints must include:'),
        _buildBulletList([
          'A physical or electronic signature of the IPR Owner or IPR Agent',
          'A description of the intellectual property right allegedly infringed',
          'A description of the nature of the alleged infringement',
          'Sufficient contact information',
          'A statement that the complaint is filed in good faith',
          'A statement that the information provided is accurate',
        ]),

        _buildSectionTitle('9. Purchase and Payment'),
        _buildSubSectionTitle('9.1 Payment Methods'),
        _buildParagraph('Payments may be processed through:'),
        _buildBulletList([
          'Cash on Delivery (COD)',
          'Credit/Debit Cards',
          'Online Payment Wallets',
          'Buy Now, Pay Later (BNPL)',
          'Check Payments (Coverage Limited to Logistics Partners)',
        ]),
        _buildSubSectionTitle('9.2 Payment Changes'),
        _buildParagraph(
          'Account users may only change their preferred payment method prior to completing payment for a purchase.',
        ),
        _buildSubSectionTitle('9.3 Responsibility for Information'),
        _buildParagraph(
          'DentPal assumes no responsibility or liability for any loss or damages arising from incorrect shipping information or incorrect payment details.',
        ),

        _buildSectionTitle('10. Returns and Order Cancellations'),
        _buildSubSectionTitle('10.1 Returns & Refunds'),
        _buildParagraph(
          'Account users may submit requests for returns or refunds in accordance with the applicable merchant\'s return and refund policies and within the timeframes permitted by DentPal.',
        ),
        _buildParagraph(
          'Return and refund requests must be submitted and approved before 5:00 PM on Wednesday of the applicable payout week. Once a transaction has been included in the weekly automated payout cycle, the transaction is no longer eligible for return or refund through DentPal.',
        ),
        _buildSubSectionTitle('10.2 Order Cancellations'),
        _buildParagraph(
          'Account users may cancel an order only if the merchant has not yet confirmed shipment in the system.',
        ),

        _buildSectionTitle('11. Disputes'),
        _buildBulletList([
          'If a problem arises with a purchase, account users should first attempt to resolve the issue directly with the merchant',
          'DentPal may assist in facilitating communication but assumes no liability for the resolution of the dispute',
          'If the dispute cannot be resolved, account users may escalate the matter to the claims tribunal or other appropriate legal forum',
          'Account users agree not to hold DentPal liable for any loss, damages, or claims arising from transactions with merchants',
        ]),

        _buildSectionTitle('12. Feedback and Product Reviews'),
        _buildSubSectionTitle('12.1 Product Reviews'),
        _buildBulletList([
          'Only account users who have purchased a product through DentPal may submit feedback or reviews',
          'Feedback and reviews must be honest, constructive, and relevant',
          'DentPal reserves the right to remove reviews that are defamatory, inappropriate, or violate applicable laws',
        ]),
        _buildSubSectionTitle('12.2 Platform Feedback'),
        _buildParagraph(
          'Account users may submit feedback regarding DentPal\'s platform, services, or processes by emailing support@dentpal.shop.',
        ),

        _buildSectionTitle('13. Disclaimers'),
        _buildSubSectionTitle('13.1 "As Is" Services'),
        _buildParagraph(
          'DentPal provides its platform and services on an "AS IS" and "AS AVAILABLE" basis. DentPal makes no warranties, expressed or implied.',
        ),
        _buildSubSectionTitle('13.2 No Guarantee of Availability or Accuracy'),
        _buildParagraph(
          'DentPal does not guarantee that the platform or its services will be uninterrupted, error-free, secure, or free from viruses or harmful code.',
        ),
        _buildSubSectionTitle('13.3 Products and Transactions'),
        _buildParagraph(
          'DentPal does not control or guarantee the quality, safety, legality, or fitness for purpose of any products sold on the platform.',
        ),
        _buildSubSectionTitle('13.4 Assumption of Risk'),
        _buildParagraph(
          'Account users acknowledge and accept that the risk of using DentPal rests entirely with them.',
        ),

        _buildSectionTitle('14. Exclusions and Limitations of Liability'),
        _buildSubSectionTitle('14.1 No Liability for Certain Damages'),
        _buildParagraph(
          'To the maximum extent permitted by law, DentPal shall not be liable for any indirect, incidental, special, or consequential damages.',
        ),
        _buildSubSectionTitle('14.2 Remedies'),
        _buildParagraph(
          'Your sole remedy for any dissatisfaction or issues with the DentPal platform is to terminate your account and/or stop using the services.',
        ),
        _buildSubSectionTitle('14.3 Maximum Liability'),
        _buildParagraph(
          'If DentPal is found legally liable (including for gross negligence), its liability is limited to the lesser of any amounts payable under applicable DentPal guarantees or PHP 4,000.00.',
        ),

        _buildSectionTitle('15. Representations and Warranties'),
        _buildParagraph('By using DentPal, you represent and warrant that:'),
        _buildBulletList([
          'You have the legal capacity to use DentPal, or have valid consent from a parent or legal guardian',
          'You will use DentPal for lawful purposes only',
          'You are not located in any country or territory subject to international sanctions',
        ]),

        _buildSectionTitle('16. Fraudulent or Suspicious Activity'),
        _buildParagraph(
          'If DentPal reasonably believes that you may have engaged in any potentially fraudulent or suspicious activity, DentPal may take actions including closing, suspending, or limiting your access to your account.',
        ),

        _buildSectionTitle('17. Indemnity'),
        _buildParagraph(
          'You agree to indemnify, defend, and hold harmless DentPal and its shareholders, subsidiaries, affiliates, directors, officers, agents, partners, and employees from any claims arising from your use of DentPal services.',
        ),

        _buildSectionTitle('18. Severability'),
        _buildParagraph(
          'If any provision of these Terms is found to be unlawful, void, or unenforceable, that provision shall be deemed severable and shall not affect the validity of the remaining provisions.',
        ),

        _buildSectionTitle('19. Governing Law and Dispute Resolution'),
        _buildBulletList([
          'These Terms shall be governed by the laws of the Republic of the Philippines',
          'Any dispute shall first be attempted to be resolved amicably',
          'If not resolved amicably, disputes shall be resolved by arbitration administered by the Philippine Dispute Resolution Center, Inc. (PDRCI)',
          'The decision of the arbitrators shall be final and binding',
        ]),

        _buildSectionTitle('20. General Provisions'),
        _buildBulletList([
          'DentPal reserves all rights not expressly granted herein',
          'DentPal may modify these Terms at any time',
          'You may not assign or transfer any rights granted to you under these Terms',
          'Nothing in these Terms creates a partnership, joint venture, or agency relationship',
          'These Terms constitute the entire agreement between you and DentPal',
          'For questions, contact: support@dentpal.shop',
        ]),

        const SizedBox(height: 16),
        _buildLastUpdatedBox(),
      ],
    );
  }

  Widget _buildSellerTerms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('1. Introduction'),
        _buildSubSectionTitle('1.1 Welcome & Agreement'),
        _buildParagraph(
          'Welcome to DentPal, powered by R&R Newtech Dental Corporation (referred to as "DentPal," "we," "us," or "our"). Please read these Terms of Service carefully before using the DentPal Merchant Portal so that you understand your legal rights and obligations as a merchant. By accessing or using the Merchant Portal, you agree to be bound by these Terms of Service.',
        ),
        _buildSubSectionTitle('1.2 Scope of Services'),
        _buildParagraph('The DentPal Merchant Portal provides a platform for merchants to list, manage, and sell dental products and equipment. DentPal\'s services include:'),
        _buildBulletList([
          'Tools to create, update, and manage product listings',
          'Order management, including tracking, fulfillment, and shipping coordination',
          'Payment processing through supported payment channels',
          'Communication channels with account users for inquiries and support',
          'Access to analytics, reports, and other tools to monitor sales and performance',
          'Any additional features, services, or content made available through the Merchant Portal',
        ]),
        _buildParagraph(
          'Note: The actual contract for the purchase of products is directly between the account user and the merchant. DentPal is not a party to these contracts and does not assume responsibility for product quality, delivery, or any disputes.',
        ),
        _buildSubSectionTitle('1.3 Account Agreement & Data Consent'),
        _buildParagraph(
          'Before creating a merchant account or using the DentPal Merchant Portal, you must read and accept these Terms of Service in full. Merchants must provide accurate and complete information during registration and keep their account details up to date. You are responsible for all activity conducted under your account.',
        ),
        _buildSubSectionTitle('1.4 Platform Rights & Modifications'),
        _buildParagraph(
          'DentPal reserves the right to change, modify, suspend, or discontinue all or any part of the DentPal Merchant Portal or its services at any time, with or without notice, in accordance with Philippine law.',
        ),
        _buildSubSectionTitle('1.5 Account Refusal, Acceptance, and Age Requirement'),
        _buildParagraph(
          'DentPal reserves the right to refuse access to the Merchant Portal or to deny the creation of an account for any reason. If you are under the minimum legal age required to enter into an agreement in the Philippines, you must obtain permission from a parent or legal guardian.',
        ),

        _buildSectionTitle('2. Privacy'),
        _buildSubSectionTitle('2.1 User Privacy and Consent'),
        _buildParagraph('By using DentPal or providing information on the platform, you:'),
        _buildBulletList([
          'Consent to DentPal\'s collection, use, disclosure, and processing of your Content, personal data, and User Information',
          'Acknowledge that proprietary rights to your User Information are jointly owned by you and DentPal',
          'Agree not to disclose your User Information to any third party without DentPal\'s prior written consent',
        ]),
        _buildSubSectionTitle('2.2 Sharing of Data with Third-Party Partners'),
        _buildParagraph('User Information may be shared with trusted third-party service providers for:'),
        _buildBulletList([
          'Payment processing',
          'Order fulfillment and delivery',
          'Platform support services',
        ]),
        _buildSubSectionTitle('2.3 Handling of Other Users\' Personal Data'),
        _buildParagraph('If you obtain personal data of another account user through DentPal, you agree to:'),
        _buildBulletList([
          'Comply with all applicable personal data protection laws',
          'Allow the account user to request removal of their data from your records',
          'Allow the account user to review the personal information you have collected',
        ]),

        _buildSectionTitle('3. Limited License'),
        _buildSubSectionTitle('3.1 Access and Intellectual Property'),
        _buildParagraph(
          'DentPal grants you, the merchant, a limited and revocable license to access and use the Merchant Portal and its services. No right or license is granted to merchants to use, reproduce, or claim ownership of any Intellectual Property, except as expressly permitted for the purpose of using the Merchant Portal.',
        ),
        _buildSubSectionTitle('3.2 Linking to DentPal'),
        _buildParagraph(
          'Merchants may link to the Merchant Portal from their websites or online channels, provided the link does not imply any endorsement, partnership, or affiliation with DentPal.',
        ),

        _buildSectionTitle('4. Software'),
        _buildParagraph(
          'Any software provided by DentPal is subject to these Terms of Service. You may use the software solely for purposes of managing your merchant account, listings, and transactions through DentPal, and you agree not to reverse engineer, modify, distribute, or otherwise misuse the software.',
        ),

        _buildSectionTitle('5. Accounts and Security'),
        _buildSubSectionTitle('5.1 Account Registration'),
        _buildParagraph(
          'Some functions of DentPal require registration for a Merchant Account by selecting a unique User ID and password, and by providing certain personal and business information.',
        ),
        _buildSubSectionTitle('5.2 Account Security Responsibilities'),
        _buildParagraph('As a merchant, you agree to:'),
        _buildBulletList([
          'Keep your password and login credentials confidential',
          'Log out from your Merchant Account at the end of each session',
          'Immediately notify DentPal of any unauthorized use of your Merchant Account',
          'Ensure that your Merchant Account information is accurate and up-to-date',
        ]),
        _buildSubSectionTitle('5.3 DentPal\'s Right to Suspend or Terminate Merchant Accounts'),
        _buildParagraph('Grounds for suspension or termination may include:'),
        _buildBulletList([
          'Extended periods of inactivity',
          'Violation of these Terms of Service',
          'Illegal, fraudulent, harassing, defamatory, threatening, or abusive behavior',
          'Maintaining multiple Merchant Accounts without authorization',
          'Abnormal or excessive transaction activity',
          'Misuse or abuse of vouchers, promotions, or platform features',
          'Failure to fulfill orders or make timely payments for transactions',
          'Use of unauthorized third-party software or tools',
          'Failure to comply with applicable tax, verification, or regulatory requirements',
        ]),
        _buildSubSectionTitle('5.4 Merchant-Initiated Account Termination'),
        _buildParagraph(
          'You may terminate your Account by sending a written request to support@dentpal.shop from your registered email address. Your Account will be terminated within 24 hours after DentPal receives the request.',
        ),
        _buildSubSectionTitle('5.5 Geographic Restrictions'),
        _buildParagraph(
          'You may only use the DentPal Merchant Portal and its Services if you are located in areas where DentPal and its logistics partners operate.',
        ),

        _buildSectionTitle('6. Term of Use and Prohibited Conduct'),
        _buildSubSectionTitle('6.1 Term of Use'),
        _buildParagraph(
          'The license to use the DentPal Merchant Portal and Services is effective until terminated. DentPal may terminate this license for non-compliance with these Terms.',
        ),
        _buildSubSectionTitle('6.2 Prohibited Activities'),
        _buildParagraph('As a merchant, you agree not to:'),
        _buildBulletList([
          'Upload or transmit Content that is unlawful, harmful, threatening, abusive, harassing, obscene, defamatory, or otherwise objectionable',
          'Violate any laws, including export/import restrictions or DentPal\'s Prohibited and Restricted Items Policy',
          'Impersonate others or submit false verification documents',
          'Manipulate pricing, inventory, or interfere with other merchants\' listings',
          'Undermine feedback, rating, or review systems',
          'Reverse engineer, hack, or bypass security of DentPal Services',
          'Collect unauthorized data on account users or other merchants',
          'Transmit viruses, malware, or harmful software',
          'List items infringing third-party intellectual property or prohibited items',
        ]),
        _buildSubSectionTitle('6.3 Responsibility for Content'),
        _buildParagraph(
          'You are solely responsible for all Content you upload, transmit, or share on the Merchant Portal, including product listings, descriptions, and images.',
        ),

        _buildSectionTitle('7. Violation of Terms of Service'),
        _buildSubSectionTitle('7.1 Consequences of Violations'),
        _buildParagraph('Violations may result in:'),
        _buildBulletList([
          'Limits or restrictions placed on your account privileges',
          'Suspension or termination of your Merchant Portal account',
          'Referral to appropriate authorities for criminal investigation',
          'Civil actions, including claims for damages',
          'Cancellation or suspension of any transactions',
        ]),
        _buildSubSectionTitle('7.2 Reporting Violations'),
        _buildParagraph(
          'If you believe another merchant or account user is violating these Terms of Service, please contact DentPal at support@dentpal.shop.',
        ),

        _buildSectionTitle('8. Reporting Intellectual Property Rights Infringement'),
        _buildSubSectionTitle('8.1 Respect for Intellectual Property'),
        _buildParagraph(
          'Merchants may not upload, submit, or share content, product listings, or other materials that infringe on the intellectual property rights of brands, manufacturers, or other rights holders.',
        ),
        _buildSubSectionTitle('8.4 Required Information for Complaints'),
        _buildParagraph('Complaints must include:'),
        _buildBulletList([
          'A physical or electronic signature of the IPR Owner or IPR Agent',
          'A description of the intellectual property right allegedly infringed',
          'A description of the alleged infringement with sufficient detail',
          'Sufficient contact information for the Informant',
          'A statement that the complaint is filed in good faith',
          'A statement that the information is accurate',
        ]),
        _buildSubSectionTitle('8.6 Merchant Indemnification'),
        _buildParagraph(
          'Merchants agree to indemnify and hold DentPal harmless from any claims, damages, or judgments arising from intellectual property infringement or content removal.',
        ),

        _buildSectionTitle('9. Payment and Pickup'),
        _buildSubSectionTitle('9.1 Payment Methods'),
        _buildParagraph('Payments may be processed through:'),
        _buildBulletList([
          'Cash on Delivery (COD)',
          'Credit/Debit Cards',
          'Online Payment Wallets',
          'Buy Now, Pay Later (BNPL)',
          'Check Payments (Coverage Limited to Logistics Partners)',
        ]),
        _buildSubSectionTitle('9.2 Payment Responsibilities'),
        _buildParagraph(
          'Merchants are responsible for ensuring that the payment details they provide to DentPal for receiving payouts are accurate and up to date.',
        ),
        _buildSubSectionTitle('9.3 Transaction Accuracy'),
        _buildParagraph(
          'Merchants must ensure that product pricing and shipping information submitted to DentPal are accurate.',
        ),
        _buildSubSectionTitle('9.4 Pickup Schedule'),
        _buildParagraph(
          'All product pickups from the merchant\'s registered address will be scheduled daily between 9:00 AM to 2:00 PM. Merchants must ensure that parcels are properly packed and ready for pickup within the specified timeframe.',
        ),

        _buildSectionTitle('10. Returns and Order Cancellations'),
        _buildSubSectionTitle('10.1 Returns & Refunds'),
        _buildParagraph(
          'Merchants may approve or deny return or refund requests at their sole discretion. Return and refund requests must be submitted and approved before 5:00 PM on Wednesday of the applicable payout week.',
        ),
        _buildParagraph(
          'DentPal is not responsible for managing, funding, or reimbursing any returns or refunds, nor for any fees, delays, or disputes arising from them.',
        ),
        _buildSubSectionTitle('10.2 Order Cancellations'),
        _buildParagraph(
          'Merchants may cancel an order at any time prior to arranging shipment. Merchants are solely responsible for any fees, refunds, or costs associated with such cancellations.',
        ),

        _buildSectionTitle('11. Payouts'),
        _buildSubSectionTitle('11.1 Overview'),
        _buildParagraph(
          'Payouts represent the funds you receive from completed sales, net of any automatic payouts, refunds, fees, or other applicable adjustments.',
        ),
        _buildSubSectionTitle('11.3 Payout Timing'),
        _buildParagraph('Clearing schedules vary by payment method:'),
        _buildDataTable([
          ['Cash on Delivery (COD)', '7 banking days'],
          ['VISA / Mastercard', '3 banking days'],
          ['E-wallets (GCash, GrabPay, Maya, ShopeePay)', '2 banking days'],
          ['BPI and UBP Online Banking', '1 banking day'],
          ['QR Ph', '1 banking day'],
          ['BillEase', '1 banking day'],
        ]),
        _buildSubSectionTitle('11.4 Inclusion in Weekly Payouts'),
        _buildParagraph(
          'For payments to be included in the current week\'s payout cycle, such payments must be fully cleared by 5:00 PM on Wednesday of that week.',
        ),
        _buildSubSectionTitle('11.5 Payout Processing and Reflection'),
        _buildParagraph(
          'Transfers are typically initiated on Wednesday and may reflect in the merchant\'s registered bank account on the same day. However, actual crediting may take an additional one (1) to two (2) banking days.',
        ),
        _buildSubSectionTitle('11.7 Fees'),
        _buildParagraph(
          'Merchants are responsible for fees associated with refunds, returns, transfers, or transaction disputes.',
        ),

        _buildSectionTitle('12. Delivery'),
        _buildSubSectionTitle('12.1 Notification of Payment Received'),
        _buildParagraph(
          'DentPal will notify the Merchant when account user payment is received. Merchants must arrange delivery of the purchased item to the account user.',
        ),
        _buildSubSectionTitle('12.3 Delivery Arrangements'),
        _buildParagraph(
          'Merchants must arrange delivery of purchased items to account users using a Logistics Service Provider. DentPal facilitates communication but does not itself deliver items.',
        ),
        _buildSubSectionTitle('12.6 Limitation of DentPal\'s Responsibility'),
        _buildParagraph(
          'DentPal is not responsible for delivery delays, lost or damaged items, or disputes with the Logistics Service Provider.',
        ),

        _buildSectionTitle('13. Merchant\'s Responsibilities'),
        _buildSubSectionTitle('13.1 Accurate Product Information'),
        _buildParagraph(
          'Merchants must properly manage and ensure that relevant information such as pricing, product details, inventory, and sales terms are accurate and updated on their listings.',
        ),
        _buildSubSectionTitle('13.2 Product Pricing'),
        _buildParagraph(
          'Merchants set the price of products at their own discretion. Product prices and shipping charges must include all applicable taxes, tariffs, and fees.',
        ),
        _buildSubSectionTitle('13.3 Invoicing'),
        _buildParagraph('Merchants shall issue invoices to Account users as required.'),
        _buildSubSectionTitle('13.4 Taxes and Duties'),
        _buildParagraph(
          'Merchants are responsible for all taxes, customs, and duties associated with products sold.',
        ),

        _buildSectionTitle('14. Fees'),
        _buildSubSectionTitle('14.1 Transaction Fees'),
        _buildParagraph(
          'Merchants are responsible for all transaction fees arising from Account user payments. The fee depends on the Account user\'s selected payment method and is automatically deducted from the Merchant\'s Payout Balance.',
        ),
        _buildSubSectionTitle('14.2 Logistics Fees'),
        _buildParagraph(
          'Shipping fees are allocated between the Account user and the Merchant based on DentPal\'s Logistics Fee Rules.',
        ),
        _buildSubSectionTitle('14.3 Platform and Marketing Fees'),
        _buildParagraph(
          'DentPal may charge platform service fees, commissions, and marketing or promotional fees for the use of the DentPal platform or participation in DentPal-run campaigns.',
        ),

        _buildSectionTitle('15. Disputes'),
        _buildSubSectionTitle('15.1 Direct Resolution'),
        _buildParagraph(
          'Merchants should attempt to resolve any issues or complaints directly with the account user before involving DentPal.',
        ),
        _buildSubSectionTitle('15.4 Limitation of Liability'),
        _buildParagraph(
          'Merchants agree that DentPal shall not be held liable for any loss, damages, or claims arising from transactions with account users.',
        ),

        _buildSectionTitle('16. Feedback and Product Reviews'),
        _buildSubSectionTitle('16.1 Product Reviews'),
        _buildBulletList([
          'Only account users who have purchased a merchant\'s product through DentPal may submit feedback or reviews',
          'DentPal may remove reviews that are defamatory, inappropriate, or violate applicable laws',
          'Account users grant DentPal a non-exclusive, worldwide, royalty-free license to display and use feedback or reviews',
        ]),

        _buildSectionTitle('17. Disclaimers'),
        _buildSubSectionTitle('17.1 "As Is" Services'),
        _buildParagraph(
          'DentPal provides its platform and services on an "AS IS" and "AS AVAILABLE" basis. DentPal makes no warranties, expressed or implied.',
        ),
        _buildSubSectionTitle('17.4 Assumption of Risk'),
        _buildParagraph(
          'Merchants acknowledge and accept that the risk of using DentPal, including listing products, processing transactions, and relying on platform information, rests entirely with them.',
        ),

        _buildSectionTitle('18. Exclusions and Limitations of Liability'),
        _buildSubSectionTitle('18.1 No Liability for Certain Damages'),
        _buildParagraph(
          'To the maximum extent permitted by law, DentPal shall not be liable for any indirect, incidental, special, or consequential damages.',
        ),
        _buildSubSectionTitle('18.3 Maximum Liability'),
        _buildParagraph(
          'If DentPal is found legally liable (including for gross negligence), its liability is limited to the lesser of any amounts payable under applicable DentPal guarantees or PHP 4,000.00.',
        ),

        _buildSectionTitle('19. Representations and Warranties'),
        _buildParagraph('By using the DentPal Merchant Portal, you represent and warrant that:'),
        _buildBulletList([
          'You have the legal capacity and authority to operate as a merchant',
          'You will use DentPal for lawful commercial purposes only',
          'You are not located in any country or territory subject to international sanctions',
          'You have all necessary rights and permissions to sell the products listed',
          'Your business, products, and services comply with all applicable laws and regulations',
        ]),

        _buildSectionTitle('20. Fraudulent or Suspicious Activity'),
        _buildParagraph(
          'If DentPal reasonably believes that you may have engaged in any potentially fraudulent or suspicious activity, DentPal may take actions including closing, suspending, or limiting your access to your Merchant Account.',
        ),

        _buildSectionTitle('21. Indemnity'),
        _buildParagraph(
          'As a merchant, you agree to indemnify, defend, and hold harmless DentPal and its shareholders, subsidiaries, affiliates, directors, officers, agents, partners, and employees from any claims arising from your use of DentPal services.',
        ),

        _buildSectionTitle('22. Severability'),
        _buildParagraph(
          'If any provision of these Terms is found to be unlawful, void, or unenforceable, that provision shall be deemed severable and shall not affect the validity of the remaining provisions.',
        ),

        _buildSectionTitle('23. Governing Law and Dispute Resolution'),
        _buildBulletList([
          'These Terms shall be governed by the laws of the Republic of the Philippines',
          'Any dispute shall first be attempted to be resolved amicably',
          'If not resolved amicably, disputes shall be resolved by arbitration administered by the Philippine Dispute Resolution Center, Inc. (PDRCI)',
          'The decision of the arbitrators shall be final, binding, and enforceable',
        ]),

        _buildSectionTitle('24. General Provisions'),
        _buildBulletList([
          'DentPal reserves all rights not expressly granted herein',
          'DentPal may modify these Terms of Service at any time',
          'You may not assign, sublicense, or transfer any rights granted to you under these Terms',
          'Nothing in these Terms creates a partnership, joint venture, or agency relationship',
          'These Terms constitute the entire agreement between you and DentPal',
          'For questions, contact DentPal at: support@dentpal.shop',
        ]),

        const SizedBox(height: 16),
        _buildLastUpdatedBox(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSubSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: AppTextStyles.titleSmall.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          height: 1.6,
          color: AppColors.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildBulletList(List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: AppTextStyles.bodyMedium.copyWith(
                          height: 1.5,
                          color: AppColors.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDataTable(List<List<String>> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return Container(
              decoration: BoxDecoration(
                color: index % 2 == 0
                    ? AppColors.surface
                    : AppColors.background,
                border: index < rows.length - 1
                    ? Border(
                        bottom: BorderSide(
                          color: AppColors.onSurface.withValues(alpha: 0.1),
                        ),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        row[0],
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        row[1],
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLastUpdatedBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact Information',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'For any questions regarding these terms and conditions, please contact us at support@dentpal.shop or visit our support center.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
