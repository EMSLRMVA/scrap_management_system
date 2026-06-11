import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    return ModuleScaffold(
      title: 'Profile',
      subtitle: 'User profile, role, password, and logout controls',
      icon: Icons.person,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final profile = EnterpriseCard(
              title: 'User Details',
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    child: Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name.characters.first
                          : 'U',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.name ?? 'User',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(user?.email ?? ''),
                  const SizedBox(height: 8),
                  StatusPill(
                    label: user?.role.label ?? AppRole.operator.label,
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.verified_user,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: auth.logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            );
            final password = EnterpriseCard(
              title: 'Change Password',
              child: Column(
                children: [
                  TextField(
                    controller: _currentPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await context.read<AuthProvider>().changePassword(
                          _currentPassword.text,
                          _newPassword.text,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password change flow is ready'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.password),
                      label: const Text('Change Password'),
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [profile, const SizedBox(height: 12), password],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 380, child: profile),
                const SizedBox(width: 12),
                Expanded(child: password),
              ],
            );
          },
        ),
      ],
    );
  }
}
