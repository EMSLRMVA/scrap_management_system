import 'package:flutter/material.dart';

class AppSettings {
  const AppSettings({
    required this.companyName,
    required this.companyPhone,
    required this.companyAddress,
    required this.language,
    required this.themeMode,
    required this.autoBackup,
    required this.fingerprintLock,
  });

  final String companyName;
  final String companyPhone;
  final String companyAddress;
  final String language;
  final ThemeMode themeMode;
  final bool autoBackup;
  final bool fingerprintLock;

  factory AppSettings.defaults() {
    return const AppSettings(
      companyName: 'Scrap System',
      companyPhone: '+91 98765 43210',
      companyAddress: 'Peelamedu, Coimbatore',
      language: 'English',
      themeMode: ThemeMode.dark,
      autoBackup: true,
      fingerprintLock: true,
    );
  }

  AppSettings copyWith({
    String? companyName,
    String? companyPhone,
    String? companyAddress,
    String? language,
    ThemeMode? themeMode,
    bool? autoBackup,
    bool? fingerprintLock,
  }) {
    return AppSettings(
      companyName: companyName ?? this.companyName,
      companyPhone: companyPhone ?? this.companyPhone,
      companyAddress: companyAddress ?? this.companyAddress,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      autoBackup: autoBackup ?? this.autoBackup,
      fingerprintLock: fingerprintLock ?? this.fingerprintLock,
    );
  }
}
