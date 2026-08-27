/// The chrome the signed-out surfaces share: sign in, and the three steps of
/// sign up.
///
/// Login and each signup step used to draw their own frame — a teal gradient
/// with a white sheet rounded over it, 30px of side padding on one page and 16
/// on another, a centred 24px headline here and a left-aligned 20px one there.
/// Nothing lined up as you moved between them, and none of it followed the
/// appearance chosen in Profile → Appearance, so signing in from a dark
/// marketplace meant a full-screen flash of white.
///
/// Everything here resolves its colours from [InkPalette] like the rest of the
/// marketplace, and borrows `AppPageHeader`'s metrics, so a signed-out page and
/// a signed-in one are cut to the same measurements.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme/app_text_styles.dart';
import '../app_theme/ink_palette.dart';
import '../app_theme/theme_utils.dart';


/// The measurements every signed-out surface is laid out on.
class AuthMetrics {
  AuthMetrics._();

  /// A signed-out form is one column of fields. Past ~460 the lines get long
  /// enough to be tiring to scan, so the column stops there and centres in
  /// whatever window it is given — phone, tablet or browser.
  static const double columnWidth = 460;

  /// Space either side of that column. Deliberately the buyer shell's gutter,
  /// so the left edge of the content does not move when you sign in.
  static const double gutter = AppLayout.gutter;

  /// Padding for the scrolling body beneath an [AuthHeader]. The 4 at the top
  /// picks up where the header's own bottom padding leaves off.
  static const EdgeInsets bodyPadding = EdgeInsets.fromLTRB(
    gutter,
    4,
    gutter,
    32,
  );

  static const double fieldRadius = 14;
  static const double cardRadius = 18;
  static const double buttonHeight = 52;

  /// The orange half of the DentPal wordmark.
  ///
  /// [InkPalette] keeps amber for urgency — deal timers, alerts — so the logo
  /// carries its own brand orange rather than borrowing that meaning.
  static const Color brandOrange = Color(0xFFF2921F);
}

/// Tones the auth surfaces need that the marketplace palette does not carry.
extension AuthInk on InkPalette {
  /// Destructive/invalid red. [InkPalette] reserves amber for urgency, so a
  /// rejected field needs its own tone that still reads in both themes.
  Color get danger => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// Secondary ink, for helper copy and inactive labels.
  Color get muted => text.withValues(alpha: 0.6);

  /// Tertiary ink, for placeholders and unmet requirements.
  Color get faint => text.withValues(alpha: 0.42);
}

/// The page frame: the palette's ground, and a centred column of fixed width.
///
/// Two shapes, because the signed-out pages come in two lengths.
///
/// The default pins [header] at the top and hands the rest of the window to
/// [body], which scrolls itself — right for the signup steps, whose forms run
/// past the bottom of the screen and whose step bar should stay visible while
/// you work down them.
///
/// [AuthScaffold.centered] scrolls the header *with* the content and sits the
/// pair in the middle of the window when they are shorter than it — right for
/// login, which is six controls tall and otherwise leaves half a phone screen
/// of empty ground beneath it. On a small screen, or once the keyboard is up,
/// the content outgrows the window and it simply scrolls.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.header,
    required Widget this.body,
    this.maxWidth = AuthMetrics.columnWidth,
  }) : children = null;

  const AuthScaffold.centered({
    super.key,
    required this.header,
    required List<Widget> this.children,
    this.maxWidth = AuthMetrics.columnWidth,
  }) : body = null;

  final Widget header;

  /// Fills the space under a pinned header. Null on the centred variant.
  final Widget? body;

  /// The content, laid out under the header inside [AuthMetrics.bodyPadding].
  /// Null on the pinned-header variant.
  final List<Widget>? children;

  final double maxWidth;

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
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: children == null ? _pinnedHeader() : _centered(),
          ),
        ),
      ),
    );
  }

  Widget _pinnedHeader() {
    return Column(
      // Stretch, not start: [Center] hands down *loose* constraints, so a
      // start-aligned column would shrink to its widest child and then sit
      // centred — the header's left margin would depend on how long its title
      // happened to be.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, Expanded(child: body!)],
    );
  }

  Widget _centered() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            // Floor the column at the height of the window: shorter content is
            // then free to centre inside it, taller content pushes past and the
            // scroll view takes over.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Padding(
                  padding: AuthMetrics.bodyPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children!,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The header every signed-out surface wears.
