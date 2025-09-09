import 'package:flutter/material.dart';
import 'signup_controller.dart';
import 'package:dentpal/core/app_theme/index.dart';

class SignupStep2AccCredentials extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const SignupStep2AccCredentials({
    super.key,
    required this.controller,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<SignupStep2AccCredentials> createState() => _SignupStep2AccCredentialsState();
}

class _SignupStep2AccCredentialsState extends State<SignupStep2AccCredentials> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _controller.passwordController.addListener(_validatePassword);
    _controller.confirmPasswordController.addListener(() {
      setState(() {});
    });
  }

  void _validatePassword() {
    _controller.validatePassword();
    setState(() {});
  }

  Widget _buildPasswordRequirement(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.radio_button_unchecked,
            color: met ? AppColors.success : AppColors.grey400,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: met ? AppColors.success : AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
  
  void _validateAndProceed() {
    if (_controller.formKeyStep2.currentState!.validate()) {
      widget.onNext();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _controller.formKeyStep2,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 30.0,
          right: 30.0,
          top: 30.0
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email field
            Text(
              'Email Address',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.emailController,
              keyboardType: TextInputType.emailAddress,
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Enter your email address',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email address';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Password field
            Text(
              'Password',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.passwordController,
              obscureText: !_isPasswordVisible,
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Create a strong password',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.grey400,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (!_controller.hasUppercase || !_controller.hasLowercase || !_controller.hasNumber || 
                    !_controller.hasSpecialCharacter || !_controller.hasMinLength) {
                  return 'Password does not meet requirements';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Confirm Password field
            Text(
              'Confirm Password',
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _controller.confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                hintText: 'Re-enter your password',
                hintStyle: AppTextStyles.inputHint,
                filled: true,
                fillColor: AppColors.grey50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.grey400,
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value != _controller.passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            
            // Password requirements section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password Requirements:',
                    style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.grey700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildPasswordRequirement('At least 8 characters', _controller.hasMinLength),
                  _buildPasswordRequirement('At least 1 uppercase letter', _controller.hasUppercase),
                  _buildPasswordRequirement('At least 1 lowercase letter', _controller.hasLowercase),
                  _buildPasswordRequirement('At least 1 number', _controller.hasNumber),
                  _buildPasswordRequirement('At least 1 special character', _controller.hasSpecialCharacter),
                  _buildPasswordRequirement(
                    'Passwords must match',
                    _controller.passwordController.text.isNotEmpty &&
                    _controller.confirmPasswordController.text.isNotEmpty &&
                    _controller.passwordController.text.trim() == _controller.confirmPasswordController.text.trim()
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onBack,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.grey200,
                      foregroundColor: AppColors.grey700,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Back',
                      style: AppTextStyles.buttonLarge,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _validateAndProceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Proceed',
                      style: AppTextStyles.buttonLarge,
                    ),
                  ),
                ),
              ],
            ),
            // Add extra space at the bottom to account for home indicator
            SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 40 : 20),
          ],
        ),
      ),
    );
  }
}
