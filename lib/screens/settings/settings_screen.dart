import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _companyName;
  late TextEditingController _companyPhone;
  late TextEditingController _companyAddress;
  String _language = AppSettings.defaults().language;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _companyName = TextEditingController(text: settings.companyName);
    _companyPhone = TextEditingController(text: settings.companyPhone);
    _companyAddress = TextEditingController(text: settings.companyAddress);
    _language = settings.language;
  }

  @override
  void dispose() {
    _companyName.dispose();
    _companyPhone.dispose();
    _companyAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;
    return ModuleScaffold(
      title: 'Settings & Security',
      subtitle:
          'Company details, theme, language, backup, and security settings',
      icon: Icons.settings,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final company = EnterpriseCard(
              title: 'Company Details',
              child: Column(
                children: [
                  TextField(
                    controller: _companyName,
                    decoration: const InputDecoration(
                      labelText: 'Company name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _companyPhone,
                    decoration: const InputDecoration(
                      labelText: 'Company phone',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _companyAddress,
                    decoration: const InputDecoration(
                      labelText: 'Company address',
                    ),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _save(settings),
                      icon: const Icon(Icons.save),
                      label: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            );
            final preferences = EnterpriseCard(
              title: 'Preferences',
              child: Column(
                children: [
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: settings.themeMode,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        provider.setThemeMode(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: [
                      for (final language in AppConstants.languageOptions)
                        DropdownMenuItem(
                          value: language,
                          child: Text(language),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _language = value);
                        _save(settings.copyWith(language: value));
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.autoBackup,
                    title: const Text('Auto backup'),
                    secondary: const Icon(Icons.backup),
                    onChanged: provider.setAutoBackup,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.fingerprintLock,
                    title: const Text('Fingerprint lock'),
                    secondary: const Icon(Icons.fingerprint),
                    onChanged: provider.setFingerprintLock,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [company, const SizedBox(height: 12), preferences],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: company),
                const SizedBox(width: 12),
                Expanded(child: preferences),
              ],
            );
          },
        ),
      ],
    );
  }

  void _save(AppSettings base) {
    context.read<SettingsProvider>().update(
      base.copyWith(
        companyName: _companyName.text,
        companyPhone: _companyPhone.text,
        companyAddress: _companyAddress.text,
        language: _language,
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }
}
