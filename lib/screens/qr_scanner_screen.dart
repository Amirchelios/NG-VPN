import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _isFinished = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isFinished) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value != null && value.isNotEmpty) {
      _isFinished = true;
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        title: const Text('اسکن QR'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'کد را درون کادر قرار دهید',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
