// Stub file for non-web platforms
import 'dart:typed_data';
import 'package:flutter/material.dart';

class WebCameraWidget extends StatelessWidget {
  final Function(Uint8List) onPhotoTaken;
  final VoidCallback onCancel;

  const WebCameraWidget({
    Key? key,
    required this.onPhotoTaken,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Camera not supported on this platform'),
    );
  }
}
