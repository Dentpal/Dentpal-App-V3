import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';

class ImageUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  /// Pick image from camera or gallery
  Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      return pickedFile;
    } catch (e) {
      AppLogger.d('Error picking image: $e');
      return null;
    }
  }

  /// Pick and crop image to square
  Future<XFile?> pickAndCropImage({required ImageSource source}) async {
    try {
      // First pick the image
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );

      if (pickedFile == null) return null;

      // On web, skip cropping and return the picked file directly
      if (kIsWeb) {
        AppLogger.d('Running on web, skipping image cropping');
        return pickedFile;
      }

      try {
        // Then crop it to square (only on mobile)
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: AppColors.onPrimary,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              aspectRatioPresets: [CropAspectRatioPreset.square],
              showCropGrid: true,
              hideBottomControls: false,
              cropGridStrokeWidth: 2,
              cropGridColor: AppColors.primary,
              activeControlsWidgetColor: AppColors.primary,
            ),
            IOSUiSettings(
              title: 'Crop Image',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              aspectRatioPresets: [CropAspectRatioPreset.square],
              showCancelConfirmationDialog: true,
              rotateClockwiseButtonHidden: false,
              hidesNavigationBar: false,
            ),
          ],
        );

        if (croppedFile != null) {
          return XFile(croppedFile.path);
        }
        
        // If cropping was cancelled, return the original image
        AppLogger.d('Image cropping was cancelled, returning original image');
        return pickedFile;
        
      } catch (cropError) {
        AppLogger.d('Error during cropping, falling back to original image: $cropError');
        // If cropping fails, return the original picked image
        return pickedFile;
      }
      
    } catch (e) {
      AppLogger.d('Error picking and cropping image: $e');
      return null;
    }
  }

  /// Resize image to optimal size while maintaining aspect ratio
  Future<Uint8List?> resizeImage(XFile imageFile, {bool forceSquare = false}) async {
    try {
      // Read the image file bytes (works on both web and mobile)
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        AppLogger.d('Failed to decode image');
        return null;
      }

      int targetWidth;
      int targetHeight;

      if (forceSquare) {
        // For square images, use 1024x1024
        targetWidth = 1024;
        targetHeight = 1024;
      } else {
        // Calculate the size to maintain aspect ratio within 1280x720 (720p)
        targetWidth = 1280;
        targetHeight = 720;
        
        final aspectRatio = image.width / image.height;
        
        if (aspectRatio > 1) {
          // Landscape: width is larger
          targetHeight = (targetWidth / aspectRatio).round();
        } else {
          // Portrait: height is larger
          targetWidth = (targetHeight * aspectRatio).round();
        }
      }

      // Resize the image
      final resized = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.cubic,
      );

      // Convert to bytes with higher quality for better visual results
      final resizedBytes = img.encodeJpg(resized, quality: 95);
      return Uint8List.fromList(resizedBytes);
    } catch (e) {
      AppLogger.d('Error resizing image: $e');
      return null;
    }
  }

  /// Upload image to Firebase Storage
  Future<String?> uploadImage({
    required Uint8List imageBytes,
    required String path,
  }) async {
    try {
      AppLogger.d('Uploading image to: $path');
      
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putData(
        imageBytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaded_at': DateTime.now().toIso8601String(),
          },
        ),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      AppLogger.d('Image uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      AppLogger.d('Error uploading image: $e');
      return null;
    }
  }

  /// Complete flow: pick, resize, and upload image
  Future<String?> pickResizeAndUpload({
    required ImageSource source,
    required String storagePath,
  }) async {
    try {
      // Pick image
      final pickedFile = await pickImage(source: source);
      if (pickedFile == null) return null;

      // Resize image
      final resizedBytes = await resizeImage(pickedFile);
      if (resizedBytes == null) return null;

      // Upload to Firebase Storage
      final downloadUrl = await uploadImage(
        imageBytes: resizedBytes,
        path: storagePath,
      );

      return downloadUrl;
    } catch (e) {
      AppLogger.d('Error in complete image flow: $e');
      return null;
    }
  }

  /// Show image source selection dialog
  Future<ImageSource?> showImageSourceDialog(BuildContext context) async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Image Source',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('Camera'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Generate storage path for product images
  static String getProductImagePath(String productId) {
    return 'ProductImages/$productId/Image';
  }

  /// Generate storage path for variation images
  static String getVariationImagePath(String productId, int variationIndex) {
    return 'ProductImages/$productId/Image/VariationImage_$variationIndex';
  }
}
