import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _consentAccepted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Mobile optional'),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consentAccepted,
                onChanged: (value) =>
                    setState(() => _consentAccepted = value ?? false),
                title: const Text('Privacy consent'),
                subtitle: const Text(
                  'I agree that Scrap System may collect my name, email, mobile number, device info, app version, login time, last active time, and in-app activity for security, support, and business monitoring.',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  if (!_consentAccepted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Accept privacy consent to register.'),
                      ),
                    );
                    return;
                  }
                  await context.read<AuthProvider>().register(
                    name: _name.text.isEmpty ? 'New User' : _name.text,
                    email: _email.text.isEmpty
                        ? 'new@mypillarscrap.local'
                        : _email.text,
                    phone: _phone.text,
                    role: AppRole.supervisor,
                  );
                  if (context.mounted) {
                    context.go('/dashboard');
                  }
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Register New User'),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
