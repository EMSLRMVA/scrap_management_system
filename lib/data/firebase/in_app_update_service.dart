import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/dynamic_config_models.dart';

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.currentVersionCode,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.updateUrl,
    required this.forceUpdate,
    required this.updateRequired,
  });

  final int currentVersionCode;
  final int latestVersionCode;
  final String latestVersionName;
  final String updateUrl;
  final bool forceUpdate;
  final bool updateRequired;
}

class InAppUpdateService {
  Future<AppUpdateDecision> check(DynamicConfigState config) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    final latestVersionCode = _max(
      config.app.latestVersionCode,
      config.remote.latestVersionCode,
    );
    final latestVersionName = config.remote.latestVersionName.isNotEmpty
        ? config.remote.latestVersionName
        : config.app.latestVersionName;
    final updateUrl = config.remote.updateUrl.isNotEmpty
        ? config.remote.updateUrl
        : config.app.updateUrl;
    final forceUpdate = config.remote.forceUpdate || config.app.forceUpdate;

    return AppUpdateDecision(
      currentVersionCode: currentVersionCode,
      latestVersionCode: latestVersionCode,
      latestVersionName: latestVersionName,
      updateUrl: updateUrl,
      forceUpdate: forceUpdate,
      updateRequired: latestVersionCode > currentVersionCode,
    );
  }

  Future<bool> startUpdate(AppUpdateDecision decision) async {
    if (Platform.isAndroid) {
      try {
        final updateInfo = await InAppUpdate.checkForUpdate();
        if (updateInfo.updateAvailability ==
                UpdateAvailability.updateAvailable &&
            updateInfo.immediateUpdateAllowed) {
          final result = await InAppUpdate.performImmediateUpdate();
          return result == AppUpdateResult.success;
        }
        if (updateInfo.updateAvailability ==
                UpdateAvailability.updateAvailable &&
            updateInfo.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            return true;
          }
        }
      } catch (_) {
        // Google Play in-app updates are unavailable for sideloaded APKs.
      }
    }

    if (decision.updateUrl.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(decision.updateUrl);
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  int _max(int left, int right) => left > right ? left : right;
}
