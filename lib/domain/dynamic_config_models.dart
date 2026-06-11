import '../core/app_branding.dart';

class RemoteFeatureConfig {
  const RemoteFeatureConfig({
    required this.maintenanceMode,
    required this.forceUpdate,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.updateUrl,
    required this.primaryColorHex,
    required this.enabledModules,
    required this.featureFlags,
  });

  factory RemoteFeatureConfig.defaults() {
    return const RemoteFeatureConfig(
      maintenanceMode: false,
      forceUpdate: false,
      latestVersionCode: 1,
      latestVersionName: '1.0.0',
      updateUrl: '',
      primaryColorHex: '#0B57D0',
      enabledModules: {
        'dashboard': true,
        'purchase': true,
        'sales': true,
        'inventory': true,
        'stock_register': true,
        'more': true,
      },
      featureFlags: {
        'dynamic_pages': true,
        'voice_purchase': true,
        'reports': true,
      },
    );
  }

  final bool maintenanceMode;
  final bool forceUpdate;
  final int latestVersionCode;
  final String latestVersionName;
  final String updateUrl;
  final String primaryColorHex;
  final Map<String, bool> enabledModules;
  final Map<String, bool> featureFlags;

  bool moduleEnabled(String key) => enabledModules[key] ?? true;
  bool flagEnabled(String key) => featureFlags[key] ?? false;
}

class DynamicAppConfig {
  const DynamicAppConfig({
    required this.companyName,
    required this.appTitle,
    required this.maintenanceMessage,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.updateUrl,
    required this.forceUpdate,
  });

  factory DynamicAppConfig.defaults() {
    return const DynamicAppConfig(
      companyName: appDisplayName,
      appTitle: appDisplayName,
      maintenanceMessage: 'The app is temporarily under maintenance.',
      latestVersionCode: 1,
      latestVersionName: '1.0.0',
      updateUrl: '',
      forceUpdate: false,
    );
  }

  final String companyName;
  final String appTitle;
  final String maintenanceMessage;
  final int latestVersionCode;
  final String latestVersionName;
  final String updateUrl;
  final bool forceUpdate;

  static DynamicAppConfig fromMap(Map<String, dynamic> data) {
    return DynamicAppConfig(
      companyName: _string(data['companyName'], appDisplayName),
      appTitle: _string(data['appTitle'], appDisplayName),
      maintenanceMessage: _string(
        data['maintenanceMessage'],
        'The app is temporarily under maintenance.',
      ),
      latestVersionCode: _int(data['latestVersionCode'], 1),
      latestVersionName: _string(data['latestVersionName'], '1.0.0'),
      updateUrl: _string(data['updateUrl'], ''),
      forceUpdate: _bool(data['forceUpdate'], false),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'appTitle': appTitle,
      'maintenanceMessage': maintenanceMessage,
      'latestVersionCode': latestVersionCode,
      'latestVersionName': latestVersionName,
      'updateUrl': updateUrl,
      'forceUpdate': forceUpdate,
    };
  }
}

class DynamicMenuItemConfig {
  const DynamicMenuItemConfig({
    required this.id,
    required this.routeKey,
    required this.label,
    required this.icon,
    required this.sortOrder,
    required this.visible,
    required this.pageId,
    required this.location,
  });

  final String id;
  final String routeKey;
  final String label;
  final String icon;
  final int sortOrder;
  final bool visible;
  final String pageId;
  final String location;

  static DynamicMenuItemConfig fromMap(String id, Map<String, dynamic> data) {
    return DynamicMenuItemConfig(
      id: id,
      routeKey: _string(data['routeKey'], id),
      label: _string(data['label'], id),
      icon: _string(data['icon'], 'apps'),
      sortOrder: _int(data['sortOrder'], 999),
      visible: _bool(data['visible'], true),
      pageId: _string(data['pageId'], id),
      location: _string(data['location'], 'bottom'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'routeKey': routeKey,
      'label': label,
      'icon': icon,
      'sortOrder': sortOrder,
      'visible': visible,
      'pageId': pageId,
      'location': location,
    };
  }
}

class DynamicFieldConfig {
  const DynamicFieldConfig({
    required this.key,
    required this.label,
    required this.type,
    required this.visible,
    required this.required,
    required this.sortOrder,
    required this.options,
  });

