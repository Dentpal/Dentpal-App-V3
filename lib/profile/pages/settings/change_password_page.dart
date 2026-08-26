import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../core/app_theme/ink_palette.dart';
import '../../../core/app_theme/theme_utils.dart';
import '../../../core/widgets/app_page_header.dart';
import '../../../utils/app_logger.dart';

/// Changing the account password, in two acts: prove you know the current one,
/// then choose the next one.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final GlobalKey<FormState> _currentPasswordFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _newPasswordFormKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _isResetEmailSent = false;
  bool _isCurrentPasswordVerified = false;

  // Password requirements tracking
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialCharacter = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_validatePassword);
    _confirmPasswordController.addListener(() {
      setState(() {});
    });
  }

  void _validatePassword() {
    final password = _newPasswordController.text;
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialCharacter = password.contains(
        RegExp(r'[!@#$%^&*(),.?":{}|<>]'),
      );
    });
  }

  bool get _passwordsMatch =>
      _newPasswordController.text.isNotEmpty &&
      _confirmPasswordController.text.isNotEmpty &&
      _newPasswordController.text.trim() ==
          _confirmPasswordController.text.trim();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Palette ──────────────────────────────────────────────────────────────

  InkPalette get ink => InkPalette.of(context);

  /// Destructive red. [InkPalette] reserves amber for urgency, so danger needs
  /// its own tone that still reads in both themes.
  Color get _danger =>
      ink.isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  Color get _muted => ink.text.withValues(alpha: 0.6);

  /// A form reads best in a narrower column than a browse grid, so the fields
  /// stop short of the page's full width — but it still centres inside the same
  /// frame every other buyer surface uses.
  static const double _formMaxWidth = 640;

  static const EdgeInsets _listPadding = EdgeInsets.fromLTRB(
    AppLayout.gutter,
    4,
    AppLayout.gutter,
    32,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _formMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  title: 'Change password',
                  subtitle: _isCurrentPasswordVerified
                      ? 'Step 2 of 2 — choose a new password'
                      : 'Step 1 of 2 — confirm it’s you',
                  subtitleColor: _isCurrentPasswordVerified
                      ? ink.emerald
                      : null,
                ),
                Expanded(
                  child: _isCurrentPasswordVerified
                      ? _buildNewPasswordForm()
                      : _buildCurrentPasswordForm(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: prove it's you ───────────────────────────────────────────────

  Widget _buildCurrentPasswordForm() {
    return Form(
      key: _currentPasswordFormKey,
      child: ListView(
        padding: _listPadding,
        children: [
          _buildBanner(
            icon: Icons.shield_outlined,
            tone: ink.emerald,
            message:
                'Enter your current password so we know it’s you before '
                'anything changes.',
          ),

          const SizedBox(height: 22),
          _buildSectionHeader('Current password'),
          const SizedBox(height: 10),
          _buildPasswordField(
            controller: _currentPasswordController,
            label: 'Current password',
            visible: _isCurrentPasswordVisible,
            onToggle: () => setState(
              () => _isCurrentPasswordVisible = !_isCurrentPasswordVisible,
            ),
            validator: (value) => (value == null || value.isEmpty)
                ? 'Please enter your current password'
                : null,
          ),

          const SizedBox(height: 20),
          _buildPrimaryButton(
            label: 'Verify password',
            busy: _isLoading,
            onPressed: _isLoading ? null : _verifyCurrentPassword,
          ),

          const SizedBox(height: 24),
          _buildOrDivider(),
          const SizedBox(height: 24),

          _buildForgotPasswordCard(),
        ],
      ),
    );
  }

  /// The way out for someone who cannot remember the current password.
  Widget _buildForgotPasswordCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.amber.withValues(alpha: ink.isDark ? 0.16 : 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.email_outlined,
                  color: ink.amber,
                  size: 19,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Forgot your password?',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ink.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'We can email you a reset link instead — you’ll set a new password '
            'from there.',
            style: AppTextStyles.bodySmall.copyWith(
              color: _muted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLoading || _isResetEmailSent
                  ? null
                  : _sendPasswordResetEmail,
              icon: Icon(
                _isResetEmailSent ? Icons.check : Icons.send_outlined,
                size: 16,
              ),
              label: Text(
                _isResetEmailSent ? 'Email sent' : 'Send reset email',
                style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink.amber,
                disabledForegroundColor: ink.amber.withValues(alpha: 0.5),
                side: BorderSide(color: ink.amber.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: ink.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.4),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: ink.border)),
      ],
    );
  }

  // ── Step 2: choose the new one ───────────────────────────────────────────

  Widget _buildNewPasswordForm() {
    return Form(
      key: _newPasswordFormKey,
      child: ListView(
        padding: _listPadding,
        children: [
          _buildBanner(
            icon: Icons.verified_user_outlined,
            tone: ink.emerald,
            message: 'Identity confirmed. Now pick your new password.',
          ),

          const SizedBox(height: 22),
          _buildSectionHeader('New password'),
          const SizedBox(height: 10),
          _buildPasswordField(
            controller: _newPasswordController,
            label: 'New password',
            visible: _isNewPasswordVisible,
            onToggle: () =>
                setState(() => _isNewPasswordVisible = !_isNewPasswordVisible),
            validator: _validateNewPassword,
          ),
          const SizedBox(height: 14),
          _buildPasswordField(
            controller: _confirmPasswordController,
            label: 'Confirm new password',
            visible: _isConfirmPasswordVisible,
            onToggle: () => setState(
              () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
            ),
            validator: _validateConfirmPassword,
          ),

          const SizedBox(height: 16),
          _buildRequirementsCard(),

          const SizedBox(height: 24),
          _buildPrimaryButton(
            label: 'Change password',
            busy: _isLoading,
            onPressed: _isLoading ? null : _changePassword,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: _isLoading ? null : _backToVerify,
              style: TextButton.styleFrom(foregroundColor: _muted),
              child: Text(
                'Back',
                style: AppTextStyles.buttonMedium.copyWith(fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the new password still has to satisfy, ticking off as it does.
  Widget _buildRequirementsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ink.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requirements',
            style: AppTextStyles.bodySmall.copyWith(
              color: ink.text.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          _buildRequirement('At least 8 characters', _hasMinLength),
          _buildRequirement('An uppercase letter', _hasUppercase),
          _buildRequirement('A lowercase letter', _hasLowercase),
          _buildRequirement('A number', _hasNumber),
          _buildRequirement('A special character', _hasSpecialCharacter),
          _buildRequirement('Both entries match', _passwordsMatch),
        ],
      ),
    );
  }

  /// Met is emerald; unmet is simply quiet.
  ///
  /// An unmet requirement is not an error — it is a step you have not taken
  /// yet — so it does not get a warning colour.
  Widget _buildRequirement(String text, bool met) {
    final tone = met ? ink.emerald : ink.text.withValues(alpha: 0.4);

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
              text,
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

  void _backToVerify() {
    setState(() {
      _isCurrentPasswordVerified = false;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  // ── Shared parts ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: ink.text,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required Color tone,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: ink.isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: ink.text.withValues(alpha: 0.75),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextFormField(
      controller: controller,
      obscureText: !visible,
      validator: validator,
      enabled: !_isLoading,
      cursorColor: ink.emerald,
      style: AppTextStyles.bodyMedium.copyWith(color: ink.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        errorMaxLines: 2,
        errorStyle: AppTextStyles.bodySmall.copyWith(
          color: _danger,
          fontSize: 11.5,
        ),
        prefixIcon: Icon(Icons.lock_outline, size: 19, color: ink.emerald),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 19,
            color: ink.text.withValues(alpha: 0.45),
          ),
          tooltip: visible ? 'Hide password' : 'Show password',
        ),
        border: border(ink.border),
        enabledBorder: border(ink.border),
        disabledBorder: border(ink.border.withValues(alpha: 0.5)),
        focusedBorder: border(ink.emerald, width: 1.5),
        errorBorder: border(_danger),
        focusedErrorBorder: border(_danger, width: 1.5),
        filled: true,
        fillColor: ink.surface,
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: ink.text.withValues(alpha: 0.6),
          fontSize: 14,
        ),
        floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
          color: ink.emerald,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ink.emerald,
          foregroundColor: ink.onEmerald,
          disabledBackgroundColor: ink.emerald.withValues(alpha: 0.5),
          disabledForegroundColor: ink.onEmerald.withValues(alpha: 0.8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
            : Text(label, style: AppTextStyles.buttonLarge),
      ),
    );
  }

  // ── Validation ───────────────────────────────────────────────────────────

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (!_hasUppercase ||
        !_hasLowercase ||
        !_hasNumber ||
        !_hasSpecialCharacter ||
        !_hasMinLength) {
      return 'Password does not meet the requirements below';
    }
    if (value == _currentPasswordController.text) {
      return 'New password must be different from the current one';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _verifyCurrentPassword() async {
    if (!_currentPasswordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('User not authenticated');
      }

      // Re-authenticate user with current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text.trim(),
      );

      await user.reauthenticateWithCredential(credential);

      if (!mounted) return;
      setState(() => _isCurrentPasswordVerified = true);
      _showSnack('Current password verified', ink.emerald);
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'Current password is incorrect. Please try again.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'requires-recent-login':
          errorMessage = 'Please sign out and back in, then try again.';
          break;
        default:
          errorMessage = 'Failed to verify password. Please try again.';
      }

      if (mounted) _showSnack(errorMessage, _danger);
    } catch (e) {
      AppLogger.d('Error verifying current password: $e');
      if (mounted) {
        _showSnack('An unexpected error occurred. Please try again.', _danger);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _changePassword() async {
    if (!_newPasswordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update password (user is already re-authenticated)
      await user.updatePassword(_newPasswordController.text.trim());

      if (!mounted) return;
      await _showOutcomeDialog(
        icon: Icons.check_circle_outline,
        tone: ink.emerald,
        title: 'Password changed',
        message: 'Your password has been updated. Use it next time you sign in.',
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'requires-recent-login':
          errorMessage =
              'Session expired. Please verify your current password again.';
          if (mounted) setState(() => _isCurrentPasswordVerified = false);
          break;
        case 'weak-password':
          errorMessage =
              'The new password is too weak. Please choose a stronger one.';
          break;
        default:
          errorMessage = 'Failed to change password. Please try again.';
      }

      if (mounted) _showSnack(errorMessage, _danger);
    } catch (e) {
      AppLogger.d('Error changing password: $e');
      if (mounted) {
        _showSnack('An unexpected error occurred. Please try again.', _danger);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _sendPasswordResetEmail() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('User not authenticated');
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);

      if (!mounted) return;
      setState(() => _isResetEmailSent = true);
      await _showOutcomeDialog(
        icon: Icons.mark_email_read_outlined,
        tone: ink.emerald,
        title: 'Email sent',
        message:
            'A reset link is on its way to ${user.email}. Open it and follow '
            'the instructions to set a new password.',
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email address.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many requests. Please try again later.';
          break;
        default:
          errorMessage = 'Failed to send reset email. Please try again.';
      }

      if (mounted) _showSnack(errorMessage, _danger);
    } catch (e) {
      AppLogger.d('Error sending password reset email: $e');
      if (mounted) {
        _showSnack('An unexpected error occurred. Please try again.', _danger);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Confirms the outcome, then leaves for Settings.
  ///
  /// The dialog and the page used to be dismissed with two `pop`s in a row off
  /// the *dialog's* context — the second one reaching through a context that
  /// the first had already torn down.
  Future<void> _showOutcomeDialog({
    required IconData icon,
    required Color tone,
    required String title,
    required String message,
  }) async {
    final navigator = Navigator.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ink.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: tone),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: ink.text))),
          ],
        ),
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: _muted, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: ink.onEmerald,
              elevation: 0,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (mounted) navigator.pop();
  }

  void _showSnack(String message, Color tone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
