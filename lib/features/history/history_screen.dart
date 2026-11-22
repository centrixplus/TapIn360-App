import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tokens.dart';
import '../../core/queue/tap_record.dart';
import '../common/tapin_widgets.dart';
import 'history_row.dart';

/// Last 50 taps from the phone, grouped by day (AppHistory artboard).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<TapRecord>? _rows;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = ref.read(tapStoreProvider).changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await ref.read(tapStoreProvider).recent(limit: 50);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _refresh() async {
    await ref.read(punchQueueProvider).flush();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TapInSpace.gutter, TapInSpace.s4, TapInSpace.gutter, 28),
            children: [
              BackHeader(title: 'history.title'.tr()),
              const SizedBox(height: TapInSpace.s4),
              if (rows == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                TapInCard(
                  child: Text('history.empty'.tr(), style: TapInText.body(arabic: isArabic(context))),
                )
              else
                for (final group in groupByDay(rows)) ...[
                  FieldLabel(dayLabel(context, group.day)),
                  const SizedBox(height: TapInSpace.s2),
                  TapInCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, tap) in group.taps.indexed) ...[
                          if (i > 0) const Divider(height: 1, color: TapInColors.border),
                          HistoryRow(tap: tap),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: TapInSpace.s4),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class DayGroup {
  DayGroup(this.day, this.taps);
  final DateTime day;
  final List<TapRecord> taps;
}

/// Newest first, one group per local day.
List<DayGroup> groupByDay(List<TapRecord> rows) {
  final groups = <DayGroup>[];
  for (final tap in rows) {
    final day = DateUtils.dateOnly(tapTime(tap));
    if (groups.isEmpty || groups.last.day != day) groups.add(DayGroup(day, []));
    groups.last.taps.add(tap);
  }
  return groups;
}

DateTime tapTime(TapRecord tap) => (tap.tappedAt ?? tap.createdAt).toLocal();

String dayLabel(BuildContext context, DateTime day, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  if (day == today) return 'history.today'.tr();
  if (day == today.subtract(const Duration(days: 1))) return 'history.yesterday'.tr();
  return DateFormat.yMMMd(context.locale.languageCode).format(day);
}
