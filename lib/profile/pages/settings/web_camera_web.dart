// Web-specific camera widget
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/app_theme/app_colors.dart';
import '../../../core/app_theme/app_text_styles.dart';
import '../../../utils/app_logger.dart';

class WebCameraWidget extends StatefulWidget {
  final Function(Uint8List) onPhotoTaken;
  final VoidCallback onCancel;

  const WebCameraWidget({
    Key? key,
    required this.onPhotoTaken,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<WebCameraWidget> createState() => _WebCameraWidgetState();
}

class _WebCameraWidgetState extends State<WebCameraWidget> {
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  bool _isInitializing = true;
  bool _hasPermission = false;
  String? _errorMessage;
  String? _viewType;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission and get media stream
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        setState(() {
          _errorMessage = 'Camera not supported in this browser';
          _isInitializing = false;
        });
        return;
      }

      _stream = await mediaDevices.getUserMedia({
        'video': {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'facingMode': 'user', // Front camera
        }
      });

      _videoElement = html.VideoElement()
        ..srcObject = _stream
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      // Register the video element with Flutter's platform view registry
      _viewType = 'camera-view-${_videoElement.hashCode}';
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType!,
        (int viewId) => _videoElement!,
      );

      setState(() {
        _hasPermission = true;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Camera permission denied or camera not available';
        _isInitializing = false;
      });
      AppLogger.d('Camera initialization error: $e');
    }
  }

  void _stopCamera() {
    if (_stream != null) {
      _stream!.getTracks().forEach((track) => track.stop());
      _stream = null;
    }
    _videoElement = null;
  }

  Future<void> _takePhoto() async {
    if (_videoElement == null || _stream == null) return;

    try {
      // Create a canvas to capture the video frame
      final canvas = html.CanvasElement();
      final context = canvas.getContext('2d') as html.CanvasRenderingContext2D;
      
      canvas.width = _videoElement!.videoWidth;
      canvas.height = _videoElement!.videoHeight;
      
      // Draw the current video frame to canvas
      context.drawImageScaled(_videoElement!, 0, 0, canvas.width!, canvas.height!);
      
      // Convert canvas to blob
      final blob = await canvas.toBlob('image/jpeg', 0.85);
      
      // Convert blob to Uint8List
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      
      await reader.onLoad.first;
      final Uint8List imageBytes = Uint8List.fromList(
        (reader.result as List<int>),
      );

      // Check file size (3MB limit)
      if (imageBytes.length > 3 * 1024 * 1024) {
        _showErrorMessage('Image size is too large. Please try again.');
        return;
      }

      widget.onPhotoTaken(imageBytes);
    } catch (e) {
      AppLogger.d('Error taking photo: $e');
      _showErrorMessage('Failed to capture photo. Please try again.');
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.camera_alt, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              'Take Photo',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.grey200,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Camera View
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.grey200, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _buildCameraContent(),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Controls
        if (_hasPermission)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _takePhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Capture',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCameraContent() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    if (_hasPermission && _viewType != null) {
      return HtmlElementView(viewType: _viewType!);
    }
    
    return const Center(
      child: Text('Camera not available'),
    );
  }
}
