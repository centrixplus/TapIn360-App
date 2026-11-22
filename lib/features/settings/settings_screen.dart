import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../core/device/device_descriptor.dart';
import '../../core/location/location_gateway.dart';
import '../common/tapin_widgets.dart';
import 'device_status.dart';
import 'logout_flow.dart';

/// Company (Change), language, phone ID, permissions, Prepare wall card,
/// Log out, version (AppSettings artboard).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appVersionLabel().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(deviceStatusProvider);
  }

  Future<void> _changeCompany() async {
    if (!await confirmChangeCompany(context, ref)) return;
    await ref.read(sessionProvider.notifier).changeCompany();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final status = ref.watch(deviceStatusProvider).valueOrNull;
    final arabic = isArabic(context);
    final muted = TapInText.bodySmall(arabic: arabic).copyWith(color: TapInColors.inkMuted);
    final language = context.locale.languageCode;
    return Scaffold(
      body: SafeArea(
        child: BottomAnchoredColumn(
          gap: 14,
          top: [
            BackHeader(title: 'settings.title'.tr()),
            TapInCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Row(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.company != null
                                    ? 'settings.company'.tr()
                                    : 'settings.custom_server'.tr(),
                                style: muted,
                              ),
                              Text(
                                session.company?.name ?? session.serverUrl ?? '',
                                style: TapInText.body(arabic: arabic).copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          key: const Key('settings.change_company'),
                          onPressed: _changeCompany,
                          child: Text('settings.change'.tr()),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: TapInColors.border),
                  _Row(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('settings.language'.tr(), style: TapInText.body(arabic: arabic)),
                        ),
                        _LanguageSwitch(
                          current: language,
                          onChanged: (code) => context.setLocale(Locale(code)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: TapInColors.border),
                  _Row(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('common.phone_id'.tr(), style: muted),
                        const SizedBox(height: 6),
                        CopyCodeRow(
                          code: ref.read(hardwareIdProvider),
                          copiedMessage: 'common.phone_id_copied'.tr(),
                          boxed: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TapInCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _StatusRow(label: 'settings.location'.tr(), value: _location(status)),
                  const Divider(height: 1, color: TapInColors.border),
                  _StatusRow(label: 'settings.camera'.tr(), value: _camera(status)),
                  const Divider(height: 1, color: TapInColors.border),
                  _StatusRow(label: 'settings.nfc'.tr(), value: _nfc(status)),
                ],
              ),
            ),
          ],
          bottom: [
            OutlinedButton(
              key: const Key('settings.logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TapInColors.danger,
                side: const BorderSide(color: TapInColors.danger),
              ),
              onPressed: () => confirmAndLogout(context, ref),
              child: Text('settings.logout'.tr()),
            ),
            Text(
              'settings.version'.tr(namedArgs: {'version': _version}),
              textAlign: TextAlign.center,
              style: TapInText.bodySmall(arabic: arabic).copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  _Value _location(DeviceStatus? s) => switch (s?.location) {
    LocationAccess.granted => _Value.ok('settings.allowed'.tr()),
    LocationAccess.approximate => _Value.bad('settings.approximate'.tr()),
    LocationAccess.denied || LocationAccess.deniedForever => _Value.bad('settings.not_allowed'.tr()),
    LocationAccess.serviceOff => _Value.bad('settings.service_off'.tr()),
    null => _Value.plain('settings.checking'.tr()),
  };

  _Value _camera(DeviceStatus? s) {
    if (s == null) return _Value.plain('settings.checking'.tr());
    return switch (s.camera) {
      true => _Value.ok('settings.allowed'.tr()),
      false => _Value.plain('settings.asked_later'.tr()),
      null => _Value.plain('settings.asked_later'.tr()),
    };
  }

  _Value _nfc(DeviceStatus? s) => switch (s?.nfc) {
    NfcAvailability.enabled => _Value.ok('settings.nfc_on'.tr()),
    NfcAvailability.disabled => _Value.bad('settings.nfc_off'.tr()),
    NfcAvailability.unsupported => _Value.bad('settings.nfc_none'.tr()),
    null => _Value.plain(s == null ? 'settings.checking'.tr() : 'settings.nfc_none'.tr()),
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: child);
}

enum _ValueKind { ok, bad, plain }

class _Value {
  const _Value(this.kind, this.text);
  const _Value.ok(this.text) : kind = _ValueKind.ok;
  const _Value.bad(this.text) : kind = _ValueKind.bad;
  const _Value.plain(this.text) : kind = _ValueKind.plain;

  final _ValueKind kind;
  final String text;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final _Value value;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final color = switch (value.kind) {
      _ValueKind.ok => TapInColors.successStrong,
      _ValueKind.bad => TapInColors.danger,
      _ValueKind.plain => TapInColors.inkMuted,
    };
    final icon = switch (value.kind) {
      _ValueKind.ok => Icons.check_rounded,
      _ValueKind.bad => Icons.close_rounded,
      _ValueKind.plain => null,
    };
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TapInText.body(arabic: arabic)),
          ),
          if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 4)],
          Text(
            value.text,
            style: TapInText.body(arabic: arabic).copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// English | العربية segmented control.
class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String code, String label, String family) {
      final selected = current == code;
      return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: Key('settings.lang_$code'),
          borderRadius: BorderRadius.circular(TapInRadius.sm),
          onTap: () => onChanged(code),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? TapInColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(TapInRadius.sm),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: family,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: TapInColors.ink,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: TapInColors.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option('en', 'settings.english'.tr(), TapInFonts.sans),
          const SizedBox(width: 3),
          option('ar', 'settings.arabic'.tr(), TapInFonts.arabic),
        ],
      ),
    );
  }
}
