import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class LocalSettingsService {
  static const _companyName = 'company_name';
  static const _companyPhone = 'company_phone';
  static const _companyAddress = 'company_address';
  static const _language = 'language';
  static const _themeMode = 'theme_mode';
  static const _autoBackup = 'auto_backup';
  static const _fingerprintLock = 'fingerprint_lock';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = AppSettings.defaults();

    return AppSettings(
      companyName: prefs.getString(_companyName) ?? defaults.companyName,
      companyPhone: prefs.getString(_companyPhone) ?? defaults.companyPhone,
      companyAddress:
          prefs.getString(_companyAddress) ?? defaults.companyAddress,
      language: prefs.getString(_language) ?? defaults.language,
      themeMode: _parseThemeMode(
        prefs.getString(_themeMode) ?? defaults.themeMode.name,
      ),
      autoBackup: prefs.getBool(_autoBackup) ?? defaults.autoBackup,
      fingerprintLock:
          prefs.getBool(_fingerprintLock) ?? defaults.fingerprintLock,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_companyName, settings.companyName);
    await prefs.setString(_companyPhone, settings.companyPhone);
    await prefs.setString(_companyAddress, settings.companyAddress);
    await prefs.setString(_language, settings.language);
    await prefs.setString(_themeMode, settings.themeMode.name);
    await prefs.setBool(_autoBackup, settings.autoBackup);
    await prefs.setBool(_fingerprintLock, settings.fingerprintLock);
  }

  ThemeMode _parseThemeMode(String value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.dark,
    );
  }
}