///
/// Unlike `AppPageHeader`, the back arrow sits on its own row above the title
/// rather than beside it. Inline, the arrow pushes the title right by its own
/// width — which would put the signup steps' titles 40px further in than
/// login's, the exact misalignment this widget exists to prevent.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.showBrand = true,
    this.onBrandTap,
    this.showBack,
    this.onBack,
    this.bottom,
  });

  final String title;

  /// Second line — the step you are on, or a one-line explanation of the page.
  final String? subtitle;
  final Color? subtitleColor;

  /// The DentPal lockup above the title. On by default: these are the pages
  /// where someone needs to know whose app they are handing a password to.
  final bool showBrand;

  /// Makes the lockup a way into the marketplace without an account, which is
  /// how the old login page let people browse as a guest.
  final VoidCallback? onBrandTap;

  /// Defaults to "show it when there is a route to pop".
  final bool? showBack;
  final VoidCallback? onBack;

  /// Anything below the title but above the scrolling content — the step bar.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final canPop = showBack ?? Navigator.of(context).canPop();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AuthMetrics.gutter,
        canPop ? 0 : 20,
        AuthMetrics.gutter,
        bottom == null ? 12 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop) ...[
            SizedBox(
              height: 48,
              child: IconButton(
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                // Zero padding and a left alignment put the glyph itself on the
                // gutter, so the arrow lines up with the title below it.
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                // Sized to Material's minimum tap target rather than something
                // smaller: at 40 the button would still be *padded* out to 48
                // and then centred inside it, nudging the glyph 4px off the
                // gutter — the one thing this header exists to prevent.
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                visualDensity: VisualDensity.standard,
                icon: Icon(Icons.arrow_back, color: ink.text, size: 22),
                tooltip: 'Back',
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (showBrand) ...[
            if (onBrandTap == null)
              const AuthBrandMark()
            else
              InkWell(
                onTap: onBrandTap,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: AuthBrandMark(),
                ),
              ),
            const SizedBox(height: 18),
          ],
          Text(
            title,
            style: AppTextStyles.titleLarge.copyWith(
              color: ink.text,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: subtitleColor ?? ink.muted,
                fontWeight: subtitleColor != null
                    ? FontWeight.w700
                    : FontWeight.w500,
                fontSize: 13,
                height: 1.4,
              ),
              maxLines: 2,
            ),
          ],
          if (bottom != null) ...[const SizedBox(height: 16), bottom!],
        ],
      ),
    );
  }
}

/// The DentPal lockup: the cart mark, then the wordmark.
class AuthBrandMark extends StatelessWidget {
  const AuthBrandMark({super.key, this.size = 38});

