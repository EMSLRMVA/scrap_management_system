import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/enterprise_theme.dart';
import 'business_controller.dart';
import 'theme_controller.dart';

class ThemeSettingsScreen extends ConsumerStatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  ConsumerState<ThemeSettingsScreen> createState() =>
      _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends ConsumerState<ThemeSettingsScreen> {
  final _url = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref
        .watch(appThemeProvider)
        .maybeWhen(
          data: (theme) => theme,
          orElse: () =>
              EnterpriseTheme.modelForMode(EnterpriseThemeMode.midnightBlue),
        );
    final tokens = EnterpriseTheme.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Theme Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ThemeHero(theme: selected),
          const SizedBox(height: 14),
          Text(
            'Premium Themes',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final theme in EnterpriseTheme.catalogThemes) ...[
            _ThemeChoiceCard(
              theme: theme,
              selected: selected.id == theme.id,
              onApply: () => _applyTheme(theme),
            ),
            const SizedBox(height: 10),
          ],
          _ImportExportPanel(
            url: _url,
            importing: _importing,
            borderColor: tokens.resolvedBorderColor,
            onPreview: _previewImport,
            onExport: () => _exportTheme(selected),
          ),
        ],
      ),
    );
  }

  Future<void> _applyTheme(AppThemeModel theme) async {
    await ref.read(appThemeProvider.notifier).applyTheme(theme);
    ref.read(businessProvider.notifier).recordThemeChanged(theme.themeName);
    if (mounted) {
      _snack('${theme.themeName} applied');
    }
  }

  Future<void> _previewImport() async {
    if (_url.text.trim().isEmpty) {
      _snack('Paste a theme JSON URL.');
      return;
    }
    setState(() => _importing = true);
    try {
      final theme = await ref
          .read(appThemeProvider.notifier)
          .fetchThemeFromUrl(_url.text);
      if (!mounted) {
        return;
      }
      final apply = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview Imported Theme',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _ThemePreview(theme: theme, compact: false),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: const Text('Apply Imported Theme'),
                ),
              ],
            ),
          ),
        ),
      );
      if (apply == true) {
        await ref.read(appThemeProvider.notifier).applyTheme(theme);
        ref.read(businessProvider.notifier).recordThemeChanged(theme.themeName);
        _snack('${theme.themeName} imported and applied');
      }
    } catch (error) {
      if (mounted) {
        _snack(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _exportTheme(AppThemeModel theme) async {
    final json = ref.read(appThemeProvider.notifier).exportThemeJson(theme);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Theme JSON',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: EnterpriseTheme.tokensOf(
                        context,
                      ).resolvedBorderColor,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      json,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Theme JSON copied to clipboard.'),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ThemeHero extends StatelessWidget {
  const _ThemeHero({required this.theme});

  final AppThemeModel theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.resolvedGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resolvedBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(
                alpha: theme.isDark ? 0.35 : 0.8,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.palette, color: theme.secondaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  theme.themeName,
                  style: TextStyle(
                    color: theme.isDark ? Colors.white : theme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Applied app theme',
                  style: TextStyle(
                    color: (theme.isDark ? Colors.white : theme.textColor)
                        .withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChoiceCard extends StatelessWidget {
  const _ThemeChoiceCard({
    required this.theme,
    required this.selected,
    required this.onApply,
  });

  final AppThemeModel theme;
  final bool selected;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    return InkWell(
      onTap: onApply,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? tokens.primaryColor : tokens.resolvedBorderColor,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: tokens.isDark ? 0.22 : 0.06,
              ),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        theme.themeName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        theme.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.resolvedMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? tokens.primaryColor
                      : tokens.resolvedMutedTextColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PaletteDots(
                  colors: [
                    theme.primaryColor,
                    theme.secondaryColor,
                    theme.backgroundColor,
                    theme.cardColor,
                    theme.successColor,
                    theme.warningColor,
                    theme.dangerColor,
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onApply,
                  icon: Icon(selected ? Icons.check : Icons.bolt, size: 18),
                  label: Text(selected ? 'Applied' : 'Apply'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ThemePreview(theme: theme),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme, this.compact = true});

  final AppThemeModel theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 76 : 120,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.resolvedGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 52,
            height: compact ? 38 : 52,
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.insights,
              color: theme.primaryColor.computeLuminance() > 0.45
                  ? const Color(0xFF0F172A)
                  : Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 8,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.textColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 8,
                  width: 110,
                  decoration: BoxDecoration(
                    color: theme.secondaryColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final color in theme.chartColors.take(4)) ...[
                      Expanded(
                        child: Container(
                          height: compact ? 18 : 30,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteDots extends StatelessWidget {
  const _PaletteDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: 118,
      child: Stack(
        children: [
          for (var index = 0; index < colors.length; index++)
            Positioned(
              left: index * 16,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors[index],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportExportPanel extends StatelessWidget {
  const _ImportExportPanel({
    required this.url,
    required this.importing,
    required this.borderColor,
    required this.onPreview,
    required this.onExport,
  });

  final TextEditingController url;
  final bool importing;
  final Color borderColor;
  final VoidCallback onPreview;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Internet Theme Import',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Theme JSON URL',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: importing ? null : onPreview,
            icon: importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download),
            label: Text(importing ? 'Checking Theme...' : 'Preview & Apply'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share),
            label: const Text('Export Current Theme as JSON'),
          ),
        ],
      ),
    );
  }
}
