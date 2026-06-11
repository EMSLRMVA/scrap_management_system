import 'package:flutter/material.dart';

enum EnterpriseThemeMode {
  midnightBlue('Midnight Blue'),
  lightMode('Light Mode'),
  royalPurple('Royal Purple'),
  forestGreen('Forest Green'),
  oceanBlue('Ocean Blue'),
  sunsetOrange('Sunset Orange'),
  darkGold('Dark Gold'),
  rosePink('Rose Pink'),
  slateDark('Slate Dark'),
  tealBlue('Teal Blue');

  const EnterpriseThemeMode(this.label);

  final String label;
}

class AppThemeModel {
  const AppThemeModel({
    required this.id,
    required this.themeName,
    required this.description,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.textColor,
    required this.successColor,
    required this.dangerColor,
    required this.warningColor,
    required this.chartColors,
    required this.isDark,
    this.borderColor,
    this.mutedTextColor,
    this.gradientColors,
    this.imported = false,
  });

  final String id;
  final String themeName;
  final String description;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;
  final Color successColor;
  final Color dangerColor;
  final Color warningColor;
  final List<Color> chartColors;
  final bool isDark;
  final Color? borderColor;
  final Color? mutedTextColor;
  final List<Color>? gradientColors;
  final bool imported;

  Color get resolvedBorderColor =>
      borderColor ??
      (isDark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.black.withValues(alpha: 0.10));

  Color get resolvedMutedTextColor =>
      mutedTextColor ??
      (isDark ? const Color(0xFFB8C4D8) : const Color(0xFF64748B));

  List<Color> get resolvedGradientColors =>
      gradientColors ?? [primaryColor, secondaryColor];

  ThemeData toThemeData() => EnterpriseTheme.fromModel(this);

  AppThemeModel copyWith({
    String? id,
    String? themeName,
    String? description,
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? cardColor,
    Color? textColor,
    Color? successColor,
    Color? dangerColor,
    Color? warningColor,
    List<Color>? chartColors,
    bool? isDark,
    Color? borderColor,
    Color? mutedTextColor,
    List<Color>? gradientColors,
    bool? imported,
  }) {
    return AppThemeModel(
      id: id ?? this.id,
      themeName: themeName ?? this.themeName,
      description: description ?? this.description,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cardColor: cardColor ?? this.cardColor,
      textColor: textColor ?? this.textColor,
      successColor: successColor ?? this.successColor,
      dangerColor: dangerColor ?? this.dangerColor,
      warningColor: warningColor ?? this.warningColor,
      chartColors: chartColors ?? this.chartColors,
      isDark: isDark ?? this.isDark,
      borderColor: borderColor ?? this.borderColor,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      gradientColors: gradientColors ?? this.gradientColors,
      imported: imported ?? this.imported,
    );
  }

