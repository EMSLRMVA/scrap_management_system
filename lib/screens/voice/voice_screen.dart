import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scrap_data_provider.dart';
import '../../providers/voice_command_provider.dart';
import '../../services/voice_parser_service.dart';
import '../../utils/formatters.dart';
import '../../voice/voice_command_examples.dart';
import '../../widgets/enterprise_card.dart';
import '../../widgets/module_scaffold.dart';
import '../../widgets/status_pill.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _manualCommand = TextEditingController(
    text: 'Add coconut shell 500 kg at 15 rupees',
  );
  final _tts = FlutterTts();

  @override
  void dispose() {
    _manualCommand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceCommandProvider>();
    final result = voice.lastResult;

    return ModuleScaffold(
      title: 'Voice System',
      subtitle:
          'Convert spoken purchase and expense commands into transaction drafts',
      icon: Icons.mic,
      actions: [
        StatusPill(
          label: voice.status,
          color: voice.listening
              ? AppTheme.red
              : voice.status == 'Permission denied' ||
                    voice.status == 'Not available'
              ? AppTheme.orange
              : AppTheme.green,
          icon: voice.listening ? Icons.hearing : Icons.check_circle,
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final commandPanel = EnterpriseCard(
              title: 'Command Input',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _manualCommand,
                    decoration: const InputDecoration(
                      labelText: 'Voice command text',
                      prefixIcon: Icon(Icons.graphic_eq),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          context.read<VoiceCommandProvider>().parseManual(
                            _manualCommand.text,
                          );
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Parse Command'),
                      ),
                      OutlinedButton.icon(
                        onPressed: voice.listening
                            ? () => context
                                  .read<VoiceCommandProvider>()
                                  .stopListening()
                            : () => context
                                  .read<VoiceCommandProvider>()
                                  .startListening(),
                        icon: Icon(voice.listening ? Icons.stop : Icons.mic),
                        label: Text(voice.listening ? 'Stop' : 'Listen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _tts.speak(
                          'Voice assistant is ready for purchase and expense entry.',
                        ),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Test Speaker'),
                      ),
                    ],
                  ),
                  if (voice.errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      voice.errorMessage,
                      style: const TextStyle(
                        color: AppTheme.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            );
            final draftPanel = _VoiceDraftCard(result: result);
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  commandPanel,
                  const SizedBox(height: 12),
                  draftPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: commandPanel),
                const SizedBox(width: 12),
                Expanded(child: draftPanel),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        EnterpriseCard(
          title: 'Command Examples',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final example in voiceCommandExamples)
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 18),
                  label: Text(example),
                  onPressed: () {
                    _manualCommand.text = example;
                    context.read<VoiceCommandProvider>().parseManual(example);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceDraftCard extends StatelessWidget {
  const _VoiceDraftCard({required this.result});

  final VoiceCommandResult? result;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    if (result is VoicePurchaseDraft) {
      final draft = result as VoicePurchaseDraft;
      final sellers = context.watch<ScrapDataProvider>().sellers;
      return EnterpriseCard(
        title: 'Purchase Draft',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.recycling)),
              title: Text(draft.item.materialName),
              subtitle: Text(
                '${Formatters.kg(draft.item.weightKg)} at ${Formatters.money(draft.item.rate)}',
              ),
              trailing: Text(
                Formatters.money(draft.item.amount),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sellers.isEmpty
                  ? null
                  : () {
                      final purchase = context
                          .read<ScrapDataProvider>()
                          .addPurchase(
                            sellerId: sellers.first.id,
                            items: [draft.item],
                            paidAmount: 0,
                            createdBy: user?.name ?? 'Voice Assistant',
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${purchase.invoiceNumber} saved'),
                        ),
                      );
                    },
              icon: const Icon(Icons.save),
              label: const Text('Save Purchase Draft'),
            ),
          ],
        ),
      );
    }

    if (result is VoiceExpenseDraft) {
      final draft = result as VoiceExpenseDraft;
      return EnterpriseCard(
        title: 'Expense Draft',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text(draft.expense.category),
              subtitle: Text(draft.expense.note ?? 'Voice expense'),
              trailing: Text(
                Formatters.money(draft.expense.amount),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                context.read<VoiceCommandProvider>().saveVoiceExpense(
                  user?.name ?? 'Voice Assistant',
                );
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Expense saved')));
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Expense Draft'),
            ),
          ],
        ),
      );
    }

    return const EnterpriseCard(
      title: 'Parsed Draft',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Text('No draft parsed yet'),
      ),
    );
  }
}
