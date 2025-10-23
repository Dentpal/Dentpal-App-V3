import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:dentpal/core/app_theme/index.dart';
import 'package:dentpal/utils/app_logger.dart';

class FaceVerificationCamera extends StatefulWidget {
  final Function(Uint8List imageBytes) onFaceVerified;
  final VoidCallback onCancel;

  const FaceVerificationCamera({
    super.key,
    required this.onFaceVerified,
    required this.onCancel,
  });

  @override
  State<FaceVerificationCamera> createState() => _FaceVerificationCameraState();
}

class _FaceVerificationCameraState extends State<FaceVerificationCamera> {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _faceDetected = false;
  bool _isCapturing = false;
  List<Face> _faces = [];
  
  // Liveness check variables
  bool _livenessCheckStarted = false;
  bool _blinkDetected = false;
  bool _leftTurnDetected = false;
  bool _rightTurnDetected = false;
  bool _centerPositionDetected = false;
  bool _allLivenessChecksPassed = false;
  
  // Blink detection variables
  int _eyesClosedFrames = 0;
  int _eyesOpenFrames = 0;
  bool _eyesClosed = false;
  
  // Head turn detection variables
  double _currentHeadAngleY = 0.0;
  int _leftTurnFrames = 0;
  int _rightTurnFrames = 0;
  int _centerFrames = 0;
  
  String _statusMessage = "Position your face in the frame";
  Color _statusColor = AppColors.grey600;
  
  // Reset timer for when face is not detected
  Timer? _resetTimer;
  
  // Capture countdown timer
  Timer? _captureTimer;
  int _captureCountdown = 0;

