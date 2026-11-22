import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _keys(Map<String, Object?> json, [String prefix = '']) {
  return {
    for (final entry in json.entries)
      ...(entry.value is Map<String, Object?>
          ? _keys(entry.value! as Map<String, Object?>, '$prefix${entry.key}.')
          : {'$prefix${entry.key}'}),
  };
}

void main() {
  Map<String, Object?> load(String code) =>
      jsonDecode(File('assets/translations/$code.json').readAsStringSync()) as Map<String, Object?>;

  test('English and Arabic have exactly the same keys', () {
    expect(_keys(load('ar')), _keys(load('en')));
  });

  test('every translation key used in lib/ exists', () {
    final keys = _keys(load('en'));
    final used = <String>{};
    final pattern = RegExp(r"'([a-z_]+\.[a-z_.]+)'\.tr\(");
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      used.addAll(pattern.allMatches(file.readAsStringSync()).map((m) => m.group(1)!));
    }
    expect(used.difference(keys), isEmpty);
  });
}
