import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../common/tapin_widgets.dart';
import '../home_state.dart';
import '../home_view.dart';

/// Dot + "Checked in" / "Checked out" + since / last tap.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final (dot, title) = switch (state.statusKind) {
      StatusKind.checkedIn => (TapInColors.success, 'home.status_in'.tr()),
      StatusKind.checkedOut => (TapInColors.borderStrong, 'home.status_out'.tr()),
      StatusKind.loading => (TapInColors.border, 'home.status_loading'.tr()),
      StatusKind.unavailable => (TapInColors.warning, 'home.status_unavailable'.tr()),
    };
    final detail = _detail(context);
    return TapInCard(
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TapInText.body(arabic: arabic).copyWith(fontWeight: FontWeight.w600),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TapInText.tabular(
                      TapInText.bodySmall(arabic: arabic).copyWith(color: TapInColors.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _detail(BuildContext context) {
    switch (state.statusKind) {
      case StatusKind.checkedIn:
        final since = state.since;
        if (since == null) return null;
        final time = DateFormat.Hm(context.locale.languageCode).format(since.toLocal());
        final site = state.site;
        return site == null
            ? 'home.since_no_site'.tr(namedArgs: {'time': time})
            : 'home.since'.tr(namedArgs: {'time': time, 'site': site});
      case StatusKind.checkedOut:
        return _lastTap(context) ?? 'home.no_taps_yet'.tr();
      case StatusKind.unavailable:
        return _lastTap(context) ?? 'home.status_unavailable_detail'.tr();
      case StatusKind.loading:
        return null;
    }
  }

  String? _lastTap(BuildContext context) {
    final at = state.lastTapAt;
    if (at == null) return null;
    final when = whenLabel(context, at);
    final site = state.lastTapSite;
    return site == null
        ? 'home.last_tap_no_site'.tr(namedArgs: {'when': when})
        : 'home.last_tap'.tr(namedArgs: {'when': when, 'site': site});
  }
}
