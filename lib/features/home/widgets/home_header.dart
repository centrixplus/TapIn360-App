import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../common/tapin_widgets.dart';
import '../home_actions.dart';
import '../home_state.dart';

/// Company name, "Hello, Ahmed", History and Settings buttons.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.state, required this.actions});

  final HomeState state;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.companyName.isNotEmpty)
                Text(
                  state.companyName,
                  // ink, not ink-muted: this line sits on `bg` (contrast rule).
                  style: TapInText.bodySmall(arabic: arabic),
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                'home.hello'.tr(namedArgs: {'name': state.firstName}),
                style: TapInText.heading(arabic: arabic),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SquareIconButton(
          key: const Key('home.history'),
          icon: Icons.history_rounded,
          tooltip: 'home.history'.tr(),
          onPressed: actions.openHistory,
        ),
        const SizedBox(width: 12),
        SquareIconButton(
          key: const Key('home.settings'),
          icon: Icons.settings_outlined,
          tooltip: 'home.settings'.tr(),
          onPressed: actions.openSettings,
        ),
      ],
    );
  }
}
