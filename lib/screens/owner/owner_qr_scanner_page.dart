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
  List<Map<String, dynamic>> _gyms = [];
  String? _selectedGymId;
  Map<String, dynamic>? _verifyResult;
  String? _scannedToken;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGyms();
  }

  @override
  void dispose() {
    _cameraCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGyms() async {
    try {
      final result = await AppScope.of(context).api.ownerGyms();
      if (!mounted) return;
      final gyms = result.cast<Map<String, dynamic>>();
      setState(() {
        _gyms = gyms;
        if (_selectedGymId == null && gyms.length == 1) {
          _selectedGymId = gyms.first['id']?.toString();
        }
      });
    } catch (_) {
      // Existing single-gym operators can still scan with their server-side default.
    }
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
      final result = await api.operatorVerifyQr(qrToken, gymId: _selectedGymId);
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
    if (_scannedToken == null || _selectedGymId == null) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.operatorCheckIn(_scannedToken!, gymId: _selectedGymId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('ownerScan.approved'))));
      final closed = await Navigator.of(context).maybePop();
      if (!closed && mounted) _reset();
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
      if (_gyms.length != 1) _selectedGymId = null;
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
    final needsGymSelection = _gyms.length > 1 && _selectedGymId == null;

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
                    name:
                        member['publicId']?.toString() ??
                        member['userCode']?.toString() ??
                        'Member',
                    src: member['photoUrl']?.toString(),
                    size: FFAvatarSize.lg,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['publicId']?.toString() ??
                              member['userCode']?.toString() ??
                              member['id']?.toString() ??
                              'Member',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: FFTokens.fgPrimary,
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
              if (_gyms.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedGymId,
                  decoration: InputDecoration(
                    labelText: context.tr('ownerScan.chooseGym'),
                    border: const OutlineInputBorder(),
                  ),
                  items: _gyms
                      .map(
                        (g) => DropdownMenuItem(
                          value: g['id']?.toString(),
                          child: Text(g['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: _busy || _scannedToken == null
                      ? null
                      : (value) async {
                          setState(() => _selectedGymId = value);
                          if (value != null) await _verify(_scannedToken!);
                        },
                ),
                const SizedBox(height: 12),
              ] else if (gym != null)
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
                      needsGymSelection
                          ? context.tr('ownerScan.selectGymToVerify')
                          : eligible
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
            onPressed: _busy || _selectedGymId == null ? null : _approveCheckIn,
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
