import '../time/iso_time.dart';

/// Company setting: server toggles (auto) or the employee picks (manual).
enum PunchMode {
  auto,
  manual;

  static PunchMode parse(Object? value) => value == 'manual' ? manual : auto;
}

/// `action` of `POST /punch`.
enum PunchAction {
  auto('auto'),
  checkIn('check_in'),
  checkOut('check_out');

  const PunchAction(this.wire);
  final String wire;

  static PunchAction? parse(Object? value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

enum AttendanceState { checkedIn, checkedOut }

class Employee {
  const Employee({required this.id, required this.name});

  final int id;
  final String name;

  static Employee? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return Employee(id: id, name: name);
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// `device` block of `POST /login` (spec §5.2 + §14.1).
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.platform,
    required this.model,
    required this.appVersion,
    required this.hardwareId,
    required this.osVersion,
  });

  /// App-install UUID.
  final String id;
  final String platform;
  final String model;
  final String appVersion;

  /// Android `ANDROID_ID` / iOS `identifierForVendor` (survives reinstalls).
  final String hardwareId;

  /// e.g. `16` (Android) or `18.1` (iOS).
  final String osVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'platform': platform,
    'model': model,
    'app_version': appVersion,
    'hardware_id': hardwareId,
    'os_version': osVersion,
  };
}

class LoginResult {
  const LoginResult({
    required this.token,
    required this.employee,
    required this.punchMode,
    this.photoRequired = false,
    this.serverTime,
  });

  final String token;
  final Employee employee;
  final PunchMode punchMode;

  /// `settings.photo_required` (spec §15.1); absent → false.
  final bool photoRequired;
  final DateTime? serverTime;

  static LoginResult? fromJson(Map<String, Object?> json) {
    final token = json['token'];
    final employee = Employee.fromJson(json['employee']);
    if (token is! String || token.isEmpty || employee == null) return null;
    final settings = json['settings'];
    return LoginResult(
      token: token,
      employee: employee,
      punchMode: PunchMode.parse(settings is Map ? settings['punch_mode'] : null),
      photoRequired: settings is Map && settings['photo_required'] == true,
      serverTime: parseServerTime(json['server_time']),
    );
  }
}

class PunchResult {
  const PunchResult({required this.result, required this.message, this.time, this.site});

  /// `check_in` or `check_out`.
  final String result;
  final String message;
  final DateTime? time;
  final String? site;

  /// Any 200 means the server recorded the tap, so parsing is lenient.
  static PunchResult fromJson(Map<String, Object?> json) {
    final result = json['result'];
    final message = json['message'];
    final site = json['site'];
    return PunchResult(
      result: result is String ? result : '',
      message: message is String ? message : '',
      time: parseServerTime(json['time']),
      site: site is String ? site : null,
    );
  }

  Map<String, Object?> toJson() => {
    'result': result,
    'message': message,
    'time': time?.toIso8601String(),
    'site': site,
  };
}

class StatusResult {
  const StatusResult({
    required this.employee,
    required this.state,
    required this.punchMode,
    this.photoRequired = false,
    this.since,
    this.site,
    this.serverTime,
  });

  final Employee employee;
  final AttendanceState state;
  final PunchMode punchMode;

  /// `settings.photo_required` (§15.1; top-level `photo_required` also read).
  final bool photoRequired;
  final DateTime? since;
  final String? site;
  final DateTime? serverTime;

  static StatusResult? fromJson(Map<String, Object?> json) {
    final employee = Employee.fromJson(json['employee']);
    final state = switch (json['state']) {
      'checked_in' => AttendanceState.checkedIn,
      'checked_out' => AttendanceState.checkedOut,
      _ => null,
    };
    if (employee == null || state == null) return null;
    final site = json['site'];
    final settings = json['settings'];
    return StatusResult(
      employee: employee,
      state: state,
      punchMode: PunchMode.parse(json['punch_mode']),
      photoRequired:
          (settings is Map && settings['photo_required'] == true) || json['photo_required'] == true,
      since: parseServerTime(json['since']),
      site: site is String ? site : null,
      serverTime: parseServerTime(json['server_time']),
    );
  }
}
