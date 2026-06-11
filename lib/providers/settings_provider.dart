import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/local_settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._service) : _settings = AppSettings.defaults();

  final LocalSettingsService _service;
  AppSettings _settings;

  AppSettings get settings => _settings;
  ThemeMode get themeMode => _settings.themeMode;

  Future<void> load() async {
    _settings = await _service.load();
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _service.save(settings);
  }

  Future<void> setThemeMode(ThemeMode themeMode) {
    return update(_settings.copyWith(themeMode: themeMode));
  }

  Future<void> setAutoBackup(bool value) {
    return update(_settings.copyWith(autoBackup: value));
  }

  Future<void> setFingerprintLock(bool value) {
    return update(_settings.copyWith(fingerprintLock: value));
  }
}
