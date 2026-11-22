/// Normalises the Server URL typed by the user (spec §5.1: the base URL under
/// which `login`, `punch`, `status` and `logout` live).
///
/// Trims whitespace, adds `https://` when no scheme is given, lower-cases the
/// scheme and strips every trailing slash. Returns null when the text is not a
/// usable http(s) base URL (no host, other scheme, query or fragment).
String? normaliseServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(' ')) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty || uri.hasQuery || uri.hasFragment) return null;
  final rest = text.substring(text.indexOf('://') + 3).replaceFirst(RegExp(r'/+$'), '');
  return '$scheme://$rest';
}

/// Hosts that may be reached over plain `http://`: the phone itself (local
/// servers over `adb reverse`) and the Android emulator's host loopback. The
/// same list is in `network_security_config.xml`; iOS allows local networking.
const cleartextHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// True for an `http://` URL whose host is not in [cleartextHosts]: the app
/// refuses it ("https required") instead of failing later as unreachable.
bool isInsecureServerUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme.toLowerCase() != 'http') return false;
  return !cleartextHosts.contains(uri.host.toLowerCase());
}

/// `base` + `/` + `path`; [base] is already normalised (no trailing slash).
String endpointUrl(String base, String path) => '$base/$path';
