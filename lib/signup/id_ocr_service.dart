import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'signup_controller.dart';

/// Simplified OCR Service for Philippine PRC ID Verification
/// 
/// Validates:
/// 1. Government ID header (PRC)
/// 2. First name match
/// 3. Last name match  
/// 4. Registration number extraction
/// 5. Valid expiry date
/// 6. Face detection on ID
class IdOcrService {
  static final TextRecognizer _textRecognizer = TextRecognizer();
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableTracking: false,
    ),
  );

  static Future<IdVerificationResult> processIdImage(
    String imagePath,
    String expectedFirstName,
    String expectedLastName,
  ) async {
    try {
      SignupController.logOcrResult('START', 'Starting simplified ID OCR');
      
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final rawText = recognizedText.text.toUpperCase();
      
      SignupController.logOcrResult('RAW_TEXT', 'OCR Output:\n$rawText');
      
      // Step 1: Detect face on ID
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        SignupController.logOcrResult('ERROR', 'No face detected on ID');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'No photo detected on ID. Please ensure the ID photo is visible.',
          registrationNumber: null,
          faceImage: null,
        );
      }
      SignupController.logOcrResult('SUCCESS', 'Face detected on ID');
      
      // Step 2: Check if this is a valid PRC ID
      if (!_isPrcId(rawText)) {
        SignupController.logOcrResult('ERROR', 'Not a valid PRC ID');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'This is not a valid PRC Professional ID. Please use your PRC ID.',
          registrationNumber: null,
          faceImage: null,
        );
      }
      
      // Step 3: Find registration number
      String? regNumber = _extractRegistrationNumber(rawText);
      if (regNumber == null) {
        SignupController.logOcrResult('ERROR', 'Registration number not found');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'Could not read registration number. Please ensure the ID is clear.',
          registrationNumber: null,
          faceImage: null,
        );
      }
      SignupController.logOcrResult('SUCCESS', 'Registration: $regNumber');
      
      // Step 3: Check if ID is expired
      bool isExpired = _isIdExpired(rawText);
      if (isExpired) {
        SignupController.logOcrResult('ERROR', 'ID is expired');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'Your PRC ID has expired. Please renew it before registration.',
          registrationNumber: regNumber,
        );
      }
      
      // Step 4: Verify names
      bool firstNameMatch = _findName(rawText, expectedFirstName);
      bool lastNameMatch = _findName(rawText, expectedLastName);
      
      if (!firstNameMatch && !lastNameMatch) {
        SignupController.logOcrResult('ERROR', 'Neither name found');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'Name does not match. Please ensure this is your PRC ID.',
          registrationNumber: regNumber,
        );
      }
      
      if (!firstNameMatch) {
        SignupController.logOcrResult('ERROR', 'First name not found');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'First name does not match. Please check your entry.',
          registrationNumber: regNumber,
          faceImage: null,
        );
      }
      
      if (!lastNameMatch) {
        SignupController.logOcrResult('ERROR', 'Last name not found');
        return IdVerificationResult(
          isValid: false,
          errorMessage: 'Last name does not match. Please check your entry.',
          registrationNumber: regNumber,
          faceImage: null,
        );
      }
      
      // All checks passed! Read the image file and convert to bytes
      SignupController.logOcrResult('SUCCESS', 'ID verification successful');
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      
      return IdVerificationResult(
        isValid: true,
        errorMessage: null,
        registrationNumber: regNumber,
        faceImage: imageBytes, // Return image as Uint8List
      );
      
    } catch (e) {
      SignupController.logOcrResult('ERROR', 'OCR failed: $e');
      return IdVerificationResult(
        isValid: false,
        errorMessage: 'Failed to read ID. Please try again with better lighting.',
        registrationNumber: null,
        faceImage: null,
      );
    }
  }

  /// Check if text contains PRC ID markers
  static bool _isPrcId(String text) {
    bool hasPRC = text.contains('PROFESSIONAL REGULATION COMMISSION') ||
                  text.contains('PROFESSIONAL REGULATION') ||
                  text.contains('PRC');
    
    bool hasIDCard = text.contains('PROFESSIONAL IDENTIFICATION CARD') ||
                     text.contains('IDENTIFICATION CARD') ||
                     (text.contains('PROF') && text.contains('CARD'));
    
    SignupController.logOcrResult('CHECK', 'PRC: $hasPRC, ID Card: $hasIDCard');
    return hasPRC && hasIDCard;
  }

  /// Extract registration number from text
  static String? _extractRegistrationNumber(String text) {
    // Pattern 1: "REGISTRATION NO. 1234567" or "REGISTRATION NO.1234567"
    RegExp pattern1 = RegExp(r'REGISTRATION\s*NO\.?\s*(\d{4,8})');
    Match? match = pattern1.firstMatch(text);
    if (match != null) {
      String number = match.group(1)!;
      SignupController.logOcrResult('FOUND', 'Reg pattern 1: $number');
      return number;
    }

    // Pattern 2: "REG NO. 1234567" or similar variants
    RegExp pattern2 = RegExp(r'REG(?:ISTRATION)?\s*NO\.?\s*(\d{4,8})');
    match = pattern2.firstMatch(text);
    if (match != null) {
      String number = match.group(1)!;
      SignupController.logOcrResult('FOUND', 'Reg pattern 2: $number');
      return number;
    }

    // Pattern 3: Standalone 6-7 digit number (most common format)
    List<String> lines = text.split('\n');
    for (String line in lines) {
      RegExp digitPattern = RegExp(r'^\d{6,7}$');
      Match? digitMatch = digitPattern.firstMatch(line.trim());
      if (digitMatch != null) {
        String number = digitMatch.group(0)!;
        SignupController.logOcrResult('FOUND', 'Reg pattern 3: $number');
        return number;
      }
    }

    SignupController.logOcrResult('ERROR', 'No registration number found');
    return null;
  }

  /// Check if any date in the text indicates expiry
  static bool _isIdExpired(String text) {
    DateTime now = DateTime.now();
    
    // Look for date patterns
    RegExp datePattern = RegExp(r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})');
    Iterable<Match> matches = datePattern.allMatches(text);
    
    for (Match match in matches) {
      try {
        int part1 = int.parse(match.group(1)!);
        int part2 = int.parse(match.group(2)!);
        int year = int.parse(match.group(3)!);
        
        // Try MM/dd/yyyy (common in Philippines)
        if (part1 <= 12 && part2 <= 31) {
          DateTime date = DateTime(year, part1, part2);
          SignupController.logOcrResult('DATE', 'Found date: $date (${date.isAfter(now) ? "valid" : "expired"})');
          
          // If date is in the future, ID is still valid
          if (date.isAfter(now)) {
            return false; // Not expired
          }
        }
      } catch (e) {
        continue;
      }
    }
    
    // If we found dates but none are in the future, it's expired
    // If we found no dates, assume not expired (benefit of doubt)
    bool expired = matches.isNotEmpty;
    SignupController.logOcrResult('EXPIRY', 'ID expired: $expired');
    return expired;
  }

  /// Find if name exists in text (flexible matching)
  static bool _findName(String text, String name) {
    String normalizedName = name.toUpperCase().trim();
    
    // Split name into words (for "JUAN DELA CRUZ" -> ["JUAN", "DELA", "CRUZ"])
    List<String> nameWords = normalizedName
        .split(' ')
        .where((w) => w.isNotEmpty && w.length >= 2)
        .toList();
    
    SignupController.logOcrResult('NAME_CHECK', 'Looking for: $normalizedName (${nameWords.length} words)');
    
    // Check if ANY significant word from the name appears in text
    for (String word in nameWords) {
      if (text.contains(word)) {
        SignupController.logOcrResult('NAME_MATCH', 'Found "$word" in OCR text');
        return true;
      }
      
      // Also check substring match (e.g., "UAN" for "JUAN")
      if (word.length >= 4) {
        String substring = word.substring(1); // Remove first letter
        if (text.contains(substring)) {
          SignupController.logOcrResult('NAME_MATCH', 'Found substring "$substring" for "$word"');
          return true;
        }
      }
    }
    
    SignupController.logOcrResult('NAME_NO_MATCH', 'Name "$normalizedName" not found');
    return false;
  }

  static void dispose() {
    _textRecognizer.close();
    _faceDetector.close();
  }
}

/// Simple result class
class IdVerificationResult {
  final bool isValid;
  final String? errorMessage;
  final String? registrationNumber;
  final String? faceImage; // Path to the ID image containing the face

  IdVerificationResult({
    required this.isValid,
    this.errorMessage,
    this.registrationNumber,
    this.faceImage,
  });

  @override
  String toString() {
    return 'IdVerificationResult(isValid: $isValid, error: $errorMessage, regNum: $registrationNumber, faceImage: ${faceImage != null ? "present" : "null"})';
  }
}
