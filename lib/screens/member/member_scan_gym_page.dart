import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

/// Member-scans-gym check-in (Tech Brief §5): the member scans the static QR
/// posted at the gym entrance. The backend runs the same BL-012 checks as a
/// staff scan, so failures come back with a specific reason.
class MemberScanGymPage extends StatefulWidget {
  const MemberScanGymPage({super.key});

  @override
  State<MemberScanGymPage> createState() => _MemberScanGymPageState();
}

class _MemberScanGymPageState extends State<MemberScanGymPage> {
  final MobileScannerController _camera = MobileScannerController();
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _result != null || _error != null) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _camera.stop();
    } catch (_) {
      // Already stopping while a frame is processed.
    }
    if (!mounted) return;
    final locale = FFLocaleScope.of(context);
    try {
      final res = await AppScope.of(context).api.scanGymQr(code);
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _result = null;
      _error = null;
    });
    await _camera.start();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final gymName = (result?['gym'] as Map?)?['name']?.toString();
    final visit = result?['visitNumberInCycle'];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('member.scanGymQr'))),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (result == null && _error == null) ...[
            Text(
              context.tr('member.scanGymQrHint'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  key: const Key('member-gym-scanner'),
                  controller: _camera,
                  onDetect: _onDetect,
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
          if (result != null)
            FFAlert(
              key: const Key('member-gym-checkin-ok'),
              tone: FFAlertTone.success,
              message: [
                context
                    .tr('member.checkedInAt')
                    .replaceAll('{gym}', gymName ?? ''),
                if (visit != null)
                  context.tr('member.visitNumber').replaceAll('{n}', '$visit'),
              ].join(' · '),
            ),
          if (_error != null)
            FFAlert(
              key: const Key('member-gym-checkin-error'),
              tone: FFAlertTone.error,
              message: _error!,
            ),
          if (result != null || _error != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _scanAgain,
                    child: Text(context.tr('member.scanAgain')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, result != null),
                    child: Text(context.tr('member.done')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