  factory AppThemeModel.fromJson(
    Map<String, dynamic> json, {
    String? id,
    bool imported = true,
  }) {
    final name = _readString(json, 'themeName', fallback: 'Imported Theme');
    final chartValues = json['chartColors'];
    final charts = chartValues is List
        ? chartValues
              .map((item) => _parseColor(item.toString()))
              .whereType<Color>()
              .toList()
        : <Color>[];

    return AppThemeModel(
      id: id ?? _themeId(name),
      themeName: name,
      description: _readString(
        json,
        'description',
        fallback: 'Imported premium theme',
      ),
      primaryColor:
          _parseColor(json['primaryColor']?.toString()) ??
          const Color(0xFF2563EB),
      secondaryColor:
          _parseColor(json['secondaryColor']?.toString()) ??
          const Color(0xFF06B6D4),
      backgroundColor:
          _parseColor(json['backgroundColor']?.toString()) ??
          const Color(0xFFF4F7FB),
      cardColor: _parseColor(json['cardColor']?.toString()) ?? Colors.white,
      textColor:
          _parseColor(json['textColor']?.toString()) ?? const Color(0xFF0F172A),
      successColor:
          _parseColor(json['successColor']?.toString()) ??
          const Color(0xFF10B981),
      dangerColor:
          _parseColor(json['dangerColor']?.toString()) ??
          const Color(0xFFEF4444),
      warningColor:
          _parseColor(json['warningColor']?.toString()) ??
          const Color(0xFFF59E0B),
      chartColors: charts.isEmpty
          ? const [
              Color(0xFF2563EB),
              Color(0xFF10B981),
              Color(0xFFF59E0B),
              Color(0xFF8B5CF6),
            ]
          : charts,
      isDark: json['isDark'] == true,
      imported: imported,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeName': themeName,
      'description': description,
      'primaryColor': _colorToHex(primaryColor),
      'secondaryColor': _colorToHex(secondaryColor),
      'backgroundColor': _colorToHex(backgroundColor),
      'cardColor': _colorToHex(cardColor),
      'textColor': _colorToHex(textColor),
      'successColor': _colorToHex(successColor),
      'dangerColor': _colorToHex(dangerColor),
      'warningColor': _colorToHex(warningColor),
      'chartColors': chartColors.map(_colorToHex).toList(),
      'isDark': isDark,
    };
  }
}

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens(this.theme);

  final AppThemeModel theme;

  @override
  AppThemeTokens copyWith({AppThemeModel? theme}) {
    return AppThemeTokens(theme ?? this.theme);
  }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) {
      return this;
    }
    return AppThemeTokens(
      AppThemeModel(
        id: t < 0.5 ? theme.id : other.theme.id,
        themeName: t < 0.5 ? theme.themeName : other.theme.themeName,
        description: t < 0.5 ? theme.description : other.theme.description,
        primaryColor: Color.lerp(
          theme.primaryColor,
          other.theme.primaryColor,
          t,
        )!,
        secondaryColor: Color.lerp(
          theme.secondaryColor,
          other.theme.secondaryColor,
          t,
        )!,
        backgroundColor: Color.lerp(
          theme.backgroundColor,
          other.theme.backgroundColor,
          t,
        )!,
        cardColor: Color.lerp(theme.cardColor, other.theme.cardColor, t)!,
        textColor: Color.lerp(theme.textColor, other.theme.textColor, t)!,
        successColor: Color.lerp(
          theme.successColor,
          other.theme.successColor,
          t,
        )!,
        dangerColor: Color.lerp(theme.dangerColor, other.theme.dangerColor, t)!,
        warningColor: Color.lerp(
          theme.warningColor,
          other.theme.warningColor,
          t,
        )!,
        chartColors: t < 0.5 ? theme.chartColors : other.theme.chartColors,
        isDark: t < 0.5 ? theme.isDark : other.theme.isDark,
        borderColor: Color.lerp(
          theme.resolvedBorderColor,
          other.theme.resolvedBorderColor,
          t,
        ),
        mutedTextColor: Color.lerp(
          theme.resolvedMutedTextColor,
          other.theme.resolvedMutedTextColor,
          t,
        ),
        gradientColors: t < 0.5
            ? theme.resolvedGradientColors
            : other.theme.resolvedGradientColors,
        imported: t < 0.5 ? theme.imported : other.theme.imported,
      ),
    );
  }
}

