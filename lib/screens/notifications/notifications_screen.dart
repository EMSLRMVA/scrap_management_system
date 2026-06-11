import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/notification_item.dart';
import '../../providers/scrap_data_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<ScrapDataProvider>().notifications;
    return ModuleScaffold(
      title: 'Notifications',
      subtitle: 'Payment reminders, low-stock alerts, and dispatch reminders',
      icon: Icons.notifications_active,
      children: [
        EnterpriseCard(
          title: 'Reminder Center',
          child: Column(
            children: [
              for (final item in notifications)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _colorFor(
                      item.type,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      _iconFor(item.type),
                      color: _colorFor(item.type),
                    ),
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.message}\n${Formatters.dateTime(item.createdAt)}',
                  ),
                  isThreeLine: true,
                  trailing: StatusPill(
                    label: item.read ? 'Read' : 'New',
                    color: item.read ? AppTheme.green : AppTheme.orange,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.payment:
        return Icons.payments;
      case NotificationType.stock:
        return Icons.inventory_2;
      case NotificationType.dispatch:
        return Icons.local_shipping;
    }
  }

  static Color _colorFor(NotificationType type) {
    switch (type) {
      case NotificationType.payment:
        return AppTheme.red;
      case NotificationType.stock:
        return AppTheme.orange;
      case NotificationType.dispatch:
        return AppTheme.blue;
    }
  }
}
