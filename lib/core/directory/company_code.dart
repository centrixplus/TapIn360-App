/// Company code rule (TapIn360 spec §5.3): 3–30 characters, lowercase a-z, 0-9
/// and `-`, starts with a letter, does not end with `-`, no `--`.
final _codePattern = RegExp(r'^[a-z][a-z0-9-]{1,28}[a-z0-9]$');

bool isValidCompanyCode(String code) => _codePattern.hasMatch(code) && !code.contains('--');

/// Trims and lower-cases a typed code; null when it breaks the rule.
String? normaliseCompanyCode(String input) {
  final code = input.trim().toLowerCase();
  return isValidCompanyCode(code) ? code : null;
}

/// Company code from a scanned QR: `tapin://company/<code>`, or a bare valid
/// code. Anything else (web links, Wi-Fi QR codes…) is refused.
String? companyCodeFromQr(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.contains('://')) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.toLowerCase() != 'tapin' || uri.host.toLowerCase() != 'company') {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.length == 1 ? normaliseCompanyCode(segments.single) : null;
  }
  return normaliseCompanyCode(text);
}
