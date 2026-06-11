import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentRole = auth.currentUser?.role ?? AppRole.owner;
    return ModuleScaffold(
      title: 'Admin',
      subtitle: 'Role-based access control and user administration',
      icon: Icons.manage_accounts,
      children: [
        EnterpriseCard(
          title: 'Role Switcher',
          child: Column(
            children: [
              for (final role in AppRole.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    currentRole == role
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(role.label),
                  trailing: currentRole == role
                      ? StatusPill(
                          label: 'Active',
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => auth.switchRole(role),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
