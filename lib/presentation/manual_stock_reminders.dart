import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/enterprise_theme.dart';
import '../core/money_format.dart';
import '../domain/business_models.dart';
import '../domain/stock_calculation.dart';
import 'business_controller.dart';
import 'enterprise_feature_screens.dart';

class StockReminderSettingsScreen extends ConsumerStatefulWidget {
  const StockReminderSettingsScreen({super.key});

  @override
  ConsumerState<StockReminderSettingsScreen> createState() =>
      _StockReminderSettingsScreenState();
}

class _StockReminderSettingsScreenState
    extends ConsumerState<StockReminderSettingsScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController(text: '+91');
  StockReminderRole _role = StockReminderRole.supervisor;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _active = true;
  final _types = <StockReminderType>{
    StockReminderType.dailyStockTarget,
    StockReminderType.physicalStockVerification,
  };
  StockReminderReceiver? _editing;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final tokens = EnterpriseTheme.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Reminder Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editing == null ? 'Add Receiver' : 'Edit Receiver',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Receiver Name',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<StockReminderRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: [
                    for (final role in StockReminderRole.values)
                      DropdownMenuItem(
                        value: role,
                        child: Text(stockReminderRoleLabel(role)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _role = value ?? _role),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Number with country code',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text('Reminder Time: ${_formatTime(_time)}'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reminder Type',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in StockReminderType.values)
                      FilterChip(
                        selected: _types.contains(type),
                        label: Text(stockReminderTypeLabel(type)),
                        onSelected: (selected) => _toggleType(type, selected),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: Text(_editing == null ? 'Add' : 'Update'),
                      ),
                    ),
                    if (_editing != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _reset,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Receiver List',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                if (state.stockReminderReceivers.isEmpty)
                  const EmptyFeatureState(
                    icon: Icons.notifications_active,
                    title: 'No receivers added',
                    subtitle:
                        'Add supervisor, manager, owner, or other WhatsApp receiver.',
                  )
                else
                  for (final receiver in state.stockReminderReceivers)
                    _ReceiverTile(
                      receiver: receiver,
                      mutedColor: tokens.resolvedMutedTextColor,
                      onEdit: () => _edit(receiver),
                      onDelete: () => ref
                          .read(businessProvider.notifier)
                          .deleteStockReminderReceiver(receiver.id),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ManualWhatsAppReminderScreen(),
              ),
            ),
            icon: const Icon(Icons.send),
            label: const Text('Open Manual WhatsApp Reminder'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  void _toggleType(StockReminderType type, bool selected) {
    setState(() {
      if (selected) {
        if (type == StockReminderType.all) {
          _types
            ..clear()
            ..add(StockReminderType.all);
        } else {
          _types
            ..remove(StockReminderType.all)
            ..add(type);
        }
      } else {
        _types.remove(type);
      }
      if (_types.isEmpty) {
        _types.add(StockReminderType.all);
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    final number = _number.text.trim();
    if (name.isEmpty || number.isEmpty) {
      _snack(context, 'Enter receiver name and WhatsApp number.');
      return;
    }
    final notifier = ref.read(businessProvider.notifier);
    final editing = _editing;
    if (editing == null) {
      notifier.addStockReminderReceiver(
        receiverName: name,
        role: _role,
        whatsAppNumber: number,
        reminderHour: _time.hour,
        reminderMinute: _time.minute,
        reminderTypes: _types.toList(),
        isActive: _active,
      );
    } else {
      notifier.updateStockReminderReceiver(
        editing.copyWith(
          receiverName: name,
          role: _role,
          whatsAppNumber: number,
          reminderHour: _time.hour,
          reminderMinute: _time.minute,
          reminderTypes: _types.toList(),
          isActive: _active,
        ),
      );
    }
    _reset();
    _snack(context, 'Receiver saved.');
  }

  void _edit(StockReminderReceiver receiver) {
    setState(() {
      _editing = receiver;
      _name.text = receiver.receiverName;
      _number.text = receiver.whatsAppNumber;
      _role = receiver.role;
      _time = TimeOfDay(
        hour: receiver.reminderHour,
        minute: receiver.reminderMinute,
      );
      _active = receiver.isActive;
      _types
        ..clear()
        ..addAll(receiver.reminderTypes);
    });
  }

  void _reset() {
    setState(() {
      _editing = null;
      _name.clear();
      _number.text = '+91';
      _role = StockReminderRole.supervisor;
      _time = const TimeOfDay(hour: 9, minute: 0);
      _active = true;
      _types
        ..clear()
        ..addAll({
          StockReminderType.dailyStockTarget,
          StockReminderType.physicalStockVerification,
        });
    });
  }
}

class _ReceiverTile extends StatelessWidget {
  const _ReceiverTile({
    required this.receiver,
    required this.mutedColor,
    required this.onEdit,
    required this.onDelete,
  });

  final StockReminderReceiver receiver;
  final Color mutedColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(receiver.isActive ? Icons.notifications : Icons.block),
      ),
      title: Text(
        receiver.receiverName,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${stockReminderRoleLabel(receiver.role)} | ${receiver.whatsAppNumber}\n${_formatTime(TimeOfDay(hour: receiver.reminderHour, minute: receiver.reminderMinute))} | ${receiver.reminderTypes.map(stockReminderTypeLabel).join(', ')}',
        style: TextStyle(color: mutedColor, fontSize: 12),
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class ManualWhatsAppReminderScreen extends ConsumerStatefulWidget {
  const ManualWhatsAppReminderScreen({
    super.key,
    this.initialType = StockReminderType.dailyStockTarget,
    this.initialReceiverId,
  });

  final StockReminderType initialType;
  final String? initialReceiverId;

  @override
  ConsumerState<ManualWhatsAppReminderScreen> createState() =>
      _ManualWhatsAppReminderScreenState();
}

class _ManualWhatsAppReminderScreenState
    extends ConsumerState<ManualWhatsAppReminderScreen> {
  StockReminderReceiver? _receiver;
  late StockReminderType _type;
  ManualReminderLog? _log;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final receivers = _eligibleReceivers(state, _type);
    _receiver = _selectedReceiver(receivers);
    final message = _receiver == null
        ? ''
        : manualReminderMessage(state, _receiver!, _type);
    final tokens = EnterpriseTheme.tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manual WhatsApp Reminder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reminder Type',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<StockReminderType>(
                  initialValue: _type,
                  items: [
                    for (final type in StockReminderType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(stockReminderTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _type = value;
                      _receiver = null;
                      _log = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (receivers.isEmpty)
                  const EmptyFeatureState(
                    icon: Icons.phone_disabled,
                    title: 'No active receiver',
                    subtitle:
                        'Add an active receiver in Stock Reminder Settings.',
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final receiver in receivers)
                        ChoiceChip(
                          selected: _receiver?.id == receiver.id,
                          label: Text(receiver.receiverName),
                          onSelected: (_) => setState(() {
                            _receiver = receiver;
                            _log = null;
                          }),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Prepared Message Preview',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (_log != null)
                      Chip(
                        label: Text(manualReminderStatusLabel(_log!.status)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.resolvedBorderColor),
                  ),
                  child: SelectableText(
                    message.isEmpty
                        ? 'Select receiver to preview message.'
                        : message,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _receiver == null
                      ? null
                      : () => _openWhatsApp(_receiver!, message),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open WhatsApp & Send Manually'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: message.isEmpty
                            ? null
                            : () => _copyMessage(message),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Message'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: message.isEmpty
                            ? null
                            : () => SharePlus.instance.share(
                                ShareParams(text: message),
                              ),
                        icon: const Icon(Icons.share),
                        label: const Text('Share Message'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _log == null
                      ? null
                      : () => _updateStatus(ManualReminderStatus.sentManually),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Mark as Sent'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ReminderLogPanel(logs: state.manualReminderLogs.take(8).toList()),
        ],
      ),
    );
  }

  List<StockReminderReceiver> _eligibleReceivers(
    BusinessState state,
    StockReminderType type,
  ) {
    final receivers = state.stockReminderReceivers
        .where((item) => item.isActive)
        .toList();
    final filtered = receivers.where((item) => item.accepts(type)).toList();
    return filtered.isEmpty ? receivers : filtered;
  }

  StockReminderReceiver? _selectedReceiver(List<StockReminderReceiver> items) {
    if (items.isEmpty) {
      return null;
    }
    final id = widget.initialReceiverId;
    final current = _receiver;
    if (current != null && items.any((item) => item.id == current.id)) {
      return current;
    }
    if (id != null) {
      for (final item in items) {
        if (item.id == id) {
          return item;
        }
      }
    }
    return items.first;
  }

  Future<void> _openWhatsApp(
    StockReminderReceiver receiver,
    String message,
  ) async {
    final number = whatsappNumberOrNull(receiver.whatsAppNumber);
    if (number == null) {
      _snack(context, 'Enter WhatsApp number with country code.');
      return;
    }
    _ensureLog(receiver, message, ManualReminderStatus.whatsappOpened);
    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _snack(
        context,
        'WhatsApp is not installed. Please install WhatsApp or copy message manually.',
      );
    }
  }

  Future<void> _copyMessage(String message) async {
    await Clipboard.setData(ClipboardData(text: message));
    final receiver = _receiver;
    if (receiver != null) {
      _ensureLog(receiver, message, ManualReminderStatus.messageCopied);
    }
    if (mounted) {
      _snack(context, 'Message copied.');
    }
  }

  void _ensureLog(
    StockReminderReceiver receiver,
    String message,
    ManualReminderStatus status,
  ) {
    final notifier = ref.read(businessProvider.notifier);
    final existing = _log;
    if (existing == null) {
      setState(() {
        _log = notifier.createManualReminderLog(
          receiver: receiver,
          messageType: _type,
          messageContent: message,
          status: status,
        );
      });
      return;
    }
    notifier.updateManualReminderLogStatus(existing.reminderId, status);
    setState(() => _log = existing.copyWith(status: status));
  }

  void _updateStatus(ManualReminderStatus status) {
    final log = _log;
    if (log == null) {
      return;
    }
    ref
        .read(businessProvider.notifier)
        .updateManualReminderLogStatus(log.reminderId, status);
    setState(() => _log = log.copyWith(status: status));
    _snack(context, manualReminderStatusLabel(status));
  }
}

class _ReminderLogPanel extends StatelessWidget {
  const _ReminderLogPanel({required this.logs});

  final List<ManualReminderLog> logs;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manual Reminder Log',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (logs.isEmpty)
            const Text('No manual reminders prepared yet.')
          else
            for (final log in logs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(log.receiverName),
                subtitle: Text(
                  '${stockReminderTypeLabel(log.messageType)} | ${manualReminderStatusLabel(log.status)}\n${shortDate(log.createdAt)}',
                ),
                isThreeLine: true,
              ),
        ],
      ),
    );
  }
}

class PhysicalStockVerificationScreen extends ConsumerStatefulWidget {
  const PhysicalStockVerificationScreen({super.key});

  @override
  ConsumerState<PhysicalStockVerificationScreen> createState() =>
      _PhysicalStockVerificationScreenState();
}

class _PhysicalStockVerificationScreenState
    extends ConsumerState<PhysicalStockVerificationScreen> {
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final rows = stockTargetRows(state);
    final checked = rows.where((row) => row.physicalStock > 0).length;
    final shortage = rows.where((row) => row.difference < -0.01).length;
    final extra = rows.where((row) => row.difference > 0.01).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Physical Stock Verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Row(
              children: [
                Expanded(
                  child: _MiniStat(label: 'Checked', value: '$checked'),
                ),
                Expanded(
                  child: _MiniStat(label: 'Shortage', value: '$shortage'),
                ),
                Expanded(
                  child: _MiniStat(label: 'Extra', value: '$extra'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _VerificationCard(
              row: row,
              controller: _controllerFor(row),
              onSave: () => _save(row),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ManualWhatsAppReminderScreen(
                  initialType: StockReminderType.physicalStockVerification,
                ),
              ),
            ),
            icon: const Icon(Icons.send),
            label: const Text('Send Report to Owner'),
          ),
        ),
      ),
    );
  }

  TextEditingController _controllerFor(StockTargetRow row) {
    return _controllers.putIfAbsent(
      row.material.id,
      () => TextEditingController(
        text: row.physicalStock > 0 ? row.physicalStock.toStringAsFixed(2) : '',
      ),
    );
  }

  void _save(StockTargetRow row) {
    final value = double.tryParse(_controllerFor(row).text.trim()) ?? -1;
    if (value < 0) {
      _snack(context, 'Enter physical stock.');
      return;
    }
    ref
        .read(businessProvider.notifier)
        .adjustMaterialStock(
          material: row.material,
          availableKg: value,
          reason: 'Supervisor physical verification',
          entryDate: DateTime.now(),
        );
    _snack(context, '${row.material.name} physical stock updated.');
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.row,
    required this.controller,
    required this.onSave,
  });

  final StockTargetRow row;
  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = EnterpriseTheme.tokensOf(context);
    final status = row.statusLabel;
    final color = row.difference < -0.01
        ? tokens.dangerColor
        : row.difference > 0.01
        ? tokens.successColor
        : tokens.secondaryColor;
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.material.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Chip(
                label: Text(status),
                backgroundColor: color.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Line('Expected Balance Stock', kg(row.expectedStock)),
          _Line('Actual Physical Stock', kg(row.physicalStock)),
          _Line('Stock Difference', kg(row.difference)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Actual Physical Stock',
              suffixText: 'KG',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('Update Physical Stock'),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class StockTargetRow {
  const StockTargetRow({
    required this.analysis,
    required this.lastSaleDate,
    required this.lastPurchaseDate,
  });

  final StockAnalysisResult analysis;
  final DateTime? lastSaleDate;
  final DateTime? lastPurchaseDate;

  MaterialStock get material => analysis.material;
  double get openingStock => analysis.monthOpeningQty;
  double get purchaseQty => analysis.purchaseQty;
  double get saleQty => analysis.saleQty;
  double get expectedStock => analysis.expectedStock;
  double get physicalStock => analysis.physicalStock;
  double get difference => physicalStock - expectedStock;
  double get weightLoss => difference < -0.01 ? difference.abs() : 0;
  String get lastPurchaseLabel => lastPurchaseDate == null
      ? '-'
      : DateFormat('dd-MM-yyyy').format(lastPurchaseDate!);
  String get lastSaleLabel => lastSaleDate == null
      ? '-'
      : DateFormat('dd-MM-yyyy').format(lastSaleDate!);

  String get statusLabel {
    if (physicalStock <= 0 && expectedStock > 0) {
      return 'Not Checked';
    }
    if (difference < -0.01) {
      return 'Shortage';
    }
    if (difference > 0.01) {
      return 'Extra';
    }
    return 'Matched';
  }
}

List<StockTargetRow> stockTargetRows(BusinessState state) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month);
  final to = DateTime(now.year, now.month, now.day);
  final groups = <String, List<MaterialStock>>{};
  for (final material in state.activeMaterials) {
    final nameKey = _normalizedStockItemName(material.name);
    final key = nameKey.isEmpty ? material.id : nameKey;
    (groups[key] ??= []).add(material);
  }
  final rows = [
    for (final materials in groups.values)
      _combinedStockTargetRow(state, materials, from, to),
  ];
  rows.sort((a, b) => b.weightLoss.compareTo(a.weightLoss));
  return rows;
}

