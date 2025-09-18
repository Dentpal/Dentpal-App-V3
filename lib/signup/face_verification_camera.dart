import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:dentpal/core/app_theme/index.dart';

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
  
  String _statusMessage = "Position your face in the frame";
  Color _statusColor = AppColors.grey600;

  @override
  void initState() {
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
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
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
        
        // Start image stream for face detection
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "Camera initialization failed";
          _statusColor = AppColors.error;
        });
      }
    }
  }

  void _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessing || _isCapturing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage != null) {
        final faces = await _faceDetector.processImage(inputImage);
        
        if (mounted) {
          setState(() {
            _faces = faces;
            _faceDetected = faces.isNotEmpty;
            _updateStatusMessage(faces);
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing camera image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _updateStatusMessage(List<Face> faces) {
    if (faces.isEmpty) {
      _statusMessage = "No face detected. Move closer to camera.";
      _statusColor = AppColors.warning;
    } else if (faces.length > 1) {
      _statusMessage = "Multiple faces detected. Only one person should be in frame.";
      _statusColor = AppColors.warning;
    } else {
      final face = faces.first;
      
      // Check if face is properly positioned
      if (face.boundingBox.width < 100 || face.boundingBox.height < 100) {
        _statusMessage = "Move closer to the camera";
        _statusColor = AppColors.warning;
      } else if (face.headEulerAngleY!.abs() > 15 || face.headEulerAngleZ!.abs() > 15) {
        _statusMessage = "Keep your head straight and look directly at camera";
        _statusColor = AppColors.warning;
      } else if (face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.5) {
        _statusMessage = "Please open your eyes";
        _statusColor = AppColors.warning;
      } else if (face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < 0.5) {
        _statusMessage = "Please open your eyes";
        _statusColor = AppColors.warning;
      } else {
        _statusMessage = "Perfect! Tap to capture";
        _statusColor = AppColors.success;
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage cameraImage) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
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
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    if (cameraImage.planes.length != 1) return null;
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

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  Future<void> _captureAndVerifyFace() async {
    if (_isCapturing || !_faceDetected || _faces.isEmpty) return;
    
    // Check if face meets quality criteria
    final face = _faces.first;
    if (face.boundingBox.width < 100 || face.boundingBox.height < 100) {
      _showSnackBar("Move closer to the camera");
      return;
    }
    
    if (face.headEulerAngleY!.abs() > 15 || face.headEulerAngleZ!.abs() > 15) {
      _showSnackBar("Keep your head straight and look directly at camera");
      return;
    }
    
    if ((face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.5) ||
        (face.rightEyeOpenProbability != null && face.rightEyeOpenProbability! < 0.5)) {
      _showSnackBar("Please open your eyes");
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      // Stop the image stream before capturing
      await _cameraController!.stopImageStream();
      
      // Capture the image
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();
      
      // Verify the captured image has a face
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final capturedFaces = await _faceDetector.processImage(inputImage);
      
      if (capturedFaces.isNotEmpty) {
        widget.onFaceVerified(imageBytes);
      } else {
        _showSnackBar("No face detected in captured image. Please try again.");
        // Restart image stream
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint('Error capturing image: $e');
      _showSnackBar("Failed to capture image. Please try again.");
      // Restart image stream
      _cameraController!.startImageStream(_processCameraImage);
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
                  isGoodQuality: _statusColor == AppColors.success,
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
          
          // Status message
          Positioned(
            bottom: 200,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
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
          
          // Capture button
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureAndVerifyFace,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _faceDetected && _statusColor == AppColors.success
                        ? AppColors.primary
                        : Colors.white.withOpacity(0.3),
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                  ),
                  child: _isCapturing
                      ? CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        )
                      : Icon(
                          Icons.camera,
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

  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.isGoodQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = isGoodQuality ? Colors.green : Colors.orange;

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
          ..color = isGoodQuality ? Colors.green : Colors.orange;
        
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
