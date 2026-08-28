import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/app_config.dart';
import 'core/app_theme/app_text_styles.dart';
import 'core/app_theme/ink_palette.dart';
import 'core/widgets/public_page_chrome.dart';
import 'utils/app_logger.dart';

/// Support, served at `/support` without an account.
///
/// Reached three ways: the Play Store listing's support URL, the web footer,
/// and the shell's own Support action — so it has to stand on its own for a
/// stranger and still look like the rest of the app for someone signed in. It
/// wears the same chrome as the two public policy documents, so the three pages
/// read as one set.
class PublicSupportPage extends StatelessWidget {
  const PublicSupportPage({super.key});

  /// The inbox, from the one place the app keeps it.
  static const String _supportEmail = AppConfig.contactEmail;

  @override
  Widget build(BuildContext context) {
    final gutter = PublicPageMetrics.gutterOf(context);

    return PublicPageScaffold(
      header: const PublicPageHeader(
        title: 'Support',
        summary: 'How to reach us, and what to tell us',
        icon: Icons.headset_mic_outlined,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 32),
        children: [
          _buildEmailCard(context),
          const SizedBox(height: 14),
          _buildChecklistCard(context),
          const SizedBox(height: 14),
          _buildResponseNote(context),
          const SizedBox(height: 14),
          _buildLegalLinks(context),
        ],
      ),
    );
  }

  // ── Email ────────────────────────────────────────────────────────────────

  Widget _buildEmailCard(BuildContext context) {
    final ink = InkPalette.of(context);

    return PublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.mail_outline, size: 22, color: ink.emerald),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email us',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The fastest way to reach a person',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: ink.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _supportEmail,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: ink.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _copyEmail(context),
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: ink.text.withValues(alpha: 0.6),
                  ),
                  tooltip: 'Copy address',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _composeEmail(context),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('Compose email', style: AppTextStyles.buttonMedium),
              style: ElevatedButton.styleFrom(
                backgroundColor: ink.emerald,
                foregroundColor: ink.onEmerald,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!context.mounted) return;
    _showNote(context, 'Address copied');
  }

  /// Opens the device's mail app with the address and a subject already filled
  /// in. Falls back to the clipboard: on desktop web, and on a phone with no
  /// mail account set up, there is nothing for a `mailto:` to open.
  Future<void> _composeEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': 'DentPal support request'},
    );

    try {
      if (await launchUrl(uri)) return;
    } catch (e) {
      AppLogger.d('Could not open mail client: $e');
    }

    if (!context.mounted) return;
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!context.mounted) return;
    _showNote(context, 'No mail app found — address copied instead');
  }

  void _showNote(BuildContext context, String message) {
    final ink = InkPalette.of(context);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTextStyles.bodyMedium.copyWith(color: ink.onEmerald),
          ),
          backgroundColor: ink.emerald,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ── What to send ─────────────────────────────────────────────────────────

  Widget _buildChecklistCard(BuildContext context) {
    final ink = InkPalette.of(context);

    return PublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Please include',
            style: AppTextStyles.titleMedium.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'With these three things we can usually answer on the first reply.',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.55),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _buildChecklistItem(
            context,
            icon: Icons.subject,
            title: 'A subject line',
            description: 'A short title summarising the issue.',
          ),
          const SizedBox(height: 14),
          _buildChecklistItem(
            context,
            icon: Icons.account_circle_outlined,
            title: 'Your account email',
            description: 'The address you use to sign in to DentPal.',
          ),
          const SizedBox(height: 14),
          _buildChecklistItem(
            context,
            icon: Icons.description_outlined,
            title: 'What happened',
            description:
                'What you were doing, what you expected, and what you saw '
                'instead. A screenshot helps.',
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final ink = InkPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: ink.emerald.withValues(alpha: ink.isDark ? 0.16 : 0.11),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: ink.emerald),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ink.text.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Notes and links ──────────────────────────────────────────────────────

  Widget _buildResponseNote(BuildContext context) {
    final ink = InkPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ink.emerald.withValues(alpha: ink.isDark ? 0.1 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ink.emerald.withValues(alpha: ink.isDark ? 0.24 : 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 18, color: ink.emerald),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'We reply within 24–48 hours on business days.',
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.75),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalLinks(BuildContext context) {
    final ink = InkPalette.of(context);

    return PublicCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _buildLinkRow(
            context,
            icon: Icons.shield_outlined,
            label: 'Privacy Policy',
            route: '/privacy-policy',
          ),
          Divider(height: 1, indent: 60, color: ink.border),
          _buildLinkRow(
            context,
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            route: '/terms-of-service',
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
  }) {
    final ink = InkPalette.of(context);

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(route),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ink.text.withValues(alpha: 0.6)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: ink.text.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}