StockTargetRow _combinedStockTargetRow(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  final analyses = [
    for (final material in materials)
      buildStockAnalysis(state, material, from: from, to: to),
  ];
  final primary = materials.first;
  final material = primary.copyWith(name: _displayStockItemName(materials));

  double sum(double Function(StockAnalysisResult analysis) valueFor) {
    return analyses.fold<double>(0, (total, item) => total + valueFor(item));
  }

  return StockTargetRow(
    analysis: StockAnalysisResult(
      material: material,
      from: from,
      to: to,
      monthOpeningQty: sum((item) => item.monthOpeningQty),
      purchaseQty: sum((item) => item.purchaseQty),
      saleQty: sum((item) => item.saleQty),
      physicalStock: sum((item) => item.physicalStock),
      expectedStock: sum((item) => item.expectedStock),
    ),
    lastSaleDate: _lastSaleDateForMaterials(state, materials, from, to),
    lastPurchaseDate: _lastPurchaseDateForMaterials(state, materials, from, to),
  );
}

String _normalizedStockItemName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _displayStockItemName(List<MaterialStock> materials) {
  final names = materials
      .map((item) => item.name.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  if (names.isEmpty) {
    return 'Item';
  }
  names.sort((a, b) => a.length.compareTo(b.length));
  return names.first;
}

String manualReminderMessage(
  BusinessState state,
  StockReminderReceiver receiver,
  StockReminderType type,
) {
  return switch (type) {
    StockReminderType.weightLossAlert => weightLossAlertMessage(state),
    StockReminderType.physicalStockVerification =>
      stockVerificationReportMessage(state),
    StockReminderType.pendingPaymentAlert => pendingPaymentReminderMessage(
      state,
    ),
    StockReminderType.dailyStockTarget ||
    StockReminderType.all => dailyStockTargetMessage(state, receiver),
  };
}

String dailyStockTargetMessage(
  BusinessState state,
  StockReminderReceiver receiver,
) {
  final rows = stockTargetRows(state);
  final lossRows = rows.where((row) => row.weightLoss > 0).take(5).toList();
  final itemLines = rows.isEmpty
      ? 'No active stock items found.'
      : rows
            .asMap()
            .entries
            .map(
              (entry) =>
                  '${entry.key + 1}. ${entry.value.material.name}: ${kg(entry.value.expectedStock)}',
            )
            .join('\n');
  final highFocus = lossRows.isEmpty
      ? 'All stock matched. No critical weight loss found today.'
      : lossRows
            .map(
              (row) =>
                  '${row.material.name}: ${kg(row.weightLoss)} weight loss',
            )
            .join('\n');
  return [
    '🚨 EMSLRMVA EXPORT - Daily Stock Verification Target',
    '',
    'Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}',
    'Dear ${stockReminderRoleLabel(receiver.role)},',
    '',
    'Today your stock verification target is ready.',
    '',
    'Please physically check shop stock and match with system expected stock.',
    '',
    'Item-wise Expected Balance:',
    itemLines,
    '',
    'Formula:',
    'Opening Stock + Purchase Stock - Sales Qty = Expected Balance',
    '',
    'Your Work:',
    '✅ Check physical weight in shop',
    '✅ Match with expected balance',
    '✅ Update physical stock in app',
    '✅ Report mismatch immediately',
    '',
    'High Focus Alert:',
    highFocus,
    '',
    'Please verify stock before end of day.',
  ].join('\n');
}

String weightLossAlertMessage(BusinessState state) {
  final lossRows = stockTargetRows(
    state,
  ).where((row) => row.weightLoss > 0).toList();
  if (lossRows.isEmpty) {
    return '✅ All stock matched. No critical weight loss found today.';
  }
  final top = lossRows.first;
  return [
    '🚨 Critical Stock Alert',
    '',
    'Item: ${top.material.name}',
    'Weight Loss: ${kg(top.weightLoss)}',
    'Expected Stock: ${kg(top.expectedStock)}',
    'Actual Physical Stock: ${kg(top.physicalStock)}',
    'Last Sale Date: ${top.lastSaleLabel}',
    '',
    'Action Required:',
    'Please verify physical stock, sales entry, and purchase entry immediately.',
  ].join('\n');
}

String stockVerificationReportMessage(BusinessState state) {
  final rows = stockTargetRows(state);
  final checked = rows.where((row) => row.physicalStock > 0).toList();
  final matched = checked.where((row) => row.statusLabel == 'Matched').length;
  final shortage = rows.where((row) => row.weightLoss > 0).toList();
  final extra = rows.where((row) => row.difference > 0.01).length;
  final critical = shortage.isEmpty
      ? 'No critical shortage.'
      : shortage
            .take(6)
            .map((row) => '${row.material.name}: ${kg(row.weightLoss)}')
            .join('\n');
  return [
    '📦 Stock Verification Report',
    '',
    'Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}',
    'Supervisor: ${state.user.name}',
    '',
    'Total Items Checked: ${checked.length}',
    'Matched: $matched',
    'Shortage: ${shortage.length}',
    'Extra: $extra',
    '',
    'Critical Shortage:',
    critical,
    '',
    'Remarks:',
    'Physical stock checked and updated.',
  ].join('\n');
}

String pendingPaymentReminderMessage(BusinessState state) {
  final pending =
      state.customers.where((customer) => customer.pendingAmount > 0).toList()
        ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
  if (pending.isEmpty) {
    return 'No pending customer payment alert found today.';
  }
  return [
    'Pending Payment Alert',
    '',
    for (var index = 0; index < pending.take(10).length; index++)
      '${index + 1}. ${pending[index].name}: ${money(pending[index].pendingAmount)}',
  ].join('\n');
}

String stockRiskTickerText(BusinessState state) {
  final lossRows = stockTargetRows(
    state,
  ).where((row) => row.weightLoss > 0).toList();
  if (lossRows.isEmpty) {
    return '✅ All stock matched. No critical weight loss found today.';
  }
  return [
    '🚨 Critical:',
    ...lossRows
        .take(5)
        .map((row) => '${row.material.name} weight loss ${kg(row.weightLoss)}'),
    'Verify physical stock today',
    'Update closing stock before end of day',
  ].join(' | ');
}

String whatsappNumber(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}

String? whatsappNumberOrNull(String value) {
  final cleaned = whatsappNumber(value);
  return cleaned.length < 8 ? null : cleaned;
}

String manualReminderStatusLabel(ManualReminderStatus status) {
  return switch (status) {
    ManualReminderStatus.pendingManualSend => 'Pending Manual Send',
    ManualReminderStatus.whatsappOpened => 'WhatsApp Opened',
    ManualReminderStatus.messageCopied => 'Message Copied',
    ManualReminderStatus.sentManually => 'Sent Manually',
    ManualReminderStatus.cancelled => 'Cancelled',
  };
}

String stockReminderRoleLabel(StockReminderRole role) {
  return switch (role) {
    StockReminderRole.supervisor => 'Supervisor',
    StockReminderRole.manager => 'Manager',
    StockReminderRole.owner => 'Owner',
    StockReminderRole.other => 'Other',
  };
}

String stockReminderTypeLabel(StockReminderType type) {
  return switch (type) {
    StockReminderType.dailyStockTarget => 'Daily Stock Target',
    StockReminderType.physicalStockVerification =>
      'Physical Stock Verification',
    StockReminderType.weightLossAlert => 'Weight Loss Alert',
    StockReminderType.pendingPaymentAlert => 'Pending Payment Alert',
    StockReminderType.all => 'All',
  };
}

DateTime? _lastSaleDateForMaterials(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  DateTime? latest;
  for (final sale in state.activeSales) {
    if (!_inRange(sale.createdAt, from, to) ||
        !sale.items.any((item) => _matchesAnyStockMaterial(item, materials))) {
      continue;
    }
    if (latest == null || sale.createdAt.isAfter(latest)) {
      latest = sale.createdAt;
    }
  }
  return latest;
}

DateTime? _lastPurchaseDateForMaterials(
  BusinessState state,
  List<MaterialStock> materials,
  DateTime from,
  DateTime to,
) {
  DateTime? latest;
  for (final purchase in state.activePurchases) {
    if (!_inRange(purchase.createdAt, from, to) ||
        !purchase.items.any(
          (item) => _matchesAnyStockMaterial(item, materials),
        )) {
      continue;
    }
    if (latest == null || purchase.createdAt.isAfter(latest)) {
      latest = purchase.createdAt;
    }
  }
  return latest;
}

bool _matchesAnyStockMaterial(LineItem item, List<MaterialStock> materials) {
  return materials.any(
    (material) =>
        stockMaterialMatches(item.materialId, item.materialName, material),
  );
}

bool _inRange(DateTime value, DateTime from, DateTime to) {
  final date = DateTime(value.year, value.month, value.day);
  return !date.isBefore(from) && !date.isAfter(to);
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _formatTime(TimeOfDay time) {
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  final hour = time.hour == 0
      ? 12
      : time.hour > 12
      ? time.hour - 12
      : time.hour;
  return '$hour:${time.minute.toString().padLeft(2, '0')} $suffix';
}
