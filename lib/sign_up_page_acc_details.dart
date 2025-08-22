// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class SignUpPageAccDetails extends StatefulWidget {
  const SignUpPageAccDetails({super.key});

  @override
  State<SignUpPageAccDetails> createState() => _SignUpPageAccDetailsState();
}

class _SignUpPageAccDetailsState extends State<SignUpPageAccDetails> {
  final _formKeyStep1 = GlobalKey<FormState>();
  String? _step1GenderError;
  String? _step1BirthdateError;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _contactNumberController = TextEditingController();
  String? _selectedGender;
  DateTime? _selectedBirthdate;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final _formKeyStep2 = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialCharacter = false;
  bool _hasMinLength = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePassword);
    _confirmPasswordController.addListener(() {
      setState(() {});
    });
  }

  void _validatePassword() {
    final password = _passwordController.text;
    setState(() {
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialCharacter = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      _hasMinLength = password.length >= 8;
    });
  }

  @override
  void dispose() {
  _pageController.dispose();
  _emailController.dispose();
  _passwordController.dispose();
  _confirmPasswordController.dispose();
  _firstNameController.dispose();
  _lastNameController.dispose();
  _contactNumberController.dispose();
  super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16.0, left: 8, right: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (_currentPage > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.ease,
                        );
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_currentPage + 1} of 3',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // To balance the row
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Container(
                    padding: const EdgeInsets.all(32.0),
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (int page) {
                        setState(() {
                          _currentPage = page;
                        });
                      },
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildStep1(),
                        _buildStep2(),
                        _buildStep3(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Personal Details',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _firstNameController,
                    cursorColor: Colors.black,
                    decoration: InputDecoration(
                      labelText: 'First Name',
                      hintText: 'Juan',
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
                      if (value == null || value.trim().isEmpty) {
                        return 'First name is required';
                      }
                      if (value.trim().length < 3) {
                        return 'First name must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lastNameController,
                    cursorColor: Colors.black,
                    decoration: InputDecoration(
                      labelText: 'Last Name',
                      hintText: 'Dela Cruz',
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
                      if (value == null || value.trim().isEmpty) {
                        return 'Last name is required';
                      }
                      if (value.trim().length < 3) {
                        return 'Last name must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contactNumberController,
                    cursorColor: Colors.black,
                    keyboardType: TextInputType.phone,
                    onChanged: (value) {
                      // Remove all non-digit characters and update the field
                      final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digitsOnly != value) {
                        _contactNumberController.value = TextEditingValue(
                          text: digitsOnly,
                          selection: TextSelection.collapsed(offset: digitsOnly.length),
                        );
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Contact Number',
                      hintText: '09123456789',
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
                      if (value == null || value.trim().isEmpty) {
                        return 'Contact number is required';
                      }
                      // Value should already be digits only due to onChanged
                      if (value.length != 11) {
                        return 'Contact number must be 11 digits';
                      }
                      if (!value.startsWith('09')) {
                        return 'Contact number must start with 09';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Gender',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    //add 1px black border
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Male'),
                          value: 'Male',
                          groupValue: _selectedGender,
                          activeColor: Colors.blue,
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Female'),
                          value: 'Female',
                          groupValue: _selectedGender,
                          activeColor: Colors.blue,
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_step1GenderError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                      child: Text(
                        _step1GenderError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Birthdate',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final initialDate = _selectedBirthdate ?? DateTime(now.year - 18, now.month, now.day);
                      final picked = await showModalBottomSheet<DateTime>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) {
                          DateTime tempPicked = initialDate;
                          return Container(
                            height: 270,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: CupertinoTheme(
                                    data: const CupertinoThemeData(
                                      brightness: Brightness.dark,
                                      textTheme: CupertinoTextThemeData(
                                        dateTimePickerTextStyle: TextStyle(color: Colors.black, fontSize: 22),
                                      ),
                                    ),
                                    child: CupertinoDatePicker(
                                      mode: CupertinoDatePickerMode.date,
                                      initialDateTime: initialDate,
                                      maximumDate: now,
                                      onDateTimeChanged: (date) {
                                        tempPicked = date;
                                      },
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: SizedBox(
                                    width: 180,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.green,
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        shadowColor: Colors.transparent,
                                        backgroundColor: Colors.transparent,
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).pop(tempPicked);
                                      },
                                      child: const Text('Select', style: TextStyle(color: Colors.green)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedBirthdate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Text(
                        _selectedBirthdate == null
                            ? 'Select your birthdate'
                            : '${_selectedBirthdate!.month.toString().padLeft(2, '0')}/'
                              '${_selectedBirthdate!.day.toString().padLeft(2, '0')}/'
                              '${_selectedBirthdate!.year}',
                        style: const TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                  ),
                  if (_step1BirthdateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                      child: Text(
                        _step1BirthdateError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final valid = _formKeyStep1.currentState?.validate() ?? false;
                String? genderError;
                String? birthdateError;
                if (_selectedGender == null) {
                  genderError = 'Please select a gender';
                }
                if (_selectedBirthdate == null) {
                  birthdateError = 'Please select your birthdate';
                }
                setState(() {
                  _step1GenderError = genderError;
                  _step1BirthdateError = birthdateError;
                });
                if (valid && genderError == null && birthdateError == null) {
                  _step1GenderError = null;
                  _step1BirthdateError = null;
                  _nextPage();
                }
              },
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
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _formKeyStep2,
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
            controller: _emailController,
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
            controller: _passwordController,
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
              if (!_hasUppercase || !_hasLowercase || !_hasNumber || !_hasSpecialCharacter || !_hasMinLength) {
                return 'Password does not meet requirements';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
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
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildPasswordRequirement('At least 1 uppercase letter.', _hasUppercase),
          _buildPasswordRequirement('At least 1 lowercase letter.', _hasLowercase),
          _buildPasswordRequirement('At least 1 number.', _hasNumber),
          _buildPasswordRequirement('At least 1 special character.', _hasSpecialCharacter),
          _buildPasswordRequirement('Minimum of 8 characters.', _hasMinLength),
          _buildPasswordRequirement('Passwords must match.',
            _passwordController.text.isNotEmpty &&
            _confirmPasswordController.text.isNotEmpty &&
            _passwordController.text.trim() == _confirmPasswordController.text.trim()),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_formKeyStep2.currentState!.validate()) {
                  _nextPage();
                }
              },
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
    );
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

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Verify Your PRC License',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Upload or capture your PRC ID to confirm your credentials. Your PRC Number and Registration Date will be detected automatically for quick verification.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Implement final step logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF43A047),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Proceed to the next step'),
          ),
        ),
      ],
    );
  }
}