  @override
  void initState() {
    AppLogger.d('🎭 FaceVerificationCamera initState called');
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: Platform.isIOS ? 0.05 : 0.1, // Lower threshold for iOS
        performanceMode: Platform.isIOS 
            ? FaceDetectorMode.fast  // Use fast mode for better real-time performance on iOS
            : FaceDetectorMode.accurate,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        Platform.isIOS ? ResolutionPreset.medium : ResolutionPreset.high, // Use medium for better iOS performance
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
        
        // Start image stream for face detection
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
    if (_isProcessing || _isCapturing || _captureCountdown > 0) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage != null) {
        try {
          final faces = await _faceDetector.processImage(inputImage);
          
          if (mounted) {
            setState(() {
              _faces = faces;
              _faceDetected = faces.isNotEmpty;
              
              // Debug logging for iOS
              if (Platform.isIOS) {
                AppLogger.d('iOS Face Detection - Faces found: ${faces.length}');
                if (faces.isNotEmpty) {
                  final face = faces.first;
                  AppLogger.d('Face box: ${face.boundingBox.width}x${face.boundingBox.height}');
                  AppLogger.d('Head angles Y: ${face.headEulerAngleY}, Z: ${face.headEulerAngleZ}');
                  AppLogger.d('Eye probabilities L: ${face.leftEyeOpenProbability}, R: ${face.rightEyeOpenProbability}');
                }
              }
              
              _updateStatusMessage(faces);
            });
          }
        } on PlatformException catch (e) {
          // Handle camera buffer issues gracefully
          if (e.code == 'IllegalArgumentException' && e.message?.contains('Bad position') == true) {
            AppLogger.d('Camera buffer issue detected, skipping frame: ${e.message}');
            // Simply skip this frame and continue with next one
          } else {
            AppLogger.d('ML Kit error processing image: $e');
          }
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

  void _updateStatusMessage(List<Face> faces) {
    // Don't update status during capture process
    if (_isCapturing || _captureCountdown > 0) {
      return;
    }
    
    if (faces.isEmpty) {
      _statusMessage = "No face detected. Move closer to camera.";
      _statusColor = AppColors.warning;
      
      // Start 3-second timer before resetting if not already started
      if (_resetTimer == null && _livenessCheckStarted) {
        _resetTimer = Timer(const Duration(seconds: 3), () {
          _resetLivenessCheck();
          _resetTimer = null;
        });
      }
    } else if (faces.length > 1) {
      _statusMessage = "Multiple faces detected. Only one person should be in frame.";
      _statusColor = AppColors.warning;
      
      // Start 3-second timer before resetting if not already started
      if (_resetTimer == null && _livenessCheckStarted) {
        _resetTimer = Timer(const Duration(seconds: 3), () {
          _resetLivenessCheck();
          _resetTimer = null;
        });
      }
    } else {
      // Cancel reset timer if face is detected again
      if (_resetTimer != null) {
        _resetTimer!.cancel();
        _resetTimer = null;
      }
      
      final face = faces.first;
      
      // Check if face is properly positioned for initial detection
      // iOS typically reports smaller bounding boxes, so adjust thresholds
      final minFaceSize = Platform.isIOS ? 100 : 150;
      if (face.boundingBox.width < minFaceSize || face.boundingBox.height < minFaceSize) {
        _statusMessage = "Move closer to the camera";
        _statusColor = AppColors.warning;
        _resetLivenessCheck();
        return;
      }
      
      // Start liveness check once face is properly positioned
      if (!_livenessCheckStarted) {
        _livenessCheckStarted = true;
        _statusMessage = "Good! Now follow the instructions for liveness check";
        _statusColor = AppColors.primary;
        return;
      }
      
      // Perform liveness checks
      _performLivenessChecks(face);
    }
  }

  void _resetLivenessCheck() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    _captureCountdown = 0;
    _livenessCheckStarted = false;
    _blinkDetected = false;
    _leftTurnDetected = false;
    _rightTurnDetected = false;
    _centerPositionDetected = false;
    _allLivenessChecksPassed = false;
    _eyesClosedFrames = 0;
    _eyesOpenFrames = 0;
    _eyesClosed = false;
    _leftTurnFrames = 0;
    _rightTurnFrames = 0;
    _centerFrames = 0;
    
    // Reset status message when not capturing
    if (!_isCapturing && mounted) {
      setState(() {
        _statusMessage = "Position your face in the frame";
        _statusColor = AppColors.grey600;
      });
    }
  }

  void _performLivenessChecks(Face face) {
    // Update current head angle
    _currentHeadAngleY = face.headEulerAngleY ?? 0.0;
    
    // Check for blink detection
    if (!_blinkDetected) {
      _checkForBlink(face);
      if (!_blinkDetected) {
        _statusMessage = "Please blink your eyes";
        _statusColor = AppColors.primary;
        return;
      }
    }
    
    // Check for head turns
    if (_blinkDetected && !_leftTurnDetected) {
      _checkForLeftTurn();
      if (!_leftTurnDetected) {
        _statusMessage = "Good! Now turn your head to the left";
        _statusColor = AppColors.primary;
        return;
      }
    }
    
    if (_blinkDetected && _leftTurnDetected && !_centerPositionDetected) {
      _checkForCenterPosition();
      if (!_centerPositionDetected) {
        _statusMessage = "Great! Now look straight ahead";
        _statusColor = AppColors.primary;
        return;
      }
    }
    
    if (_blinkDetected && _leftTurnDetected && _centerPositionDetected && !_rightTurnDetected) {
      _checkForRightTurn();
      if (!_rightTurnDetected) {
        _statusMessage = "Excellent! Now turn your head to the right";
        _statusColor = AppColors.primary;
        return;
      }
    }
    
    // All checks passed
    if (_blinkDetected && _leftTurnDetected && _centerPositionDetected && _rightTurnDetected) {
      _allLivenessChecksPassed = true;
      
      // Start automatic capture countdown if not already started
      if (_captureTimer == null && !_isCapturing) {
        _startCaptureCountdown();
      }
    }
  }

  void _startCaptureCountdown() {
    _captureCountdown = 3;
    
    setState(() {
      _statusMessage = "Capturing in $_captureCountdown...";
      _statusColor = AppColors.primary;
    });
    
    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _captureCountdown--;
          if (_captureCountdown > 0) {
            _statusMessage = "Capturing in $_captureCountdown...";
          } else {
            _statusMessage = "Capturing now! Hold still...";
            timer.cancel();
            _captureTimer = null;
            // Automatically capture the photo
            _captureAndVerifyFace();
          }
        });
      } else {
        timer.cancel();
        _captureTimer = null;
      }
    });
  }

  void _checkForBlink(Face face) {
    bool eyesClosed = false;
    
    if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
      // iOS might need more lenient eye closure detection
      final eyeClosureThreshold = Platform.isIOS ? 0.4 : 0.3;
      eyesClosed = face.leftEyeOpenProbability! < eyeClosureThreshold && 
                   face.rightEyeOpenProbability! < eyeClosureThreshold;
    }
    
    if (eyesClosed) {
      _eyesClosedFrames++;
      _eyesOpenFrames = 0;
      // Use fewer frames for iOS for more responsive detection
      final minClosedFrames = Platform.isIOS ? 2 : 3;
      if (_eyesClosedFrames >= minClosedFrames && !_eyesClosed) {
        _eyesClosed = true;
      }
    } else {
      _eyesOpenFrames++;
      _eyesClosedFrames = 0;
      // Use fewer frames for iOS for more responsive detection
      final minOpenFrames = Platform.isIOS ? 2 : 3;
      if (_eyesOpenFrames >= minOpenFrames && _eyesClosed) {
        _blinkDetected = true;
        _eyesClosed = false;
      }
    }
  }

  void _checkForLeftTurn() {
    // iOS might have different angle conventions, so adjust thresholds
    final leftThreshold = Platform.isIOS ? 10 : 15;
    if (_currentHeadAngleY > leftThreshold) {  // Head turned left (positive angle)
      _leftTurnFrames++;
      if (_leftTurnFrames >= (Platform.isIOS ? 8 : 10)) {  // Slightly fewer frames for iOS
        _leftTurnDetected = true;
      }
    } else {
      _leftTurnFrames = 0;
    }
  }

  void _checkForCenterPosition() {
    // More lenient center position for iOS
    final centerThreshold = Platform.isIOS ? 15 : 10;
    if (_currentHeadAngleY.abs() < centerThreshold) {  // Head in center position
      _centerFrames++;
      if (_centerFrames >= (Platform.isIOS ? 8 : 10)) {  // Slightly fewer frames for iOS
        _centerPositionDetected = true;
      }
    } else {
      _centerFrames = 0;
    }
  }

  void _checkForRightTurn() {
    // iOS might have different angle conventions, so adjust thresholds
    final rightThreshold = Platform.isIOS ? -10 : -15;
    if (_currentHeadAngleY < rightThreshold) {  // Head turned right (negative angle)
      _rightTurnFrames++;
      if (_rightTurnFrames >= (Platform.isIOS ? 8 : 10)) {  // Slightly fewer frames for iOS
        _rightTurnDetected = true;
      }
    } else {
      _rightTurnFrames = 0;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage cameraImage) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      // For iOS, we need to handle rotation differently for front camera
      if (camera.lensDirection == CameraLensDirection.front) {
        // Front camera on iOS typically needs 270 degree rotation for portrait
        rotation = InputImageRotation.rotation270deg;
      } else {
        rotation = InputImageRotation.rotation90deg;
      }
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
    InputImageFormat finalFormat;
    
    if (format == null) {
      // iOS fallback - assume bgra8888 if format detection fails
      if (Platform.isIOS) {
        AppLogger.d('iOS: Format detection failed, using bgra8888 fallback');
        finalFormat = InputImageFormat.bgra8888;
      } else {
        return null;
      }
    } else if (Platform.isAndroid && format != InputImageFormat.nv21) {
      return null;
    } else if (Platform.isIOS && format != InputImageFormat.bgra8888) {
      AppLogger.d('iOS: Unexpected format ${format.name}, trying to proceed anyway');
      finalFormat = format;
    } else {
      finalFormat = format;
    }

    // iOS can have multiple planes, Android typically has 1
    if (Platform.isAndroid && cameraImage.planes.length != 1) return null;
    if (Platform.isIOS && cameraImage.planes.isEmpty) return null;
    
    final plane = cameraImage.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: rotation,
        format: finalFormat,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> _captureAndVerifyFace() async {
    if (_isCapturing || !_faceDetected || _faces.isEmpty || !_allLivenessChecksPassed) {
      if (!_allLivenessChecksPassed) {
        _showSnackBar("Please complete all liveness checks first");
      }
      return;
    }
    
    // Check if face meets quality criteria
    final face = _faces.first;
    final minFaceSize = Platform.isIOS ? 100 : 150;
    if (face.boundingBox.width < minFaceSize || face.boundingBox.height < minFaceSize) {
      _showSnackBar("Move closer to the camera");
      return;
    }
    
    // Final check: face should be in center position for capture
    // More lenient angle checking for iOS
    final angleThreshold = Platform.isIOS ? 15 : 10;
    if (face.headEulerAngleY!.abs() > angleThreshold || face.headEulerAngleZ!.abs() > angleThreshold) {
      _showSnackBar("Please look straight at the camera for capture");
      return;
    }
    
    // More lenient eye open probability for iOS
    final eyeOpenThreshold = Platform.isIOS ? 0.5 : 0.7;
    if ((face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < eyeOpenThreshold) ||
        (face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < eyeOpenThreshold)) {
      _showSnackBar("Please keep your eyes open for capture");
      return;
    }

    setState(() {
      _isCapturing = true;
      _statusMessage = "Capturing image...";
      _statusColor = AppColors.primary;
    });

    try {
      // Stop the image stream before capturing
      await _cameraController!.stopImageStream();
      
      // Add a small delay to ensure the stream is fully stopped
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Update status before capture
      if (mounted) {
        setState(() {
          _statusMessage = "Processing...";
        });
      }
      
      // Capture the image
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();
      
      // Update status during verification
      if (mounted) {
        setState(() {
          _statusMessage = "Verifying face...";
        });
      }
      
      // Verify the captured image has a face
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final capturedFaces = await _faceDetector.processImage(inputImage);
      
      if (capturedFaces.isNotEmpty) {
        // Success - update status and call callback
        if (mounted) {
          setState(() {
            _statusMessage = "Face verification successful!";
            _statusColor = AppColors.success;
          });
        }
        
        // Small delay to show success message
        await Future.delayed(const Duration(milliseconds: 500));
        
        widget.onFaceVerified(imageBytes);
      } else {
        _showSnackBar("No face detected in captured image. Please try again.");
        // Reset and restart
        _resetLivenessCheck();
        if (mounted && _cameraController != null) {
          _cameraController!.startImageStream(_processCameraImage);
        }
      }
    } catch (e) {
      AppLogger.d('Error capturing image: $e');
      _showSnackBar("Failed to capture image. Please try again.");
      // Reset and restart
      _resetLivenessCheck();
      if (mounted && _cameraController != null) {
        _cameraController!.startImageStream(_processCameraImage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildProgressIndicator(String label, bool completed) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? AppColors.success : Colors.transparent,
            border: Border.all(
              color: completed ? AppColors.success : Colors.white.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: completed
              ? Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                )
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: completed ? AppColors.success : Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Initializing camera...',
                style: AppTextStyles.bodyLarge.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview with proper scaling to fill screen
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize!.height,
                height: _cameraController!.value.previewSize!.width,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          
          // Face detection overlay
          if (_faces.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: FaceOverlayPainter(
                  faces: _faces,
                  imageSize: Size(
                    _cameraController!.value.previewSize!.height,
                    _cameraController!.value.previewSize!.width,
                  ),
                  isGoodQuality: _allLivenessChecksPassed,
                  livenessCheckStarted: _livenessCheckStarted,
                ),
              ),
            ),
          
          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onCancel,
                  icon: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Face Verification',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 44), // Balance the close button
              ],
            ),
          ),
          
          // Liveness check progress indicators at the top
          if (_livenessCheckStarted)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Liveness Check Progress',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildProgressIndicator('Blink', _blinkDetected),
                        _buildProgressIndicator('Turn Left', _leftTurnDetected),
                        _buildProgressIndicator('Center', _centerPositionDetected),
                        _buildProgressIndicator('Turn Right', _rightTurnDetected),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          
          // Status message at bottom
          Positioned(
            bottom: 50,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          
          // Capture status indicator
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _faceDetected && _allLivenessChecksPassed
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.3),
                  border: Border.all(
                    color: Colors.white,
                    width: 4,
                  ),
                ),
                child: Center(
                  child: _isCapturing
                      ? CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        )
                      : _captureCountdown > 0
                          ? Text(
                              '$_captureCountdown',
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Icon(
                              _allLivenessChecksPassed ? Icons.check : Icons.camera,
                              color: Colors.white,
                              size: 32,
                            ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}

class FaceOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool isGoodQuality;
  final bool livenessCheckStarted;

  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.isGoodQuality,
    required this.livenessCheckStarted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Color borderColor;
    if (isGoodQuality) {
      borderColor = Colors.green;
    } else if (livenessCheckStarted) {
      borderColor = Colors.blue;
    } else {
      borderColor = Colors.orange;
    }
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = borderColor;

    // Calculate scale factor for FittedBox.cover behavior
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    final double scale = math.max(scaleX, scaleY);
    
    // Calculate offset to center the scaled image
    final double offsetX = (size.width - imageSize.width * scale) / 2;
    final double offsetY = (size.height - imageSize.height * scale) / 2;

    for (final face in faces) {
      final rect = Rect.fromLTRB(
        face.boundingBox.left * scale + offsetX,
        face.boundingBox.top * scale + offsetY,
        face.boundingBox.right * scale + offsetX,
        face.boundingBox.bottom * scale + offsetY,
      );
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );
      
      // Draw face landmarks if available
      if (face.landmarks.isNotEmpty) {
        final landmarkPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = borderColor;
        
        for (final landmark in face.landmarks.values) {
          if (landmark != null) {
            final point = Offset(
              landmark.position.x.toDouble() * scale + offsetX,
              landmark.position.y.toDouble() * scale + offsetY,
            );
            canvas.drawCircle(point, 2, landmarkPaint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
