import 'package:flutter/material.dart';
import 'signup_controller.dart';

class SignupStep3IdVerification extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onBack;

  const SignupStep3IdVerification({
    super.key,
    required this.controller,
    required this.onBack,
  });

  @override
  State<SignupStep3IdVerification> createState() => _SignupStep3IdVerificationState();
}

class _SignupStep3IdVerificationState extends State<SignupStep3IdVerification> {
  // This is a placeholder file
  // Actual implementation will be done later
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Step 3: ID Verification', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            const Text('This section will be implemented later'),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onBack,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // This would submit the entire form
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Form submitted! (Placeholder)')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
