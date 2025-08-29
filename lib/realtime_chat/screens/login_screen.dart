import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'admin_chat_list_screen.dart';
import 'user_chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  String _selectedOption = '';
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Create predefined users on app start
    _authService.createPredefinedUsersIfNeeded();
  }

  void _login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please select a user type';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      User? user = await _authService.signInWithEmailAndPassword(email, password);
      
      if (user != null) {
        // Register the user in the database
        await _authService.registerUserInDatabase(user);
        
        // Check if this is an admin account
        bool isAdmin = await _authService.isAdmin(user.uid);
        
        if (!mounted) return;

        if (isAdmin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminChatListScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const UserChatScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to sign in. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DentPal Chat Login'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Welcome to DentPal Chat',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Please select your user type:',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                _buildUserTypeSelection(
                  'User',
                  'user@provider.com',
                  'Test123!',
                  Icons.person,
                ),
                const SizedBox(height: 16),
                _buildUserTypeSelection(
                  'Admin',
                  'admin@provider.com',
                  'Test123!',
                  Icons.admin_panel_settings,
                ),
                const SizedBox(height: 30),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_selectedOption == 'User') {
                            _login('user@provider.com', 'Test123!');
                          } else if (_selectedOption == 'Admin') {
                            _login('admin@provider.com', 'Test123!');
                          } else {
                            setState(() {
                              _errorMessage = 'Please select a user type';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'LOGIN',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTypeSelection(
    String title,
    String email,
    String password,
    IconData icon,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedOption = title;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: _selectedOption == title ? Colors.blue : Colors.grey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: _selectedOption == title
              ? Colors.blue.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: _selectedOption == title ? Colors.blue : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _selectedOption == title ? Colors.blue : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: title,
              groupValue: _selectedOption,
              onChanged: (value) {
                setState(() {
                  _selectedOption = value!;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
