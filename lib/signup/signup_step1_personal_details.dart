// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'signup_controller.dart';

class SignupStep1PersonalDetails extends StatefulWidget {
  final SignupController controller;
  final VoidCallback onNext;

  const SignupStep1PersonalDetails({
    super.key,
    required this.controller,
    required this.onNext,
  });

  @override
  State<SignupStep1PersonalDetails> createState() => _SignupStep1PersonalDetailsState();
}

class _SignupStep1PersonalDetailsState extends State<SignupStep1PersonalDetails> {
  // Quick access to controller
  SignupController get _controller => widget.controller;
  
  @override
  Widget build(BuildContext context) {
    return Form(
      key: _controller.formKeyStep1,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                controller: _controller.firstNameController,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  labelText: 'First Name',
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
                  if (value == null || value.isEmpty) {
                    return 'Please enter your first name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller.lastNameController,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  labelText: 'Last Name',
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
                  if (value == null || value.isEmpty) {
                    return 'Please enter your last name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _controller.contactNumberController,
                      keyboardType: TextInputType.phone,
                      cursorColor: Colors.black,
                      onChanged: (value) {
                        // Enable or disable verification button based on input format
                        setState(() {
                          _controller.isVerifyButtonEnabled = value.startsWith('09') && value.length == 11;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Contact Number',
                        hintText: '09XXXXXXXXX',
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
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your contact number';
                        }
                        if (!value.startsWith('09') || value.length != 11) {
                          return 'Contact number must start with 09';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Gender',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Male'),
                      value: 'Male',
                      groupValue: _controller.selectedGender,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          _controller.selectedGender = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Female'),
                      value: 'Female',
                      groupValue: _controller.selectedGender,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          _controller.selectedGender = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_controller.step1GenderError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _controller.step1GenderError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
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
                  final initialDate = _controller.selectedBirthdate ?? DateTime(now.year - 18, now.month, now.day);
                  final picked = await showModalBottomSheet<DateTime>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      DateTime tempPicked = initialDate;
                      return Container(
                        height: 270,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
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
                      _controller.selectedBirthdate = picked;
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _controller.selectedBirthdate == null
                            ? 'Select your birthdate'
                            : '${_controller.selectedBirthdate!.month.toString().padLeft(2, '0')}/'
                              '${_controller.selectedBirthdate!.day.toString().padLeft(2, '0')}/'
                              '${_controller.selectedBirthdate!.year}',
                        style: TextStyle(
                          fontSize: 16, 
                          color: _controller.selectedBirthdate == null ? Colors.grey : Colors.black,
                        ),
                      ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                ),
              ),
              if (_controller.step1BirthdateError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _controller.step1BirthdateError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
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
              // Add bottom padding to prevent overlap with system UI
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
  
  void _validateAndProceed() {
    final valid = _controller.formKeyStep1.currentState?.validate() ?? false;
    String? genderError;
    String? birthdateError;
    
    if (_controller.selectedGender == null) {
      genderError = 'Please select a gender';
    }
    if (_controller.selectedBirthdate == null) {
      birthdateError = 'Please select your birthdate';
    }
    
    setState(() {
      _controller.step1GenderError = genderError;
      _controller.step1BirthdateError = birthdateError;
    });
    
    if (valid && genderError == null && birthdateError == null) {
      _controller.step1GenderError = null;
      _controller.step1BirthdateError = null;
      widget.onNext();
    }
  }

  // The rest of your methods (phone verification, OTP handling, etc.)
}
