import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../utils/app_logger.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final GlobalKey<FormState> _currentPasswordFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _newPasswordFormKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
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
      _hasSpecialCharacter = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  Widget _buildPasswordRequirement(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            color: met ? AppColors.success : AppColors.onSurface.withValues(alpha: 0.4),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: met ? AppColors.success : AppColors.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _verifyCurrentPassword() async {
    if (!_currentPasswordFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

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

      setState(() {
        _isCurrentPasswordVerified = true;
      });

      if (mounted) {
        _showSuccessSnackBar('Current password verified successfully!');
      }
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
          errorMessage = 'Please log out and log back in, then try again.';
          break;
        default:
          errorMessage = 'Failed to verify password. Please try again.';
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      AppLogger.d('Error verifying current password: $e');
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred. Please try again.');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _changePassword() async {
    if (!_newPasswordFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update password (user is already re-authenticated)
      await user.updatePassword(_newPasswordController.text.trim());

      if (mounted) {
        _showSuccessDialog();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'requires-recent-login':
          errorMessage = 'Session expired. Please verify your current password again.';
          setState(() {
            _isCurrentPasswordVerified = false;
          });
          break;
        case 'weak-password':
          errorMessage = 'The new password is too weak. Please choose a stronger password.';
          break;
        default:
          errorMessage = 'Failed to change password. Please try again.';
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      AppLogger.d('Error changing password: $e');
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred. Please try again.');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _sendPasswordResetEmail() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('User not authenticated');
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);

      setState(() {
        _isResetEmailSent = true;
      });

      if (mounted) {
        _showResetEmailSentDialog();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email address.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many requests. Please try again later.';
          break;
        default:
          errorMessage = 'Failed to send reset email. Please try again.';
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      AppLogger.d('Error sending password reset email: $e');
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred. Please try again.');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Success',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'Your password has been changed successfully!',
            style: AppTextStyles.bodyLarge,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Return to settings
              },
              style: TextButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('OK'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showResetEmailSentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.email_outlined,
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Email Sent',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'A password reset link has been sent to your email address. Please check your inbox and follow the instructions to reset your password.',
            style: AppTextStyles.bodyLarge,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Return to settings
              },
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('OK'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your current password';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a new password';
    }
    if (!_hasUppercase || !_hasLowercase || !_hasNumber || 
        !_hasSpecialCharacter || !_hasMinLength) {
      return 'Password does not meet requirements';
    }
    if (value == _currentPasswordController.text) {
      return 'New password must be different from current password';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
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
            Icon(Icons.lock_outline, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Change Password',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _isCurrentPasswordVerified 
            ? _buildNewPasswordForm()
            : _buildCurrentPasswordForm(),
      ),
    );
  }

  Widget _buildCurrentPasswordForm() {
    return Form(
      key: _currentPasswordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          
          // Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.security,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'First, please verify your identity by entering your current password.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Current Password Field
          Text(
            'Current Password',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextFormField(
              controller: _currentPasswordController,
              obscureText: !_isCurrentPasswordVisible,
              validator: _validateCurrentPassword,
              decoration: InputDecoration(
                hintText: 'Enter your current password',
                prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isCurrentPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Verify Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyCurrentPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Verify Password',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Divider
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: AppColors.onSurface.withValues(alpha: 0.2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: AppColors.onSurface.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Forgot Password Section
          Container(
            padding: const EdgeInsets.all(20),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      color: AppColors.warning,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Forgot Your Password?',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'If you can\'t remember your current password, we can send you a reset link via email.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading || _isResetEmailSent ? null : _sendPasswordResetEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: BorderSide(color: AppColors.warning),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isResetEmailSent
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Email Sent',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Send Reset Email',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildNewPasswordForm() {
    return Form(
      key: _newPasswordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          
          // Success Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Identity verified! Now you can set your new password.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // New Password Field
          Text(
            'New Password',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextFormField(
              controller: _newPasswordController,
              obscureText: !_isNewPasswordVisible,
              validator: _validateNewPassword,
              decoration: InputDecoration(
                hintText: 'Create a strong password',
                prefixIcon: Icon(Icons.lock, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isNewPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _isNewPasswordVisible = !_isNewPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Confirm Password Field
          Text(
            'Confirm New Password',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextFormField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              validator: _validateConfirmPassword,
              decoration: InputDecoration(
                hintText: 'Re-enter your password',
                prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Password requirements section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.onSurface.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Password Requirements:',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 12),
                _buildPasswordRequirement('At least 8 characters', _hasMinLength),
                _buildPasswordRequirement('At least 1 uppercase letter', _hasUppercase),
                _buildPasswordRequirement('At least 1 lowercase letter', _hasLowercase),
                _buildPasswordRequirement('At least 1 number', _hasNumber),
                _buildPasswordRequirement('At least 1 special character', _hasSpecialCharacter),
                _buildPasswordRequirement(
                  'Passwords must match',
                  _newPasswordController.text.isNotEmpty &&
                  _confirmPasswordController.text.isNotEmpty &&
                  _newPasswordController.text.trim() == _confirmPasswordController.text.trim()
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Change Password Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Change Password',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Back to Verify Button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _isLoading ? null : () {
                setState(() {
                  _isCurrentPasswordVerified = false;
                  _currentPasswordController.clear();
                  _newPasswordController.clear();
                  _confirmPasswordController.clear();
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Cancel',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
