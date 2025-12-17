import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import 'package:dentpal/utils/app_logger.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
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
            Icon(Icons.shield_outlined, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Privacy Policy',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                      ? _buildSellerPrivacyPolicy()
                      : _buildBuyerPrivacyPolicy(),
                ),
              ),
            ),
    );
  }

  Widget _buildBuyerPrivacyPolicy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('1. Introduction'),
        _buildSubSectionTitle('1.1 Welcome to DentPal'),
        _buildParagraph(
          'Welcome to DentPal, powered by R&R Newtech Dental Corporation ("DentPal", "we", "us", or "our"). DentPal respects your privacy and is committed to protecting the personal data of all account users ("Account Users", "you", or "your") who register for an account or use our mobile application and related services ("Services").\n\nThis Privacy Policy explains how we collect, use, store, and disclose your personal data. By using DentPal, you consent to this Policy and our data practices.',
        ),
        _buildSubSectionTitle('1.2 Definition of Personal Data'),
        _buildParagraph(
          '"Personal Data" means any information that can directly or indirectly identify you, including your name, contact details, shipping information, and any data you provide while using the app.',
        ),
        _buildSubSectionTitle('1.3 Consent and Acceptance'),
        _buildParagraph(
          'By creating an account or using DentPal, you acknowledge that you have read and accepted this Privacy Policy. If you do not agree, stop using the Services immediately. Continued use constitutes acceptance of this Policy, including any updates.',
        ),
        _buildSubSectionTitle('1.4 Relationship with Other Notices'),
        _buildParagraph(
          'This Privacy Policy works alongside other notices, agreements, or consent forms related to your personal data. It does not replace them unless expressly stated.',
        ),
        _buildSubSectionTitle('1.5 Applicability'),
        _buildParagraph(
          'This Policy applies to all DentPal account users, including both account users and merchants, unless otherwise specified.',
        ),

        _buildSectionTitle('2. Collection of Personal Data'),
        _buildSubSectionTitle('2.1 When We Collect Your Data'),
        _buildParagraph('We may collect personal data when you:'),
        _buildBulletList([
          'Register for an account',
          'Use the Services',
          'Submit forms or documents',
          'Interact with customer support',
          'Carry out orders, payments, or refunds',
          'Use the mobile app (including device permissions and cookies)',
          'Link social media accounts',
          'Provide feedback, participate in surveys, or join promotions',
          'Submit any data while using the platform',
        ]),
        _buildSubSectionTitle('2.2 Data From Third Parties'),
        _buildParagraph('We may obtain personal data from:'),
        _buildBulletList([
          'Payment processors',
          'Courier or logistics partners',
          'Business or marketing partners',
          'Other DentPal users',
          'Public or government sources',
        ]),
        _buildSubSectionTitle('2.3 Personal Data of Others'),
        _buildParagraph(
          'If you provide DentPal with personal data of other individuals (e.g., recipients), you confirm that you have obtained their consent for DentPal to process their data in accordance with this Privacy Policy.',
        ),

        _buildSectionTitle('3. Types of Personal Data Collected'),
        _buildSubSectionTitle('3.1 Categories'),
        _buildParagraph('DentPal may collect:'),
        _buildBulletList([
          'Name',
          'Email address',
          'Date of birth',
          'Billing and/or delivery address',
          'Bank account and payment information',
          'Telephone number',
          'Gender',
          'Information sent by or associated with the device(s) used to access our Services or Platform',
          'Information about your network and the people and accounts you interact with',
          'Photographs or audio or video recordings',
          'Government issued identification or other information required for our due diligence, know your customer, identity verification, or fraud prevention purposes',
          'Marketing and communications data',
          'Usage and transaction data',
          'Location data',
          'Which mobile applications you have installed',
          'Any other information about the User when the User signs up to use our Services or Platform',
          'Aggregate data on content the User engages with',
        ]),
        _buildSubSectionTitle('3.2 Accuracy'),
        _buildParagraph(
          'You agree to submit accurate information and notify DentPal of any changes. DentPal may request documentation to verify data.',
        ),
        _buildSubSectionTitle('3.3 Social Media Integration'),
        _buildParagraph(
          'If you link a social media account, DentPal may access information shared with that platform, subject to their policies.',
        ),
        _buildSubSectionTitle('3.4 Opting Out'),
        _buildParagraph(
          'You may request to opt out of certain data collection via our Data Protection Officer (DPO). Some features, such as location-based delivery, may become unavailable.',
        ),

        _buildSectionTitle('4. Device, Usage, and Location Data'),
        _buildSubSectionTitle('4.1 Device & Usage Information'),
        _buildParagraph('Your device may send:'),
        _buildBulletList([
          'IP address',
          'Device type, OS, browser version',
          'Mobile device identifiers',
          'Referring website address',
          'Screens/pages viewed',
          'Dates and times of visits',
        ]),
        _buildSubSectionTitle('4.2 Location Data'),
        _buildParagraph('Collected for:'),
        _buildBulletList([
          'Delivery estimates',
          'Location-based features',
          'Content personalization',
        ]),
        _buildParagraph(
          'You may disable location access via device settings, but some Services may not function properly.',
        ),
        _buildSubSectionTitle('4.3 Content & Interaction Data'),
        _buildParagraph('We may collect:'),
        _buildBulletList([
          'Content viewed',
          'Time spent on features',
          'Ads interacted with',
          'Relevant device-based app data required for functionality',
        ]),

        _buildSectionTitle('5. Cookies & Similar Technologies'),
        _buildSubSectionTitle('5.1 Use of Cookies'),
        _buildParagraph('DentPal and authorized partners may use cookies to:'),
        _buildBulletList([
          'Improve app functionality',
          'Personalize content',
          'Remember preferences',
          'Analyze usage patterns',
          'Support performance and security',
        ]),
        _buildSubSectionTitle('5.2 Managing Cookies'),
        _buildParagraph(
          'You may disable cookies via device or browser settings. Some features may not function if cookies are disabled.',
        ),

        _buildSectionTitle('6. Purpose of Personal Data Collection'),
        _buildDataTable([
          ['Account & Verification', 'Create, maintain, verify accounts, prevent fraud'],
          ['Transactions', 'Process orders, payments, refunds, delivery'],
          ['Customer Support', 'Respond to inquiries, resolve disputes'],
          ['Marketing', 'Send promotions, surveys (with opt-out)'],
          ['Analytics', 'Improve app, analyze usage, research trends'],
          ['Legal & Compliance', 'Comply with laws, audits, investigations'],
          ['Business Continuity', 'Hosting, backups, corporate transactions'],
        ]),

        _buildSectionTitle('7. Data Security and Retention'),
        _buildSubSectionTitle('7.1 Security Measures'),
        _buildParagraph('DentPal uses administrative, technical, and physical safeguards, including:'),
        _buildBulletList([
          'Encryption of sensitive data',
          'Access controls and regular audits',
          'Secure storage of servers and backups',
        ]),
        _buildParagraph(
          'No system is fully secure, but reasonable steps are taken to prevent unauthorized access.',
        ),
        _buildSubSectionTitle('7.2 Retention Periods'),
        _buildDataTable([
          ['Account & Transaction', '5 years after account closure'],
          ['Fraud Prevention / Analytics', 'Up to 3 years'],
          ['Legal / Regulatory Compliance', 'As required by law'],
          ['Marketing / Cookies / Analytics', 'Up to 2 years or until opt-out'],
        ]),
        _buildParagraph(
          'Data is anonymized or securely deleted when no longer required.',
        ),

        _buildSectionTitle('8. Disclosure of Personal Data'),
        _buildParagraph('DentPal may share your data with:'),
        _buildBulletList([
          'Subsidiaries or affiliates',
          'Merchants or account users you transact with',
          'Other users to fulfill transactions',
          'Logistics, couriers, and payment processors',
          'IT, cloud, marketing, analytics, or customer support providers',
          'Government authorities if required by law',
          'Corporate successors in mergers or acquisitions',
        ]),
        _buildSubSectionTitle('8.2 Analytics & Advertising'),
        _buildParagraph(
          'Anonymized or aggregated data may be shared; personal identification is not disclosed.',
        ),
        _buildSubSectionTitle('8.3 Legal Disclosures'),
        _buildParagraph(
          'Data may be disclosed to comply with laws, regulations, or legitimate interests.',
        ),
        _buildSubSectionTitle('8.4 Third-Party Integrations'),
        _buildParagraph(
          'External platforms follow their own privacy policies; DentPal is not responsible for their practices.',
        ),
        _buildSubSectionTitle('8.5 Merchant Obligations'),
        _buildParagraph('Merchants must:'),
        _buildBulletList([
          'Use account users data only for fulfilling orders',
          'Not contact account user outside DentPal',
          'Not share account users data without consent',
          'Securely store and delete data upon request',
          'Notify DentPal immediately of breaches',
        ]),

        _buildSectionTitle('9. Children\'s Privacy'),
        _buildParagraph(
          'DentPal is not intended for children under 13. We do not knowingly collect data from children under 13. If discovered, such data will be deleted unless parental consent is provided. Parents or guardians can provide consent by contacting our DPO.',
        ),

        _buildSectionTitle('10. Third-Party Tools'),
        _buildParagraph(
          'DentPal uses analytics tools (e.g., Google Analytics) that may collect usage data, device information, and IP addresses. Data may be stored outside the Philippines. Third parties may share data when required by law.',
        ),

        _buildSectionTitle('11. Overseas Data Transfers'),
        _buildParagraph(
          'Your personal data may be transferred to countries outside the Philippines. DentPal ensures compliance with applicable international data protection laws and safeguards.',
        ),

        _buildSectionTitle('12. User Rights'),
        _buildSubSectionTitle('12.1 Access, Correction, and Deletion'),
        _buildParagraph(
          'You may request access, correction, deletion, or portability of your personal data via your account or DPO. Verification may be required. A reasonable administrative fee may apply.',
        ),
        _buildSubSectionTitle('12.2 Withdrawing Consent'),
        _buildParagraph(
          'You may withdraw consent at any time by contacting the DPO:\n📧 dpo@dentpal.shop\n\nWithdrawal may limit certain Services or result in account suspension/termination.',
        ),
        _buildSubSectionTitle('12.3 Other Rights'),
        _buildParagraph('Depending on applicable laws, you may also:'),
        _buildBulletList([
          'Object to processing',
          'Request restriction of processing',
          'Request erasure ("right to be forgotten")',
          'Request data portability',
        ]),

        _buildSectionTitle('13. Changes to Privacy Policy'),
        _buildParagraph(
          'We may update this Privacy Policy. Users will be notified via app updates, emails, or website notices. Continued use constitutes acceptance of changes.',
        ),

        _buildSectionTitle('14. Questions or Complaints'),
        _buildParagraph(
          'For questions or complaints regarding this Privacy Policy, contact:\n📧 dpo@dentpal.shop\n📍 R&R Newtech Dental Corporation\n\nDentPal will respond in accordance with applicable laws and within a reasonable timeframe.',
        ),

        const SizedBox(height: 16),
        _buildContactBox(),
      ],
    );
  }

  Widget _buildSellerPrivacyPolicy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('1. Introduction'),
        _buildSubSectionTitle('1.1 Welcome to DentPal'),
        _buildParagraph(
          'Welcome to DentPal, powered by R&R Newtech Dental Corporation ("DentPal," "we," "us," or "our"). DentPal respects your privacy and is committed to protecting the personal and business data of all registered merchants ("Merchants," "you," or "your") who create a merchant account or use our web application and related services ("Services").\n\nThis Privacy Policy explains how we collect, use, store, and disclose your personal and business data. By using DentPal, you consent to this Policy and our data practices.',
        ),
        _buildSubSectionTitle('1.2 Definition of Personal and Business Data'),
        _buildParagraph(
          'Personal Data: Information that can directly or indirectly identify you, such as name, email, phone number, and identification documents.\n\nBusiness Data: Information about your business or products, such as business name, tax identification number, bank account details, product listings, and sales data.',
        ),
        _buildSubSectionTitle('1.3 Consent and Acceptance'),
        _buildParagraph(
          'By creating a merchant account or using DentPal, you acknowledge that you have read and accepted this Privacy Policy. If you do not agree, stop using the Services immediately. Continued use constitutes acceptance of this Policy, including any updates.',
        ),
        _buildSubSectionTitle('1.4 Relationship with Other Notices'),
        _buildParagraph(
          'This Privacy Policy works alongside other notices, agreements, or consent forms related to your personal or business data. It does not replace them unless expressly stated.',
        ),
        _buildSubSectionTitle('1.5 Applicability'),
        _buildParagraph(
          'This Policy applies to all DentPal merchants, unless otherwise specified.',
        ),

        _buildSectionTitle('2. Collection of Personal and Business Data'),
        _buildSubSectionTitle('2.1 When We Collect Your Data'),
        _buildParagraph('We may collect personal and business data when you:'),
        _buildBulletList([
          'Register for a merchant account',
          'Upload product listings, pricing, or inventory information',
          'Submit forms or documents for verification or compliance',
          'Interact with customer support',
          'Receive checks, process payments, or manage refunds',
          'Link social media or business accounts',
          'Provide feedback, participate in surveys, or join promotions',
          'Submit any other data while using the platform',
        ]),
        _buildSubSectionTitle('2.2 Data from Third Parties'),
        _buildParagraph('We may obtain data from:'),
        _buildBulletList([
          'Payment processors',
          'Logistics or courier partners',
          'Business or marketing partners',
          'Other DentPal users',
          'Public or government sources',
        ]),
        _buildSubSectionTitle('2.2 Data Obtained from Third Parties'),
        _buildParagraph(
          'To operate the platform effectively and comply with legal and commercial obligations, we may receive information relating to merchants from third parties. Such data is obtained only where necessary and may include information from:',
        ),
        _buildBulletList([
          'Payment processors – transaction confirmations, payout status, refunds, chargebacks, dispute records, and fraud-related signals',
          'Logistics or courier partners – shipping status, pickup and delivery confirmations, failed delivery reports, and logistics performance data',
          'Business or marketing partners – referral information, campaign attribution data, and co-marketing performance metrics',
          'Customers or other platform users – reviews, ratings, communications, dispute reports, or other interactions involving the merchant',
          'Public or government sources – business registration records, licenses, tax or compliance-related information, and other legally accessible public records',
        ]),
        _buildParagraph(
          'Data obtained from third parties is used strictly for purposes such as payment processing, order fulfillment, fraud prevention, compliance with legal requirements, dispute resolution, and general platform operations. We do not collect third-party data beyond what is reasonably necessary for these purposes.',
        ),
        _buildSubSectionTitle('2.3 Personal Data of Others'),
        _buildParagraph(
          'If you provide DentPal with personal data of other individuals (e.g., employees or customers), you confirm that you have obtained their consent for DentPal to process their data in accordance with this Privacy Policy.',
        ),

        _buildSectionTitle('3. Types of Data Collected'),
        _buildSubSectionTitle('3.1 Personal Data'),
        _buildParagraph('The personal data that DentPal may collect includes but is not limited to:'),
        _buildBulletList([
          'Name',
          'Email address',
          'Date of birth',
          'Billing and/or delivery address',
          'Bank account and payment information',
          'Telephone number',
          'Gender',
          'Information sent by or associated with the device(s) used to access our Services or Platform',
          'Information about your network and the people and accounts you interact with',
          'Photographs or audio or video recordings',
          'Government issued identification or other information required for our due diligence, know your customer, identity verification, or fraud prevention purposes',
          'Marketing and communications data',
          'Usage and transaction data',
          'Location data',
          'Which mobile applications you have installed',
          'Any other information about the User when the User signs up to use our Services or Platform',
          'Aggregate data on content the User engages with',
        ]),
        _buildSubSectionTitle('3.2 Additional Merchant Data'),
        _buildParagraph('Additional data collected from merchants includes but is not limited to:'),
        _buildBulletList([
          'Company Name',
          'Address',
          'Customer Service Contact Person',
          'Landline Number',
          'Mobile Number',
          'Email Address',
          'Website',
          'TIN Number',
          'Payment / Banking Information',
          'Bank Branch Address',
          'Merchant Agreement / Contract',
          'SEC Certificate or DTI Registration',
          'BIR Certificate of Registration (Form 2303)',
          'FDA LTO for Medical Devices (if applicable)',
          'Catalogue / Product Lists',
          'Warranty / After-Sales Policy',
        ]),
        _buildSubSectionTitle('3.3 Accuracy'),
        _buildParagraph(
          'You agree to submit accurate information and notify DentPal of any changes. DentPal may request documentation to verify data.',
        ),
        _buildSubSectionTitle('3.4 Social Media / Business Account Integration'),
        _buildParagraph(
          'If you link social media or business accounts, DentPal may access information shared with those platforms, subject to their policies.',
        ),
        _buildSubSectionTitle('3.5 Opting Out'),
        _buildParagraph(
          'You may request to opt out of certain data collection via our Data Protection Officer (DPO). Some Services, including order fulfillment or analytics features, may become unavailable.\n📧 dpo@dentpal.shop',
        ),

        _buildSectionTitle('4. Device, Usage, and Location Data'),
        _buildSubSectionTitle('4.1 Device & Usage Information'),
        _buildParagraph('Your device may send:'),
        _buildBulletList([
          'IP address',
          'Device type, OS, browser version',
          'Mobile device identifiers',
          'Referring website address',
          'Screens/pages viewed',
          'Dates and times of visits',
        ]),
        _buildSubSectionTitle('4.2 Location Data'),
        _buildParagraph('Collected for:'),
        _buildBulletList([
          'Delivery estimates',
          'Location-based features',
          'Content personalization',
        ]),
        _buildParagraph(
          'You may disable location access via device settings, but some Services may not function properly.',
        ),
        _buildSubSectionTitle('4.3 Content & Interaction Data'),
        _buildParagraph('We may collect:'),
        _buildBulletList([
          'Product or content viewed',
          'Time spent on features',
          'Ads interacted with',
          'Relevant device-based app data required for functionality',
        ]),

        _buildSectionTitle('5. Cookies & Similar Technologies'),
        _buildSubSectionTitle('5.1 Use of Cookies'),
        _buildParagraph('DentPal and authorized partners may use cookies to:'),
        _buildBulletList([
          'Improve app functionality',
          'Personalize content',
          'Remember preferences',
          'Analyze usage patterns',
          'Support performance and security',
        ]),
        _buildSubSectionTitle('5.2 Managing Cookies'),
        _buildParagraph(
          'You may disable cookies via device or browser settings. Some features may not function if cookies are disabled.',
        ),

        _buildSectionTitle('6. Purpose of Data Collection'),
        _buildDataTable([
          ['Account & Verification', 'Create, maintain, verify accounts, prevent fraud'],
          ['Transactions & Orders', 'Process payments, fulfill orders, manage refunds, logistics'],
          ['Customer Support', 'Respond to inquiries, resolve disputes'],
          ['Marketing', 'Send promotions, surveys (with opt-out)'],
          ['Analytics', 'Improve app, analyze merchant performance, research trends'],
          ['Legal & Compliance', 'Comply with laws, audits, investigations'],
          ['Business Continuity', 'Hosting, backups, corporate transactions'],
        ]),

        _buildSectionTitle('7. Data Security and Retention'),
        _buildSubSectionTitle('7.1 Security Measures'),
        _buildParagraph('DentPal uses administrative, technical, and physical safeguards, including:'),
        _buildBulletList([
          'Encryption of sensitive data',
          'Access controls and regular audits',
          'Secure storage of servers and backups',
        ]),
        _buildParagraph(
          'No system is fully secure, but reasonable steps are taken to prevent unauthorized access.',
        ),
        _buildSubSectionTitle('7.2 Retention Periods'),
        _buildDataTable([
          ['Account & Transaction', '5 years after account closure'],
          ['Fraud Prevention / Analytics', 'Up to 3 years'],
          ['Legal / Regulatory Compliance', 'As required by law'],
          ['Marketing / Cookies / Analytics', 'Up to 2 years or until opt-out'],
        ]),
        _buildParagraph(
          'Data is anonymized or securely deleted when no longer required.',
        ),
        _buildSubSectionTitle('7.3 Data Breach Notification'),
        _buildParagraph(
          'DentPal will notify affected merchants without undue delay if personal or business data is compromised, in accordance with applicable laws.',
        ),

        _buildSectionTitle('8. Disclosure of Data'),
        _buildSubSectionTitle('8.1 Service Providers'),
        _buildParagraph('DentPal may share your data with:'),
        _buildBulletList([
          'Subsidiaries or affiliates',
          'Account users or users for transaction fulfillment',
          'Logistics, couriers, and payment processors',
          'IT, cloud, marketing, analytics, or customer support providers',
          'Government authorities if required by law',
          'Corporate successors in mergers or acquisitions',
        ]),
        _buildSubSectionTitle('8.2 Analytics & Advertising'),
        _buildParagraph(
          'Anonymized or aggregated data may be shared; personal or business identification is not disclosed.',
        ),
        _buildSubSectionTitle('8.3 Legal Disclosures'),
        _buildParagraph(
          'Data may be disclosed to comply with laws, regulations, or legitimate interests.',
        ),
        _buildSubSectionTitle('8.4 Third-Party Integrations'),
        _buildParagraph(
          'External platforms follow their own privacy policies; DentPal is not responsible for their practices but ensures reasonable safeguards are implemented.',
        ),
        _buildSubSectionTitle('8.5 Merchants Obligations'),
        _buildParagraph('Merchants must:'),
        _buildBulletList([
          'Use account user data only for fulfilling orders',
          'Not contact account users outside DentPal',
          'Not share account user data without consent',
          'Securely store and delete data upon request',
          'Notify DentPal immediately of breaches',
        ]),

        _buildSectionTitle('9. Children\'s Privacy'),
        _buildParagraph(
          'DentPal is not intended for children under 13. We do not knowingly collect data from children under 13. If discovered, such data will be deleted unless parental consent is provided.',
        ),

        _buildSectionTitle('10. Third-Party Tools'),
        _buildParagraph(
          'DentPal uses analytics tools (e.g., Google Analytics) that may collect usage data, device information, and IP addresses. Data may be stored outside the Philippines. Third parties may share data when required by law.',
        ),

        _buildSectionTitle('11. Overseas Data Transfers'),
        _buildParagraph(
          'Your personal or business data may be transferred to countries outside the Philippines. DentPal ensures compliance with applicable international data protection laws and safeguards.',
        ),

        _buildSectionTitle('12. Merchant Rights'),
        _buildSubSectionTitle('12.1 Access, Correction, and Deletion'),
        _buildParagraph(
          'You may request access, correction, deletion, or portability of your personal or business data via your account or DPO. Verification may be required. A reasonable administrative fee may apply.',
        ),
        _buildSubSectionTitle('12.2 Withdrawing Consent'),
        _buildParagraph(
          'You may withdraw consent at any time by contacting the DPO:\n📧 dpo@dentpal.shop\n\nWithdrawal may limit certain Services or result in account suspension/termination.',
        ),
        _buildSubSectionTitle('12.3 Other Rights'),
        _buildParagraph('Depending on applicable laws, you may also:'),
        _buildBulletList([
          'Object to processing',
          'Request restriction of processing',
          'Request erasure ("right to be forgotten")',
          'Request data portability',
        ]),

        _buildSectionTitle('13. Changes to Privacy Policy'),
        _buildParagraph(
          'We may update this Privacy Policy. Merchants will be notified via app updates, emails, or website notices. Continued use constitutes acceptance of changes.',
        ),

        const SizedBox(height: 16),
        _buildContactBox(),
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
                    flex: 3,
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

  Widget _buildContactBox() {
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
            'For questions or complaints regarding this Privacy Policy, contact:\n📧 dpo@dentpal.shop\n📍 R&R Newtech Dental Corporation\n\nDentPal will respond in accordance with applicable laws and within a reasonable timeframe.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
