import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../../domain/dynamic_config_models.dart';

class DynamicConfigService {
  DynamicConfigService({
    FirebaseFirestore? firestore,
    FirebaseRemoteConfig? remoteConfig,
  }) : _providedFirestore = firestore,
       _providedRemoteConfig = remoteConfig;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseRemoteConfig? _providedRemoteConfig;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  FirebaseRemoteConfig get _remoteConfig =>
      _providedRemoteConfig ?? FirebaseRemoteConfig.instance;

  DocumentReference<Map<String, dynamic>> get _appConfigDoc =>
      _firestore.collection('app_config').doc('main');

  CollectionReference<Map<String, dynamic>> get _menuConfig =>
      _firestore.collection('menu_config');

  CollectionReference<Map<String, dynamic>> get _pageConfig =>
      _firestore.collection('page_config');

  CollectionReference<Map<String, dynamic>> get _dashboardConfig =>
      _firestore.collection('dashboard_config');

  CollectionReference<Map<String, dynamic>> get _userRoles =>
      _firestore.collection('user_roles');

  Future<RemoteFeatureConfig> fetchRemoteConfig() async {
    if (!isAvailable) {
      return RemoteFeatureConfig.defaults();
    }

    await _remoteConfig.setDefaults({
      'maintenance_mode': false,
      'force_update': false,
      'latest_version_code': 1,
      'latest_version_name': '1.0.0',
      'apk_update_url': '',
      'theme_primary': '#0B57D0',
      'enabled_modules_json':
          '{"dashboard":true,"purchase":true,"sales":true,"inventory":true,"more":true}',
      'feature_flags_json':
          '{"dynamic_pages":true,"voice_purchase":true,"reports":true}',
    });
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 12),
        minimumFetchInterval: const Duration(minutes: 5),
      ),
    );
    await _remoteConfig.fetchAndActivate();

    return RemoteFeatureConfig(
      maintenanceMode: _remoteConfig.getBool('maintenance_mode'),
      forceUpdate: _remoteConfig.getBool('force_update'),
      latestVersionCode: _remoteConfig.getInt('latest_version_code'),
      latestVersionName: _remoteConfig.getString('latest_version_name'),
      updateUrl: _remoteConfig.getString('apk_update_url'),
      primaryColorHex: _remoteConfig.getString('theme_primary'),
      enabledModules: _boolMapFromJson(
        _remoteConfig.getString('enabled_modules_json'),
        RemoteFeatureConfig.defaults().enabledModules,
      ),
      featureFlags: _boolMapFromJson(
        _remoteConfig.getString('feature_flags_json'),
        RemoteFeatureConfig.defaults().featureFlags,
      ),
    );
  }

  Stream<DynamicAppConfig> watchAppConfig() {
    return _appConfigDoc.snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return DynamicAppConfig.defaults();
      }
      return DynamicAppConfig.fromMap(data);
    });
  }

  Stream<List<DynamicMenuItemConfig>> watchMenuConfig() {
    return _menuConfig.orderBy('sortOrder').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return defaultMenuConfig;
      }
      return snapshot.docs
          .map((doc) => DynamicMenuItemConfig.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  Stream<Map<String, DynamicPageDefinition>> watchPageConfig() {
    return _pageConfig.orderBy('sortOrder').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return defaultPageConfig;
      }
      return {
        for (final doc in snapshot.docs)
          doc.id: DynamicPageDefinition.fromMap(doc.id, doc.data()),
      };
    });
  }

  Stream<List<DynamicDashboardCardConfig>> watchDashboardConfig() {
    return _dashboardConfig.orderBy('sortOrder').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return defaultDashboardConfig;
      }
      return snapshot.docs
          .map((doc) => DynamicDashboardCardConfig.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  Stream<Map<String, DynamicRoleConfig>> watchUserRoles() {
    return _userRoles.snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return defaultRoleConfig;
      }
      return {
        for (final doc in snapshot.docs)
          doc.id: DynamicRoleConfig.fromMap(doc.id, doc.data()),
      };
    });
  }

  Future<void> seedDefaultConfigIfMissing() async {
    if (!isAvailable) {
      return;
    }

    await _setIfMissing(_appConfigDoc, DynamicAppConfig.defaults().toMap());

    for (final item in defaultMenuConfig) {
      await _setIfMissing(_menuConfig.doc(item.id), item.toMap());
    }

    for (final entry in defaultPageConfig.entries) {
      await _setIfMissing(_pageConfig.doc(entry.key), entry.value.toMap());
    }

    for (final item in defaultDashboardConfig) {
      await _setIfMissing(_dashboardConfig.doc(item.id), item.toMap());
    }

    for (final entry in defaultRoleConfig.entries) {
      await _setIfMissing(_userRoles.doc(entry.key), entry.value.toMap());
    }
  }

  Future<void> _setIfMissing(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
  ) async {
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await doc.set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Map<String, bool> _boolMapFromJson(String raw, Map<String, bool> fallback) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value == true),
        );
      }
    } catch (_) {
      return fallback;
    }
    return fallback;
  }
}
