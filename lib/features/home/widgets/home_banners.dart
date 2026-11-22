import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import '../../../app/tokens.dart';
import '../../../core/location/location_gateway.dart';
import '../../common/tapin_widgets.dart';
import '../home_actions.dart';
import '../home_state.dart';

/// Blocking banners (spec §6.1): not logged in, access switched off by
/// TapIn360, location permission/service off or only approximate, NFC off
/// (Android).
class HomeBanners extends StatelessWidget {
  const HomeBanners({super.key, required this.state, required this.actions});

  final HomeState state;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[
      if (!state.loggedIn)
        _Banner(text: 'banner.not_logged_in'.tr(), button: 'banner.log_in'.tr(), onPressed: actions.logIn),
      if (state.loggedIn && state.accessSwitchedOff)
        _Banner(
          key: const Key('banner.switched_off'),
          text: 'banner.switched_off'.tr(),
          button: 'banner.check_again'.tr(),
          onPressed: actions.refresh,
        ),
      ...switch (state.locationAccess) {
        LocationAccess.denied => [
          _Banner(
            text: 'banner.location_denied'.tr(),
            button: 'banner.allow'.tr(),
            onPressed: actions.allowLocation,
          ),
        ],
        LocationAccess.deniedForever => [
          _Banner(
            text: 'banner.location_denied'.tr(),
            button: 'banner.open_settings'.tr(),
            onPressed: actions.openAppSettings,
          ),
        ],
        LocationAccess.approximate => [
          _Banner(
            key: const Key('banner.location_approximate'),
            text: 'banner.location_approximate'.tr(),
            button: 'banner.open_settings'.tr(),
            onPressed: actions.openAppSettings,
          ),
        ],
        LocationAccess.serviceOff => [
          _Banner(
            text: 'banner.location_service_off'.tr(),
            button: 'banner.turn_on'.tr(),
            onPressed: actions.openLocationSettings,
          ),
        ],
        LocationAccess.granted || null => const <Widget>[],
      },
      if (!state.isIos && state.nfc == NfcAvailability.disabled)
        _Banner(
          text: 'banner.nfc_off'.tr(),
          button: 'banner.turn_on'.tr(),
          onPressed: actions.openNfcSettings,
        ),
      if (!state.isIos && state.nfc == NfcAvailability.unsupported)
        _Banner(text: 'banner.nfc_unsupported'.tr()),
    ];
    return Column(
      children: [
        for (final banner in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: banner),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.button, this.onPressed});

  final String text;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TapInCard(
      border: TapInColors.danger,
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: TapInColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TapInText.bodySmall(arabic: isArabic(context)).copyWith(fontSize: 15)),
          ),
          if (button != null) ...[
            const SizedBox(width: TapInSpace.s2),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: onPressed,
              child: Text(button!),
            ),
          ],
        ],
      ),
    );
  }
}
