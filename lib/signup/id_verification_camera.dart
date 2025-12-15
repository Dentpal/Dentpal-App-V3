import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'id_ocr_service.dart';

class IdVerificationCamera extends StatefulWidget {
  final Function(IdVerificationResult result) onIdVerified;
  final VoidCallback onCancel;
  final String expectedFirstName;
  final String expectedLastName;

  const IdVerificationCamera({
    super.key,
    required this.onIdVerified,
    required this.onCancel,
    required this.expectedFirstName,
    required this.expectedLastName,
  });

  @override
  State<IdVerificationCamera> createState() => _IdVerificationCameraState();
}

class _IdVerificationCameraState extends State<IdVerificationCamera> {
  CameraController? _cameraController;
  TextRecognizer? _textRecognizer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _idDetected = false;
  bool _isCapturing = false;
  bool _ocrConfirmed = false; // Flag to stop OCR once PRC ID is confirmed
  
  String _statusMessage = "Position your PRC ID in the frame";
  Color _statusColor = AppColors.grey600;
  
  // Auto-capture timer
  Timer? _captureTimer;
  int _captureCountdown = 0;
  
  // Detection state
  int _validIdFrames = 0;
  static const int _requiredValidFrames = 3; // Need 3 consecutive frames with valid ID
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeTextRecognizer();
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _androidOcrTimer?.cancel();
    _cameraController?.dispose();
    _textRecognizer?.close();
    super.dispose();
  }

  void _initializeTextRecognizer() {
    _textRecognizer = TextRecognizer();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Platform-specific camera configuration
      ResolutionPreset resolutionPreset;
      if (Platform.isIOS) {
        resolutionPreset = ResolutionPreset.high;
      } else {
        // Android: Use medium resolution for stability
        resolutionPreset = ResolutionPreset.high;
      }

      _cameraController = CameraController(
        backCamera,
        resolutionPreset,
        enableAudio: false,
        // Only set imageFormatGroup for iOS - Android will use default
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : null,
      );

      await _cameraController!.initialize();
      
      // Lock orientation for consistent preview
      await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        if (Platform.isIOS) {
          // iOS: Use image stream for real-time OCR
          await Future.delayed(const Duration(milliseconds: 500));
          _cameraController!.startImageStream(_processCameraImage);
        } else {
          // Android: Use periodic photo capture for OCR (avoids CameraX crash)
          await Future.delayed(const Duration(milliseconds: 500));
          _startAndroidPeriodicOcr();
        }
      }
    } catch (e) {
      AppLogger.d('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "Camera initialization failed. Please check permissions.";
          _statusColor = AppColors.error;
        });
      }
    }
  }

  // Android-specific: Periodic OCR using photo capture
  Timer? _androidOcrTimer;
  
  void _startAndroidPeriodicOcr() {
    _androidOcrTimer?.cancel();
    _androidOcrTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_isProcessing || _isCapturing || _ocrConfirmed || !mounted) return;
      await _processAndroidFrame();
    });
  }
  
  void _stopAndroidPeriodicOcr() {
    _androidOcrTimer?.cancel();
    _androidOcrTimer = null;
  }
  
  Future<void> _processAndroidFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isProcessing || _isCapturing || _ocrConfirmed) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // Take a picture for OCR
      final XFile image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      
      if (_textRecognizer != null) {
        final recognizedText = await _textRecognizer!.processImage(inputImage);
        final text = recognizedText.text.toUpperCase();
        
        AppLogger.d('Android OCR (photo): ${text.length} chars detected');
        
        bool isValidId = _isValidGovernmentId(text);
        
        if (mounted) {
          setState(() {
            if (isValidId) {
              _validIdFrames++;
              _idDetected = true;
              _statusMessage = "Valid PRC ID detected! Hold still...";
              _statusColor = Colors.green;
              
              if (_validIdFrames >= _requiredValidFrames && _captureTimer == null) {
                _ocrConfirmed = true;
                _stopAndroidPeriodicOcr();
                _startCaptureCountdown();
              }
            } else if (!_ocrConfirmed) {
              _validIdFrames = 0;
              _idDetected = false;
              _statusMessage = "Position your PRC ID in the frame";
              _statusColor = AppColors.grey600;
              _cancelCapture();
            }
          });
        }
      }
      
      // Clean up temp file
      try {
        await File(image.path).delete();
      } catch (_) {}
      
    } catch (e) {
      AppLogger.d('Android OCR error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // iOS only: Process camera image stream
  void _processCameraImage(CameraImage cameraImage) async {
    // This method is only used on iOS
    if (!Platform.isIOS) return;
    if (_isProcessing || _isCapturing || _ocrConfirmed) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage != null && _textRecognizer != null) {
        final recognizedText = await _textRecognizer!.processImage(inputImage);
        final text = recognizedText.text.toUpperCase();
        
        // Check if this looks like a valid government ID
        bool isValidId = _isValidGovernmentId(text);
        
        if (mounted) {
          setState(() {
            if (isValidId) {
              _validIdFrames++;
              _idDetected = true;
              _statusMessage = "Valid PRC ID detected! Hold still...";
              _statusColor = Colors.green;
              
              // For iOS, reduce the required frames for faster detection
              final requiredFrames = 2;
              
              // If we've detected a valid ID for enough consecutive frames, confirm OCR and start capture
              if (_validIdFrames >= requiredFrames && _captureTimer == null) {
                _ocrConfirmed = true; // Stop further OCR processing
                _startCaptureCountdown();
              }
            } else if (!_ocrConfirmed) {
              // Only reset if OCR hasn't been confirmed yet
              _validIdFrames = 0;
              _idDetected = false;
              _statusMessage = "Position your PRC ID in the frame";
              _statusColor = AppColors.grey600;
              _cancelCapture();
            }
          });
        }
      }
    } catch (e) {
      AppLogger.d('Error processing camera image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  bool _isValidGovernmentId(String text) {
    // Check for required government phrases
    bool hasProfessionalRegulation = text.contains('PROFESSIONAL REGULATION COMMISSION');
    bool hasProfessionalId = text.contains('PROFESSIONAL IDENTIFICATION CARD');
    
    return hasProfessionalRegulation && hasProfessionalId;
  }

  void _startCaptureCountdown() {
    if (_captureTimer != null) return;
    
    _captureCountdown = 3;
    setState(() {
      _statusMessage = "Capturing in $_captureCountdown...";
      _statusColor = AppColors.primary;
    });

    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _captureCountdown--;
        if (_captureCountdown > 0) {
          setState(() {
            _statusMessage = "Capturing in $_captureCountdown...";
          });
        } else {
          timer.cancel();
          _captureTimer = null;
          // Automatically capture the photo
          _captureId();
        }
      }
    });
  }

  void _cancelCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _captureCountdown = 0;
    // Reset OCR confirmation when capture is cancelled
    if (_ocrConfirmed) {
      setState(() {
        _ocrConfirmed = false;
        _validIdFrames = 0;
        _idDetected = false;
        _statusMessage = "Position your PRC ID in the frame";
        _statusColor = AppColors.grey600;
      });
    }
  }

  Future<void> _captureId() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() {
      _isCapturing = true;
      _statusMessage = "Processing PRC ID...";
      _statusColor = AppColors.primary;
    });

    try {
      // Stop the image stream before taking picture
      // Stop image stream on iOS before taking picture
      if (Platform.isIOS) {
        await _cameraController!.stopImageStream();
      }
      
      final XFile image = await _cameraController!.takePicture();
      
      // Update status to show verification in progress
      if (mounted) {
        setState(() {
          _statusMessage = "Verifying PRC ID...";
        });
      }
      
      // Perform full OCR verification on the captured image
      final verificationResult = await IdOcrService.processIdImage(
        image.path,
        widget.expectedFirstName,
        widget.expectedLastName,
      );
      
      // Call the callback with the verification result
      widget.onIdVerified(verificationResult);
      
    } catch (e) {
      AppLogger.d('Error capturing ID: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "Failed to capture PRC ID. Please try again.";
          _statusColor = AppColors.error;
          _isCapturing = false;
          // Reset OCR confirmation so user can try again
          _ocrConfirmed = false;
          _validIdFrames = 0;
          _idDetected = false;
        });
        
        // Restart OCR detection based on platform
        if (Platform.isIOS) {
          _cameraController!.startImageStream(_processCameraImage);
        } else {
          _startAndroidPeriodicOcr();
        }
      }
    }
  }

  // iOS only: Convert camera image to InputImage for ML Kit
  InputImage? _inputImageFromCameraImage(CameraImage cameraImage) {
    // This is only used for iOS image stream
    if (!Platform.isIOS) return null;
    if (_cameraController == null) return null;

    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    rotation ??= InputImageRotation.rotation0deg;

    // iOS BGRA8888 format - single plane
    final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
    if (format == null || format != InputImageFormat.bgra8888) {
      return null;
    }
    
    if (cameraImage.planes.length != 1) {
      return null;
    }
    final plane = cameraImage.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Build camera preview with platform-specific aspect ratio handling
  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final size = MediaQuery.of(context).size;
    final cameraAspectRatio = _cameraController!.value.aspectRatio;
    
    // Platform-specific preview handling
    if (Platform.isIOS) {
      // iOS: Use FittedBox with BoxFit.cover to fill screen while maintaining aspect ratio
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.width * cameraAspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      );
    } else {
      // Android: The aspect ratio is already good, use Transform to fill screen
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.width * cameraAspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview with proper aspect ratio handling
          if (_isInitialized && _cameraController != null)
            Positioned.fill(
              child: _buildCameraPreview(),
            )
          else
            const Center(
              child: CircularProgressIndicator(),
            ),
          
          // Overlay for ID frame
          Positioned.fill(
            child: CustomPaint(
              painter: IdFramePainter(
                idDetected: _idDetected,
                isCapturing: _isCapturing,
              ),
            ),
          ),
          
          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: widget.onCancel,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha:0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ID Verification',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 48), // Placeholder for symmetry
              ],
            ),
          ),
          
          // Bottom status
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha:0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _idDetected ? Icons.check_circle : Icons.badge_outlined,
                    color: _statusColor,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_captureCountdown > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        value: (3 - _captureCountdown) / 3,
                        strokeWidth: 3,
                        backgroundColor: Colors.white.withValues(alpha:0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(_statusColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IdFramePainter extends CustomPainter {
  final bool idDetected;
  final bool isCapturing;

  IdFramePainter({
    required this.idDetected,
    required this.isCapturing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Determine frame color based on state
    if (isCapturing) {
      paint.color = AppColors.primary;
    } else if (idDetected) {
      paint.color = Colors.green;
    } else {
      paint.color = Colors.white.withValues(alpha:0.8);
    }

    // Calculate frame dimensions (credit card ratio: 3.375 x 2.125)
    const aspectRatio = 3.375 / 2.125;
    final frameWidth = size.width * 0.8;
    final frameHeight = frameWidth / aspectRatio;
    
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;

    // Draw main frame
    final rect = Rect.fromLTWH(left, top, frameWidth, frameHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );

    // Draw corner brackets
    final bracketLength = 30.0;
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = paint.color;

    // Top-left corner
    canvas.drawLine(
      Offset(left, top + bracketLength),
      Offset(left, top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(left + bracketLength, top),
      bracketPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(left + frameWidth - bracketLength, top),
      Offset(left + frameWidth, top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(left + frameWidth, top),
      Offset(left + frameWidth, top + bracketLength),
      bracketPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(left, top + frameHeight - bracketLength),
      Offset(left, top + frameHeight),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(left, top + frameHeight),
      Offset(left + bracketLength, top + frameHeight),
      bracketPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(left + frameWidth - bracketLength, top + frameHeight),
      Offset(left + frameWidth, top + frameHeight),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(left + frameWidth, top + frameHeight - bracketLength),
      Offset(left + frameWidth, top + frameHeight),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(IdFramePainter oldDelegate) {
    return oldDelegate.idDetected != idDetected || 
           oldDelegate.isCapturing != isCapturing;
  }
}

// Device orientation mapping for Android
final orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};
