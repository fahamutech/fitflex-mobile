import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class OwnerQrScannerPage extends StatefulWidget {
  const OwnerQrScannerPage({super.key});

  @override
  State<OwnerQrScannerPage> createState() => _OwnerQrScannerPageState();
}

class _OwnerQrScannerPageState extends State<OwnerQrScannerPage> {
  final MobileScannerController _cameraCtrl = MobileScannerController();
  bool _busy = false;
  Map<String, dynamic>? _verifyResult;
  String? _scannedToken;
  String? _error;

  @override
  void dispose() {
    _cameraCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _verifyResult != null) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _scannedToken = code;
    await _verify(code);
  }

  Future<void> _verify(String qrToken) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      final result = await api.operatorVerifyQr(qrToken);
      if (!mounted) return;
      setState(() => _verifyResult = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body is Map ? e.body as Map : {};
      setState(
        () => _error =
            body['failure']?.toString() ??
            body['error']?.toString() ??
            'Error ${e.status}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveCheckIn() async {
    if (_scannedToken == null) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.operatorCheckIn(_scannedToken!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('ownerScan.approved'))));
      _reset();
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body is Map ? e.body as Map : {};
      setState(
        () => _error =
            body['failure']?.toString() ??
            body['error']?.toString() ??
            'Error ${e.status}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _verifyResult = null;
      _scannedToken = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ownerScan.title'))),
      body: _verifyResult != null ? _resultView() : _scannerView(),
    );
  }

  Widget _scannerView() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(controller: _cameraCtrl, onDetect: _onDetect),
        ),
        if (_busy)
          const Padding(padding: EdgeInsets.all(16), child: FFSpinner()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FFAlert(message: _error!, tone: FFAlertTone.error),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _reset,
                  child: Text(context.tr('ownerScan.scanAgain')),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.tr('ownerScan.hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: FFTokens.fgTertiary),
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final r = _verifyResult!;
    final member = r['member'] as Map<String, dynamic>? ?? {};
    final sub = r['subscription'] as Map<String, dynamic>?;
    final gym = r['gym'] as Map<String, dynamic>?;
    final eligible = r['eligible'] == true;
    final reason = r['reason']?.toString() ?? '';
    final visitsUsed = r['visitsUsed'] as num? ?? 0;
    final visitCap = r['visitCap'] as num?;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        // Member info
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FFAvatar(
                    name: member['displayName']?.toString() ?? 'Member',
                    src: member['photoUrl']?.toString(),
                    size: FFAvatarSize.lg,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['displayName']?.toString() ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: FFTokens.fgPrimary,
                          ),
                        ),
                        if (member['email'] != null)
                          Text(
                            member['email'].toString(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: FFTokens.fgTertiary,
                            ),
                          ),
                        if (member['phone'] != null)
                          Text(
                            member['phone'].toString(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: FFTokens.fgTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Subscription info
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('ownerScan.passInfo'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (sub != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('ownerScan.tier')),
                    FFBadge(
                      label: sub['tier']?.toString() ?? '-',
                      tone: FFBadgeTone.brand,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.tr('ownerScan.visits')),
                    Text(
                      visitCap != null
                          ? '$visitsUsed / $visitCap'
                          : '$visitsUsed / ${context.tr("pass.unlimited")}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ] else
                Text(
                  context.tr('ownerScan.noPass'),
                  style: const TextStyle(color: FFTokens.fgQuaternary),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Gym & eligibility
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gym != null)
                Text(
                  '${context.tr("ownerScan.gym")}: ${gym['name']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: FFTokens.fgSecondary,
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    eligible ? Icons.check_circle : Icons.cancel,
                    color: eligible ? FFTokens.success : FFTokens.danger,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eligible
                          ? context.tr('ownerScan.eligible')
                          : context.tr('ownerScan.reason_$reason'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: eligible ? FFTokens.success : FFTokens.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Actions
        if (eligible)
          FilledButton.icon(
            onPressed: _busy ? null : _approveCheckIn,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(context.tr('ownerScan.approve')),
          ),
        if (!eligible)
          FFAlert(
            message: context.tr('ownerScan.cannotApprove'),
            tone: FFAlertTone.warning,
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _reset,
          child: Text(context.tr('ownerScan.scanAgain')),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          FFAlert(message: _error!, tone: FFAlertTone.error),
        ],
      ],
    );
  }
}
