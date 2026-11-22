import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/server_url.dart';
import 'api_models.dart';
import 'api_outcome.dart';
import 'error_codes.dart';
import 'server_probe.dart';

/// Dio set up for API contract v1: every status is returned to us (no
/// exceptions for 4xx), bodies are read as text so non-JSON error pages are
/// handled, and redirects are not followed (a redirected POST would lose its
/// body).
Dio createApiDio({Duration timeout = AttendanceApi.defaultTimeout}) {
  return Dio(
    BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      responseType: ResponseType.plain,
      followRedirects: false,
      validateStatus: (_) => true,
    ),
  );
}

/// Client side of API contract v1 (spec §5).
class AttendanceApi {
  AttendanceApi({
    required this._dio,
    required this._baseUrl,
    required this._token,
    required this._language,
    this.timeout = defaultTimeout,
  });

  /// Punch send timeout from spec §6.2; used for every call.
  static const defaultTimeout = Duration(seconds: 10);

  final Dio _dio;
  final String? Function() _baseUrl;
  final String? Function() _token;
  final String Function() _language;
  final Duration timeout;

  Future<ApiOutcome<LoginResult>> login({
    required String login,
    required String password,
    required DeviceInfo device,
  }) async {
    final raw = await _send(
      'POST',
      'login',
      body: {'login': login, 'password': password, 'device': device.toJson()},
      auth: false,
    );
    return _typed(raw, LoginResult.fromJson);
  }

  /// [body] is the stored request JSON (§5.2), sent unchanged.
  Future<ApiOutcome<PunchResult>> punch(Map<String, Object?> body) async {
    final raw = await _send('POST', 'punch', body: body);
    return _typed(raw, PunchResult.fromJson);
  }

  Future<ApiOutcome<StatusResult>> status() async {
    final raw = await _send('GET', 'status');
    return _typed(raw, StatusResult.fromJson);
  }

  Future<ApiOutcome<bool>> logout() async {
    final raw = await _send('POST', 'logout', body: const {});
    return _typed(raw, (_) => true);
  }

  /// Server setup **Test**: `GET /status` on [baseUrl] without a token.
  Future<ServerProbe> probe(String baseUrl) async {
    final Response<String> response;
    try {
      response = await _dio
          .get<String>(endpointUrl(baseUrl, 'status'), options: _options('GET', auth: false))
          .timeout(timeout);
    } on DioException {
      return const ServerProbe(ProbeKind.unreachable);
    } on TimeoutException {
      return const ServerProbe(ProbeKind.unreachable);
    }
    final status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) {
      return ServerProbe(ProbeKind.redirect, status: status, location: response.headers.value('location'));
    }
    final error = _errorOf(_decode(response.data));
    if (status == 401 && error?['code'] == ErrorCodes.invalidToken) {
      return ServerProbe(ProbeKind.ok, status: status);
    }
    return ServerProbe(ProbeKind.notAttendanceServer, status: status);
  }

  Future<ApiOutcome<Map<String, Object?>>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool auth = true,
  }) async {
    final base = _baseUrl();
    if (base == null) return const ApiUnreachable('no_server');
    if (auth && _token() == null) {
      return const ApiRejected(status: 401, code: ErrorCodes.invalidToken, message: '');
    }
    try {
      final response = await _dio
          .request<String>(
            endpointUrl(base, path),
            data: body == null ? null : jsonEncode(body),
            options: _options(method, auth: auth, hasBody: body != null),
          )
          .timeout(timeout);
      return _map(response.statusCode ?? 0, response.data);
    } on DioException catch (e) {
      return ApiUnreachable(e.type.name);
    } on TimeoutException {
      return const ApiUnreachable('timeout');
    }
  }

  Options _options(String method, {required bool auth, bool hasBody = false}) {
    final token = auth ? _token() : null;
    return Options(
      method: method,
      sendTimeout: hasBody ? timeout : null,
      headers: {
        'Accept': 'application/json',
        'Accept-Language': _language(),
        if (hasBody) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }

  /// Gateway answers: the proxy is up but the server behind it is not.
  static const _gatewayDown = {502, 503, 504};

  ApiOutcome<Map<String, Object?>> _map(int status, String? text) {
    final json = _decode(text);
    if (status >= 200 && status < 300) {
      return json == null ? const ApiUnreachable('invalid_response', answered: true) : ApiOk(json);
    }
    if (status >= 400 && status < 500) {
      final error = _errorOf(json);
      if (error == null) {
        // Not our API answering (wrong URL, proxy page): keep the tap Waiting
        // instead of losing it as a final rejection.
        return ApiUnreachable('http_$status', answered: true);
      }
      final message = error['message'];
      return ApiRejected(
        status: status,
        code: error['code'] as String,
        message: message is String ? message : '',
        details: error,
      );
    }
    return ApiUnreachable('http_$status', answered: !_gatewayDown.contains(status));
  }

  static ApiOutcome<T> _typed<T>(
    ApiOutcome<Map<String, Object?>> raw,
    T? Function(Map<String, Object?> json) parse,
  ) {
    return switch (raw) {
      ApiOk(:final value) => switch (parse(value)) {
        final T parsed => ApiOk(parsed),
        null => const ApiUnreachable('invalid_response', answered: true),
      },
      ApiRejected() => raw.cast<T>(),
      ApiUnreachable() => raw.cast<T>(),
    };
  }

  static Map<String, Object?>? _decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final value = jsonDecode(text);
      return value is Map<String, Object?> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// The `error` object of the standard error shape, when it has a code.
  static Map<String, Object?>? _errorOf(Map<String, Object?>? json) {
    final error = json?['error'];
    if (error is Map<String, Object?> && error['code'] is String) return error;
    return null;
  }
}
