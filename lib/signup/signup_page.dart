import 'package:flutter/material.dart';
import 'signup_step1_personal_details.dart';
import 'signup_step2_acc_credentials.dart';
import 'signup_step3_id_verification.dart';
import 'signup_step4_face_verification.dart';
import 'signup_step5_phone_verification.dart';
import 'signup_controller.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _controller = SignupController();
  int _currentStep = 0;

  void _goToNextStep() {
    setState(() {
      if (_currentStep < 4) {
        _currentStep++;
      }
    });
  }

  void _goToPreviousStep() {
    setState(() {
      if (_currentStep > 0) {
        _currentStep--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: List.generate(5, (index) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    color: index <= _currentStep ? const Color(0xFF43A047) : Colors.grey.shade300,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          
          // Step labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Personal Details',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _currentStep == 0 ? FontWeight.bold : FontWeight.normal,
                      color: _currentStep == 0 ? const Color(0xFF43A047) : Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Account Setup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _currentStep == 1 ? FontWeight.bold : FontWeight.normal,
                      color: _currentStep == 1 ? const Color(0xFF43A047) : Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'ID Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _currentStep == 2 ? FontWeight.bold : FontWeight.normal,
                      color: _currentStep == 2 ? const Color(0xFF43A047) : Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Face Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _currentStep == 3 ? FontWeight.bold : FontWeight.normal,
                      color: _currentStep == 3 ? const Color(0xFF43A047) : Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Phone Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _currentStep == 4 ? FontWeight.bold : FontWeight.normal,
                      color: _currentStep == 4 ? const Color(0xFF43A047) : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Step content
          Expanded(
            child: _buildCurrentStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return SignupStep1PersonalDetails(
          controller: _controller,
          onNext: _goToNextStep,
        );
      case 1:
        return SignupStep2AccCredentials(
          controller: _controller,
          onNext: _goToNextStep,
          onBack: _goToPreviousStep,
        );
      case 2:
        return SignupStep3IdVerification(
          controller: _controller,
          onNext: _goToNextStep,
          onBack: _goToPreviousStep,
        );
      case 3:
        return SignupStep4FaceVerification(
          controller: _controller,
          onNext: _goToNextStep,
          onBack: _goToPreviousStep,
        );
      case 4:
        return SignupStep5PhoneVerification(
          controller: _controller,
          onBack: _goToPreviousStep,
        );
      default:
        return Container(); // Should never happen
    }
  }
}
