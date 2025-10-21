import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'dart:typed_data';
// Conditional imports for platform-specific camera widget
import 'web_camera_stub.dart' 
    if (dart.library.html) 'web_camera_web.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../utils/app_logger.dart';
import 'package:intl/intl.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  
  // Current values for comparison
  String _originalDisplayName = '';
  String _originalFirstName = '';
  String _originalMiddleName = '';
  String _originalLastName = '';
  String _originalGender = '';
  DateTime? _originalBirthdate;
  String _originalPhotoURL = '';
  
  // Form state
  String _selectedGender = '';
  DateTime? _selectedBirthdate;
  bool _isLoading = false;
  bool _hasLoadedData = false;
  
  // Photo state
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes; // For web
  String? _currentPhotoURL;
  bool _isUploadingPhoto = false;
  bool _hasNewPhoto = false; // Track if user has selected/captured a new photo

  @override
  void initState() {
    super.initState();
    _loadUserData();
    
    // Add listeners to text controllers to detect changes
    _displayNameController.addListener(_onFieldChanged);
    _firstNameController.addListener(_onFieldChanged);
    _middleNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {
      // This will trigger a rebuild to update the button state
    });
  }

  @override
  void dispose() {
    // Remove listeners
    _displayNameController.removeListener(_onFieldChanged);
    _firstNameController.removeListener(_onFieldChanged);
    _middleNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);
    
    // Dispose controllers
    _displayNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists && mounted) {
          final userData = userDoc.data()!;
          
          // Load current values
          _originalDisplayName = userData['displayName'] ?? '';
          _displayNameController.text = _originalDisplayName;
          
          // Load individual name fields first (preferred method)
          // Check if we have individual name fields (even if some are null/empty)
          if (userData.containsKey('firstName') || userData.containsKey('middleName') || userData.containsKey('lastName')) {
            // Use individual name fields if they exist
            _originalFirstName = userData['firstName'] ?? '';
            _originalMiddleName = userData['middleName'] ?? '';
            _originalLastName = userData['lastName'] ?? '';
          } else {
            // Fall back to parsing fullName for backward compatibility
            final fullName = userData['fullName'] ?? '';
            final nameParts = fullName.split(' ').where((part) => part.isNotEmpty).toList();
            
            _originalFirstName = '';
            _originalMiddleName = '';
            _originalLastName = '';
            
            if (nameParts.isNotEmpty) {
              _originalFirstName = nameParts[0];
            }
            
            if (nameParts.length > 2) {
              // If more than 2 parts, middle name is everything except first and last
              _originalMiddleName = nameParts.sublist(1, nameParts.length - 1).join(' ');
              _originalLastName = nameParts.last;
            } else if (nameParts.length == 2) {
              // Only first and last name
              _originalLastName = nameParts[1];
            }
          }
          
          // Set the controller values
          _firstNameController.text = _originalFirstName;
          _middleNameController.text = _originalMiddleName;
          _lastNameController.text = _originalLastName;
          
          // Debug logging
          AppLogger.d('Loaded Profile Data:');
          AppLogger.d('  firstName: $_originalFirstName');
          AppLogger.d('  middleName: $_originalMiddleName');
          AppLogger.d('  lastName: $_originalLastName');
          AppLogger.d('  Has individual fields: ${userData.containsKey('firstName') || userData.containsKey('middleName') || userData.containsKey('lastName')}');
          
          _originalGender = userData['gender'] ?? '';
          _selectedGender = _originalGender.toLowerCase(); // Normalize to lowercase to match dropdown items
          
          // Handle photo URL
          _originalPhotoURL = userData['photoURL'] ?? '';
          _currentPhotoURL = _originalPhotoURL;
          
          // Handle birthdate
          if (userData['birthdate'] != null) {
            final timestamp = userData['birthdate'] as Timestamp;
            _originalBirthdate = timestamp.toDate();
            _selectedBirthdate = _originalBirthdate;
          }
          
          _hasLoadedData = true;
        }
      }
    } catch (e) {
      AppLogger.d('Error loading user data: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to load profile data');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildFullName() {
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    
    String fullName = firstName;
    
    if (middleName.isNotEmpty) {
      // Add middle initial(s)
      final middleInitials = middleName.split(' ')
          .map((name) => name.isNotEmpty ? '${name[0]}.' : '')
          .where((initial) => initial.isNotEmpty)
          .join(' ');
      
      if (middleInitials.isNotEmpty) {
        fullName += ' $middleInitials';
      }
    }
    
    if (lastName.isNotEmpty) {
      fullName += ' $lastName';
    }
    
    return fullName;
  }

  bool _hasChanges() {
    if (!_hasLoadedData) return false; // No changes if data isn't loaded yet
    
    final currentDisplayName = _displayNameController.text.trim();
    final currentFirstName = _firstNameController.text.trim();
    final currentMiddleName = _middleNameController.text.trim();
    final currentLastName = _lastNameController.text.trim();
    
    // Normalize gender for comparison (handle empty strings)
    final originalGenderNormalized = _originalGender.toLowerCase();
    final selectedGenderNormalized = _selectedGender.toLowerCase();
    
    return currentDisplayName != _originalDisplayName ||
           currentFirstName != _originalFirstName ||
           currentMiddleName != _originalMiddleName ||
           currentLastName != _originalLastName ||
           selectedGenderNormalized != originalGenderNormalized ||
           _selectedBirthdate != _originalBirthdate ||
           _selectedImageFile != null ||
           _selectedImageBytes != null ||
           _hasNewPhoto;
  }

  Future<void> _selectBirthdate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthdate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedBirthdate) {
      setState(() {
        _selectedBirthdate = picked;
      });
    }
  }

  Future<void> _showPhotoSelectionDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Select Photo',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: Text('Take Photo', style: AppTextStyles.bodyLarge),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePhoto();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: Text('Choose from Gallery', style: AppTextStyles.bodyLarge),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImageFromGallery();
                },
              ),
              if (_currentPhotoURL != null && _currentPhotoURL!.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text('Remove Photo', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.error)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _removePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePhoto() async {
    try {
      if (kIsWeb) {
        // For web, show camera dialog
        await _showWebCameraDialog();
      } else {
        // For mobile, request camera permission and use camera directly
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          _showErrorSnackBar('Camera permission is required to take photos');
          return;
        }

        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1080,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          await _processSelectedImage(image);
        }
      }
    } catch (e) {
      AppLogger.d('Error taking photo: $e');
      _showErrorSnackBar('Failed to take photo');
    }
  }

  Future<void> _showWebCameraDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 500,
            height: 600,
            padding: const EdgeInsets.all(20),
            child: WebCameraWidget(
              onPhotoTaken: (Uint8List imageBytes) async {
                Navigator.of(context).pop();
                
                setState(() {
                  _selectedImageBytes = imageBytes;
                  _selectedImageFile = null;
                  _hasNewPhoto = true;
                });
                
                _showSuccessSnackBar('Photo captured successfully');
              },
              onCancel: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        await _processSelectedImage(image);
      }
    } catch (e) {
      AppLogger.d('Error picking image: $e');
      _showErrorSnackBar('Failed to select image');
    }
  }

  Future<void> _processSelectedImage(XFile image) async {
    try {
      final int fileSize = await image.length();
      const int maxSizeBytes = 3 * 1024 * 1024; // 3MB

      if (fileSize > maxSizeBytes) {
        _showErrorSnackBar('Image size must be less than 3MB');
        return;
      }

      // Check file extension
      final String extension = image.name.toLowerCase().split('.').last;
      const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
      
      if (!allowedExtensions.contains(extension)) {
        _showErrorSnackBar('Please select a valid image file (JPG, PNG, GIF, etc.)');
        return;
      }

      setState(() {
        if (kIsWeb) {
          _selectedImageFile = null;
          // For web, we'll load bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _selectedImageBytes = bytes;
              _hasNewPhoto = true;
            });
          });
        } else {
          _selectedImageFile = File(image.path);
          _selectedImageBytes = null;
          _hasNewPhoto = true;
        }
      });

      _showSuccessSnackBar('Image selected successfully');
    } catch (e) {
      AppLogger.d('Error processing image: $e');
      _showErrorSnackBar('Failed to process image');
    }
  }

  void _removePhoto() {
    setState(() {
      _selectedImageFile = null;
      _selectedImageBytes = null;
      _currentPhotoURL = null;
      _hasNewPhoto = true; // Removing is also a change
    });
    _showSuccessSnackBar('Photo removed');
  }

  Future<String?> _uploadPhotoToFirebase() async {
    try {
      setState(() {
        _isUploadingPhoto = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final FirebaseStorage storage = FirebaseStorage.instance;
      
      // Determine file extension
      String extension = 'jpg'; // default
      if (_selectedImageFile != null) {
        extension = _selectedImageFile!.path.split('.').last.toLowerCase();
      } else if (_selectedImageBytes != null) {
        extension = 'jpg'; // default for web
      }

      final String fileName = 'displayimage.$extension';
      final Reference ref = storage.ref().child('UserImages/${user.uid}/$fileName');

      UploadTask uploadTask;
      
      if (kIsWeb && _selectedImageBytes != null) {
        uploadTask = ref.putData(_selectedImageBytes!);
      } else if (_selectedImageFile != null) {
        uploadTask = ref.putFile(_selectedImageFile!);
      } else {
        return null;
      }

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      AppLogger.d('Error uploading photo: $e');
      _showErrorSnackBar('Failed to upload photo');
      return null;
    } finally {
      setState(() {
        _isUploadingPhoto = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_hasChanges()) {
      _showInfoSnackBar('No changes detected');
      return;
    }

    // Show confirmation dialog
    final shouldSave = await _showConfirmationDialog();
    if (!shouldSave) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final updates = <String, dynamic>{};
      
      // Update display name
      final newDisplayName = _displayNameController.text.trim();
      if (newDisplayName != _originalDisplayName) {
        updates['displayName'] = newDisplayName;
      }
      
      // Update full name
      final newFullName = _buildFullName();
      final originalFullName = _buildOriginalFullName();
      if (newFullName != originalFullName) {
        updates['fullName'] = newFullName;
      }
      
      // Update individual name fields
      final newFirstName = _firstNameController.text.trim();
      final newMiddleName = _middleNameController.text.trim();
      final newLastName = _lastNameController.text.trim();
      
      // Debug logging
      AppLogger.d('Save Profile - Name Fields:');
      AppLogger.d('  Original: $_originalFirstName | $_originalMiddleName | $_originalLastName');
      AppLogger.d('  New: $newFirstName | $newMiddleName | $newLastName');
      
      // Check if any name field has changed
      bool nameFieldsChanged = newFirstName != _originalFirstName ||
                              newMiddleName != _originalMiddleName ||
                              newLastName != _originalLastName;
      
      AppLogger.d('  Name fields changed: $nameFieldsChanged');
      
      // If any name field changed, update all name fields to ensure consistency
      if (nameFieldsChanged) {
        updates['firstName'] = newFirstName;
        updates['middleName'] = newMiddleName;
        updates['lastName'] = newLastName;
        AppLogger.d('  Added name updates to batch: firstName=$newFirstName, middleName=$newMiddleName, lastName=$newLastName');
      }
      
      // Update gender
      final originalGenderNormalized = _originalGender.toLowerCase();
      final selectedGenderNormalized = _selectedGender.toLowerCase();
      if (selectedGenderNormalized != originalGenderNormalized) {
        updates['gender'] = _selectedGender;
      }
      
      // Update birthdate
      if (_selectedBirthdate != _originalBirthdate) {
        if (_selectedBirthdate != null) {
          // Set time to 12:00 AM UTC+8 (Philippine time)
          final birthdatePhilippines = DateTime(
            _selectedBirthdate!.year,
            _selectedBirthdate!.month,
            _selectedBirthdate!.day,
            0, // 12:00 AM
            0,
            0,
          ).add(const Duration(hours: 8)); // UTC+8
          
          updates['birthdate'] = Timestamp.fromDate(birthdatePhilippines);
        } else {
          updates['birthdate'] = null;
        }
      }
      
      // Upload photo if selected
      String? newPhotoURL;
      if (_selectedImageFile != null || _selectedImageBytes != null) {
        newPhotoURL = await _uploadPhotoToFirebase();
        if (newPhotoURL != null) {
          updates['photoURL'] = newPhotoURL;
          _currentPhotoURL = newPhotoURL;
        }
      } else if (_currentPhotoURL == null && _originalPhotoURL.isNotEmpty) {
        // Photo was removed
        updates['photoURL'] = null;
      }
      
      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        
        await FirebaseFirestore.instance
            .collection('User')
            .doc(user.uid)
            .update(updates);
        
        // Update original values after successful save
        _updateOriginalValues();
        
        if (mounted) {
          _showSuccessSnackBar('Profile updated successfully');
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      AppLogger.d('Error updating profile: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to update profile');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildOriginalFullName() {
    String fullName = _originalFirstName;
    
    if (_originalMiddleName.isNotEmpty) {
      final middleInitials = _originalMiddleName.split(' ')
          .map((name) => name.isNotEmpty ? '${name[0]}.' : '')
          .where((initial) => initial.isNotEmpty)
          .join(' ');
      
      if (middleInitials.isNotEmpty) {
        fullName += ' $middleInitials';
      }
    }
    
    if (_originalLastName.isNotEmpty) {
      fullName += ' $_originalLastName';
    }
    
    return fullName;
  }

  void _updateOriginalValues() {
    _originalDisplayName = _displayNameController.text.trim();
    _originalFirstName = _firstNameController.text.trim();
    _originalMiddleName = _middleNameController.text.trim();
    _originalLastName = _lastNameController.text.trim();
    _originalGender = _selectedGender;
    _originalBirthdate = _selectedBirthdate;
    _originalPhotoURL = _currentPhotoURL ?? '';
    
    // Clear selected image after successful save
    _selectedImageFile = null;
    _selectedImageBytes = null;
    _hasNewPhoto = false; // Reset photo change flag
  }

  Future<bool> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.save_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Save Changes',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to save the following changes?',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              ..._buildChangesList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
              ),
              child: Text('Cancel', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Save Changes', style: AppTextStyles.buttonMedium),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _showDiscardChangesDialog() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_outlined,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Discard Changes',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Text(
            'You have unsaved changes. Are you sure you want to discard them?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurface.withValues(alpha: 0.6),
              ),
              child: Text('Keep Editing', style: AppTextStyles.buttonMedium),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
              ),
              child: Text('Discard', style: AppTextStyles.buttonMedium),
            ),
          ],
        );
      },
    );

    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  List<Widget> _buildChangesList() {
    final changes = <Widget>[];
    
    // Display Name changes
    final currentDisplayName = _displayNameController.text.trim();
    if (currentDisplayName != _originalDisplayName) {
      changes.add(_buildChangeItem(
        'Display Name',
        _originalDisplayName.isEmpty ? '(Empty)' : _originalDisplayName,
        currentDisplayName.isEmpty ? '(Empty)' : currentDisplayName,
      ));
    }
    
    // Full Name changes
    final currentFullName = _buildFullName();
    final originalFullName = _buildOriginalFullName();
    if (currentFullName != originalFullName) {
      changes.add(_buildChangeItem(
        'Full Name',
        originalFullName.isEmpty ? '(Empty)' : originalFullName,
        currentFullName.isEmpty ? '(Empty)' : currentFullName,
      ));
    }
    
    // Gender changes
    final originalGenderNormalized = _originalGender.toLowerCase();
    final selectedGenderNormalized = _selectedGender.toLowerCase();
    if (selectedGenderNormalized != originalGenderNormalized) {
      changes.add(_buildChangeItem(
        'Gender',
        _originalGender.isEmpty ? '(Not set)' : _originalGender,
        _selectedGender.isEmpty ? '(Not set)' : _selectedGender,
      ));
    }
    
    // Birthdate changes
    if (_selectedBirthdate != _originalBirthdate) {
      final originalDateStr = _originalBirthdate != null 
          ? DateFormat('MMMM d, yyyy').format(_originalBirthdate!)
          : '(Not set)';
      final newDateStr = _selectedBirthdate != null 
          ? DateFormat('MMMM d, yyyy').format(_selectedBirthdate!)
          : '(Not set)';
      
      changes.add(_buildChangeItem(
        'Birthdate',
        originalDateStr,
        newDateStr,
      ));
    }
    
    // Photo changes
    if (_selectedImageFile != null || _selectedImageBytes != null || _hasNewPhoto) {
      changes.add(_buildChangeItem(
        'Profile Photo',
        _originalPhotoURL.isEmpty ? '(No photo)' : 'Current photo',
        'New photo selected',
      ));
    }
    
    if (changes.isEmpty) {
      changes.add(
        Text(
          'No changes detected',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    return changes;
  }

  Widget _buildChangeItem(String label, String before, String after) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            TextSpan(
              text: before,
              style: TextStyle(
                color: AppColors.error,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const TextSpan(
              text: ' → ',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
            TextSpan(
              text: after,
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges(),
      onPopInvoked: (didPop) {
        if (!didPop && _hasChanges()) {
          _showDiscardChangesDialog();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () {
            if (_hasChanges()) {
              _showDiscardChangesDialog();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Row(
          children: [
            Icon(Icons.edit_outlined, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              'Edit Profile',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading && !_hasLoadedData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    
                    // Profile Photo Section
                    _buildProfilePhotoSection(),
                    const SizedBox(height: 32),
                    
                    // Basic Information Section
                    _buildSectionHeader('Basic Information'),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.onSurface.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _displayNameController,
                            label: 'Display Name',
                            icon: Icons.badge_outlined,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Display name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _firstNameController,
                            label: 'First Name',
                            icon: Icons.person_outline,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'First name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _middleNameController,
                            label: 'Middle Name (Optional)',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildTextField(
                            controller: _lastNameController,
                            label: 'Last Name',
                            icon: Icons.person_outline,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Last name is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Personal Details Section
                    _buildSectionHeader('Personal Details'),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.onSurface.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gender Selection
                          Text(
                            'Gender',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.onSurface.withValues(alpha: 0.2),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonFormField<String>(
                              value: _selectedGender.isEmpty ? null : _selectedGender,
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.wc_outlined,
                                  color: AppColors.primary,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              hint: Text(
                                'Select gender',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'male',
                                  child: Text('Male'),
                                ),
                                DropdownMenuItem(
                                  value: 'female',
                                  child: Text('Female'),
                                ),
                                DropdownMenuItem(
                                  value: 'rather not say',
                                  child: Text('Rather not say'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedGender = value ?? '';
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select your gender';
                                }
                                return null;
                              },
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Birthdate Selection
                          Text(
                            'Birthdate',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _selectBirthdate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.onSurface.withValues(alpha: 0.2),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      _selectedBirthdate != null
                                          ? DateFormat('MMMM d, yyyy').format(_selectedBirthdate!)
                                          : 'Select birthdate',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: _selectedBirthdate != null
                                            ? AppColors.onSurface
                                            : AppColors.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: AppColors.onSurface.withValues(alpha: 0.6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Action Buttons
                    if (_hasLoadedData) ...[
                      Row(
                        children: [
                          // Cancel Button
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : () {
                                if (_hasChanges()) {
                                  _showDiscardChangesDialog();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppColors.onSurface.withValues(alpha: 0.3)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: AppTextStyles.buttonLarge.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Save Button
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_isLoading || !_hasChanges()) ? null : _saveProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _hasChanges() ? AppColors.primary : AppColors.grey300,
                                foregroundColor: AppColors.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: AppColors.onPrimary,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Save Changes',
                                      style: AppTextStyles.buttonLarge.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: _hasChanges() ? AppColors.onPrimary : AppColors.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ), // Close PopScope
    );
  }

  Widget _buildProfilePhotoSection() {
    return Center(
      child: Column(
        children: [
          // Profile Photo
          GestureDetector(
            onTap: _showPhotoSelectionDialog,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipOval(
                    child: Container(
                      width: 120,
                      height: 120,
                      color: AppColors.grey100,
                      child: _buildPhotoContent(),
                    ),
                  ),
                  // Upload overlay
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: AppColors.onPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  // Loading overlay
                  if (_isUploadingPhoto)
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.onSurface.withValues(alpha: 0.7),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.onPrimary,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap to change photo',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (_selectedImageFile != null || _selectedImageBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'New photo selected',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoContent() {
    // Show selected image first
    if (_selectedImageBytes != null) {
      return Image.memory(
        _selectedImageBytes!,
        fit: BoxFit.cover,
        width: 120,
        height: 120,
      );
    }
    
    if (_selectedImageFile != null) {
      return Image.file(
        _selectedImageFile!,
        fit: BoxFit.cover,
        width: 120,
        height: 120,
      );
    }
    
    // Show current photo
    if (_currentPhotoURL != null && _currentPhotoURL!.isNotEmpty) {
      return Image.network(
        _currentPhotoURL!,
        fit: BoxFit.cover,
        width: 120,
        height: 120,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultAvatar();
        },
      );
    }
    
    // Show default avatar
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 120,
      height: 120,
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Icon(
        Icons.person,
        size: 60,
        color: AppColors.primary.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      style: AppTextStyles.bodyMedium,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.onSurface.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

