// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'dart:io';
import 'signup_controller.dart';
import 'id_ocr_service.dart';
import 'id_verification_camera.dart';
import 'package:dentpal/core/app_theme/index.dart';

class SignupStep3IdVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const SignupStep3IdVerification({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onNext,
  });

  @override
  State<SignupStep3IdVerification> createState() => _SignupStep3IdVerificationState();
}

class _SignupStep3IdVerificationState extends State<SignupStep3IdVerification> {
  File? _capturedImage;

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
          // ID verification section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'ID Verification',
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We need to verify your identity to ensure account security and comply with regulations.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.grey600,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Show verification status - either captured image or verification result
                if (_capturedImage != null || widget.controller.isIdVerified || widget.controller.idVerificationError != null) ...[
                  if (widget.controller.isIdVerified) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha:0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ID verified successfully!',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (widget.controller.idVerificationError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.controller.idVerificationError!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Only show recapture button since verification is automatic
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _captureImage,
                      icon: Icon(Icons.camera_alt),
                      label: Text('Recapture PRC ID'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 32,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Smart Verification Ready',
                          style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Our smart camera will automatically detect, capture, and verify your PRC ID when positioned correctly. Simply hold your PRC ID steady in the frame.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _captureImage,
                            icon: Icon(Icons.camera_alt),
                            label: Text('Start Auto Verification'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
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
                  onPressed: widget.controller.isIdVerified ? widget.onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.controller.isIdVerified 
                        ? AppColors.primary 
                        : AppColors.grey300,
                    foregroundColor: widget.controller.isIdVerified 
                        ? AppColors.onPrimary 
                        : AppColors.grey600,
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

  Future<void> _captureImage() async {
    try {
      // Navigate to the auto-capture ID camera
      final result = await Navigator.of(context).push<IdVerificationResult>(
        MaterialPageRoute(
          builder: (context) => IdVerificationCamera(
            onIdVerified: (verificationResult) {
              Navigator.of(context).pop(verificationResult);
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
            expectedFirstName: widget.controller.firstNameController.text,
            expectedLastName: widget.controller.lastNameController.text,
          ),
        ),
      );

      if (result != null) {
        // ID was auto-captured and verified
        setState(() {
          // Set the captured image path if available
          if (result.isValid) {
            // We don't have direct access to image path from result, but we have verification data
            widget.controller.isIdVerified = true;
            widget.controller.idNumber = result.registrationNumber;
            widget.controller.idVerificationError = null;
            widget.controller.idFaceImage = result.faceImage;
            // Set a placeholder image to show verification was successful
            _capturedImage = null; // We'll handle this differently
          } else {
            widget.controller.isIdVerified = false;
            widget.controller.idVerificationError = result.errorMessage;
            widget.controller.idNumber = null;
            widget.controller.idFaceImage = null;
            _capturedImage = null;
          }
        });
      } else {
        // User cancelled the camera - mark as failed
        setState(() {
          widget.controller.isIdVerified = false;
          widget.controller.idVerificationError = 'ID verification cancelled. Please try again to complete your registration.';
          widget.controller.idNumber = null;
          widget.controller.idFaceImage = null;
          _capturedImage = null;
        });
      }
    } catch (e) {
      SignupController.logOcrResult('ERROR', 'Failed to capture image: $e');
      if (mounted) {
        setState(() {
          widget.controller.isIdVerified = false;
          widget.controller.idVerificationError = 'Unable to access camera. Please check permissions and try again.';
          widget.controller.idNumber = null;
          widget.controller.idFaceImage = null;
          _capturedImage = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to access camera. Please check permissions and try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

}
