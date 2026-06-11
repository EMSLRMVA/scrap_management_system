import 'package:flutter/material.dart';

import '../models/app_user.dart';

class AppConstants {
  const AppConstants._();

  static const materials = [
    'Iron',
    'Steel',
    'Copper',
    'Brass',
    'Aluminium',
    'Plastic',
    'PET Bottle',
    'Cardboard',
    'Paper',
    'E-Waste',
    'Rubber',
    'Tyres',
    'Coconut Shell',
  ];

  static const expenseCategories = [
    'Fuel',
    'Transport',
    'Salary',
    'Rent',
    'Maintenance',
    'Electricity',
    'Food',
    'Miscellaneous',
  ];

  static const languageOptions = ['English', 'Hindi', 'Tamil', 'Kannada'];

  static const roleAccess = <AppRole, Set<String>>{
    AppRole.owner: {'*'},
    AppRole.supervisor: {
      'dashboard',
      'purchase',
      'sellers',
      'customers',
      'stock',
      'sales',
      'dispatch',
      'voice',
      'notifications',
      'settings',
      'profile',
      'supervisor',
    },
    AppRole.operator: {
      'dashboard',
      'purchase',
      'sales',
      'stock',
      'voice',
      'settings',
      'notifications',
      'profile',
    },
    AppRole.accountant: {
      'dashboard',
      'expenses',
      'invoices',
      'ledgers',
      'reports',
      'profit-loss',
      'analytics',
      'settings',
      'notifications',
      'profile',
    },
    AppRole.yardManager: {
      'dashboard',
      'stock',
      'dispatch',
      'reports',
      'notifications',
      'settings',
      'profile',
    },
  };

  static const materialIcons = <String, IconData>{
    'Iron': Icons.construction,
    'Steel': Icons.precision_manufacturing,
    'Copper': Icons.cable,
    'Brass': Icons.hardware,
    'Aluminium': Icons.inventory_2,
    'Plastic': Icons.recycling,
    'PET Bottle': Icons.local_drink,
    'Cardboard': Icons.inventory,
    'Paper': Icons.description,
    'E-Waste': Icons.memory,
    'Rubber': Icons.circle,
    'Tyres': Icons.trip_origin,
    'Coconut Shell': Icons.eco,
  };
}
