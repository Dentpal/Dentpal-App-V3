import 'package:flutter/material.dart';

import '../app_theme/app_text_styles.dart';
import '../app_theme/ink_palette.dart';
import '../app_theme/theme_utils.dart';

/// The header every buyer surface wears.
///
/// Browse, Cart, Orders and Notifications each grew their own: different type
/// sizes, one centred title among left-aligned ones, a back arrow on some and
/// not others, and four different paddings. Switching tabs made the whole top
/// of the screen jump. One widget now, so they can't drift again.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.bottom,
    this.showBack,
    this.onBack,
  });

  final String title;

  /// Optional second line — a count, a state, a one-line summary.
  final String? subtitle;
  final Color? subtitleColor;

  /// Action at the far right of the title row.
  final Widget? trailing;

  /// Anything that belongs under the title but above the scrolling content:
  /// a search field, a row of filter pills.
  final Widget? bottom;

  /// Defaults to "show it when there is a route to pop", which is what tells a
  /// pushed page from a shell tab.
  final bool? showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final canPop = showBack ?? Navigator.of(context).canPop();

    return Padding(
      // The arrow carries its own 8px of tap padding, so the row starts that
      // much earlier and the title still lands on the gutter.
      padding: EdgeInsets.fromLTRB(
        canPop ? AppLayout.gutter - 8 : AppLayout.gutter,
        // Breathing room above the title. The header is the first thing under
        // the safe area, and at 4px the text read as if it were falling off the
        // top of the window.
        20,
        AppLayout.gutter,
        bottom == null ? 10 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        fontSize: 28,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: subtitleColor ?? ink.text.withValues(alpha: 0.5),
                          fontWeight: subtitleColor != null
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 12),
            Padding(
              // Undo the arrow's inset so the field below lines up with the
              // content, not with the icon.
              padding: EdgeInsets.only(left: canPop ? 8 : 0),
              child: bottom!,
            ),
          ],
        ],
      ),
    );
  }
}
