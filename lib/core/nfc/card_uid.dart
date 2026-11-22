import 'dart:typed_data';

/// Formats an NFC tag UID as uppercase hex without separators,
/// e.g. `[0x04, 0xDB, ...]` → `04DB8FE23B1590` (API contract §5.2 `card_uid`).
String formatCardUid(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'UID must not be empty');
  }
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString().toUpperCase();
}
