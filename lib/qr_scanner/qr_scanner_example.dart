import 'package:flutter/material.dart';
import 'qr_scanner.dart';

class QRScannerExample extends StatelessWidget {
  const QRScannerExample({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const QRScannerPage(),
    );
  }
}

void main() {
  runApp(const QRScannerExample());
}
