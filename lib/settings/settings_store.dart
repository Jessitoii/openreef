import 'dart:convert';
import 'dart:io';

import 'package:openreef/settings/app_settings.dart';

class SettingsStore {
  SettingsStore(this._file);

  final File _file;

  Future<AppSettings> read() async {
    if (!await _file.exists()) {
      return const AppSettings();
    }

    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const AppSettings();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const AppSettings();
    }

    return AppSettings.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> write(AppSettings settings) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
  }
}
