import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/tokens.dart';
import '../../core/directory/company_code.dart';
import '../common/tapin_widgets.dart';

/// Opens the scanner; returns the company code from a `tapin://company/<code>` QR.
Future<String?> scanCompanyQr(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String?>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QrScanScreen()));
}

/// Back camera, QR codes only. Other QR codes show a short notice.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  String? _notice;
  bool _done = false;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = companyCodeFromQr(raw);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    _noticeTimer?.cancel();
    setState(() => _notice = 'scan.not_tapin'.tr());
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final white = TapInText.body(arabic: arabic).copyWith(color: TapInColors.surfaceRaised);
    return Scaffold(
      backgroundColor: TapInColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TapInSpace.gutter, 20, TapInSpace.gutter, 24),
          child: Column(
            children: [
              Text(
                'scan.title'.tr(),
                style: TapInText.heading(arabic: arabic).copyWith(color: TapInColors.surfaceRaised),
              ),
              const SizedBox(height: TapInSpace.s1),
              Text('scan.hint'.tr(), style: white.copyWith(fontSize: 15), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TapInRadius.lg),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: TapInColors.cameraWell,
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'scan.camera_denied'.tr(),
                                style: white,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              border: Border.all(color: TapInColors.surfaceRaised, width: 4),
                              borderRadius: BorderRadius.circular(TapInRadius.lg),
                            ),
                          ),
                        ),
                      ),
                      if (_notice != null)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: Pill(
                              text: _notice!,
                              icon: Icons.error_outline_rounded,
                              foreground: TapInColors.ink,
                              iconColor: TapInColors.warning,
                              background: TapInColors.warningTint,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: TapInColors.surfaceRaised,
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('common.cancel'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
