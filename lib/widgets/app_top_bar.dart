import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/app_theme.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import 'status_pill.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.onMenuPressed,
    required this.title,
    this.subtitle,
    this.onNotificationsPressed,
  });

  final VoidCallback onMenuPressed;
  final String title;
  final String? subtitle;
  final VoidCallback? onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;

    return Container(
      height: compact ? 54 : 66,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Navigation',
            onPressed: onMenuPressed,
            icon: const Icon(Icons.menu, color: Colors.white),
          ),
          if (!compact) const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? title : AppConfig.brandName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 14 : 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!compact)
                  Text(
                    subtitle ?? AppConfig.appTagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (!compact) ...[
            const StatusPill(
              label: 'Easy',
              color: AppTheme.green,
              icon: Icons.check_circle,
            ),
            const SizedBox(width: 8),
            const StatusPill(
              label: 'Fast',
              color: AppTheme.green,
              icon: Icons.speed,
            ),
            const SizedBox(width: 8),
            const StatusPill(
              label: 'Voice',
              color: AppTheme.green,
              icon: Icons.mic,
            ),
          ],
          if (compact)
            IconButton(
              tooltip: 'Alerts',
              onPressed: onNotificationsPressed,
              icon: const Icon(Icons.notifications_none, color: Colors.white),
            ),
          if (!compact) const SizedBox(width: 12),
          PopupMenuButton<AppRole>(
            tooltip: 'Role switcher',
            onSelected: auth.switchRole,
            itemBuilder: (context) => [
              for (final role in AppRole.values)
                PopupMenuItem(value: role, child: Text(role.label)),
            ],
            child: Row(
              children: [
                if (!compact)
                  const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 18),
                  ),
                if (!compact && user != null) ...[
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        user.role.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
                Icon(
                  compact ? Icons.account_circle : Icons.expand_more,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
