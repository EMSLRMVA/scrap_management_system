import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/enterprise_theme.dart';

final appThemeProvider =
    AsyncNotifierProvider<AppThemeController, AppThemeModel>(
      AppThemeController.new,
    );

final enterpriseThemeModeProvider =
    AsyncNotifierProvider<EnterpriseThemeModeController, EnterpriseThemeMode>(
      EnterpriseThemeModeController.new,
    );

class AppThemeController extends AsyncNotifier<AppThemeModel> {
  static const _selectedThemeKey = 'app_theme_selected_id';
  static const _legacyModeKey = 'enterprise_theme_mode';
  static const _importedThemeKey = 'app_theme_imported_json';

  @override
  Future<AppThemeModel> build() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId =
        prefs.getString(_selectedThemeKey) ??
        _legacyId(prefs.getString(_legacyModeKey));
    final imported = _readImportedTheme(prefs);
    if (imported != null && selectedId == imported.id) {
      return imported;
    }
    if (selectedId != null && selectedId.isNotEmpty) {
      final catalogTheme = EnterpriseTheme.catalogThemes.where(
        (theme) => theme.id == selectedId,
      );
      if (catalogTheme.isNotEmpty) {
        return catalogTheme.first;
      }
    }
    return EnterpriseTheme.modelForMode(EnterpriseThemeMode.midnightBlue);
  }

  Future<void> applyMode(EnterpriseThemeMode mode) async {
    await applyTheme(EnterpriseTheme.modelForMode(mode));
  }

  Future<void> applyTheme(AppThemeModel theme) async {
    state = AsyncData(theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedThemeKey, theme.id);
    await prefs.setString(
      _legacyModeKey,
      EnterpriseTheme.modeForId(theme.id)?.name ?? theme.id,
    );
    if (theme.imported) {
      await prefs.setString(_importedThemeKey, jsonEncode(theme.toJson()));
    }
  }

  Future<AppThemeModel> fetchThemeFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Enter a valid theme JSON URL.');
    }
    final raw = await NetworkAssetBundle(
      Uri.base,
    ).loadString(uri.toString()).timeout(const Duration(seconds: 18));
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Theme JSON must be an object.');
    }
    final theme = AppThemeModel.fromJson(
      decoded,
      id: _importedId(decoded),
      imported: true,
    );
    _validateTheme(theme);
    return theme;
  }

  Future<AppThemeModel> importThemeFromUrl(String url) async {
    final theme = await fetchThemeFromUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_importedThemeKey, jsonEncode(theme.toJson()));
    await applyTheme(theme);
    return theme;
  }

  String exportThemeJson(AppThemeModel theme) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(theme.toJson());
  }

  AppThemeModel? _readImportedTheme(SharedPreferences prefs) {
    final raw = prefs.getString(_importedThemeKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final theme = AppThemeModel.fromJson(
        decoded,
        id: _importedId(decoded),
        imported: true,
      );
      _validateTheme(theme);
      return theme;
    } catch (_) {
      return null;
    }
  }

  void _validateTheme(AppThemeModel theme) {
    if (theme.themeName.trim().isEmpty) {
      throw const FormatException('Theme name is required.');
    }
    if (theme.chartColors.length < 2) {
      throw const FormatException('At least two chart colors are required.');
    }
  }

  String? _legacyId(String? saved) {
    return switch (saved) {
      'executiveBlue' => 'light_mode',
      'financeDark' => 'midnight_blue',
      'premiumEmerald' => 'forest_green',
      'steelGrey' => 'slate_dark',
      'cleanWhite' => 'light_mode',
      'midnightGraphite' => 'slate_dark',
      'emeraldExecutive' => 'forest_green',
      'sapphireSteel' => 'ocean_blue',
      'copperSlate' => 'sunset_orange',
      _ =>
        saved == null
            ? null
            : EnterpriseTheme.catalogThemes
                  .where((theme) => theme.id == saved)
                  .firstOrNull
                  ?.id,
    };
  }
}

class EnterpriseThemeModeController extends AsyncNotifier<EnterpriseThemeMode> {
  @override
  Future<EnterpriseThemeMode> build() async {
    final theme = await ref.watch(appThemeProvider.future);
    return EnterpriseTheme.modeForId(theme.id) ??
        EnterpriseThemeMode.midnightBlue;
  }

  Future<void> setMode(EnterpriseThemeMode mode) async {
    await ref.read(appThemeProvider.notifier).applyMode(mode);
    state = AsyncData(mode);
  }
}

String _importedId(Map<String, dynamic> json) {
  final name = (json['themeName'] ?? 'Imported Theme').toString();
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'imported_${slug.isEmpty ? 'theme' : slug}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
