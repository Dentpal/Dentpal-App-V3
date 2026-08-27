import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dentpal/core/app_theme/app_text_styles.dart';
import 'package:dentpal/core/app_theme/ink_palette.dart';
import 'package:dentpal/core/widgets/auth_chrome.dart';
import 'package:dentpal/utils/app_logger.dart';
import 'id_ocr_service.dart';

/// What the scanner is doing, as one value.
///
/// The page used to carry this as a loose message string and a colour that
/// every OCR callback had to remember to set together — so a state could be
/// half-applied, and the frame, the icon and the words could disagree. The
/// phase is derived from the flags the camera logic already keeps, and the
/// whole overlay is drawn from it.
enum _ScanPhase { starting, searching, found, counting, capturing, failed }

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

class _IdVerificationCameraState extends State<IdVerificationCamera>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  TextRecognizer? _textRecognizer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _idDetected = false;
  bool _isCapturing = false;
  bool _ocrConfirmed = false; // Flag to stop OCR once PRC ID is confirmed
  
  /// Set when the camera could not start, or a capture failed. With
  /// [_isInitialized] still false it is the fatal kind and offers a retry;
  /// otherwise scanning has already resumed underneath it.
  String? _errorMessage;

  /// What the capture is busy with — taking the shot, then reading it.
  String _captureStage = '';

  bool _torchOn = false;

  /// Whether the scan has gone on long enough to be worth advising about.
  ///
  /// Tips are held back rather than shown up front: most scans land in a couple
  /// of seconds, and advice nobody needs yet is just clutter over a viewfinder.
  bool _tipsEarned = false;
  Timer? _tipsTimer;

  /// Drives the sweep line inside the window while the scanner is looking.
  late final AnimationController _sweep;

  // Auto-capture timer
  Timer? _captureTimer;
  int _captureCountdown = 0;
  
  // Detection state
  int _validIdFrames = 0;
  static const int _requiredValidFrames = 3; // Need 3 consecutive frames with valid ID
  
  @override
  void initState() {
    super.initState();
    // A PRC card is landscape, so a portrait phone can only ever give it the
    // narrow axis — about 390pt of window. Turned sideways it gets the long
    // one, and the card lands on the sensor nearly twice the size, which is
    // what the text recogniser actually cares about.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _initializeCamera();
    _initializeTextRecognizer();
  }

  @override
  void dispose() {
    // An empty list is "no preference", which hands the decision back to the
    // platform — rather than pinning the rest of the app to portrait, which is
    // not this page's business to decide.
    SystemChrome.setPreferredOrientations(const []);
    _captureTimer?.cancel();
    _androidOcrTimer?.cancel();
    _tipsTimer?.cancel();
    _sweep.dispose();
    _cameraController?.dispose();
    _textRecognizer?.close();
    super.dispose();
  }

  void _initializeTextRecognizer() {
    _textRecognizer = TextRecognizer();
  }

  /// How long the camera gets to come up before the page gives up on it.
  /// Startup is normally well under a second.
  static const Duration _startupTimeout = Duration(seconds: 8);

  Future<void> _initializeCamera() async {
    // Re-entered by the retry button, so the previous attempt's controller has
    // to go before a new one is built.
    if (_cameraController != null) {
      final previous = _cameraController;
      _cameraController = null;
      try {
        await previous!.dispose();
      } catch (_) {}
    }
    if (mounted) setState(() => _errorMessage = null);

    try {
      // Bounded, because both of these can simply never come back — a wedged
      // camera service, or a permission dialog that was dismissed without an
      // answer. Without a ceiling the page sits on "Starting the camera" with
      // no way forward and only the X to escape with.
      final cameras = await availableCameras().timeout(_startupTimeout);
      if (cameras.isEmpty) {
        throw StateError('This device reports no cameras.');
      }
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

      await _cameraController!.initialize().timeout(_startupTimeout);

      // Deliberately *not* locked. The old portraitUp lock was right for a page
      // that could only be portrait; now that the page turns, a fixed lock
      // would rotate the shot away from what the dentist is looking at — and a
      // card photographed sideways is a card the recogniser cannot read.
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = null;
        });

        _tipsTimer?.cancel();
        _tipsTimer = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => _tipsEarned = true);
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
          _isInitialized = false;
          _errorMessage =
              'We could not open the camera. Check that DentPal is allowed to '
              'use it, then try again.';
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
    
    // Not a setState: nothing on screen reads this, and on the iOS stream path
    // it would rebuild the preview and both painters at frame rate.
    _isProcessing = true;

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
              _errorMessage = null;

              if (_validIdFrames >= _requiredValidFrames && _captureTimer == null) {
                _ocrConfirmed = true;
                _stopAndroidPeriodicOcr();
                _startCaptureCountdown();
              }
            } else if (!_ocrConfirmed) {
              _validIdFrames = 0;
              _idDetected = false;
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
      _isProcessing = false;
    }
  }

  // iOS only: Process camera image stream
  void _processCameraImage(CameraImage cameraImage) async {
    // This method is only used on iOS
    if (!Platform.isIOS) return;
    if (_isProcessing || _isCapturing || _ocrConfirmed) return;
    
    _isProcessing = true;

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
              _errorMessage = null;

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
              _cancelCapture();
            }
          });
        }
      }
    } catch (e) {
      AppLogger.d('Error processing camera image: $e');
    } finally {
      _isProcessing = false;
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
    
    setState(() => _captureCountdown = _countdownFrom);

    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _captureCountdown--;
        if (_captureCountdown > 0) {
          setState(() {});
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
      });
    }
  }

  Future<void> _captureId() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
      _captureStage = 'Taking the shot…';
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
        setState(() => _captureStage = 'Checking your licence…');
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
          _errorMessage =
              'That shot did not come through. Line the card up and we will '
              'try again.';
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

    // The buffer arrives in the sensor's own orientation, which does not turn
    // with the phone — so how far it has to be rotated to read upright depends
    // on how the phone is being held.
    //
    // This used to be the raw sensor orientation, which is the same thing only
    // while the device is portrait — true of this page until it started asking
    // to be turned sideways. The subtraction reduces to the old value at
    // portraitUp, and gives 0° in landscape, where the card's text already runs
    // along the sensor's long axis.
    final deviceDegrees =
        _deviceRotationDegrees[_cameraController!.value.deviceOrientation] ?? 0;
    final compensated = (sensorOrientation - deviceDegrees + 360) % 360;

    final rotation =
        InputImageRotationValue.fromRawValue(compensated) ??
        InputImageRotation.rotation0deg;

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

  /// Clockwise degrees each way of holding the phone represents.
  static const Map<DeviceOrientation, int> _deviceRotationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

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

  // ── The overlay ──────────────────────────────────────────────────────────

  /// Colours for chrome that sits on a live camera feed.
  ///
  /// Always the dark palette: a viewfinder cannot be tinted to match a light
  /// appearance, so this one page does not follow the user's choice — but its
  /// green, amber and red are still the app's.
  static const InkPalette _ink = InkPalette.onDarkSurface;

  static const int _countdownFrom = 3;

  _ScanPhase get _phase {
    if (!_isInitialized) {
      return _errorMessage != null ? _ScanPhase.failed : _ScanPhase.starting;
    }
    if (_errorMessage != null) return _ScanPhase.failed;
    if (_isCapturing) return _ScanPhase.capturing;
    if (_captureCountdown > 0) return _ScanPhase.counting;
    if (_idDetected) return _ScanPhase.found;
    return _ScanPhase.searching;
  }

  /// The colour the whole overlay agrees on for the current phase.
  Color get _tone => switch (_phase) {
    _ScanPhase.failed => _ink.danger,
    _ScanPhase.found ||
    _ScanPhase.counting ||
    _ScanPhase.capturing => _ink.emerald,
    _ScanPhase.starting || _ScanPhase.searching => Colors.white,
  };

  /// Where the card goes, in screen coordinates.
  ///
  /// Both the painter and the copy arranged around it need this, so it is
  /// worked out once rather than derived twice and left to drift apart.
  Rect _idWindow(Size size) {
    // ID-1, the format a PRC card is printed in.
    const aspect = 85.6 / 54.0;

    // The panel is docked to the right in landscape, so the window gets what is
    // left of the width rather than the whole of it.
    final available = Size(size.width - _panelWidth, size.height);

    var width = available.width - 48;
    var height = width / aspect;

    // On a short screen the height runs out before the width does; fall back to
    // fitting by height so the card never overflows its own frame.
    final maxHeight = available.height - 120;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }

    return Rect.fromLTWH(
      (available.width - width) / 2,
      (available.height - height) / 2,
      width,
      height,
    );
  }

  /// Width the status panel takes out of the right-hand side.
  static const double _panelWidth = 300;

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (e) {
      // Plenty of devices have no torch on the back camera, and asking is the
      // only way to find out. Falling back to "off" is honest.
      AppLogger.d('Torch unavailable: $e');
      if (mounted) setState(() => _torchOn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;

          // Until the screen actually turns there is nothing worth showing: the
          // window would be the narrow one this page exists to get away from.
          // The OS is not obliged to honour the request above — rotation lock,
          // or a tablet in a stand — so the page asks rather than assumes.
          if (size.width < size.height) return _rotatePrompt();

          final window = _idWindow(size);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_isInitialized && _cameraController != null)
                _buildCameraPreview()
              else
                const ColoredBox(color: Color(0xFF08100D)),

              // The window is only cut out of the scrim once there is a picture
              // behind it to look through.
              if (_isInitialized)
                CustomPaint(
                  painter: _IdWindowPainter(
                    window: window,
                    tone: _tone,
                    sweep: _sweep,
                    showSweep: _phase == _ScanPhase.searching,
                  ),
                ),

              _topBar(),

              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: _panelWidth,
                child: _statusPanel(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar() {
    final padding = MediaQuery.paddingOf(context);

    return Positioned(
      top: padding.top + 8,
      left: math.max(12, padding.left + 8),
      // Stops short of the status panel, which owns the right-hand strip.
      right: _panelWidth + 12,
      child: Row(
        children: [
          _GlassButton(
            icon: Icons.close,
            tooltip: 'Cancel',
            onTap: widget.onCancel,
          ),
          // Expanded rather than a pair of Spacers: the two buttons are the
          // same width, so the pill still lands dead centre — but it can now
          // give way instead of overflowing on a narrow screen or at a large
          // text scale.
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  'Scan your PRC ID',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          _GlassButton(
            icon: _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
            tooltip: _torchOn ? 'Turn off the light' : 'Turn on the light',
            active: _torchOn,
            onTap: _isInitialized ? _toggleTorch : null,
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    final phase = _phase;
    final fatal = phase == _ScanPhase.failed && !_isInitialized;
    final padding = MediaQuery.paddingOf(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        padding.top + 20,
        math.max(24, padding.right + 12),
        math.max(24, padding.bottom + 12),
      ),
      decoration: const BoxDecoration(
        // Fades the panel into the picture rather than cutting a hard edge down
        // the side of it.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00000000), Color(0xCC000000), Color(0xF2000000)],
          stops: [0, 0.35, 1],
        ),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _phaseIndicator(phase),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _headline(phase),
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _detail(phase),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (fatal) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        height: AuthMetrics.buttonHeight,
                        child: ElevatedButton.icon(
                          onPressed: _initializeCamera,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(
                            'Try again',
                            style: AppTextStyles.buttonLarge,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _ink.emerald,
                            foregroundColor: _ink.onEmerald,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AuthMetrics.fieldRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_tipsEarned && phase == _ScanPhase.searching) ...[
                      const SizedBox(height: 20),
                      _tipsCard(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _manualEntryLink(),
          ],
        ),
      ),
    );
  }

  /// The way out for a dentist whose card is at the clinic, laminated past
  /// reading, or simply will not scan.
  ///
  /// Always offered rather than unlocked after a number of failures: "I do not
  /// have it on me" is answered by neither waiting nor retrying. It is the
  /// quietest control on the page because scanning is still the path that
  /// actually proves anything.
  Widget _manualEntryLink() {
    return TextButton(
      onPressed: () => Navigator.of(
        context,
      ).pop(IdVerificationResult.manualEntryRequested()),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        "Can't scan it? Enter your details",
        textAlign: TextAlign.center,
        style: AppTextStyles.buttonMedium.copyWith(
          fontSize: 13,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  /// Shown until the screen turns. Also the one place the dentist can bail out
  /// to manual entry without ever seeing the viewfinder.
  Widget _rotatePrompt() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.screen_rotation_outlined,
            size: 46,
            color: _ink.emerald,
          ),
          const SizedBox(height: 22),
          Text(
            'Turn your phone sideways',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your PRC card is wider than it is tall. Held sideways your phone '
            'gives it about twice the frame, which is what makes it readable.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Still not turning? Check your rotation lock.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 26),
          _manualEntryLink(),
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.55),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonMedium.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// The one moving part of the panel: a spinner, a tick, or the countdown.
  Widget _phaseIndicator(_ScanPhase phase) {
    const diameter = 40.0;

    Widget shell(Widget child) => SizedBox(
      width: diameter,
      height: diameter,
      child: Center(child: child),
    );

    switch (phase) {
      case _ScanPhase.starting:
      case _ScanPhase.capturing:
        return shell(
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _tone),
          ),
        );

      case _ScanPhase.counting:
        return SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Runs down as the seconds do, so the ring and the number say the
              // same thing.
              CircularProgressIndicator(
                value: _captureCountdown / _countdownFrom,
                strokeWidth: 2.6,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                valueColor: AlwaysStoppedAnimation<Color>(_tone),
              ),
              Text(
                '$_captureCountdown',
                style: AppTextStyles.titleMedium.copyWith(
                  color: _tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );

      case _ScanPhase.found:
        return shell(Icon(Icons.check_circle, color: _tone, size: 26));

      case _ScanPhase.failed:
        return shell(Icon(Icons.error_outline, color: _tone, size: 26));

      case _ScanPhase.searching:
        return shell(
          Icon(
            Icons.credit_card_outlined,
            color: Colors.white.withValues(alpha: 0.75),
            size: 24,
          ),
        );
    }
  }

  String _headline(_ScanPhase phase) => switch (phase) {
    _ScanPhase.starting => 'Starting the camera',
    _ScanPhase.searching => 'Looking for your ID',
    _ScanPhase.found => 'Got it — hold still',
    _ScanPhase.counting => 'Hold still',
    _ScanPhase.capturing => 'Reading your card',
    _ScanPhase.failed => _isInitialized ? 'That did not work' : 'No camera',
  };

  String _detail(_ScanPhase phase) => switch (phase) {
    _ScanPhase.starting => 'One moment.',
    _ScanPhase.searching =>
      'Lay the card flat and fill the frame. It captures on its own.',
    _ScanPhase.found => 'Keep the card where it is.',
    _ScanPhase.counting => 'Capturing in $_captureCountdown…',
    _ScanPhase.capturing => _captureStage,
    _ScanPhase.failed => _errorMessage ?? 'Something went wrong.',
  };

  Widget _tipsCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: _ink.amber, size: 17),
              const SizedBox(width: 9),
              Text(
                'Trouble scanning?',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _tip('Fill the frame, corners included'),
          _tip('Tilt the card away from overhead lights to kill glare'),
          _tip('In a dim room, turn on the light up top'),
        ],
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 9, left: 3),
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round control that reads on top of whatever the camera happens to see.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Filled rather than smoked, for a control that is currently doing
  /// something — the torch while it is on.
  final bool active;

  @override
  Widget build(BuildContext context) {
    const ink = InkPalette.onDarkSurface;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? ink.emerald.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              size: 21,
              color: active ? ink.onEmerald : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dims the picture everywhere but the card window, and draws the window.
///
/// The old overlay drew a plain outlined rectangle over an undimmed preview,
/// which left the frame competing with whatever was behind it. Cutting the
/// window out of a scrim makes the target unmistakable and gives the corner
/// brackets something to sit against.
class _IdWindowPainter extends CustomPainter {
  _IdWindowPainter({
    required this.window,
    required this.tone,
    required this.sweep,
    required this.showSweep,
  }) : super(repaint: sweep);

  final Rect window;
  final Color tone;

  /// Repaints the sweep line without rebuilding the widget tree.
  final Animation<double> sweep;
  final bool showSweep;

  static const double _radius = 18;
  static const double _bracket = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      window,
      const Radius.circular(_radius),
    );

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rrect),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // A hairline all the way round, so the window still reads as a shape when
    // the brackets are the only bright part of it.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = tone.withValues(alpha: 0.3),
    );

    if (showSweep) _paintSweep(canvas, rrect);

    _paintBrackets(canvas);
  }

  /// A band of light running down the window — the one thing on screen that
  /// says the scanner is working rather than stuck.
  void _paintSweep(Canvas canvas, RRect rrect) {
    const trail = 44.0;
    // Ease at both ends so the line settles instead of snapping back.
    final t = Curves.easeInOut.transform(
      sweep.value <= 0.5 ? sweep.value * 2 : (1 - sweep.value) * 2,
    );
    final y = window.top + window.height * t;

    canvas.save();
    canvas.clipRRect(rrect);

    final band = Rect.fromLTWH(window.left, y - trail, window.width, trail);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: 0), tone.withValues(alpha: 0.16)],
        ).createShader(band),
    );
    canvas.drawLine(
      Offset(window.left, y),
      Offset(window.right, y),
      Paint()
        ..color = tone.withValues(alpha: 0.7)
        ..strokeWidth = 1.6,
    );

    canvas.restore();
  }

  void _paintBrackets(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = tone;

    // Each bracket runs along one edge, round the corner, and back along the
    // other — following the window's radius rather than cutting the corner off
    // square the way two straight lines did.
    void corner(double x, double y, double dx, double dy) {
      canvas.drawPath(
        Path()
          ..moveTo(x + dx * (_radius + _bracket), y)
          ..lineTo(x + dx * _radius, y)
          ..quadraticBezierTo(x, y, x, y + dy * _radius)
          ..lineTo(x, y + dy * (_radius + _bracket)),
        paint,
      );
    }

    corner(window.left, window.top, 1, 1);
    corner(window.right, window.top, -1, 1);
    corner(window.left, window.bottom, 1, -1);
    corner(window.right, window.bottom, -1, -1);
  }

  @override
  bool shouldRepaint(_IdWindowPainter old) {
    return old.window != window ||
        old.tone != tone ||
        old.showSweep != showSweep;
  }
}
