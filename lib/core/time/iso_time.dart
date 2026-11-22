/// ISO 8601 with the phone's UTC offset and whole seconds, as the API wants for
/// `tapped_at` and `location.captured_at` (spec §5.1), e.g.
/// `2026-11-17T09:02:11+03:00`.
String isoWithOffset(DateTime instant, Duration offset) {
  final wall = instant.toUtc().add(offset);
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '${_four(wall.year)}-${_two(wall.month)}-${_two(wall.day)}'
      'T${_two(wall.hour)}:${_two(wall.minute)}:${_two(wall.second)}'
      '$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)}';
}

/// [isoWithOffset] using [time]'s own local offset.
String localIso(DateTime time) {
  final local = time.toLocal();
  return isoWithOffset(local, local.timeZoneOffset);
}

/// Server timestamps are ISO 8601 UTC (spec §5.1). Null when absent or invalid.
DateTime? parseServerTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

String _two(int n) => n.toString().padLeft(2, '0');
String _four(int n) => n.toString().padLeft(4, '0');
