import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../design_tokens.dart';

/// A scannable QR code. Always dark ink ([FFTokens.qrInk]) on white
/// ([FFTokens.qrBackground]) regardless of the app theme: a bright theme
/// primary (e.g. Volt in the dark theme) on white is unreadable to scanners.
class FFQrCode extends StatelessWidget {
  const FFQrCode({super.key, required this.data, this.size});

  final String data;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      size: size,
      backgroundColor: FFTokens.qrBackground,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: FFTokens.qrInk,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: FFTokens.qrInk,
      ),
    );
  }
}