  final String key;
  final String label;
  final String type;
  final bool visible;
  final bool required;
  final int sortOrder;
  final List<String> options;

  static DynamicFieldConfig fromMap(Map<String, dynamic> data) {
    return DynamicFieldConfig(
      key: _string(data['key'], ''),
      label: _string(data['label'], ''),
      type: _string(data['type'], 'text'),
      visible: _bool(data['visible'], true),
      required: _bool(data['required'], false),
      sortOrder: _int(data['sortOrder'], 999),
      options: _stringList(data['options']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'label': label,
      'type': type,
      'visible': visible,
      'required': required,
      'sortOrder': sortOrder,
      'options': options,
    };
  }
}

class DynamicActionConfig {
  const DynamicActionConfig({
    required this.label,
    required this.icon,
    required this.targetRoute,
    required this.visible,
    required this.sortOrder,
  });

  final String label;
  final String icon;
  final String targetRoute;
  final bool visible;
  final int sortOrder;

  static DynamicActionConfig fromMap(Map<String, dynamic> data) {
    return DynamicActionConfig(
      label: _string(data['label'], ''),
      icon: _string(data['icon'], 'apps'),
      targetRoute: _string(data['targetRoute'], ''),
      visible: _bool(data['visible'], true),
      sortOrder: _int(data['sortOrder'], 999),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'icon': icon,
      'targetRoute': targetRoute,
      'visible': visible,
      'sortOrder': sortOrder,
    };
  }
}

class DynamicPageDefinition {
  const DynamicPageDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.collection,
    required this.visible,
    required this.sortOrder,
    required this.fields,
    required this.actions,
  });

  final String id;
  final String title;
  final String subtitle;
  final String type;
  final String collection;
  final bool visible;
  final int sortOrder;
  final List<DynamicFieldConfig> fields;
  final List<DynamicActionConfig> actions;

