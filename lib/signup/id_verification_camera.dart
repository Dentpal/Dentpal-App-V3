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

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        // Start image stream for text detection
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      AppLogger.d('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "Camera initialization failed";
          _statusColor = AppColors.error;
        });
      }
    }
  }

  void _processCameraImage(CameraImage cameraImage) async {
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
              
              // If we've detected a valid ID for enough consecutive frames, confirm OCR and start capture
              if (_validIdFrames >= _requiredValidFrames && _captureTimer == null) {
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
      await _cameraController!.stopImageStream();
      
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
        
        // Restart image stream
        _cameraController!.startImageStream(_processCameraImage);
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage cameraImage) {
    if (_cameraController == null) return null;

    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) {
        return null;
      }
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          if (_isInitialized && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
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
