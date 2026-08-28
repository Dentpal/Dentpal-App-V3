/// The chrome the three signed-out informational pages share: Privacy Policy,
/// Terms of Service and Support.
///
/// These are the pages a stranger lands on — from the Play Store listing, from
/// the web footer, from a pasted link — so until now each drew its own frame: a
/// 70px Material `AppBar` with a hardcoded white surface, a 1200px content
/// column on one page and 800 on another, and paddings of 16, 24, 32 and 40.
/// None of it followed the appearance chosen in Profile → Appearance, so
/// opening the Privacy Policy from a dark marketplace meant a flash of white.
///
/// Everything here resolves its colours from [InkPalette] and borrows the
/// marketplace's metrics, so a public page and a signed-in one are cut to the
/// same measurements.
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../app_theme/app_text_styles.dart';
import '../app_theme/ink_palette.dart';
import '../app_theme/theme_utils.dart';
import 'auth_chrome.dart' show AuthBrandMark;

/// The measurements every public page is laid out on.
class PublicPageMetrics {
  PublicPageMetrics._();

  /// A reading column, not a page-wide one: long prose set across a full
  /// desktop window is unreadable. Deliberately the same width the in-app
  /// policy screen already uses, so the documents do not reflow when you read
  /// the same text signed in.
  static const double columnWidth = 760;

  /// Space either side of that column. The buyer shell's gutter on a phone, one
  /// step wider once there is a window to spare.
  static double gutterOf(BuildContext context) =>
      context.isWideLayout ? 24.0 : AppLayout.gutter;

  static const double cardRadius = 18;
}

/// The page frame: the palette's ground, and a centred reading column with the
/// header pinned above the content that scrolls under it.
class PublicPageScaffold extends StatelessWidget {
  const PublicPageScaffold({
    super.key,
    required this.header,
    required this.body,
  });

  final Widget header;

  /// Fills the space under the pinned header, and scrolls itself.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Scaffold(
      backgroundColor: ink.bg,
      // Let the content run to the bottom edge; the body's own padding keeps it
      // clear of the home indicator.
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: PublicPageMetrics.columnWidth,
            ),
            // Stretch, not start: [Center] hands down loose constraints, so a
            // start-aligned column would shrink to its widest child and the
            // header's left margin would depend on how long its title is.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, Expanded(child: body)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header a public page wears: the title on the gutter, the page's icon in
/// a tile at the far right, and — when the page was landed on directly — the
/// DentPal lockup above the pair.
///
/// The lockup and the back arrow are the two halves of one switch. Pushed from
/// inside the app there is a route to pop, so the page shows an arrow and the
/// person already knows whose app they are in; landed on from a link there is
/// nothing to pop, and the lockup is what names the site and offers a way into
/// the marketplace.
class PublicPageHeader extends StatelessWidget {
  const PublicPageHeader({
    super.key,
    required this.title,
    required this.icon,
    this.summary,
    this.showBack,
    this.onBack,
    this.showBrand,
  });

  final String title;

  /// The page's mark, in a tinted tile at the end of the title row.
  final IconData icon;

  /// One line under the title saying what the page is for.
  final String? summary;

  /// Defaults to "show it when there is a route to pop", which is what tells a
  /// pushed page from a landing.
  final bool? showBack;
  final VoidCallback? onBack;

  /// Defaults to the opposite of the back arrow — see the class comment.
  final bool? showBrand;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final gutter = PublicPageMetrics.gutterOf(context);
    final canPop = showBack ?? Navigator.of(context).canPop();
    final brand = showBrand ?? !canPop;

    return Padding(
      // The arrow carries its own 8px of tap padding, so the row starts that
      // much earlier and the title still lands on the gutter.
      padding: EdgeInsets.fromLTRB(
        canPop ? gutter - 8 : gutter,
        brand ? 16 : 4,
        gutter,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (brand) ...[
            InkWell(
              // Nothing to pop, so the lockup is the way into the marketplace —
              // the same thing a logo does in the corner of any web page.
              onTap: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: AuthBrandMark(size: 34),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              if (canPop)
                IconButton(
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: ink.text),
                  tooltip: 'Back',
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ink.text.withValues(alpha: 0.5),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: ink.emerald),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A raised block on the page ground — the frame every public page groups its
/// content in.
class PublicCard extends StatelessWidget {
  const PublicCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(PublicPageMetrics.cardRadius),
        border: Border.all(color: ink.border),
      ),
      child: child,
    );
  }
}

/// Who to write to, and who you would be writing to.
///
/// Closes the two policy documents, which otherwise end mid-sentence on
/// whatever the admin dashboard last published.
class PublicContactCard extends StatelessWidget {
  const PublicContactCard({
    super.key,
    required this.title,
    required this.message,
    required this.email,
    this.company = AppConfig.companyName,
  });

  final String title;
  final String message;
  final String email;
  final String company;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return PublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, size: 18, color: ink.emerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ink.emerald.withValues(alpha: ink.isDark ? 0.1 : 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ink.emerald.withValues(alpha: ink.isDark ? 0.24 : 0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  email,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  company,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ink.text.withValues(alpha: 0.6),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
