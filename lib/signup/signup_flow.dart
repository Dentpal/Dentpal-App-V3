import 'package:flutter/material.dart';
import 'signup_controller.dart';
import 'signup_step1_personal_details.dart';
import 'signup_step2_acc_credentials.dart';
import 'signup_step3_id_verification.dart';
import 'signup_step4_face_verification.dart';
import 'signup_step5_phone_verification.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';

class SignupFlow extends StatefulWidget {
  const SignupFlow({super.key});

  @override
  State<SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<SignupFlow> {
  final SignupController _controller = SignupController();
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  void nextPage() {
    AppLogger.d('SignupFlow nextPage called - current: $_currentPage');
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _currentPage++;
        AppLogger.d('SignupFlow moved to page: $_currentPage');
      });
    }
  }
  
  void previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _currentPage--;
      });
    }
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.teal),
        child: SafeArea(
          // Don't apply bottom padding to allow content to extend to the bottom edge
          bottom: false,
          child: Column(
            children: [
              // Top section with step indicator and title
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Step indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStepIndicator(0),
                        _buildStepIndicator(1),
                        _buildStepIndicator(2),
                        _buildStepIndicator(3),
                        _buildStepIndicator(4),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Title - dynamic based on current step
                    Text(
                      _getStepTitle(),
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.surface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getStepDescription(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              // Bottom section with signup form
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                      bottomLeft: Radius.zero,
                      bottomRight: Radius.zero,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Page view - remove the progress indicator section
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) {
                            AppLogger.d('SignupFlow page changed to: $index');
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          children: [
                            SignupStep1PersonalDetails(
                              controller: _controller, 
                              onNext: nextPage
                            ),
                            SignupStep2AccCredentials(
                              controller: _controller,
                              onNext: nextPage,
                              onBack: previousPage,
                            ),
                            SignupStep3IdVerification(
                              controller: _controller,
                              onNext: nextPage,
                              onBack: previousPage,
                            ),
                            SignupStep4FaceVerification(
                              controller: _controller,
                              onNext: nextPage,
                              onBack: previousPage,
                            ),
                            SignupStep5PhoneVerification(
                              controller: _controller,
                              onBack: previousPage,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStepIndicator(int step) {
    final bool isActive = _currentPage >= step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.surface : AppColors.surface.withValues(alpha: 0.3),
              border: Border.all(
                color: AppColors.surface,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  color: isActive ? AppColors.primary : AppColors.surface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Step ${step + 1}',
            style: TextStyle(
              color: AppColors.surface,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  String _getStepTitle() {
    switch (_currentPage) {
      case 0:
        return 'Personal Details';
      case 1:
        return 'Account Setup';
      case 2:
        return 'ID Verification';
      case 3:
        return 'Face Verification';
      case 4:
        return 'Phone Verification';
      default:
        return 'Personal Details';
    }
  }
  
  String _getStepDescription() {
    switch (_currentPage) {
      case 0:
        return 'Enter your personal information to get started.';
      case 1:
        return 'Create your account credentials.';
      case 2:
        return 'Verify your identity with a valid ID.';
      case 3:
        return 'Take a selfie to confirm your identity.';
      case 4:
        return 'Verify your phone number to complete signup.';
      default:
        return 'Enter your personal information to get started.';
    }
  }
}