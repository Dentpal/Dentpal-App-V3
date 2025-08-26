import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _processing = false;
  String _rawText = '';
  Map<String, String> _parsed = {};

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _processing = true;
        _rawText = '';
        _parsed = {};
      });

      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) {
        setState(() => _processing = false);
        return;
      }

      _imageFile = File(picked.path);
      await _runOCR(_imageFile!);
    } catch (e) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _runOCR(File image) async {
    final inputImage = InputImage.fromFile(image);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognized = await textRecognizer.processImage(inputImage);
      _rawText = recognized.text;
      _parsed = _parsePRC(_rawText);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR failed: $e')));
    } finally {
      await textRecognizer.close();
      if (mounted) setState(() => _processing = false);
    }
  }

  Map<String, String> _parsePRC(String text) {
    // Normalize whitespace and uppercase for easier matching
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final up = normalized.toUpperCase();

    String? findAfter(String label) {
      final lbl = label.toUpperCase();
      final idx = up.indexOf(lbl);
      if (idx == -1) return null;
      final start = idx + lbl.length;
      // allow separators like :, >, ►
      final sub = up.substring(start).trimLeft();
      final match = RegExp(r'^[\:\>\►\s]*([A-Z0-9 \/\\\-.,]+?)((?=LAST NAME|FIRST NAME|MIDDLE NAME|REGISTRATION|REG\. NO|REG NO|REGISTRATION NO|REGISTRATION DATE|VALID UNTIL|OCCUPATIONAL|$))',
              caseSensitive: false)
          .firstMatch(sub);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!.trim();
      }
      // fallback: take first token sequence until a numeric-heavy token
      final fallback = sub.split(RegExp(r'\s{2,}|\n')).first;
      return fallback.isNotEmpty ? fallback.trim() : null;
    }

    final Map<String, String> out = {};

    // Try common labels
    out['last_name'] = (findAfter('LAST NAME') ?? findAfter('SURNAME') ?? '').trim();
    out['first_name'] = (findAfter('FIRST NAME') ?? findAfter('GIVEN NAME') ?? '').trim();
    out['middle_name'] = (findAfter('MIDDLE NAME') ?? '').trim();
    out['registration_no'] = (findAfter('REGISTRATION NO') ?? findAfter('REG. NO') ?? findAfter('REG NO') ?? '').trim();
    out['registration_date'] = (findAfter('REGISTRATION DATE') ?? findAfter('REG DATE') ?? '').trim();
    out['valid_until'] = (findAfter('VALID UNTIL') ?? findAfter('VALIDITY') ?? '').trim();
    out['profession'] = (findAfter('OCCUPATIONAL') ?? findAfter('PROFESSION') ?? '').trim();

    // If registration_no still empty, try to find a sequence of digits
    if ((out['registration_no'] ?? '').isEmpty) {
      final reg = RegExp(r'\b\d{4,}\b').firstMatch(up);
      if (reg != null) out['registration_no'] = reg.group(0) ?? '';
    }

    // Remove empty values
    out.removeWhere((key, value) => value.isEmpty);
    return out;
  }

  void _accept() {
    // Save parsed values into the controller where applicable
    if (_parsed.isNotEmpty) {
      if (_parsed.containsKey('first_name')) {
        widget.controller.firstNameController.text = _parsed['first_name']!;
      }
      if (_parsed.containsKey('last_name')) {
        widget.controller.lastNameController.text = _parsed['last_name']!;
      }
      // Middle name isn't present in the controller as a separate field in the
      // current SignupController; if you add one later, map it here.
      // You may also want to store registration_no in a new controller field.
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID accepted')));
    widget.onBack();
  }

  void _retry() {
    setState(() {
      _imageFile = null;
      _rawText = '';
      _parsed = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 3: ID Verification', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 12),
          const Text('Take a clear photo of your PRC ID or upload an image. The app will try to read Name and Registration details using OCR.'),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Take Photo'),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload'),
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_processing) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('Processing image...')),
          ],

          if (_imageFile != null) ...[
            Center(child: Image.file(_imageFile!, height: 180)),
            const SizedBox(height: 8),
          ],

          if (_rawText.isNotEmpty) ...[
            const Text('Detected text:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Text(_rawText, style: const TextStyle(fontSize: 12)),
              ),
              constraints: const BoxConstraints(maxHeight: 120),
            ),
            const SizedBox(height: 12),
          ],

          if (_parsed.isNotEmpty) ...[
            const Text('Parsed fields:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ..._parsed.entries.map((e) => ListTile(
                  dense: true,
                  title: Text(_prettyKey(e.key)),
                  subtitle: Text(e.value),
                )),
            const SizedBox(height: 12),
          ],

          const Spacer(),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onBack,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _parsed.isNotEmpty ? _accept : null,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43A047)),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _retry,
                tooltip: 'Retry / Clear',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _prettyKey(String k) {
    switch (k) {
      case 'last_name':
        return 'Last name';
      case 'first_name':
        return 'First name';
      case 'middle_name':
        return 'Middle name';
      case 'registration_no':
        return 'Registration No.';
      case 'registration_date':
        return 'Registration date';
      case 'valid_until':
        return 'Valid until';
      case 'profession':
        return 'Profession';
      default:
        return k;
    }
  }
}