  static DynamicPageDefinition fromMap(String id, Map<String, dynamic> data) {
    final fields =
        (data['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DynamicFieldConfig.fromMap)
            .where((field) => field.key.isNotEmpty)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final actions =
        (data['actions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DynamicActionConfig.fromMap)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return DynamicPageDefinition(
      id: id,
      title: _string(data['title'], id),
      subtitle: _string(data['subtitle'], ''),
      type: _string(data['type'], 'static'),
      collection: _string(data['collection'], ''),
      visible: _bool(data['visible'], true),
      sortOrder: _int(data['sortOrder'], 999),
      fields: fields,
      actions: actions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'type': type,
      'collection': collection,
      'visible': visible,
      'sortOrder': sortOrder,
      'fields': fields.map((field) => field.toMap()).toList(),
      'actions': actions.map((action) => action.toMap()).toList(),
    };
  }

  List<DynamicFieldConfig> get visibleFields =>
      fields.where((field) => field.visible).toList();
}

class DynamicDashboardCardConfig {
  const DynamicDashboardCardConfig({
    required this.id,
    required this.label,
    required this.metricKey,
    required this.icon,
    required this.colorHex,
    required this.visible,
    required this.sortOrder,
  });

  final String id;
  final String label;
  final String metricKey;
  final String icon;
  final String colorHex;
  final bool visible;
  final int sortOrder;

  static DynamicDashboardCardConfig fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return DynamicDashboardCardConfig(
      id: id,
      label: _string(data['label'], id),
      metricKey: _string(data['metricKey'], id),
      icon: _string(data['icon'], 'dashboard'),
      colorHex: _string(data['colorHex'], '#0B57D0'),
      visible: _bool(data['visible'], true),
      sortOrder: _int(data['sortOrder'], 999),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'metricKey': metricKey,
      'icon': icon,
      'colorHex': colorHex,
      'visible': visible,
      'sortOrder': sortOrder,
    };
  }
}

class DynamicRoleConfig {
  const DynamicRoleConfig({
    required this.id,
    required this.label,
    required this.allowedRoutes,
    required this.permissions,
  });

  final String id;
  final String label;
  final List<String> allowedRoutes;
  final Map<String, bool> permissions;

  static DynamicRoleConfig fromMap(String id, Map<String, dynamic> data) {
    return DynamicRoleConfig(
      id: id,
      label: _string(data['label'], id),
      allowedRoutes: _stringList(data['allowedRoutes']),
      permissions: _boolMap(data['permissions']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'allowedRoutes': allowedRoutes,
      'permissions': permissions,
    };
  }
}

class DynamicConfigState {
  const DynamicConfigState({
    required this.remote,
    required this.app,
    required this.menu,
    required this.pages,
    required this.dashboardCards,
    required this.roles,
    required this.loadedFromFirebase,
  });

  factory DynamicConfigState.defaults() {
    return DynamicConfigState(
      remote: RemoteFeatureConfig.defaults(),
      app: DynamicAppConfig.defaults(),
      menu: defaultMenuConfig,
      pages: defaultPageConfig,
      dashboardCards: defaultDashboardConfig,
      roles: defaultRoleConfig,
      loadedFromFirebase: false,
    );
  }

  final RemoteFeatureConfig remote;
  final DynamicAppConfig app;
  final List<DynamicMenuItemConfig> menu;
  final Map<String, DynamicPageDefinition> pages;
  final List<DynamicDashboardCardConfig> dashboardCards;
  final Map<String, DynamicRoleConfig> roles;
  final bool loadedFromFirebase;

  List<DynamicMenuItemConfig> get visibleBottomMenu {
    return menu
        .where((item) => item.visible)
        .where((item) => item.location == 'bottom')
        .where((item) => remote.moduleEnabled(item.routeKey))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<DynamicMenuItemConfig> get visibleMoreMenu {
    return menu
        .where((item) => item.visible)
        .where((item) => item.location == 'more')
        .where((item) => remote.moduleEnabled(item.routeKey))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  DynamicPageDefinition pageFor(String pageId) {
    return pages[pageId] ??
        defaultPageConfig[pageId] ??
        defaultPageConfig['dashboard']!;
  }

  DynamicConfigState copyWith({
    RemoteFeatureConfig? remote,
    DynamicAppConfig? app,
    List<DynamicMenuItemConfig>? menu,
    Map<String, DynamicPageDefinition>? pages,
    List<DynamicDashboardCardConfig>? dashboardCards,
    Map<String, DynamicRoleConfig>? roles,
    bool? loadedFromFirebase,
  }) {
    return DynamicConfigState(
      remote: remote ?? this.remote,
      app: app ?? this.app,
      menu: menu ?? this.menu,
      pages: pages ?? this.pages,
      dashboardCards: dashboardCards ?? this.dashboardCards,
      roles: roles ?? this.roles,
      loadedFromFirebase: loadedFromFirebase ?? this.loadedFromFirebase,
    );
  }
}

const defaultMenuConfig = [
  DynamicMenuItemConfig(
    id: 'dashboard',
    routeKey: 'dashboard',
    label: 'Dashboard',
    icon: 'dashboard',
    sortOrder: 10,
    visible: true,
    pageId: 'dashboard',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'purchase',
    routeKey: 'purchase',
    label: 'Purchase',
    icon: 'purchase',
    sortOrder: 20,
    visible: true,
    pageId: 'purchase',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'sales',
    routeKey: 'sales',
    label: 'Sales',
    icon: 'sales',
    sortOrder: 30,
    visible: true,
    pageId: 'sales',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'inventory',
    routeKey: 'inventory',
    label: 'Inventory',
    icon: 'inventory',
    sortOrder: 40,
    visible: true,
    pageId: 'inventory',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'stock_register',
    routeKey: 'stock_register',
    label: 'Analysis',
    icon: 'stock_register',
    sortOrder: 45,
    visible: true,
    pageId: 'stock_register',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'more',
    routeKey: 'more',
    label: 'More',
    icon: 'more',
    sortOrder: 50,
    visible: true,
    pageId: 'more',
    location: 'bottom',
  ),
  DynamicMenuItemConfig(
    id: 'reports',
    routeKey: 'reports',
    label: 'Scrap Report',
    icon: 'reports',
    sortOrder: 60,
    visible: true,
    pageId: 'reports',
    location: 'more',
  ),
  DynamicMenuItemConfig(
    id: 'finance',
    routeKey: 'finance',
    label: 'Finance',
    icon: 'finance',
    sortOrder: 70,
    visible: true,
    pageId: 'finance',
    location: 'more',
  ),
];

final defaultPageConfig = <String, DynamicPageDefinition>{
  'dashboard': const DynamicPageDefinition(
    id: 'dashboard',
    title: 'Dashboard',
    subtitle: 'Live business summary',
    type: 'dashboard',
    collection: 'dashboard',
    visible: true,
    sortOrder: 10,
    fields: [],
    actions: [
      DynamicActionConfig(
        label: 'New Purchase',
        icon: 'purchase',
        targetRoute: 'purchase',
        visible: true,
        sortOrder: 10,
      ),
      DynamicActionConfig(
        label: 'Supervisors',
        icon: 'security',
        targetRoute: 'supervisor_admin',
        visible: true,
        sortOrder: 20,
      ),
      DynamicActionConfig(
        label: 'Cash',
        icon: 'finance',
        targetRoute: 'cash_allocation',
        visible: true,
        sortOrder: 30,
      ),
      DynamicActionConfig(
        label: 'Cash With Supervisor',
        icon: 'wallet',
        targetRoute: 'cash_with_supervisor',
        visible: true,
        sortOrder: 35,
      ),
      DynamicActionConfig(
        label: 'Voice',
        icon: 'voice',
        targetRoute: 'voice_entry',
        visible: true,
        sortOrder: 40,
      ),
    ],
  ),
  'purchase': const DynamicPageDefinition(
    id: 'purchase',
    title: 'Purchase',
    subtitle: 'Supplier bills and pending balances',
    type: 'purchase',
    collection: 'purchases',
    visible: true,
    sortOrder: 20,
    fields: [
      DynamicFieldConfig(
        key: 'seller',
        label: 'Seller',
        type: 'party_seller',
        visible: true,
        required: true,
        sortOrder: 10,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'material',
        label: 'Material',
        type: 'material',
        visible: true,
        required: true,
        sortOrder: 20,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'weightKg',
        label: 'Weight (KG)',
        type: 'number',
        visible: true,
        required: true,
        sortOrder: 30,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'rate',
        label: 'Rate / KG',
        type: 'number',
        visible: true,
        required: true,
        sortOrder: 40,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'paidAmount',
        label: 'Paid Amount',
        type: 'number',
        visible: true,
        required: false,
        sortOrder: 50,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'remarks',
        label: 'Remarks',
        type: 'text',
        visible: true,
        required: false,
        sortOrder: 60,
        options: [],
      ),
    ],
    actions: [],
  ),
  'sales': const DynamicPageDefinition(
    id: 'sales',
    title: 'Sales',
    subtitle: 'Customer invoices and receipts',
    type: 'sales',
    collection: 'sales',
    visible: true,
    sortOrder: 30,
    fields: [
      DynamicFieldConfig(
        key: 'customer',
        label: 'Customer',
        type: 'party_customer',
        visible: true,
        required: true,
        sortOrder: 10,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'material',
        label: 'Material',
        type: 'material',
        visible: true,
        required: true,
        sortOrder: 20,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'weightKg',
        label: 'Weight (KG)',
        type: 'number',
        visible: true,
        required: true,
        sortOrder: 30,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'rate',
        label: 'Rate / KG',
        type: 'number',
        visible: true,
        required: true,
        sortOrder: 40,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'receivedAmount',
        label: 'Paid Amount',
        type: 'number',
        visible: true,
        required: false,
        sortOrder: 50,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'remarks',
        label: 'Remarks',
        type: 'text',
        visible: true,
        required: false,
        sortOrder: 60,
        options: [],
      ),
    ],
    actions: [],
  ),
  'inventory': const DynamicPageDefinition(
    id: 'inventory',
    title: 'Inventory',
    subtitle: 'Material stock, rates and value',
    type: 'inventory',
    collection: 'inventory',
    visible: true,
    sortOrder: 40,
    fields: [
      DynamicFieldConfig(
        key: 'name',
        label: 'Material Name',
        type: 'text',
        visible: true,
        required: true,
        sortOrder: 10,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'category',
        label: 'Category',
        type: 'text',
        visible: true,
        required: false,
        sortOrder: 20,
        options: [],
      ),
      DynamicFieldConfig(
        key: 'currentBuyingRate',
        label: 'Current Buying Rate',
        type: 'number',
        visible: true,
        required: false,
        sortOrder: 30,
        options: [],
      ),
    ],
    actions: [],
  ),
  'stock_register': const DynamicPageDefinition(
    id: 'stock_register',
    title: 'Analysis',
    subtitle: 'Item-wise live purchase and sale register',
    type: 'stock_register',
    collection: 'inventory',
    visible: true,
    sortOrder: 45,
    fields: [],
    actions: [],
  ),
  'more': const DynamicPageDefinition(
    id: 'more',
    title: 'More',
    subtitle: 'Ledgers, finance, reports and security',
    type: 'more',
    collection: '',
    visible: true,
    sortOrder: 50,
    fields: [],
    actions: [],
  ),
  'reports': const DynamicPageDefinition(
    id: 'reports',
    title: 'Scrap Report',
    subtitle: 'PDF and Excel ready summaries',
    type: 'report',
    collection: 'dashboard',
    visible: true,
    sortOrder: 60,
    fields: [],
    actions: [],
  ),
  'finance': const DynamicPageDefinition(
    id: 'finance',
    title: 'Finance',
    subtitle: 'Cash in, cash out and expenses',
    type: 'finance',
    collection: 'expenses',
    visible: true,
    sortOrder: 70,
    fields: [],
    actions: [],
  ),
};

const defaultDashboardConfig = [
  DynamicDashboardCardConfig(
    id: 'cash_allocated',
    label: 'Cash With Supervisor',
    metricKey: 'cashWithSupervisor',
    icon: 'wallet',
    colorHex: '#16A34A',
    visible: true,
    sortOrder: 10,
  ),
  DynamicDashboardCardConfig(
    id: 'total_expense',
    label: 'Total Expense',
    metricKey: 'totalExpense',
    icon: 'reports',
    colorHex: '#0B57D0',
    visible: true,
    sortOrder: 20,
  ),
  DynamicDashboardCardConfig(
    id: 'cash_balance',
    label: 'Pending Balance',
    metricKey: 'cashBalance',
    icon: 'finance',
    colorHex: '#F59E0B',
    visible: true,
    sortOrder: 30,
  ),
  DynamicDashboardCardConfig(
    id: 'stock_value',
    label: 'Inventory Value',
    metricKey: 'stockValue',
    icon: 'inventory',
    colorHex: '#38BDF8',
    visible: true,
    sortOrder: 40,
  ),
];

final defaultRoleConfig = <String, DynamicRoleConfig>{
  'owner': const DynamicRoleConfig(
    id: 'owner',
    label: 'Owner',
    allowedRoutes: ['*'],
    permissions: {'all': true},
  ),
  'supervisor': const DynamicRoleConfig(
    id: 'supervisor',
    label: 'Supervisor',
    allowedRoutes: [
      'dashboard',
      'purchase',
      'sales',
      'inventory',
      'stock_register',
      'more',
    ],
    permissions: {'purchase_write': true, 'sales_write': true},
  ),
  'manager': const DynamicRoleConfig(
    id: 'manager',
    label: 'Manager',
    allowedRoutes: [
      'dashboard',
      'purchase',
      'sales',
      'inventory',
      'stock_register',
      'more',
    ],
    permissions: {
      'purchase_write': true,
      'sales_write': true,
      'stock_review': true,
    },
  ),
  'accountant': const DynamicRoleConfig(
    id: 'accountant',
    label: 'Accountant',
    allowedRoutes: [
      'dashboard',
      'sales',
      'stock_register',
      'more',
      'reports',
      'finance',
    ],
    permissions: {'reports': true, 'finance': true},
  ),
};

String _string(Object? value, String fallback) {
  final text = value?.toString();
  return text == null || text.isEmpty ? fallback : text;
}

int _int(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _bool(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}

Map<String, bool> _boolMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _bool(item, false)),
    );
  }
  return const {};
}
