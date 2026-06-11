import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/dynamic_config_service.dart';
import '../domain/dynamic_config_models.dart';

final dynamicConfigProvider =
    NotifierProvider<DynamicConfigController, DynamicConfigState>(
      DynamicConfigController.new,
    );

class DynamicConfigController extends Notifier<DynamicConfigState> {
  final _service = DynamicConfigService();
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  DynamicConfigState build() {
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscriptions.clear();
    });

    if (_service.isAvailable) {
      Future.microtask(_start);
    }

    return DynamicConfigState.defaults();
  }

  Future<void> refreshRemoteConfig() async {
    if (!_service.isAvailable) {
      return;
    }
    try {
      final remote = await _service.fetchRemoteConfig();
      state = state.copyWith(remote: remote);
    } catch (_) {
      state = state.copyWith(remote: RemoteFeatureConfig.defaults());
    }
  }

  Future<void> _start() async {
    try {
      await _service.seedDefaultConfigIfMissing();
    } catch (_) {
      // Firestore may be temporarily offline; defaults keep the app usable.
    }
    await refreshRemoteConfig();

    if (_subscriptions.isNotEmpty) {
      return;
    }

    _subscriptions.addAll([
      _service.watchAppConfig().listen((app) {
        state = state.copyWith(app: app, loadedFromFirebase: true);
      }, onError: (_) {}),
      _service.watchMenuConfig().listen((menu) {
        state = state.copyWith(menu: menu, loadedFromFirebase: true);
      }, onError: (_) {}),
      _service.watchPageConfig().listen((pages) {
        state = state.copyWith(pages: pages, loadedFromFirebase: true);
      }, onError: (_) {}),
      _service.watchDashboardConfig().listen((dashboardCards) {
        state = state.copyWith(
          dashboardCards: dashboardCards,
          loadedFromFirebase: true,
        );
      }, onError: (_) {}),
      _service.watchUserRoles().listen((roles) {
        state = state.copyWith(roles: roles, loadedFromFirebase: true);
      }, onError: (_) {}),
    ]);
  }
}
