import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dentpal/core/app_theme/app_colors.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

/// Professional Footer Widget - Web Only
/// Modern ecommerce footer with branding, navigation, and legal links
class WebFooter extends StatelessWidget {
  const WebFooter({super.key});

  @override
  Widget build(BuildContext context) {
    // Only render on web platform
    if (!kIsWeb) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideWeb = screenWidth >= 900;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Main Footer Content
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: EdgeInsets.symmetric(
              horizontal: isWideWeb ? 48 : 24,
              vertical: isWideWeb ? 64 : 40,
            ),
            child: isWideWeb ? _buildWideLayout(context) : _buildMobileLayout(context),
          ),

          // Divider
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            margin: EdgeInsets.symmetric(horizontal: isWideWeb ? 48 : 24),
            height: 1,
            color: AppColors.grey300,
          ),

          // Bottom Bar (Copyright)
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: EdgeInsets.symmetric(
              horizontal: isWideWeb ? 48 : 24,
              vertical: 24,
            ),
            child: _buildBottomBar(context, isWideWeb),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column 1: Branding & Description (35%)
        Expanded(
          flex: 3,
          child: _buildBrandingSection(context),
        ),
        const SizedBox(width: 32),

        // Column 2: Customer Service
        Expanded(
          flex: 2,
          child: _buildCustomerServiceSection(context),
        ),
        const SizedBox(width: 24),

        // Column 3: Legal
        Expanded(
          flex: 2,
          child: _buildLegalSection(context),
        ),
        const SizedBox(width: 24),

        // Column 4: Download App (more space)
        Expanded(
          flex: 3,
          child: _buildDownloadAppSection(context),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBrandingSection(context),
        const SizedBox(height: 40),
        _buildCustomerServiceSection(context),
        const SizedBox(height: 32),
        _buildLegalSection(context),
        const SizedBox(height: 32),
        _buildDownloadAppSection(context),
      ],
    );
  }

  Widget _buildBrandingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo & Brand Name
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'lib/assets/icons/dentpal_icon.png',
              width: 48,
              height: 48,
            ),
            const SizedBox(width: 12),
            Text(
              'DentPal',
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tagline
        Text(
          'Your trusted dental supplies marketplace',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.grey700,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'Connecting dental professionals with quality products and reliable sellers across the Philippines.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.grey600,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),

        // Social Media Icons
        Row(
          children: [
            _buildSocialIcon(Icons.facebook, () {
              // TODO: Add Facebook link
            }),
            const SizedBox(width: 12),
            _buildSocialIcon(Icons.email, () async {
              final uri = Uri.parse('mailto:support@dentpal.ph');
              final success = await launchUrl(uri);
              if (!success) {
                final scaffold = ScaffoldMessenger.of(context);
                scaffold.showSnackBar(
                  SnackBar(
                    content: Text('Could not open mail app. Email copied to clipboard.'),
                    duration: Duration(seconds: 3),
                  ),
                );
                Clipboard.setData(ClipboardData(text: 'support@dentpal.ph'));
              }
            }),
            const SizedBox(width: 12),
            _buildSocialIcon(Icons.phone, () {
              // TODO: Add Phone link
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.grey300,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: AppColors.grey700,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildCustomerServiceSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer Service',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _buildFooterLink('Help Center', () {
          Navigator.of(context).pushNamed('/support-url');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Track Order', () {
          Navigator.of(context).pushNamed('/');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Returns & Refunds', () {
          Navigator.of(context).pushNamed('/');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Shipping Info', () {
          Navigator.of(context).pushNamed('/');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Contact Us', () {
          Navigator.of(context).pushNamed('/support-url');
        }),
      ],
    );
  }

  Widget _buildLegalSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Legal',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _buildFooterLink('Privacy Policy', () {
          Navigator.of(context).pushNamed('/privacy-policy');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Terms of Service', () {
          Navigator.of(context).pushNamed('/terms-of-service');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Seller Agreement', () {
          Navigator.of(context).pushNamed('/');
        }),
        const SizedBox(height: 12),
        _buildFooterLink('Cookie Policy', () {
          Navigator.of(context).pushNamed('/');
        }),
      ],
    );
  }

  Widget _buildDownloadAppSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Download Our App',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        
        // Single QR Code with App Store Badges
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR Code
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.grey300, width: 2),
              ),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Icon(Icons.qr_code, size: 50, color: AppColors.grey400),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // App Store Badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Store Button
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.grey900,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.grey300),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // TODO: Add App Store link
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.apple, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Download',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.white,
                                        fontSize: 8,
                                        height: 1,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'App Store',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  
                  // Google Play Button
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.grey900,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.grey300),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // TODO: Add Play Store link
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GET IT ON',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.white,
                                        fontSize: 8,
                                        height: 1,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Google Play',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterLink(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.grey700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isWideWeb) {
    return Center(
      child: _buildCopyright(),
    );
  }

  Widget _buildCopyright() {
    return Text(
      '© ${DateTime.now().year} DentPal. All rights reserved.',
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.grey600,
        fontSize: 13,
      ),
    );
  }
}
