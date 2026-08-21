import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
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
  int _scanCount = 0;

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

  Future<List<Map<String, dynamic>>> _loadGyms() async {
    try {
      final result = await AppScope.of(context).api.ownerGyms();
      final gyms = result.cast<Map<String, dynamic>>();
      if (!mounted) return gyms;
      setState(() {
        _gyms = gyms;
        if (_selectedGymId == null && gyms.length == 1) {
          _selectedGymId = gyms.first['id']?.toString();
        }
      });
      return gyms;
    } catch (_) {
      // Existing single-gym operators can still scan with their server-side default.
      return _gyms;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _verifyResult != null) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _scannedToken = code;
    try {
      await _cameraCtrl.stop();
    } catch (_) {
      // The scanner may already be stopped while a frame is being processed.
    }
    await _verify(code);
  }

  Future<void> _verify(String qrToken) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).api;
      var selectedGymId = _selectedGymId;
      var result = await api.operatorVerifyQr(qrToken, gymId: selectedGymId);
      if (!mounted) return;
      var gyms = _gyms;

      if (result['requiresGymSelection'] == true) {
        if (gyms.isEmpty) {
          gyms = await _loadGyms();
        }
        selectedGymId ??= gyms.length == 1
            ? gyms.first['id']?.toString()
            : null;
        if (selectedGymId != null && selectedGymId.isNotEmpty) {
          result = await api.operatorVerifyQr(qrToken, gymId: selectedGymId);
        }
      }

      if (!mounted) return;
      final resultGym = result['gym'] as Map<String, dynamic>?;
      final resultGymId = resultGym?['id']?.toString();
      setState(() {
        _gyms = gyms;
        _verifyResult = result;
        _selectedGymId = selectedGymId ?? resultGymId;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveCheckIn() async {
    final gymId = _effectiveGymId();
    if (_scannedToken == null || gymId == null) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.operatorCheckIn(_scannedToken!, gymId: gymId);
      if (!mounted) return;
      setState(() => _scanCount++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('ownerScan.approved')} ($_scanCount)'),
          duration: const Duration(seconds: 2),
        ),
      );
      // Auto-reset to allow scanning next member immediately
      await _reset();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _verifyResult = null;
      _scannedToken = null;
      _error = null;
      if (_gyms.length != 1) _selectedGymId = null;
    });
    try {
      await _cameraCtrl.start();
    } catch (_) {
      // Scanner may already be running or unavailable during route changes.
    }
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
            style: Theme.of(context).textTheme.bodyMedium,
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
    final needsGymSelection = ownerScanNeedsGymSelection(
      verifyResult: r,
      gyms: _gyms,
      selectedGymId: _selectedGymId,
    );
    final effectiveGymId = _effectiveGymId();

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
                          style: Theme.of(context).textTheme.titleLarge,
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
                style: Theme.of(context).textTheme.titleSmall,
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
                  style: Theme.of(context).textTheme.bodyMedium,
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
              if (needsGymSelection || _gyms.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedGymId,
                  decoration: InputDecoration(
                    labelText: context.tr('ownerScan.chooseGym'),
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
                      : (value) {
                          setState(() => _selectedGymId = value);
                          if (value != null) _verify(_scannedToken!);
                        },
                ),
                if (_gyms.isEmpty) ...[
                  const SizedBox(height: 8),
                  const FFSpinner(size: 18),
                ],
                const SizedBox(height: 12),
              ] else if (gym != null)
                Text(
                  '${context.tr("ownerScan.gym")}: ${gym['name']}',
                  style: Theme.of(context).textTheme.bodyMedium,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
            onPressed: _busy || effectiveGymId == null ? null : _approveCheckIn,
            icon: _busy
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
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

  String? _effectiveGymId() {
    if (_selectedGymId != null && _selectedGymId!.isNotEmpty) {
      return _selectedGymId;
    }
    final gym = _verifyResult?['gym'] as Map<String, dynamic>?;
    return gym?['id']?.toString();
  }
}

bool ownerScanNeedsGymSelection({
  required Map<String, dynamic> verifyResult,
  required List<Map<String, dynamic>> gyms,
  required String? selectedGymId,
}) {
  if (selectedGymId != null && selectedGymId.isNotEmpty) return false;
  return verifyResult['requiresGymSelection'] == true || gyms.length > 1;
}
