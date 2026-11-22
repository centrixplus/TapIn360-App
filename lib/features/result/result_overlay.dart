import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/tokens.dart';
import '../../core/tap/tap_outcome.dart';
import '../common/tapin_widgets.dart';

/// Result screen (AppResult artboard): checked in / rejected / saved, with
/// vibration; closes after [duration] or on **Done** / Back.
class ResultOverlay extends StatefulWidget {
  const ResultOverlay({
    super.key,
    required this.outcome,
    required this.onClose,
    this.duration = const Duration(seconds: 4),
  });

  final TapOutcome outcome;
  final VoidCallback onClose;
  final Duration duration;

  @override
  State<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<ResultOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onClose);
    if (widget.outcome is TapSent) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.vibrate();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _lookOf(context, widget.outcome);
    final arabic = isArabic(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(TapInSpace.gutter, TapInSpace.s4, TapInSpace.gutter, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TapInCard(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: reduceMotion ? 1 : 0.6, end: 1),
                            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(color: look.circle, shape: BoxShape.circle),
                              child: Icon(look.icon, size: 56, color: look.iconColor),
                            ),
                          ),
                          const SizedBox(height: TapInSpace.s4),
                          Text(
                            look.title,
                            textAlign: TextAlign.center,
                            style: TapInText.title(arabic: arabic).copyWith(color: look.titleColor),
                          ),
                          if (look.message.isNotEmpty) ...[
                            const SizedBox(height: TapInSpace.s4),
                            Text(
                              look.message,
                              textAlign: TextAlign.center,
                              style: TapInText.tabular(
                                TapInText.body(
                                  arabic: arabic,
                                ).copyWith(fontSize: 18, height: (arabic ? 28 : 26) / 18),
                              ),
                            ),
                          ],
                          if (look.rows.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            const Divider(height: 1, color: TapInColors.border),
                            const SizedBox(height: TapInSpace.s4),
                            for (final row in look.rows) _CheckRow(row: row),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('result.done'),
                  onPressed: widget.onClose,
                  child: Text('result.done'.tr()),
                ),
                const SizedBox(height: 10),
                Text(
                  'result.closes'.tr(),
                  textAlign: TextAlign.center,
                  style: TapInText.bodySmall(arabic: arabic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _RowKind { ok, bad, wait }

class _Row {
  const _Row(this.kind, this.text);
  final _RowKind kind;
  final String text;
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (row.kind) {
      _RowKind.ok => (Icons.check_rounded, TapInColors.successStrong),
      _RowKind.bad => (Icons.close_rounded, TapInColors.danger),
      _RowKind.wait => (Icons.schedule_rounded, TapInColors.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.text,
              style: TapInText.bodySmall(arabic: isArabic(context)).copyWith(fontSize: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Look {
  const _Look({
    required this.circle,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor = TapInColors.ink,
    this.message = '',
    this.rows = const [],
  });

  final Color circle;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final String message;
  final List<_Row> rows;
}

/// Reason rows for the codes the employee can act on.
const _reasons = {
  'out_of_range',
  'too_soon',
  'mock_location',
  'location_required',
  'unknown_card',
  'device_not_allowed',
  'already_checked_in',
  'not_checked_in',
  'photo_required',
  'invalid_photo',
  'subscription_inactive',
  'too_old',
  'invalid_time',
  'older_than_last',
  'cannot_record',
  'invalid_token',
  'access_switched_off',
};

_Look _lookOf(BuildContext context, TapOutcome outcome) {
  final locale = context.locale.languageCode;
  String hm(DateTime? t) => DateFormat.Hm(locale).format((t ?? DateTime.now()).toLocal());
  const rejected = (TapInColors.danger, Icons.close_rounded, TapInColors.surfaceRaised);
  switch (outcome) {
    case TapSent(:final result, :final message, :final site, :final time, :final tappedAt, :final photoTaken):
      final when = hm(time ?? tappedAt);
      return _Look(
        circle: TapInColors.success,
        icon: Icons.check_rounded,
        iconColor: TapInColors.ink,
        title: switch (result) {
          'check_in' => 'result.checked_in'.tr(),
          'check_out' => 'result.checked_out'.tr(),
          _ => 'result.recorded'.tr(),
        },
        message: site != null
            ? 'result.time_site'.tr(namedArgs: {'time': when, 'site': site})
            : (message.isNotEmpty ? message : when),
        rows: [
          _Row(_RowKind.ok, 'result.row_in_range'.tr()),
          if (photoTaken) _Row(_RowKind.ok, 'result.row_photo'.tr()),
        ],
      );
    case TapRejected(:final code, :final message):
      return _Look(
        circle: rejected.$1,
        icon: rejected.$2,
        iconColor: rejected.$3,
        title: 'result.rejected'.tr(),
        titleColor: TapInColors.danger,
        message: message.isNotEmpty ? message : 'result.rejected_code'.tr(namedArgs: {'code': code}),
        rows: [if (_reasons.contains(code)) _Row(_RowKind.bad, 'result.reason.$code'.tr())],
      );
    case TapNoGps():
      return _Look(
        circle: rejected.$1,
        icon: rejected.$2,
        iconColor: rejected.$3,
        title: 'result.rejected'.tr(),
        titleColor: TapInColors.danger,
        message: 'result.no_gps'.tr(),
        rows: [_Row(_RowKind.bad, 'result.row_no_gps'.tr())],
      );
    case TapSaved(:final tappedAt, :final photoTaken, :final heldBy):
      return _Look(
        circle: TapInColors.warningTint,
        icon: Icons.schedule_rounded,
        iconColor: TapInColors.warning,
        title: 'result.saved'.tr(),
        titleColor: TapInColors.warning,
        message: 'result.saved_body'.tr(namedArgs: {'time': hm(tappedAt)}),
        rows: [
          _Row(_RowKind.ok, photoTaken ? 'result.row_recorded_photo'.tr() : 'result.row_recorded'.tr()),
          if (heldBy != null && _reasons.contains(heldBy)) _Row(_RowKind.bad, 'result.reason.$heldBy'.tr()),
          _Row(_RowKind.wait, 'result.row_waiting'.tr()),
        ],
      );
    case TapNeedsLogin():
      return _Look(
        circle: TapInColors.warningTint,
        icon: Icons.schedule_rounded,
        iconColor: TapInColors.warning,
        title: 'result.saved'.tr(),
        titleColor: TapInColors.warning,
        message: 'result.saved_body'.tr(namedArgs: {'time': hm(null)}),
        rows: [_Row(_RowKind.wait, 'result.row_waiting'.tr())],
      );
    case TapIgnored() || TapNeedsAction() || TapCancelled():
      return const _Look(
        circle: TapInColors.border,
        icon: Icons.info_outline_rounded,
        iconColor: TapInColors.ink,
        title: '',
      );
  }
}
