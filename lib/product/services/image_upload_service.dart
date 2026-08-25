import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:dentpal/utils/app_logger.dart';
import '../../core/app_theme/app_colors.dart';
import '../../core/app_theme/app_text_styles.dart';
import '../../core/app_theme/ink_palette.dart';

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
  Future<Uint8List?> resizeImage(
    XFile imageFile, {
    bool forceSquare = false,
    int maxWidth = 1280,
    int maxHeight = 720,
    int quality = 82,
  }) async {
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
        // Calculate the size to maintain aspect ratio within maxWidth x maxHeight
        targetWidth = maxWidth;
        targetHeight = maxHeight;

        final aspectRatio = image.width / image.height;

        if (aspectRatio > 1) {
          // Landscape: width is larger
          targetHeight = (targetWidth / aspectRatio).round();
        } else {
          // Portrait: height is larger
          targetWidth = (targetHeight * aspectRatio).round();
        }

        // Never upscale: cap targets to the source dimensions.
        if (targetWidth > image.width) targetWidth = image.width;
        if (targetHeight > image.height) targetHeight = image.height;
      }

      // Resize the image
      final resized = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.cubic,
      );

      // Convert to bytes at the requested JPEG quality
      final resizedBytes = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(resizedBytes);
    } catch (e) {
      AppLogger.d('Error resizing image: $e');
      return null;
    }
  }

  /// Generate a small square thumbnail (JPEG) for use in grids/lists/carts.
  ///
  /// Kept intentionally tiny — the full-size image is uploaded separately and
  /// used only on the product detail page. On Flutter web the `image` package
  /// cannot encode WebP, so thumbnails produced here are JPEG (the seller-center
  /// web app emits WebP thumbnails; both display fine everywhere).
  Future<Uint8List?> resizeThumbnail(
    XFile imageFile, {
    int size = 400,
    int quality = 75,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        AppLogger.d('Failed to decode image for thumbnail');
        return null;
      }

      final thumb = img.copyResizeCropSquare(
        image,
        size: size,
        interpolation: img.Interpolation.average,
      );
      return Uint8List.fromList(img.encodeJpg(thumb, quality: quality));
    } catch (e) {
      AppLogger.d('Error creating thumbnail: $e');
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
    bool forceSquare = false,
    int maxWidth = 1280,
    int maxHeight = 720,
    int quality = 82,
  }) async {
    try {
      // Pick image
      final pickedFile = await pickImage(source: source);
      if (pickedFile == null) return null;

      // Resize image
      final resizedBytes = await resizeImage(
        pickedFile,
        forceSquare: forceSquare,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
      );
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

  /// "Camera or gallery?", in the marketplace sheet shape.
  ///
  /// Carried no colours at all before, so it fell back to the Material theme —
  /// which is still the light one — and opened as a white sheet over pages that
  /// had already gone dark.
  Future<ImageSource?> showImageSourceDialog(BuildContext context) async {
    final ink = InkPalette.of(context);

    return await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: ink.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: ink.border),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ink.text.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _imageSourceRow(
                ink: ink,
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                detail: 'Take a new photo',
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              _imageSourceRow(
                ink: ink,
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                detail: 'Choose one you already have',
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  /// One option in the sheet, in the icon-tile row shape the menus use.
  Widget _imageSourceRow({
    required InkPalette ink,
    required IconData icon,
    required String label,
    required String detail,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ink.emerald.withValues(
                    alpha: ink.isDark ? 0.16 : 0.11,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: ink.emerald, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: ink.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ink.text.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generate storage path for product images
  static String getProductImagePath(String productId) {
    return 'ProductImages/$productId/Image';
  }

  /// Generate storage path for the small product thumbnail
  static String getProductThumbnailPath(String productId) {
    return 'ProductImages/$productId/Thumb';
  }

  /// Generate storage path for variation images
  static String getVariationImagePath(String productId, int variationIndex) {
    return 'ProductImages/$productId/Image/VariationImage_$variationIndex';
  }

  /// Generate storage path for the small variation thumbnail
  static String getVariationThumbnailPath(String productId, int variationIndex) {
    return 'ProductImages/$productId/Image/VariationThumb_$variationIndex';
  }
}
