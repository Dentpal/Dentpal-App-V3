import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:mobile_scanner/mobile_scanner.dart';
import 'camera_permission_handler.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({Key? key}) : super(key: key);

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  late MobileScannerController controller;
  bool _hasDetectedCode = false;
  String _scannedData = '';

  @override
  void initState() {
    super.initState();
    _initializeScannerController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCameraPermission();
    });
  }
  
  void _initializeScannerController() {
    // Create controller with enhanced configurations
    controller = MobileScannerController(
      // Enable auto torch mode when lighting is low
      detectionSpeed: DetectionSpeed.normal,
      // Enhance the scanning experience
      facing: CameraFacing.back,
      // Enable scanning multiple formats - though QR is primary
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _checkCameraPermission() async {
    final hasPermission = await CameraPermissionHandler.requestCameraPermission(context);
    if (!hasPermission) {
      // Handle no permission scenario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to use the QR scanner'),
          ),
        );
      }
    }
  }

  void _resetScanner() {
    // Dispose the current controller
    controller.dispose();
    
    // Initialize a new controller
    _initializeScannerController();
    
    setState(() {
      _hasDetectedCode = false;
      _scannedData = '';
    });
  }

  void _showScannedDataDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('QR Code Content'),
        content: Text(_scannedData),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
        centerTitle: true,
        actions: [
          if (!_hasDetectedCode)
            IconButton(
              icon: ValueListenableBuilder(
                valueListenable: controller.torchState,
                builder: (context, state, child) {
                  switch (state) {
                    case TorchState.off:
                      return const Icon(Icons.flash_off);
                    case TorchState.on:
                      return const Icon(Icons.flash_on);
                  }
                },
              ),
              onPressed: () => controller.toggleTorch(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _hasDetectedCode
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 80,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'QR Code Detected',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _showScannedDataDialog,
                              icon: const Icon(Icons.visibility),
                              label: const Text('View Details'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            ElevatedButton.icon(
                              onPressed: _resetScanner,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Scan Again'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      // QR Scanner
                      MobileScanner(
                        controller: controller,
                        onDetect: (capture) {
                          // Only process if we haven't already detected a code
                          if (!_hasDetectedCode) {
                            final List<Barcode> barcodes = capture.barcodes;
                            if (barcodes.isNotEmpty) {
                              final Barcode barcode = barcodes.first;
                              if (barcode.rawValue != null) {
                                // Stop the scanner to prevent more captures
                                controller.stop();
                                
                                // Update the UI
                                setState(() {
                                  _hasDetectedCode = true;
                                  _scannedData = barcode.rawValue!;
                                });
                                
                                // Give haptic feedback if available
                                HapticFeedback.mediumImpact();
                              }
                            }
                          }
                        },
                      ),
                      
                      // Scan area overlay
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withOpacity(0.7),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: MediaQuery.of(context).size.width * 0.7,
                      ),
                    ],
                  ),
          ),
          if (!_hasDetectedCode)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black.withOpacity(0.1),
              child: const Text(
                'Position the QR code within the frame to scan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