class EnterpriseTheme {
  static const primary = Color(0xFF102A56);
  static const accent = Color(0xFF2563EB);
  static const secondary = Color(0xFF334155);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFE05252);
  static const surface = Color(0xFF0F172A);
  static const panel = Color(0xFF111C2E);
  static const panelSoft = Color(0xFF17243A);
  static const border = Color(0xFF26364F);
  static const dashboardBackground = Color(0xFFF4F7FB);
  static const purchaseBackground = Color(0xFFFAF8F1);
  static const inventoryBackground = Color(0xFFF1FAF7);
  static const sellersBackground = Color(0xFFF7F5FB);
  static const reportsBackground = Color(0xFFF0FAFA);
  static const settingsBackground = Color(0xFFF6F7F9);
  static const lightBorder = Color(0xFFD8E0EA);

  static const _catalog = {
    EnterpriseThemeMode.midnightBlue: AppThemeModel(
      id: 'midnight_blue',
      themeName: 'Midnight Blue',
      description: 'Dark premium finance look with navy, blue, and cyan.',
      primaryColor: Color(0xFF2563EB),
      secondaryColor: Color(0xFF22D3EE),
      backgroundColor: Color(0xFF07111F),
      cardColor: Color(0xFF101B2E),
      textColor: Color(0xFFEAF2FF),
      successColor: Color(0xFF19C37D),
      dangerColor: Color(0xFFFF5B5B),
      warningColor: Color(0xFFFBBF24),
      chartColors: [
        Color(0xFF2F8CFF),
        Color(0xFF23C483),
        Color(0xFFFFA21A),
        Color(0xFF8B5CF6),
        Color(0xFF16C6D5),
      ],
      isDark: true,
      borderColor: Color(0xFF26364F),
      mutedTextColor: Color(0xFFB8C4D8),
      gradientColors: [Color(0xFF07111F), Color(0xFF102A56)],
    ),
    EnterpriseThemeMode.lightMode: AppThemeModel(
      id: 'light_mode',
      themeName: 'Light Mode',
      description: 'Clean white professional business workspace.',
      primaryColor: Color(0xFF1D4ED8),
      secondaryColor: Color(0xFF0EA5E9),
      backgroundColor: Color(0xFFF4F7FB),
      cardColor: Colors.white,
      textColor: Color(0xFF0F172A),
      successColor: Color(0xFF059669),
      dangerColor: Color(0xFFDC2626),
      warningColor: Color(0xFFF59E0B),
      chartColors: [
        Color(0xFF1D4ED8),
        Color(0xFF059669),
        Color(0xFFF59E0B),
        Color(0xFF7C3AED),
        Color(0xFF0D9488),
      ],
      isDark: false,
      borderColor: Color(0xFFD8E0EA),
      mutedTextColor: Color(0xFF64748B),
      gradientColors: [Color(0xFFFFFFFF), Color(0xFFEFF6FF)],
    ),
    EnterpriseThemeMode.royalPurple: AppThemeModel(
      id: 'royal_purple',
      themeName: 'Royal Purple',
      description: 'Luxury dashboard style with violet and neon accents.',
      primaryColor: Color(0xFF7C3AED),
      secondaryColor: Color(0xFFEC4899),
      backgroundColor: Color(0xFF140B2D),
      cardColor: Color(0xFF21113E),
      textColor: Color(0xFFF6EEFF),
      successColor: Color(0xFF34D399),
      dangerColor: Color(0xFFFB7185),
      warningColor: Color(0xFFFBBF24),
      chartColors: [
        Color(0xFFA855F7),
        Color(0xFFEC4899),
        Color(0xFF22D3EE),
        Color(0xFFF59E0B),
        Color(0xFF34D399),
      ],
      isDark: true,
      borderColor: Color(0xFF4C1D95),
      mutedTextColor: Color(0xFFD8B4FE),
      gradientColors: [Color(0xFF140B2D), Color(0xFF3B0764)],
    ),
    EnterpriseThemeMode.forestGreen: AppThemeModel(
      id: 'forest_green',
      themeName: 'Forest Green',
      description: 'Growth-focused green, emerald, and mint palette.',
      primaryColor: Color(0xFF047857),
      secondaryColor: Color(0xFF34D399),
      backgroundColor: Color(0xFF052E24),
      cardColor: Color(0xFF0D3B2E),
      textColor: Color(0xFFE8FFF5),
      successColor: Color(0xFF22C55E),
      dangerColor: Color(0xFFEF4444),
      warningColor: Color(0xFFFBBF24),
      chartColors: [
        Color(0xFF10B981),
        Color(0xFF84CC16),
        Color(0xFF22D3EE),
        Color(0xFFF59E0B),
        Color(0xFF60A5FA),
      ],
      isDark: true,
      borderColor: Color(0xFF155E45),
      mutedTextColor: Color(0xFFBBF7D0),
      gradientColors: [Color(0xFF052E24), Color(0xFF065F46)],
    ),
    EnterpriseThemeMode.oceanBlue: AppThemeModel(
      id: 'ocean_blue',
      themeName: 'Ocean Blue',
      description: 'Fresh modern blue, cyan, and navy business theme.',
      primaryColor: Color(0xFF0284C7),
      secondaryColor: Color(0xFF22D3EE),
      backgroundColor: Color(0xFFEAF8FF),
      cardColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF0F172A),
      successColor: Color(0xFF059669),
      dangerColor: Color(0xFFE11D48),
      warningColor: Color(0xFFF59E0B),
      chartColors: [
        Color(0xFF0284C7),
        Color(0xFF06B6D4),
        Color(0xFF10B981),
        Color(0xFFF97316),
        Color(0xFF6366F1),
      ],
      isDark: false,
      borderColor: Color(0xFFBAE6FD),
      mutedTextColor: Color(0xFF475569),
      gradientColors: [Color(0xFFEAF8FF), Color(0xFFCFFAFE)],
    ),
    EnterpriseThemeMode.sunsetOrange: AppThemeModel(
      id: 'sunset_orange',
      themeName: 'Sunset Orange',
      description: 'Warm energetic business UI with amber and brown.',
      primaryColor: Color(0xFFEA580C),
      secondaryColor: Color(0xFFF59E0B),
      backgroundColor: Color(0xFFFFF7ED),
      cardColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF1F2937),
      successColor: Color(0xFF059669),
      dangerColor: Color(0xFFDC2626),
      warningColor: Color(0xFFD97706),
      chartColors: [
        Color(0xFFEA580C),
        Color(0xFFF59E0B),
        Color(0xFF10B981),
        Color(0xFF2563EB),
        Color(0xFF92400E),
      ],
      isDark: false,
      borderColor: Color(0xFFFED7AA),
      mutedTextColor: Color(0xFF7C2D12),
      gradientColors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
    ),
    EnterpriseThemeMode.darkGold: AppThemeModel(
      id: 'dark_gold',
      themeName: 'Dark Gold',
      description: 'Luxury financial theme with black and gold.',
      primaryColor: Color(0xFFEAB308),
      secondaryColor: Color(0xFFF97316),
      backgroundColor: Color(0xFF0F0B06),
      cardColor: Color(0xFF1A140B),
      textColor: Color(0xFFFFF7D6),
      successColor: Color(0xFF22C55E),
      dangerColor: Color(0xFFEF4444),
      warningColor: Color(0xFFFBBF24),
      chartColors: [
        Color(0xFFEAB308),
        Color(0xFFF97316),
        Color(0xFF22C55E),
        Color(0xFF38BDF8),
        Color(0xFFA16207),
      ],
      isDark: true,
      borderColor: Color(0xFF4A3715),
      mutedTextColor: Color(0xFFE7C879),
      gradientColors: [Color(0xFF0F0B06), Color(0xFF3B2A0C)],
    ),
    EnterpriseThemeMode.rosePink: AppThemeModel(
      id: 'rose_pink',
      themeName: 'Rose Pink',
      description: 'Soft modern premium rose, pink, and white look.',
      primaryColor: Color(0xFFE11D48),
      secondaryColor: Color(0xFFFB7185),
      backgroundColor: Color(0xFFFFF1F5),
      cardColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF1F2937),
      successColor: Color(0xFF059669),
      dangerColor: Color(0xFFBE123C),
      warningColor: Color(0xFFF59E0B),
      chartColors: [
        Color(0xFFE11D48),
        Color(0xFFFB7185),
        Color(0xFF8B5CF6),
        Color(0xFF10B981),
        Color(0xFFF59E0B),
      ],
      isDark: false,
      borderColor: Color(0xFFFBCFE8),
      mutedTextColor: Color(0xFF9F1239),
      gradientColors: [Color(0xFFFFF1F5), Color(0xFFFCE7F3)],
    ),
    EnterpriseThemeMode.slateDark: AppThemeModel(
      id: 'slate_dark',
      themeName: 'Slate Dark',
      description: 'Minimal dark professional charcoal and blue-grey.',
      primaryColor: Color(0xFF64748B),
      secondaryColor: Color(0xFF38BDF8),
      backgroundColor: Color(0xFF0F172A),
      cardColor: Color(0xFF182235),
      textColor: Color(0xFFF8FAFC),
      successColor: Color(0xFF22C55E),
      dangerColor: Color(0xFFF87171),
      warningColor: Color(0xFFFBBF24),
      chartColors: [
        Color(0xFF94A3B8),
        Color(0xFF38BDF8),
        Color(0xFF22C55E),
        Color(0xFFFBBF24),
        Color(0xFFA78BFA),
      ],
      isDark: true,
      borderColor: Color(0xFF334155),
      mutedTextColor: Color(0xFFCBD5E1),
      gradientColors: [Color(0xFF0F172A), Color(0xFF1E293B)],
    ),
    EnterpriseThemeMode.tealBlue: AppThemeModel(
      id: 'teal_blue',
      themeName: 'Teal Blue',
      description: 'Modern business analytics with teal and cyan.',
      primaryColor: Color(0xFF0D9488),
      secondaryColor: Color(0xFF06B6D4),
      backgroundColor: Color(0xFFEFFDFB),
      cardColor: Color(0xFFFFFFFF),
      textColor: Color(0xFF102A43),
      successColor: Color(0xFF16A34A),
      dangerColor: Color(0xFFDC2626),
      warningColor: Color(0xFFD97706),
      chartColors: [
        Color(0xFF0D9488),
        Color(0xFF06B6D4),
        Color(0xFF2563EB),
        Color(0xFFF97316),
        Color(0xFF22C55E),
      ],
      isDark: false,
      borderColor: Color(0xFF99F6E4),
      mutedTextColor: Color(0xFF0F766E),
      gradientColors: [Color(0xFFEFFDFB), Color(0xFFCCFBF1)],
    ),
  };

  static List<AppThemeModel> get catalogThemes => _catalog.values.toList();

  static AppThemeModel modelForMode(EnterpriseThemeMode mode) =>
      _catalog[mode] ?? _catalog[EnterpriseThemeMode.midnightBlue]!;

  static AppThemeModel modelForId(String id) {
    return catalogThemes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => modelForMode(EnterpriseThemeMode.midnightBlue),
    );
  }

  static EnterpriseThemeMode? modeForId(String id) {
    for (final entry in _catalog.entries) {
      if (entry.value.id == id) {
        return entry.key;
      }
    }
    return null;
  }

  static AppThemeModel tokensOf(BuildContext context) {
    return Theme.of(context).extension<AppThemeTokens>()?.theme ??
        modelForMode(EnterpriseThemeMode.midnightBlue);
  }

  static ThemeData forMode(EnterpriseThemeMode mode) {
    return fromModel(modelForMode(mode));
  }

  static ThemeData fromModel(AppThemeModel model) {
    final scheme = ColorScheme.fromSeed(
      seedColor: model.primaryColor,
      brightness: model.isDark ? Brightness.dark : Brightness.light,
      primary: model.primaryColor,
      secondary: model.secondaryColor,
      error: model.dangerColor,
      surface: model.cardColor,
    );
    final radius = BorderRadius.circular(8);

    return ThemeData(
      useMaterial3: true,
      brightness: model.isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: model.backgroundColor,
      fontFamily: 'Roboto',
      extensions: [AppThemeTokens(model)],
      textTheme:
          ThemeData(
            brightness: model.isDark ? Brightness.dark : Brightness.light,
          ).textTheme.apply(
            bodyColor: model.textColor,
            displayColor: model.textColor,
          ),
      iconTheme: IconThemeData(color: model.primaryColor),
      dividerTheme: DividerThemeData(
        color: model.resolvedBorderColor,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: model.backgroundColor,
        foregroundColor: model.textColor,
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: model.textColor,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: model.cardColor,
        elevation: model.isDark ? 0 : 3,
        shadowColor: model.isDark
            ? Colors.black.withValues(alpha: 0.45)
            : const Color(0x260F172A),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: model.resolvedBorderColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: model.primaryColor,
          foregroundColor: _onColor(model.primaryColor),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: model.primaryColor,
          side: BorderSide(color: model.resolvedBorderColor),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: model.primaryColor,
        foregroundColor: _onColor(model.primaryColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: model.isDark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.04),
                model.cardColor,
              )
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: model.resolvedBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: model.resolvedBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: model.primaryColor, width: 1.4),
        ),
        labelStyle: TextStyle(color: model.resolvedMutedTextColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: model.cardColor,
        indicatorColor: model.primaryColor.withValues(alpha: 0.16),
        elevation: model.isDark ? 0 : 6,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? model.primaryColor
                : model.resolvedMutedTextColor,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? model.primaryColor
                : model.resolvedMutedTextColor,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: model.isDark
            ? const Color(0xFF111827)
            : model.textColor,
        contentTextStyle: TextStyle(
          color: model.isDark ? Colors.white : _onColor(model.textColor),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData light() => forMode(EnterpriseThemeMode.lightMode);

  static ThemeData dark() => forMode(EnterpriseThemeMode.midnightBlue);

  static ThemeData financeDark() => dark();

  static ThemeData executiveBlue() => forMode(EnterpriseThemeMode.lightMode);
}

Color _onColor(Color color) {
  return color.computeLuminance() > 0.45
      ? const Color(0xFF0F172A)
      : Colors.white;
}

String _readString(
  Map<String, dynamic> json,
  String key, {
  required String fallback,
}) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

Color? _parseColor(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  var value = raw.trim();
  if (value.startsWith('#')) {
    value = value.substring(1);
  }
  if (value.startsWith('0x')) {
    value = value.substring(2);
  }
  if (value.length == 6) {
    value = 'FF$value';
  }
  if (value.length != 8) {
    return null;
  }
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String _colorToHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${value.substring(2).toUpperCase()}';
}

String _themeId(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'imported_theme' : slug;
}
