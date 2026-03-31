// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'dart:io';
import 'signup_controller.dart';
import 'id_ocr_service.dart';
import 'id_verification_camera.dart';
import 'specialty_selection_widget.dart';
import 'package:dentpal/core/app_theme/index.dart';

class SignupNewStep1IdVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;

  const SignupNewStep1IdVerification({
    super.key,
    required this.controller,
    required this.onNext,
  });

  @override
  State<SignupNewStep1IdVerification> createState() => _SignupNewStep1IdVerificationState();
}

class _SignupNewStep1IdVerificationState extends State<SignupNewStep1IdVerification> {
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
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.controller.idVerificationError!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                                // Add iOS-specific tip if it's a face detection error on iOS
                                if (Platform.isIOS && widget.controller.idVerificationError!.contains('face')) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'iOS Tip: Ensure good lighting and hold the ID steady. The verification may still proceed even if face detection has issues.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.grey600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
          
          // ID Number field - only show when ID is verified
          if (widget.controller.isIdVerified) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.card_membership,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PRC Registration Number',
                        style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: widget.controller.idNumberController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter your PRC registration number',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.grey300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.grey300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary, width: 2),
                      ),
                      prefixIcon: Icon(Icons.numbers, color: AppColors.grey600),
                      helperText: 'Auto-filled from ID scan. You can edit if incorrect.',
                      helperMaxLines: 2,
                      helperStyle: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.grey600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    style: AppTextStyles.bodyLarge,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'PRC registration number is required';
                      }
                      if (value.trim().length < 4) {
                        return 'Please enter a valid registration number';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      // Update the idNumber when user edits
                      widget.controller.idNumber = value.trim();
                    },
                  ),
                ],
              ),
            ),
          ],
          
          // Specialty selection section - only show when ID is verified
          if (widget.controller.isIdVerified) ...[
            const SizedBox(height: 24),
            SpecialtySelectionWidget(
              selectedSpecialties: widget.controller.selectedSpecialties,
              onSelectionChanged: (specialties) {
                setState(() {
                  widget.controller.selectedSpecialties = specialties;
                });
              },
            ),
          ],
          
          const SizedBox(height: 32),
          
          // Action buttons - Only Proceed button for first step
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (widget.controller.isIdVerified && widget.controller.selectedSpecialties.isNotEmpty) ? widget.onNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (widget.controller.isIdVerified && widget.controller.selectedSpecialties.isNotEmpty)
                    ? AppColors.primary 
                    : AppColors.grey300,
                foregroundColor: (widget.controller.isIdVerified && widget.controller.selectedSpecialties.isNotEmpty)
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
          const SizedBox(height: 8),
          
          // Login link
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTextStyles.bodyMedium,
                children: [
                  TextSpan(
                    text: "Already have an account? ",
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.grey600,
                    ),
                  ),
                  TextSpan(
                    text: 'Log In',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
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
      // Note: We pass empty strings since names haven't been entered yet in this flow
      // The OCR service will skip name validation when empty strings are provided
      final result = await Navigator.of(context).push<IdVerificationResult>(
        MaterialPageRoute(
          builder: (context) => IdVerificationCamera(
            onIdVerified: (verificationResult) {
              Navigator.of(context).pop(verificationResult);
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
            // Pass empty strings to skip name validation in the new flow
            expectedFirstName: '',
            expectedLastName: '',
          ),
        ),
      );

      if (result != null) {
        // ID was auto-captured and verified
        setState(() {
          // Set the captured image path if available
          if (result.isValid) {
            widget.controller.isIdVerified = true;
            widget.controller.idNumber = result.registrationNumber;
            // Auto-fill the ID number text field
            widget.controller.idNumberController.text = result.registrationNumber ?? '';
            widget.controller.idVerificationError = null;
            widget.controller.idFaceImage = result.faceImage;
            
            // Pre-fill name fields from OCR if available
            if (result.firstName != null && result.firstName!.isNotEmpty) {
              widget.controller.firstNameController.text = result.firstName!;
            }
            if (result.lastName != null && result.lastName!.isNotEmpty) {
              widget.controller.lastNameController.text = result.lastName!;
            }
            
            _capturedImage = null;
          } else {
            widget.controller.isIdVerified = false;
            widget.controller.idVerificationError = result.errorMessage;
            widget.controller.idNumber = null;
            widget.controller.idNumberController.text = '';
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
          widget.controller.idNumberController.text = '';
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
          widget.controller.idNumberController.text = '';
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
