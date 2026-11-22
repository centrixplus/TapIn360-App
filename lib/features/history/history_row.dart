import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../core/api/api_models.dart';
import '../../core/api/error_codes.dart';
import '../../core/queue/tap_record.dart';
import '../common/tapin_widgets.dart';
import 'history_screen.dart';

/// One tap: status dot, title, detail, time.
class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.tap});

  final TapRecord tap;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final (icon, fill, iconColor) = switch (tap.status) {
      TapStatus.sent => (Icons.check_rounded, TapInColors.success, TapInColors.ink),
      TapStatus.rejected => (Icons.close_rounded, TapInColors.danger, TapInColors.surfaceRaised),
      TapStatus.waiting => (Icons.schedule_rounded, TapInColors.warningTint, TapInColors.warning),
    };
    final time = DateFormat.Hm(context.locale.languageCode).format(tapTime(tap));
    final detail = _detail();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(),
                  style: TapInText.bodySmall(
                    arabic: arabic,
                  ).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TapInText.bodySmall(arabic: arabic).copyWith(color: TapInColors.inkMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(time, style: TapInText.tabular(TapInText.bodySmall(arabic: arabic).copyWith(fontSize: 15))),
        ],
      ),
    );
  }

  String _title() => switch (tap.status) {
    TapStatus.sent => switch (tap.resultCode) {
      'check_in' => 'history.checked_in'.tr(),
      'check_out' => 'history.checked_out'.tr(),
      _ => 'history.recorded'.tr(),
    },
    TapStatus.rejected => 'history.rejected'.tr(),
    TapStatus.waiting => 'history.waiting'.tr(),
  };

  String _detail() {
    final action = switch (tap.action) {
      PunchAction.checkIn => 'history.action_in'.tr(),
      PunchAction.checkOut => 'history.action_out'.tr(),
      _ => 'history.action_auto'.tr(),
    };
    final message = tap.resultMessage ?? '';
    return switch (tap.status) {
      TapStatus.sent => tap.resultSite ?? message,
      TapStatus.rejected => switch (tap.resultCode) {
        ErrorCodes.discarded => 'history.discarded'.tr(),
        ErrorCodes.undeliverable => 'history.undeliverable'.tr(),
        _ => message.isNotEmpty ? message : tap.resultCode ?? '',
      },
      TapStatus.waiting =>
        tap.attempts > 0
            ? 'history.tries'.tr(namedArgs: {'action': action, 'count': '${tap.attempts}'})
            : 'history.not_sent_yet'.tr(namedArgs: {'action': action}),
    };
  }
}
