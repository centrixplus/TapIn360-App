import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/server_url.dart';
import '../config/tapin_config.dart';
import 'company.dart';

sealed class CompanyLookup {
  const CompanyLookup();
}

/// Active or in grace: the employee can continue to Login.
final class CompanyFound extends CompanyLookup {
  const CompanyFound(this.company);
  final Company company;
}

/// Known but not usable now (provisioning, suspended, unknown state).
final class CompanyNotReady extends CompanyLookup {
  const CompanyNotReady(this.company);
  final Company company;
}

final class CompanyNotFound extends CompanyLookup {
  const CompanyNotFound();
}

/// The directory gave a plain `http://` API base on a host other than the
/// phone itself: refused, "https required" (never stored or contacted).
final class CompanyInsecure extends CompanyLookup {
  const CompanyInsecure(this.company);
  final Company company;
}

final class CompanyLookupRateLimited extends CompanyLookup {
  const CompanyLookupRateLimited();
}

/// No usable answer (no connection, timeout, 5xx, garbled body).
final class CompanyLookupFailed extends CompanyLookup {
  const CompanyLookupFailed(this.reason);
  final String reason;
}

/// TapIn360 master directory: `GET /tapin/api/v1/company/<code>` (spec §5.6).
class DirectoryApi {
  DirectoryApi({
    required this._dio,
    required this._masterUrl,
    required this._language,
    this.timeout = const Duration(seconds: 10),
  });

  final Dio _dio;
  final String _masterUrl;
  final String Function() _language;
  final Duration timeout;

  Future<CompanyLookup> lookup(String code) async {
    final Response<String> response;
    try {
      response = await _dio
          .get<String>(
            directoryUrl(_masterUrl, code),
            options: Options(headers: {'Accept': 'application/json', 'Accept-Language': _language()}),
          )
          .timeout(timeout);
    } on DioException catch (e) {
      return CompanyLookupFailed(e.type.name);
    } on TimeoutException {
      return const CompanyLookupFailed('timeout');
    }
    final status = response.statusCode ?? 0;
    if (status == 404 || status == 400) return const CompanyNotFound();
    if (status == 429) return const CompanyLookupRateLimited();
    if (status < 200 || status >= 300) return CompanyLookupFailed('http_$status');
    final company = Company.fromJson(_decode(response.data));
    if (company == null) return const CompanyLookupFailed('invalid_response');
    if (isInsecureServerUrl(company.apiBaseUrl)) return CompanyInsecure(company);
    return company.canLogIn ? CompanyFound(company) : CompanyNotReady(company);
  }

  static Object? _decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
