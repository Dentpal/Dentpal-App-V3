import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dentpal/config/app_config.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/app_theme/theme_utils.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

/// Professional Footer Widget - Web Only
/// Modern ecommerce footer with branding, navigation, and legal links
///
/// It used to carry its own two palettes behind a `dark` flag, which meant it
/// followed the appearance only on the one page that remembered to pass the
/// flag — every other page left a white slab under a near-black window. It
/// resolves [InkPalette] itself now, so the footer matches whatever page it is
/// standing at the bottom of.
class WebFooter extends StatelessWidget {
  const WebFooter({super.key});

  @override
  Widget build(BuildContext context) =>
      _FooterBody(ink: InkPalette.of(context));
}

class _FooterBody extends StatelessWidget {
  const _FooterBody({required this.ink});

  final InkPalette ink;

  /// A band at the bottom of the page rather than more of the page's ground:
  /// the footer is raised, with the hairline above it doing the separating.
  Color get _ground => ink.surface;
  Color get _raised => ink.surfaceHigh;
  Color get _line => ink.border;
  Color get _heading => ink.text;
  Color get _body => ink.text.withValues(alpha: 0.7);
  Color get _muted => ink.text.withValues(alpha: 0.5);

  /// The store badges are black with white type in Apple's and Google's own
  /// artwork, so they keep that in both appearances.
  static const Color _storeBadge = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Only use the wide multi-column layout on web desktop widths.
    // Native mobile (and narrow web) uses the stacked mobile layout.
    final isWideWeb = kIsWeb && screenWidth >= 900;

    // A card on the shell's content column, like every other block on the
    // pages it closes — rather than a slab running the full width of the
    // window. The detail page already sits inside that column, so it only
    // needed the corners; Browse hands the footer the whole viewport, so the
    // column has to be reasserted here for the two to line up.
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        margin: const EdgeInsets.fromLTRB(
          AppLayout.gutter,
          8,
          AppLayout.gutter,
          AppLayout.gutter,
        ),
        // The corners have to cut the content, not just the ground: the wide
        // layout's columns run to the edge of the band.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _ground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
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
              child: isWideWeb
                  ? _buildWideLayout(context)
                  : _buildMobileLayout(context),
            ),

            // Divider
            Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              margin: EdgeInsets.symmetric(horizontal: isWideWeb ? 48 : 24),
              height: 1,
              color: _line,
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
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column 1: Branding & Description (35%)
        Expanded(flex: 3, child: _buildBrandingSection(context)),
        const SizedBox(width: 32),

        // Column 2: Customer Service
        Expanded(flex: 2, child: _buildCustomerServiceSection(context)),
        const SizedBox(width: 24),

        // Column 3: Legal
        Expanded(flex: 2, child: _buildLegalSection(context)),
        const SizedBox(width: 24),

        // Column 4: Download App (more space)
        Expanded(flex: 3, child: _buildDownloadAppSection(context)),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBrandingSection(context),
        const SizedBox(height: 32),
        // Customer Service (left) | Legal (right)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCustomerServiceSection(context)),
            const SizedBox(width: 16),
            Expanded(child: _buildLegalSection(context)),
          ],
        ),
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
                color: _heading,
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
          style: AppTextStyles.bodyMedium.copyWith(color: _body, height: 1.6),
        ),
        const SizedBox(height: 12),

        Text(
          'Connecting dental professionals with quality products and reliable sellers across the Philippines.',
          style: AppTextStyles.bodySmall.copyWith(color: _muted, height: 1.6),
        ),
        const SizedBox(height: 24),

        // Social Media Icons
        Row(
          children: [
            _buildSocialIcon(Icons.facebook, () async {
              final uri = Uri.parse(
                'https://www.facebook.com/p/DentPal-100064135209127/',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }),
            const SizedBox(width: 12),
            _buildSocialIcon(Icons.email, () async {
              final uri = Uri.parse('mailto:${AppConfig.contactEmail}');
              final success = await launchUrl(uri);
              if (!success) {
                final scaffold = ScaffoldMessenger.of(context);
                scaffold.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open mail app. Email copied to clipboard.',
                    ),
                    duration: Duration(seconds: 3),
                  ),
                );
                Clipboard.setData(
                  const ClipboardData(text: AppConfig.contactEmail),
                );
              }
            }),
            const SizedBox(width: 12),
            _buildSocialIcon(Icons.phone, () async {
              final uri = Uri.parse('tel:09178287353');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
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
          color: _raised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line, width: 1),
        ),
        child: Icon(icon, color: _body, size: 20),
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
            color: _heading,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _buildFooterLink('Help Center', () {
          Navigator.of(context).pushNamed('/support');
        }),
        // const SizedBox(height: 12),
        // _buildFooterLink('Track Order', () {
        //   Navigator.of(context).pushNamed('/');
        // }),
        // const SizedBox(height: 12),
        // _buildFooterLink('Returns & Refunds', () {
        //   Navigator.of(context).pushNamed('/');
        // }),
        // const SizedBox(height: 12),
        // _buildFooterLink('Shipping Info', () {
        //   Navigator.of(context).pushNamed('/');
        // }),
        const SizedBox(height: 12),
        _buildFooterLink('Contact Us', () {
          Navigator.of(context).pushNamed('/support');
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
            color: _heading,
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
        // const SizedBox(height: 12),
        // _buildFooterLink('Seller Agreement', () {
        //   Navigator.of(context).pushNamed('/');
        // }),
        // const SizedBox(height: 12),
        // _buildFooterLink('Cookie Policy', () {
        //   Navigator.of(context).pushNamed('/');
        // }),
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
            color: _heading,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),

        // iOS QR Code with App Store Badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // iOS QR Code
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'lib/assets/icons/qr_ios.jpeg',
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // App Store Badge
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _storeBadge,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _line),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      const appStoreUrl =
                          'https://apps.apple.com/ph/app/dentpal/id6758815697';
                      final uri = Uri.parse(appStoreUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.apple,
                            color: Colors.white,
                            size: 20,
                          ),
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
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Android QR Code with Google Play Badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Android QR Code
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  'lib/assets/icons/qr_android.jpeg',
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Google Play Badge
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _storeBadge,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _line),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      const playStoreUrl =
                          'https://play.google.com/store/apps/details?id=com.rrnewtech.dentpal';
                      final uri = Uri.parse(playStoreUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 20,
                          ),
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
        // The label used to sit in a `Row(mainAxisSize: min)`, which handed it
        // unbounded width — so "Terms of Service" ran off the side of its
        // column on a phone instead of wrapping.
        child: Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(color: _body, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isWideWeb) {
    return Center(child: _buildCopyright());
  }

  Widget _buildCopyright() {
    return Text(
      '© ${DateTime.now().year} DentPal. All rights reserved.',
      style: AppTextStyles.bodySmall.copyWith(
        color: _body,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
    );
  }
}