  /// Height of the mark. The wordmark scales with it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    final wordmark = AppTextStyles.headlineSmall.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: size * 0.56,
      letterSpacing: -0.4,
      height: 1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'lib/assets/icons/dentpal_icon.png',
          width: size,
          height: size,
          // Decorative — the wordmark beside it already names the app.
          excludeFromSemantics: true,
        ),
        SizedBox(width: size * 0.22),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Dent',
                style: wordmark.copyWith(color: ink.emerald),
              ),
              TextSpan(
                text: 'Pal',
                style: wordmark.copyWith(color: AuthMetrics.brandOrange),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How far through a multi-step flow you are, as a row of segments.
///
/// The step *number* is carried by the header's subtitle ("Step 2 of 3 — …"),
/// so this only has to show the shape of the progress.
class AuthStepBar extends StatelessWidget {
  const AuthStepBar({super.key, required this.total, required this.current});

  final int total;

  /// Zero-based index of the step being shown.
  final int current;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Row(
      children: List.generate(total, (index) {
        final done = index <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              decoration: BoxDecoration(
                color: done ? ink.emerald : ink.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A raised block on the page ground — the frame for grouped fields, notes and
/// requirement lists.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(AuthMetrics.cardRadius),
        border: Border.all(color: ink.border),
      ),
      child: child,
    );
  }
}

/// The label above a group of fields.
class AuthSectionLabel extends StatelessWidget {
  const AuthSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// A tinted note: what is about to happen, what just did, or what went wrong.
class AuthBanner extends StatelessWidget {
  const AuthBanner({
    super.key,
    required this.icon,
    required this.tone,
    required this.message,
    this.title,
    this.action,
    this.onClose,
  });

  final IconData icon;

  /// The colour that carries the meaning — `ink.emerald` for progress,
  /// `ink.danger` for a failure, `ink.amber` for something time-sensitive.
  final Color tone;
  final String message;

  /// Optional bold first line, when the message alone is not enough.
  final String? title;

  /// Optional control below the message — "Go to login", "Try again".
  final Widget? action;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: ink.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      message,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.75),
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: Icon(Icons.close, size: 17, color: tone),
                  tooltip: 'Dismiss',
                ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// The shared border shape for every field on a signed-out page.
///
/// Exposed on its own so the pickers that are not [TextField]s — the birthdate
/// tap target, the location dropdown — can wear the same outline.
InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? helperText,
  bool enabled = true,
  bool floatingLabel = true,
}) {
  final ink = InkPalette.of(context);

  OutlineInputBorder border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: floatingLabel ? label : null,
    hintText: hint,
    helperText: helperText,
    helperMaxLines: 2,
    helperStyle: AppTextStyles.bodySmall.copyWith(
      color: ink.faint,
      fontSize: 11.5,
    ),
    errorMaxLines: 2,
    errorStyle: AppTextStyles.bodySmall.copyWith(
      color: ink.danger,
      fontSize: 11.5,
    ),
    hintStyle: AppTextStyles.bodyMedium.copyWith(
      color: ink.faint,
      fontSize: 14,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    border: border(ink.border),
    enabledBorder: border(ink.border),
    disabledBorder: border(ink.border.withValues(alpha: 0.5)),
    focusedBorder: border(ink.emerald, width: 1.5),
    errorBorder: border(ink.danger),
    focusedErrorBorder: border(ink.danger, width: 1.5),
    filled: true,
    fillColor: enabled ? ink.surface : ink.surfaceHigh,
    labelStyle: AppTextStyles.bodyMedium.copyWith(
      color: ink.muted,
      fontSize: 14,
    ),
    floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
      color: ink.emerald,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    ),
  );
}

/// A text field in the shared auth outline.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.enabled = true,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;

  /// Passed as an [IconData] rather than a widget so every field gets the same
  /// size and emerald tint without each caller repeating it.
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      enabled: enabled,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      cursorColor: ink.emerald,
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      decoration: authInputDecoration(
        context,
        label: label,
        hint: hint,
        helperText: helperText,
        enabled: enabled,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 19, color: ink.emerald),
        suffixIcon: suffixIcon,
      ).copyWith(counterText: maxLength == null ? null : ''),
    );
  }
}

/// The show/hide control for a password field, in the shared field metrics.
class AuthPasswordToggle extends StatelessWidget {
  const AuthPasswordToggle({
    super.key,
    required this.visible,
    required this.onToggle,
  });

  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return IconButton(
      onPressed: onToggle,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 19,
        color: ink.text.withValues(alpha: 0.45),
      ),
      tooltip: visible ? 'Hide password' : 'Show password',
    );
  }
}

