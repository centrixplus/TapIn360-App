import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../common/tapin_widgets.dart';
import '../home_actions.dart';
import '../home_state.dart';

/// GPS pill and "N taps waiting to send" pill.
class HomeChips extends StatelessWidget {
  const HomeChips({super.key, required this.state, required this.actions});

  final HomeState state;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final (gpsText, gpsColor, gpsIcon) = switch (state.gpsKind) {
      GpsKind.fix => (
        'home.gps_fix'.tr(namedArgs: {'accuracy': '${(state.gpsAccuracy ?? 0).round()}'}),
        TapInColors.successStrong,
        Icons.location_on_outlined,
      ),
      GpsKind.searching => ('home.gps_searching'.tr(), TapInColors.warning, Icons.location_searching_rounded),
      GpsKind.off || GpsKind.error => ('home.gps_off'.tr(), TapInColors.danger, Icons.location_off_outlined),
    };
    final waiting = state.waitingCount;
    return Wrap(
      spacing: TapInSpace.s2,
      runSpacing: TapInSpace.s2,
      children: [
        Pill(key: const Key('home.gps'), text: gpsText, icon: gpsIcon, foreground: gpsColor),
        if (waiting > 0)
          Pill(
            key: const Key('home.waiting'),
            text: waiting == 1
                ? 'home.waiting_one'.tr()
                : 'home.waiting_many'.tr(namedArgs: {'count': '$waiting'}),
            icon: Icons.schedule_rounded,
            foreground: TapInColors.ink,
            iconColor: TapInColors.warning,
            background: TapInColors.warningTint,
            onTap: actions.openHistory,
          ),
      ],
    );
  }
}
