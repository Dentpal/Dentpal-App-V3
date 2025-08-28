import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraPermissionHandler {
  /// Request camera permission
  static Future<bool> requestCameraPermission(BuildContext context) async {
    PermissionStatus status = await Permission.camera.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      // Show a dialog explaining why we need camera permission
      // and provide a button to open app settings
      _showPermissionPermanentlyDeniedDialog(context);
      return false;
    }

    status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Show a dialog when camera permission is permanently denied
  static void _showPermissionPermanentlyDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
            'Camera permission is required to scan QR codes. Please enable it in your device settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
