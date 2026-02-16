import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'package:dentpal/reset_password_page.dart';
import 'package:dentpal/change_password_standalone_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Firebase Action Handler Page
/// Handles Firebase email action links (password reset, email verification, email change)
/// Firebase sends users to this page with query parameters:
/// - mode: resetPassword, verifyEmail, recoverEmail
/// - oobCode: The verification code
/// - apiKey: Firebase API key
///
/// This page routes users to the appropriate screen based on the mode
class FirebaseActionHandlerPage extends StatefulWidget {
  final String? mode;
  final String? oobCode;
  final String? apiKey;
  final String? continueUrl;

  const FirebaseActionHandlerPage({
    super.key,
    this.mode,
    this.oobCode,
    this.apiKey,
    this.continueUrl,
  });

  @override
  State<FirebaseActionHandlerPage> createState() =>
      _FirebaseActionHandlerPageState();
}

class _FirebaseActionHandlerPageState extends State<FirebaseActionHandlerPage> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _handleAction();
  }

  Future<void> _handleAction() async {
    // Validate required parameters
    if (widget.mode == null || widget.oobCode == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid action link. Please request a new link.';
      });
      return;
    }

    AppLogger.d(
      'Firebase Action Handler - Mode: ${widget.mode}, OobCode: ${widget.oobCode != null ? "present" : "null"}',
    );

    try {
      switch (widget.mode) {
        case 'resetPassword':
          _handlePasswordReset();
          break;

        case 'verifyEmail':
          await _handleEmailVerification();
          break;

        case 'recoverEmail':
          await _handleEmailRecovery();
          break;

        default:
          setState(() {
            _isLoading = false;
            _errorMessage = 'Unknown action type: ${widget.mode}';
          });
      }
    } catch (e) {
      AppLogger.d('Error handling Firebase action: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred. Please try again.';
      });
    }
  }

  /// Handle password reset - navigate to appropriate reset page
  void _handlePasswordReset() {
    AppLogger.d('Handling password reset');

    // Navigate to the appropriate reset password page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (kIsWeb) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  ChangePasswordStandalonePage(oobCode: widget.oobCode ?? ''),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) =>
                  ResetPasswordPage(oobCode: widget.oobCode ?? ''),
            ),
          );
        }
      }
    });
  }

  /// Handle email verification
  Future<void> _handleEmailVerification() async {
    AppLogger.d('Handling email verification');

    try {
      // Apply the email verification code
      await FirebaseAuth.instance.applyActionCode(widget.oobCode!);

      setState(() {
        _isLoading = false;
      });

      // Show success message with portal selection
      if (mounted) {
        _showEmailVerificationSuccessDialog();
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'expired-action-code':
          message =
              'This verification link has expired. Please request a new one.';
          break;
        case 'invalid-action-code':
          message =
              'This verification link is invalid. Please request a new one.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'user-not-found':
          message = 'No account found for this verification link.';
          break;
        default:
          message = e.message ?? 'Failed to verify email. Please try again.';
      }

      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    }
  }

  /// Handle email recovery (when user changes their email and wants to undo)
  Future<void> _handleEmailRecovery() async {
    AppLogger.d('Handling email recovery');

    try {
      // Check the action code to get the restored email
      final info = await FirebaseAuth.instance.checkActionCode(widget.oobCode!);
      final restoredEmail = info.data['email'] as String?;

      // Apply the email recovery
      await FirebaseAuth.instance.applyActionCode(widget.oobCode!);

      setState(() {
        _isLoading = false;
      });

      // Show success message
      if (mounted) {
        _showSuccessDialog(
          title: 'Email Recovered!',
          message: restoredEmail != null
              ? 'Your email has been restored to: $restoredEmail'
              : 'Your email has been successfully recovered.',
          actionText: 'Go to Login',
          onAction: () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
          },
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'expired-action-code':
          message = 'This recovery link has expired. Please request a new one.';
          break;
        case 'invalid-action-code':
          message = 'This recovery link is invalid. Please request a new one.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'user-not-found':
          message = 'No account found for this recovery link.';
          break;
        default:
          message = e.message ?? 'Failed to recover email. Please try again.';
      }

      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    }
  }

  /// Show email verification success dialog with portal selection
  void _showEmailVerificationSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.check_circle,
                size: 50,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Email Verified!',
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your email has been successfully verified. Choose where you want to go:',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.grey600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Buyer Portal Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (kIsWeb) {
                    // For web, navigate to dentpal.shop
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (route) => false,
                    );
                  } else {
                    // For mobile app, go to login page
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.shopping_bag, size: 20),
                label: Text('Buyer Portal', style: AppTextStyles.buttonLarge),
              ),
            ),
            const SizedBox(height: 12),
            // Seller Center Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Import url_launcher at the top if not already imported
                  final Uri sellerUrl = Uri.parse('https://dentpal-site.web.app');
                  try {
                    // Try to launch the URL
                    await launchUrl(sellerUrl, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    AppLogger.d('Error launching Seller Center URL: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Unable to open Seller Center. Please visit dentpal-site.web.app manually.'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.primary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.store, size: 20),
                label: Text('Seller Center', style: AppTextStyles.buttonLarge),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog({
    required String title,
    required String message,
    required String actionText,
    required VoidCallback onAction,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.check_circle,
                size: 50,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: AppTextStyles.headlineSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.grey600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(actionText, style: AppTextStyles.buttonLarge),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Processing your request...',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: AppColors.error),
                const SizedBox(height: 20),
                Text(
                  'Action Failed',
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (route) => false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Go to Home', style: AppTextStyles.buttonLarge),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // This should not be reached, but just in case
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Text('Processing...', style: AppTextStyles.bodyMedium),
      ),
    );
  }
}
