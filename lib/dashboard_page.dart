import 'package:flutter/material.dart';
import 'qr_scanner/qr_scanner.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    // For now, we're just displaying the QR scanner as the main page
    // Later, this can be extended to include other dashboard elements
    return const QRScannerPage();
  }
}
