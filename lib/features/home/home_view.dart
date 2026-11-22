import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../result/result_overlay.dart';
import 'home_actions.dart';
import 'home_state.dart';
import 'widgets/home_banners.dart';
import 'widgets/home_chips.dart';
import 'widgets/home_header.dart';
import 'widgets/status_card.dart';
import 'widgets/tap_panel.dart';

/// Tap screen (AppHome / AppHomeAr artboards); the result covers it when present.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.state, required this.actions});

  final HomeState state;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: actions.refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      TapInSpace.gutter,
                      TapInSpace.s4,
                      TapInSpace.gutter,
                      28,
                    ),
                    sliver: SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HomeHeader(state: state, actions: actions),
                          const SizedBox(height: TapInSpace.s4),
                          HomeBanners(state: state, actions: actions),
                          StatusCard(state: state),
                          const SizedBox(height: TapInSpace.s4),
                          Expanded(
                            child: TapPanel(state: state, actions: actions),
                          ),
                          const SizedBox(height: TapInSpace.s4),
                          HomeChips(state: state, actions: actions),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (result != null)
          Positioned.fill(
            child: ResultOverlay(key: ValueKey(result), outcome: result, onClose: actions.dismissResult),
          ),
      ],
    );
  }
}

/// "today 08:02", "yesterday 17:31" or "12 Nov 09:15", local time.
String whenLabel(BuildContext context, DateTime instant, {DateTime? now}) {
  final local = instant.toLocal();
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(local);
  final locale = context.locale.languageCode;
  final time = DateFormat.Hm(locale).format(local);
  if (day == today) return 'home.when_today'.tr(namedArgs: {'time': time});
  if (day == today.subtract(const Duration(days: 1))) {
    return 'home.when_yesterday'.tr(namedArgs: {'time': time});
  }
  return 'home.when_date'.tr(namedArgs: {'date': DateFormat.MMMd(locale).format(local), 'time': time});
}
