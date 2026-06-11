import 'package:flutter/material.dart';

class DashboardTileDefinition {
  const DashboardTileDefinition({
    required this.title,
    required this.icon,
    required this.route,
  });

  final String title;
  final IconData icon;
  final String route;
}

const dashboardTileDefinitions = [
  DashboardTileDefinition(
    title: 'Quick Purchase',
    icon: Icons.add_shopping_cart,
    route: '/purchase',
  ),
  DashboardTileDefinition(
    title: 'Sales Entry',
    icon: Icons.point_of_sale,
    route: '/sales',
  ),
  DashboardTileDefinition(
    title: 'Dispatch',
    icon: Icons.local_shipping,
    route: '/dispatch',
  ),
  DashboardTileDefinition(
    title: 'Reports',
    icon: Icons.summarize,
    route: '/reports',
  ),
];