/// The one action a page is really asking for: sign in, proceed, finish.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return SizedBox(
      height: AuthMetrics.buttonHeight,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.emerald.withValues(alpha: 0.35),
          disabledForegroundColor: ink.onEmerald.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
          ),
        ),
        child: busy
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ink.onEmerald,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label, style: AppTextStyles.buttonLarge),
                ],
              ),
      ),
    );
  }
}

/// An action that matters but is not the one being urged — "Recapture ID",
/// "Send reset email".
class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Defaults to the brand emerald; pass `ink.amber` or `ink.danger` when the
  /// action belongs to a warning.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final colour = tone ?? ink.emerald;

    return SizedBox(
      height: 46,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 17),
        label: Text(
          label,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13.5),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: colour,
          disabledForegroundColor: colour.withValues(alpha: 0.45),
          side: BorderSide(color: colour.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
          ),
        ),
      ),
    );
  }
}

/// A way back, or out — deliberately the quietest control on the page.
class AuthQuietButton extends StatelessWidget {
  const AuthQuietButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return SizedBox(
      height: 46,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 17),
        label: Text(
          label,
          style: AppTextStyles.buttonMedium.copyWith(fontSize: 13.5),
        ),
        style: TextButton.styleFrom(
          foregroundColor: ink.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuthMetrics.fieldRadius),
          ),
        ),
      ),
    );
  }
}

/// "OR", with a rule either side.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.label = 'OR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Row(
      children: [
        Expanded(child: Divider(color: ink.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.faint,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: ink.border)),
      ],
    );
  }
}

/// One line of a requirement list.
///
/// Met is emerald; unmet is simply quiet. An unmet requirement is not an error
/// — it is a step not taken yet — so it does not get a warning colour.
class AuthCheckRow extends StatelessWidget {
  const AuthCheckRow({super.key, required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);
    final tone = met ? ink.emerald : ink.faint;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            color: tone,
            size: 15,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: met ? ink.text.withValues(alpha: 0.75) : tone,
                fontWeight: met ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card of requirements a password still has to satisfy.
class AuthChecklistCard extends StatelessWidget {
  const AuthChecklistCard({
    super.key,
    required this.title,
    required this.rows,
  });

  final String title;
  final List<AuthCheckRow> rows;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }
}

/// The cross-link at the foot of a signed-out page: "Already have an account?
/// Log in".
class AuthFooterPrompt extends StatelessWidget {
  const AuthFooterPrompt({
    super.key,
    required this.question,
    required this.actionLabel,
    required this.onPressed,
  });

  final String question;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = InkPalette.of(context);

    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: ink.emerald,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$question ',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.muted,
                  fontSize: 13.5,
                ),
              ),
              TextSpan(
                text: actionLabel,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ink.emerald,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// A snack in the page's own palette, rather than Material's default slate.
void showAuthSnack(BuildContext context, String message, Color tone) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: tone,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// A dialog wearing the auth surfaces' card, so a confirmation does not arrive
/// as a slab of Material white on a dark page.
Future<T?> showAuthDialog<T>({
  required BuildContext context,
  required IconData icon,
  required Color tone,
  required String title,
  required String message,
  bool barrierDismissible = false,
  List<Widget> Function(BuildContext dialogContext)? actions,
}) {
  final ink = InkPalette.of(context);

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: ink.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: ink.isDark ? 0.18 : 0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: tone, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: AppTextStyles.bodyMedium.copyWith(
          color: ink.muted,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
      actions:
          actions?.call(dialogContext) ??
          [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: tone,
                foregroundColor: ink.onEmerald,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Got it'),
            ),
          ],
    ),
  );
}

/// The blocking spinner shown while an account is being created.
void showAuthLoadingOverlay(BuildContext context, String message) {
  final ink = InkPalette.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ink.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ink.emerald, strokeWidth: 3),
            const SizedBox(height: 22),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ink.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
