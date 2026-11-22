import 'package:flutter/foundation.dart';

import '../config/server_url.dart';

enum CompanyStatus { active, grace, provisioning, suspended, unknown }

/// A TapIn360 customer from the master's directory (TapIn360 spec §5.6).
@immutable
class Company {
  const Company({
    required this.code,
    required this.name,
    required this.apiBaseUrl,
    required this.status,
    this.logoUrl,
  });

  final String code;
  final String name;

  /// Base URL of the company's attendance API (`…/nfc/api/v1`), normalised.
  final String apiBaseUrl;
  final CompanyStatus status;
  final String? logoUrl;

  /// Active, or in the grace period after expiry (the app keeps working).
  bool get canLogIn => status == CompanyStatus.active || status == CompanyStatus.grace;

  /// Host shown under the name, e.g. `acme.karrix.com`.
  String get host => Uri.tryParse(apiBaseUrl)?.host ?? '';

  /// Up to two initials for the logo placeholder.
  String get initials {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'\w').hasMatch(w[0]))
        .toList();
    if (words.isEmpty) return code.substring(0, 1).toUpperCase();
    return words.take(2).map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  }

  static Company? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    final name = json['name'];
    final base = json['api_base_url'];
    if (code is! String || name is! String || base is! String) return null;
    final apiBaseUrl = normaliseServerUrl(base);
    if (apiBaseUrl == null) return null;
    final logo = json['logo_url'];
    return Company(
      code: code,
      name: name,
      apiBaseUrl: apiBaseUrl,
      status: switch (json['status']) {
        'active' => CompanyStatus.active,
        'grace' => CompanyStatus.grace,
        'provisioning' => CompanyStatus.provisioning,
        'suspended' => CompanyStatus.suspended,
        _ => CompanyStatus.unknown,
      },
      logoUrl: logo is String && logo.isNotEmpty ? logo : null,
    );
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'logo_url': logoUrl,
    'api_base_url': apiBaseUrl,
    'status': status.name,
  };
}
