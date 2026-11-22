import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_models.dart';
import '../directory/company.dart';
import '../session/session.dart';
import 'key_value_store.dart';

/// Persists the [Session] fields (token and device ID live in secure storage,
/// spec §6.5).
class SessionStore {
  SessionStore(this._kv, {required this._newDeviceId});

  static const _kServerUrl = 'server_url';
  static const _kToken = 'token';
  static const _kEmployee = 'employee';
  static const _kPunchMode = 'punch_mode';
  static const _kPhotoRequired = 'photo_required';
  static const _kCompany = 'company';
  static const _kDeviceId = 'device_id';
  static const _kSwitchedOff = 'access_switched_off';

  final KeyValueStore _kv;
  final String Function() _newDeviceId;

  /// Loads the session, creating the device ID on first launch. If storage is
  /// unreadable (Android can lose the keystore key after a restore) it is
  /// wiped and the app starts from Server setup.
  Future<Session> load() async {
    try {
      return await _read();
    } catch (error) {
      debugPrint('Session storage unreadable, resetting: $error');
      try {
        await _kv.clear();
        return await _read();
      } catch (_) {
        return Session(deviceId: _newDeviceId());
      }
    }
  }

  Future<Session> _read() async {
    var deviceId = await _kv.read(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _newDeviceId();
      await _kv.write(_kDeviceId, deviceId);
    }
    final employeeJson = await _kv.read(_kEmployee);
    final companyJson = await _kv.read(_kCompany);
    final token = await _kv.read(_kToken);
    return Session(
      deviceId: deviceId,
      serverUrl: await _kv.read(_kServerUrl),
      token: token,
      employee: employeeJson == null ? null : Employee.fromJson(jsonDecode(employeeJson)),
      punchMode: PunchMode.parse(await _kv.read(_kPunchMode)),
      photoRequired: await _kv.read(_kPhotoRequired) == 'true',
      company: companyJson == null ? null : Company.fromJson(jsonDecode(companyJson)),
      // Kept across restarts: taps stay blocked until a /status succeeds.
      accessSwitchedOff: token != null && await _kv.read(_kSwitchedOff) == 'true',
    );
  }

  Future<void> saveSwitchedOff(bool off) => _kv.write(_kSwitchedOff, off ? 'true' : null);

  Future<void> saveServerUrl(String url) => _kv.write(_kServerUrl, url);

  /// The company picked by code, or null for a custom server URL.
  Future<void> saveCompany(Company? company) =>
      _kv.write(_kCompany, company == null ? null : jsonEncode(company.toJson()));

  /// Change company: forget the server and the company.
  Future<void> clearServer() async {
    await _kv.write(_kServerUrl, null);
    await _kv.write(_kCompany, null);
  }

  Future<void> saveLogin({
    required String token,
    required Employee employee,
    required PunchMode punchMode,
    bool photoRequired = false,
  }) async {
    await _kv.write(_kToken, token);
    await saveEmployee(employee: employee, punchMode: punchMode, photoRequired: photoRequired);
  }

  /// Employee and the company settings from `/login` or `/status`.
  Future<void> saveEmployee({
    required Employee employee,
    required PunchMode punchMode,
    bool photoRequired = false,
  }) async {
    await _kv.write(_kEmployee, jsonEncode(employee.toJson()));
    await _kv.write(_kPunchMode, punchMode.name);
    await _kv.write(_kPhotoRequired, '$photoRequired');
  }

  Future<void> clearLogin() async {
    await _kv.write(_kToken, null);
    await _kv.write(_kEmployee, null);
    await _kv.write(_kSwitchedOff, null);
  }
}
