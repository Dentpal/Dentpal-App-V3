import 'package:flutter/material.dart';
import 'signup_controller.dart';
import 'signup_step1_personal_details.dart';
import 'signup_step2_acc_credentials.dart';
import 'signup_step3_id_verification.dart';

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
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      setState(() {
        _currentPage++;
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentPage + 1) / 3,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF43A047)),
            ),
            
            // Step indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStepIndicator(0, 'Personal Details'),
                  _buildStepIndicator(1, 'Account Credentials'),
                  _buildStepIndicator(2, 'ID Verification'),
                ],
              ),
            ),
            
            // Page view
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
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
                    onBack: previousPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStepIndicator(int step, String label) {
    final bool isActive = _currentPage >= step;
    
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? const Color(0xFF43A047) : Colors.grey[300],
            ),
            child: Center(
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF43A047) : Colors.grey[600],
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
