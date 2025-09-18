// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'signup_controller.dart';
import 'face_verification_camera.dart';
import 'package:dentpal/core/app_theme/index.dart';

class SignupStep4FaceVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const SignupStep4FaceVerification({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onNext,
  });

  @override
  State<SignupStep4FaceVerification> createState() => _SignupStep4FaceVerificationState();
}

class _SignupStep4FaceVerificationState extends State<SignupStep4FaceVerification> {
  void _startFaceVerification() async {
    // Navigate to the camera screen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceVerificationCamera(
          onFaceVerified: (imageBytes) {
            // Handle successful face verification
            widget.controller.setFaceVerification(imageBytes);
            Navigator.pop(context, true); // Return success
          },
          onCancel: () {
            // Handle cancellation
            Navigator.pop(context, false); // Return cancelled
          },
        ),
      ),
    );
    
    // Handle the result when returning from camera
    if (result == true) {
      // Face verification was successful
      setState(() {}); // Refresh the UI
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Face verification completed successfully!'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
    // If result is false or null, user cancelled - no action needed
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 30.0,
        right: 30.0,
        top: 30.0
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Face verification section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.controller.isFaceVerified 
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.grey50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.controller.isFaceVerified 
                    ? AppColors.success
                    : AppColors.grey200,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  widget.controller.isFaceVerified 
                      ? Icons.check_circle
                      : Icons.face_retouching_natural,
                  size: 48,
                  color: widget.controller.isFaceVerified 
                      ? AppColors.success
                      : AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.controller.isFaceVerified 
                      ? 'Face Verified Successfully'
                      : 'Face Verification',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.controller.isFaceVerified 
                        ? AppColors.success
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.controller.isFaceVerified
                      ? 'Your identity has been successfully verified using face recognition.'
                      : 'Please take a selfie to verify your identity. This helps us ensure the security of your account.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                ),
                const SizedBox(height: 24),
                
                if (!widget.controller.isFaceVerified) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 32,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selfie Required',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please ensure good lighting and look directly at the camera',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _startFaceVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Start Face Verification',
                          style: AppTextStyles.buttonLarge,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.verified_user,
                          size: 32,
                          color: AppColors.success,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verification Complete',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your face has been successfully verified',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        widget.controller.clearFaceVerification();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Retake Selfie',
                        style: AppTextStyles.buttonLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )

                ],
              ],
            ),
          ),
          
          const SizedBox(height: 30), // Spacer for content
          
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
                  onPressed: widget.controller.isFaceVerified ? widget.onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.controller.isFaceVerified 
                        ? AppColors.primary 
                        : AppColors.grey300,
                    foregroundColor: widget.controller.isFaceVerified 
                        ? AppColors.onPrimary 
                        : AppColors.grey500,
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
    );
  }
}
