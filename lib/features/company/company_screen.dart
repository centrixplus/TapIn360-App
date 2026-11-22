import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/tokens.dart';
import '../../core/directory/company.dart';
import '../../core/directory/company_code.dart';
import '../../core/directory/directory_api.dart';
import '../common/tapin_widgets.dart';
import 'company_card.dart';

/// First screen (TapIn360 spec §7): company code typed or scanned → directory
/// lookup → name and logo → Continue → Login.
class CompanyScreen extends ConsumerStatefulWidget {
  const CompanyScreen({super.key});

  @override
  ConsumerState<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends ConsumerState<CompanyScreen> {
  final _code = TextEditingController();
  CompanyLookup? _lookup;
  String? _lookedUp;
  String? _inputError;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find(String typed) async {
    final code = normaliseCompanyCode(typed);
    if (code == null) {
      setState(() {
        _inputError = 'company.invalid'.tr();
        _lookup = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _inputError = null;
      _lookup = null;
    });
    final result = await ref.read(directoryApiProvider).lookup(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lookup = result;
      _lookedUp = code;
      _code.text = code;
    });
  }

  Future<void> _continue() async {
    final lookup = _lookup;
    if (lookup is CompanyFound && _lookedUp == normaliseCompanyCode(_code.text)) {
      await ref.read(sessionProvider.notifier).chooseCompany(lookup.company);
      return;
    }
    await _find(_code.text);
  }

  Future<void> _scan() async {
    final code = await ref.read(qrScannerProvider)(context);
    if (code == null || !mounted) return;
    _code.text = code;
    await _find(code);
  }

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    return Scaffold(
      body: SafeArea(
        child: BottomAnchoredColumn(
          top: [
            Row(
              children: [
                Expanded(
                  // Wordmark: "Tap" in ink + "In360" in brand blue (Latin, so it reads
                  // left to right in Arabic too).
                  child: Text.rich(
                    const TextSpan(
                      text: 'Tap',
                      children: [
                        TextSpan(text: 'In360', style: TextStyle(color: TapInColors.primaryStrong)),
                      ],
                    ),
                    style: TapInText.heading().copyWith(fontFamily: TapInFonts.sans, letterSpacing: -0.3),
                  ),
                ),
                TextButton(
                  key: const Key('language.toggle'),
                  style: TextButton.styleFrom(
                    foregroundColor: TapInColors.ink,
                    textStyle: const TextStyle(fontSize: 15),
                  ),
                  onPressed: () => context.setLocale(arabic ? const Locale('en') : const Locale('ar')),
                  child: Text('common.switch_language'.tr()),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('company.title'.tr(), style: TapInText.title(arabic: arabic)),
                  const SizedBox(height: 6),
                  Text('company.intro'.tr(), style: TapInText.body(arabic: arabic)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel('company.code_label'.tr()),
                const SizedBox(height: TapInSpace.s2),
                TextField(
                  key: const Key('company.code'),
                  controller: _code,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.go,
                  style: TapInText.code.copyWith(fontSize: 18),
                  decoration: InputDecoration(hintText: 'acme', errorText: _inputError, errorMaxLines: 3),
                  onChanged: (_) {
                    if (_lookup != null || _inputError != null) {
                      setState(() {
                        _lookup = null;
                        _inputError = null;
                      });
                    }
                  },
                  onSubmitted: _find,
                ),
              ],
            ),
            ?_result(),
          ],
          bottom: [
            FilledButton(
              key: const Key('company.continue'),
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: TapInColors.surfaceRaised),
                    )
                  : Text('company.continue'.tr()),
            ),
            OutlinedButton.icon(
              key: const Key('company.scan'),
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: Text('company.scan'.tr()),
            ),
            Center(
              child: TextButton(
                key: const Key('company.custom'),
                onPressed: () => context.push(Routes.customServer),
                child: Text('company.custom'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _result() {
    return switch (_lookup) {
      null => null,
      CompanyFound(:final company) => CompanyCard(company: company, foundLabel: 'company.found'.tr()),
      CompanyNotReady(:final company) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CompanyCard(company: company, foundLabel: 'company.found'.tr()),
          const SizedBox(height: 12),
          NoticeCard(
            kind: NoticeKind.warning,
            title: switch (company.status) {
              CompanyStatus.provisioning => 'company.provisioning'.tr(),
              CompanyStatus.suspended => 'company.suspended'.tr(),
              _ => 'company.unavailable'.tr(),
            },
          ),
        ],
      ),
      CompanyNotFound() => NoticeCard(kind: NoticeKind.danger, title: 'company.not_found'.tr()),
      CompanyInsecure() => NoticeCard(kind: NoticeKind.danger, title: 'company.insecure'.tr()),
      CompanyLookupRateLimited() => NoticeCard(kind: NoticeKind.warning, title: 'company.rate_limited'.tr()),
      CompanyLookupFailed() => NoticeCard(kind: NoticeKind.danger, title: 'company.unreachable'.tr()),
    };
  }
}
