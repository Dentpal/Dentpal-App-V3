import 'package:flutter/material.dart';
import 'signup_controller.dart';

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
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.cancel,
          color: met ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Text(text),
      ],
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Account Creation',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your details to set up your new account.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller.emailController,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  labelText: 'Email',
                  floatingLabelStyle: const TextStyle(color: Colors.black),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty || !value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller.passwordController,
                obscureText: !_isPasswordVisible,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  labelText: 'Password',
                  floatingLabelStyle: const TextStyle(color: Colors.black),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
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
              TextFormField(
                controller: _controller.confirmPasswordController,
                obscureText: !_isConfirmPasswordVisible,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  floatingLabelStyle: const TextStyle(color: Colors.black),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.black),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
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
              const SizedBox(height: 24),
              _buildPasswordRequirement('At least 1 uppercase letter.', _controller.hasUppercase),
              _buildPasswordRequirement('At least 1 lowercase letter.', _controller.hasLowercase),
              _buildPasswordRequirement('At least 1 number.', _controller.hasNumber),
              _buildPasswordRequirement('At least 1 special character.', _controller.hasSpecialCharacter),
              _buildPasswordRequirement('Minimum of 8 characters.', _controller.hasMinLength),
              _buildPasswordRequirement(
                'Passwords must match.',
                _controller.passwordController.text.isNotEmpty &&
                _controller.confirmPasswordController.text.isNotEmpty &&
                _controller.passwordController.text.trim() == _controller.confirmPasswordController.text.trim()
              ),
              // Add spacing before buttons
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onBack,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _validateAndProceed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43A047),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Proceed'),
                    ),
                  ),
                ],
              ),
              // Add bottom padding to prevent overlap with system UI
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
