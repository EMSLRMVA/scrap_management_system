enum AppRole { owner, supervisor, operator, accountant, yardManager }

extension AppRoleX on AppRole {
  String get label {
    switch (this) {
      case AppRole.owner:
        return 'Owner';
      case AppRole.supervisor:
        return 'Supervisor';
      case AppRole.operator:
        return 'Operator';
      case AppRole.accountant:
        return 'Accountant';
      case AppRole.yardManager:
        return 'Yard Manager';
    }
  }

  String get key => name;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.active,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final AppRole role;
  final bool active;

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    AppRole? role,
    bool? active,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      active: active ?? this.active,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.key,
      'active': active,
    };
  }
}
