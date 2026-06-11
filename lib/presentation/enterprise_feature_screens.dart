import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_branding.dart';
import '../core/enterprise_theme.dart';
import '../core/file_helpers.dart';
import '../core/money_format.dart';
import '../domain/business_models.dart';
import '../domain/stock_calculation.dart';
import '../services/document_ai_service.dart';
import '../services/firebase_login_service.dart';
import '../services/pricing_insight_service.dart';
import 'business_controller.dart';
import 'manual_stock_reminders.dart';
import 'theme_controller.dart';
import 'theme_settings_screen.dart';

const _expenseCategories = [
  'Scrap Purchase',
  'Other Purchase',
  'Transport Expense',
  'Loading Expense',
  'Miscellaneous Expense',
  'Inventory Purchase',
  'Inventory Adjustment',
];

const _paymentModes = ['Cash', 'UPI', 'Bank', 'Other'];
const _rememberLoginEmailKey = 'remember_login_email';
const _lastLoginEmailKey = 'last_login_email';

final authProfileProvider =
    NotifierProvider<AuthProfileController, AuthenticatedProfile?>(
      AuthProfileController.new,
    );

class AuthProfileController extends Notifier<AuthenticatedProfile?> {
  @override
  AuthenticatedProfile? build() => null;

  void setProfile(AuthenticatedProfile profile) {
    state = profile;
  }

  void clear() {
    state = null;
  }
}

class OwnerLoginGate extends ConsumerStatefulWidget {
  const OwnerLoginGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OwnerLoginGate> createState() => _OwnerLoginGateState();
}

class _OwnerLoginGateState extends ConsumerState<OwnerLoginGate> {
  final _loginService = FirebaseLoginService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _registerName = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _registerMobile = TextEditingController();
  final _resetEmail = TextEditingController();
  bool _consentAccepted = false;
  bool _loadingSession = true;
  bool _submitting = false;
  bool _showRegister = false;
  bool _showForgotPassword = false;
  bool _rememberEmail = true;
  bool _passwordVisible = false;
  bool _registerPasswordVisible = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _email.text = ownerEmail;
    Future.microtask(() async {
      await _loadRememberedEmail();
      await _restoreSession();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _registerName.dispose();
    _registerEmail.dispose();
    _registerPassword.dispose();
    _registerMobile.dispose();
    _resetEmail.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final profile = await _loginService.currentProfile();
      if (!mounted) {
        return;
      }
      if (profile != null) {
        _applyProfile(profile);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSession = false);
      }
    }
  }

  Future<void> _loadRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberLoginEmailKey) ?? true;
      final savedEmail = prefs.getString(_lastLoginEmailKey)?.trim() ?? '';
      if (!mounted) {
        return;
      }
      setState(() {
        _rememberEmail = remember;
        if (remember && savedEmail.isNotEmpty) {
          _email.text = savedEmail;
        }
      });
    } catch (_) {
      // Remembering the email is only a convenience.
    }
  }

  Future<void> _rememberSuccessfulLogin(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberLoginEmailKey, _rememberEmail);
    if (_rememberEmail) {
      await prefs.setString(_lastLoginEmailKey, email);
    } else {
      await prefs.remove(_lastLoginEmailKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProfileProvider) != null) {
      return widget.child;
    }
    if (_loadingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: FeaturePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: EnterpriseTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.recycling,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appDisplayName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Email/password access',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_showRegister)
                      _registerForm()
                    else if (_showForgotPassword)
                      _forgotPasswordForm()
                    else
                      _loginForm(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_passwordVisible,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _rememberEmail,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _rememberEmail = value ?? true),
            title: const Text('Remember email'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: EnterpriseTheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _login,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('Login'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _showRegister = true;
                    _showForgotPassword = false;
                    _errorMessage = null;
                  }),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Register New User'),
          ),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _showForgotPassword = true;
                    _showRegister = false;
                    _resetEmail.text = _normalizedEmail(_email.text);
                    _errorMessage = null;
                  }),
            child: const Text('Forgot Password'),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openDebugOwnerDemo,
              icon: const Icon(Icons.offline_bolt_outlined),
              label: const Text('Open Debug Owner Demo'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use only when emulator DNS/network blocks Firebase login.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _registerForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _registerName,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _registerEmail,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _registerPassword,
            obscureText: !_registerPasswordVisible,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _registerPasswordVisible
                    ? 'Hide password'
                    : 'Show password',
                onPressed: () => setState(
                  () => _registerPasswordVisible = !_registerPasswordVisible,
                ),
                icon: Icon(
                  _registerPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _registerMobile,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Mobile optional',
              prefixIcon: Icon(Icons.phone_android),
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consentAccepted,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _consentAccepted = value ?? false),
            title: const Text('Privacy consent'),
            subtitle: const Text(appPrivacyConsentText),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: EnterpriseTheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _register,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: const Text('Register New User'),
          ),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _showRegister = false;
                    _errorMessage = null;
                  }),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Widget _forgotPasswordForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _resetEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This resets your app/Firebase password, not your Gmail password.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: EnterpriseTheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _sendPasswordReset,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_read_outlined),
            label: const Text('Send Reset Link'),
          ),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _showForgotPassword = false;
                    _errorMessage = null;
                  }),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _errorMessage = 'Email and password are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final email = _normalizedEmail(_email.text);
      final profile = await _loginService.signIn(
        email: email,
        password: _password.text,
      );
      if (!mounted) {
        return;
      }
      await _rememberSuccessfulLogin(email);
      TextInput.finishAutofillContext(shouldSave: true);
      _applyProfile(profile);
    } on FirebaseLoginException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _register() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final profile = await _loginService.register(
        name: _registerName.text,
        email: _normalizedEmail(_registerEmail.text),
        password: _registerPassword.text,
        mobile: _registerMobile.text,
        consentAccepted: _consentAccepted,
      );
      if (!mounted) {
        return;
      }
      TextInput.finishAutofillContext(shouldSave: true);
      _applyProfile(profile);
    } on FirebaseLoginException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_resetEmail.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Email is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await _loginService.sendPasswordReset(_normalizedEmail(_resetEmail.text));
      if (mounted) {
        _snack(
          context,
          'If this email is registered, a reset link has been sent. Please check Inbox, Spam, and Promotions.',
        );
        setState(() => _showForgotPassword = false);
      }
    } on FirebaseLoginException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _applyProfile(AuthenticatedProfile profile) {
    ref.read(authProfileProvider.notifier).setProfile(profile);
    ref
        .read(businessProvider.notifier)
        .setAuthenticatedUser(
          name: profile.name,
          email: profile.email,
          mobile: profile.mobile,
          role: profile.role,
        );
  }

  void _openDebugOwnerDemo() {
    _applyProfile(
      const AuthenticatedProfile(
        uid: 'debug-owner',
        email: ownerEmail,
        name: 'Owner',
        role: UserRole.owner,
        active: true,
      ),
    );
  }
}

class FeatureRecordTile extends StatelessWidget {
  const FeatureRecordTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.statusColor,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    this.onWhatsApp,
    this.onInvoicePdf,
    this.showEdit = true,
    this.showDelete = true,
    this.lockedEditMessage = '',
    this.avatarPath = '',
    this.icon = Icons.receipt_long,
  });

  final String title;
  final String subtitle;
  final String amount;
  final String status;
  final Color statusColor;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onInvoicePdf;
  final bool showEdit;
  final bool showDelete;
  final String lockedEditMessage;
  final String avatarPath;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              EntityAvatar(path: avatarPath, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$amount\n$status',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                OutlinedButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility, size: 17),
                  label: const Text('View'),
                ),
                if (onWhatsApp != null)
                  OutlinedButton.icon(
                    onPressed: onWhatsApp,
                    icon: const Icon(Icons.chat, size: 17),
                    label: const Text('WhatsApp'),
                  ),
                if (onInvoicePdf != null)
                  OutlinedButton.icon(
                    onPressed: onInvoicePdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 17),
                    label: const Text('Invoice PDF'),
                  ),
                if (showEdit)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 17),
                    label: const Text('Edit'),
                  ),
                if (showDelete)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: const Text('Delete'),
                  ),
              ];
              final itemWidth = actions.length <= 2
                  ? (constraints.maxWidth - 8) / actions.length
                  : (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions)
                    SizedBox(width: itemWidth, child: action),
                ],
              );
            },
          ),
          if (!showEdit && lockedEditMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.lock_clock,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lockedEditMessage,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PurchaseEditorScreen extends ConsumerStatefulWidget {
  const PurchaseEditorScreen({super.key, this.purchase, this.initialCreatedBy});

  final PurchaseRecord? purchase;
  final String? initialCreatedBy;

  @override
  ConsumerState<PurchaseEditorScreen> createState() =>
      _PurchaseEditorScreenState();
}

enum _PreviousBalanceAction { apply, keepForLater, settleSeparately }

enum _CurrentBillSettlementAction { carryForward, settleNow }

class _PurchaseEditorScreenState extends ConsumerState<PurchaseEditorScreen> {
  final _paid = TextEditingController();
  final _remarks = TextEditingController();
  final _purchaseTts = FlutterTts();
  final _lines = <LineDraft>[];
  Party? _seller;
  DateTime _purchaseDate = DateTime.now();
  String _createdBy = '';
  String _voiceStatus = 'Ready';
  bool _voiceListening = false;
  bool _itemsChanged = false;
  _PreviousBalanceAction _previousBalanceAction =
      _PreviousBalanceAction.keepForLater;
  _CurrentBillSettlementAction _settlementAction =
      _CurrentBillSettlementAction.carryForward;

  bool get _editing => widget.purchase != null;

  @override
  void initState() {
    super.initState();
    final initialCreator = widget.initialCreatedBy?.trim() ?? '';
    _createdBy = initialCreator.isNotEmpty
        ? initialCreator
        : ref.read(businessProvider).user.name;
    final purchase = widget.purchase;
    if (purchase == null) {
      _lines.add(LineDraft());
      return;
    }
    _seller = purchase.seller;
    _purchaseDate = purchase.createdAt;
    _createdBy = purchase.createdBy.trim().isEmpty
        ? ref.read(businessProvider).user.name
        : purchase.createdBy.trim();
    _paid.text = purchase.paidAmount.toStringAsFixed(0);
    _remarks.text = purchase.remarks;
    _lines.addAll(purchase.items.map(LineDraft.fromItem));
    _previousBalanceAction = purchase.previousBalanceAppliedAmount.abs() > 0.01
        ? _PreviousBalanceAction.apply
        : _PreviousBalanceAction.keepForLater;
    _settlementAction = purchase.currentSettlementAdjustmentAmount.abs() > 0.01
        ? _CurrentBillSettlementAction.settleNow
        : _CurrentBillSettlementAction.carryForward;
  }

  @override
  void dispose() {
    _paid.dispose();
    _remarks.dispose();
    _purchaseTts.stop();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final staffNames = _cashStaffNameOptions(state, _createdBy);
    final selectedCreator = staffNames.contains(_createdBy.trim())
        ? _createdBy.trim()
        : staffNames.contains(state.user.name.trim())
        ? state.user.name.trim()
        : staffNames.first;
    _createdBy = selectedCreator;
    final originalPurchase = widget.purchase;
    final recalculatedOriginalBill = roundMoneyValue(
      _lines.fold<double>(
        0,
        (runningTotal, line) => runningTotal + line.amount,
      ),
    );
    final originalBillAmount = originalPurchase != null && !_itemsChanged
        ? originalPurchase.originalBillAmount
        : recalculatedOriginalBill;
    final paidForCurrentBill = _read(_paid);
    final previousBalanceReferences = _seller == null
        ? <SellerBalanceReference>[]
        : state.previousBalanceReferencesForSeller(
            _seller!.id,
            excludingPurchaseId: originalPurchase?.id,
          );
    var availablePreviousBalance = _editing
        ? roundMoneyValue(
            previousBalanceReferences.fold<double>(
              0,
              (runningTotal, item) => runningTotal + item.balanceAmount,
            ),
          )
        : 0.0;
    if (availablePreviousBalance.abs() <= 0.01 &&
        originalPurchase != null &&
        originalPurchase.previousBalanceAppliedAmount.abs() > 0.01 &&
        _seller?.id == originalPurchase.seller.id) {
      availablePreviousBalance = originalPurchase.previousBalanceAppliedAmount;
    }
    final previousBalanceToApply =
        _editing && _previousBalanceAction == _PreviousBalanceAction.apply
        ? availablePreviousBalance
        : 0.0;
    final billBeforeSettlement = roundMoneyValue(
      originalBillAmount + previousBalanceToApply,
    );
    final currentBillDifference = roundMoneyValue(
      billBeforeSettlement - paidForCurrentBill,
    );
    final settlementAdjustment =
        _editing &&
            _settlementAction == _CurrentBillSettlementAction.settleNow &&
            currentBillDifference.abs() > 0.01
        ? roundMoneyValue(paidForCurrentBill - billBeforeSettlement)
        : 0.0;
    final finalBillAmount = roundMoneyValue(
      billBeforeSettlement + settlementAdjustment,
    );
    final balance = roundMoneyValue(finalBillAmount - paidForCurrentBill);
    final sellerBalanceBeforeSave = _seller == null
        ? 0.0
        : state.sellerNetBalanceFor(
            _seller!.id,
            excludingPurchaseId: originalPurchase?.id,
          );
    final sellerBalanceAfterSave = roundMoneyValue(
      sellerBalanceBeforeSave +
          originalBillAmount +
          settlementAdjustment -
          paidForCurrentBill,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Purchase' : 'New Purchase')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openVoiceParser,
        icon: Icon(_voiceListening ? Icons.hearing : Icons.mic),
        label: const Text('Voice'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PartyDropdown(
              label: 'Seller',
              value: _seller,
              items: state.sellers,
              emptyLabel: 'Add seller',
              onAdd: () async {
                final created = await showPartyEditor(
                  context,
                  ref,
                  PartyKind.seller,
                );
                if (created != null) {
                  setState(() => _seller = created);
                }
              },
              onChanged: (value) => setState(() {
                _seller = value;
                _previousBalanceAction = _PreviousBalanceAction.keepForLater;
              }),
            ),
            if (_seller != null) ...[
              const SizedBox(height: 10),
              SellerSnapshot(seller: _seller!),
              if (_editing && availablePreviousBalance.abs() > 0.01) ...[
                const SizedBox(height: 10),
                FeaturePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            availablePreviousBalance > 0
                                ? Icons.pending_actions
                                : Icons.account_balance_wallet,
                            size: 18,
                            color: availablePreviousBalance > 0
                                ? EnterpriseTheme.warning
                                : EnterpriseTheme.success,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Previous Bill Balance',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AmountLine(
                        label: availablePreviousBalance > 0
                            ? 'Total Amount to Add'
                            : 'Total Amount to Reduce',
                        value: money(availablePreviousBalance.abs()),
                        color: availablePreviousBalance > 0
                            ? EnterpriseTheme.warning
                            : EnterpriseTheme.success,
                      ),
                      for (final reference in previousBalanceReferences)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _PreviousBalanceReferenceRow(
                            reference: reference,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            selected:
                                _previousBalanceAction ==
                                _PreviousBalanceAction.apply,
                            avatar: const Icon(Icons.call_merge, size: 16),
                            label: const Text('Apply previous balance'),
                            onSelected: (_) => setState(
                              () => _previousBalanceAction =
                                  _PreviousBalanceAction.apply,
                            ),
                          ),
                          ChoiceChip(
                            selected:
                                _previousBalanceAction ==
                                _PreviousBalanceAction.keepForLater,
                            avatar: const Icon(Icons.schedule, size: 16),
                            label: const Text('Keep for later'),
                            onSelected: (_) => setState(
                              () => _previousBalanceAction =
                                  _PreviousBalanceAction.keepForLater,
                            ),
                          ),
                          ChoiceChip(
                            selected:
                                _previousBalanceAction ==
                                _PreviousBalanceAction.settleSeparately,
                            avatar: const Icon(Icons.receipt_long, size: 16),
                            label: const Text('Settle separately'),
                            onSelected: (_) => setState(
                              () => _previousBalanceAction =
                                  _PreviousBalanceAction.settleSeparately,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _previousBalanceAction == _PreviousBalanceAction.apply
                            ? 'This amount is included only after you save.'
                            : 'This old balance stays separate and is not added to this bill.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickPurchaseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Purchase Date: ${DateFormat('dd MMM yyyy').format(_purchaseDate)}',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select any purchase date: 2 years back to 2 years future.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCreator,
              decoration: const InputDecoration(
                labelText: 'Purchase Added By',
                helperText:
                    'Default is login user. Owner can correct staff name.',
              ),
              items: staffNames
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: isOwner
                  ? (value) =>
                        setState(() => _createdBy = value ?? selectedCreator)
                  : null,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _lines.length; index++) ...[
              PurchaseLineEditor(
                index: index,
                line: _lines[index],
                materials: state.activeMaterials,
                onChanged: () => setState(() => _itemsChanged = true),
                onRemove: _lines.length == 1
                    ? null
                    : () {
                        setState(() {
                          _lines.removeAt(index).dispose();
                          _itemsChanged = true;
                        });
                      },
                onAddMaterial: () async {
                  final created = await showMaterialEditor(context, ref);
                  if (created != null) {
                    setState(() {
                      _lines[index].setMaterial(created);
                      _itemsChanged = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _lines.add(LineDraft());
                _itemsChanged = true;
              }),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Paid Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 12),
            FeaturePanel(
              child: Column(
                children: [
                  AmountLine(
                    label: 'Original Bill Amount',
                    value: money(originalBillAmount),
                  ),
                  if (previousBalanceToApply.abs() > 0.01)
                    AmountLine(
                      label: previousBalanceToApply > 0
                          ? 'Previous Balance Added'
                          : 'Previous Balance Reduced',
                      value: money(previousBalanceToApply),
                      color: previousBalanceToApply > 0
                          ? EnterpriseTheme.warning
                          : EnterpriseTheme.success,
                    ),
                  if (settlementAdjustment.abs() > 0.01)
                    AmountLine(
                      label: 'Current Settlement Adjustment',
                      value: money(settlementAdjustment),
                      color: settlementAdjustment < 0
                          ? EnterpriseTheme.success
                          : EnterpriseTheme.warning,
                    ),
                  AmountLine(
                    label: 'Final Bill Amount',
                    value: money(finalBillAmount),
                  ),
                  AmountLine(
                    label: 'Paid for Current Bill',
                    value: money(paidForCurrentBill),
                  ),
                  AmountLine(
                    label: 'Current Bill Balance',
                    value: balance >= 0
                        ? money(balance)
                        : 'Advance ${money(balance.abs())}',
                    color: balance > 0
                        ? EnterpriseTheme.warning
                        : EnterpriseTheme.success,
                  ),
                  if (_editing && currentBillDifference.abs() > 0.01) ...[
                    const Divider(height: 18),
                    AmountLine(
                      label: currentBillDifference > 0
                          ? 'Current Difference'
                          : 'Current Extra Paid',
                      value: money(currentBillDifference.abs()),
                      color: currentBillDifference > 0
                          ? EnterpriseTheme.warning
                          : EnterpriseTheme.success,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          selected:
                              _settlementAction ==
                              _CurrentBillSettlementAction.carryForward,
                          avatar: const Icon(Icons.redo, size: 16),
                          label: const Text('Carry to next bill'),
                          onSelected: (_) => setState(
                            () => _settlementAction =
                                _CurrentBillSettlementAction.carryForward,
                          ),
                        ),
                        ChoiceChip(
                          selected:
                              _settlementAction ==
                              _CurrentBillSettlementAction.settleNow,
                          avatar: const Icon(Icons.done_all, size: 16),
                          label: const Text('Settle current difference'),
                          onSelected: (_) => setState(
                            () => _settlementAction =
                                _CurrentBillSettlementAction.settleNow,
                          ),
                        ),
                      ],
                    ),
                    AmountLine(
                      label: 'Seller Balance Before Save',
                      value: sellerBalanceBeforeSave >= 0
                          ? money(sellerBalanceBeforeSave)
                          : 'Advance ${money(sellerBalanceBeforeSave.abs())}',
                      color: sellerBalanceBeforeSave > 0
                          ? EnterpriseTheme.warning
                          : EnterpriseTheme.success,
                    ),
                    AmountLine(
                      label: 'Seller Balance After Save',
                      value: sellerBalanceAfterSave >= 0
                          ? money(sellerBalanceAfterSave)
                          : 'Advance ${money(sellerBalanceAfterSave.abs())}',
                      color: sellerBalanceAfterSave > 0
                          ? EnterpriseTheme.warning
                          : EnterpriseTheme.success,
                    ),
                  ],
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
                      Icon(
                        _voiceListening ? Icons.hearing : Icons.mic_none,
                        color: _voiceListening
                            ? EnterpriseTheme.primary
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _voiceStatus,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  if (_voiceListening) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 4),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openVoiceParser,
                          icon: const Icon(Icons.mic),
                          label: const Text('Mic'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _speakPurchaseVoiceHelp,
                          icon: const Icon(Icons.help_outline),
                          label: const Text('Voice Help'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _save(),
              icon: const Icon(Icons.save),
              label: Text(_editing ? 'Update Purchase' : 'Save Purchase'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final firstAllowedDate = DateTime(now.year - 2, now.month, now.day);
    final lastAllowedDate = DateTime(now.year + 2, now.month, now.day);
    final initialAllowedDate = _purchaseDate.isBefore(firstAllowedDate)
        ? firstAllowedDate
        : _purchaseDate.isAfter(lastAllowedDate)
        ? lastAllowedDate
        : _purchaseDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialAllowedDate,
      firstDate: firstAllowedDate,
      lastDate: lastAllowedDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(
      () => _purchaseDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        now.hour,
        now.minute,
        now.second,
      ),
    );
  }

  Future<void> _openVoiceParser() async {
    _setVoiceState('Listening...', listening: true);
    final command = await showVoiceCommandDialog(
      context,
      ref: ref,
      title: 'Voice Purchase Assistant',
      helpText: _purchaseVoiceHelpText,
    );
    if (!mounted) {
      return;
    }
    final text = command?.trim() ?? '';
    if (text.isEmpty) {
      _setVoiceState('No Speech Detected...');
      await _speakVoice('No speech detected');
      return;
    }
    _setVoiceState('Processing...');

    final draft = parseSmartPurchaseCommand(text);
    if (draft != null) {
      await _applyVoiceDraft(draft);
      if (_isVoiceSaveCommand(text)) {
        await _save(fromVoice: true);
      }
      return;
    }

    if (await _applyDirectPurchaseVoiceCommand(text)) {
      return;
    }

    ref
        .read(businessProvider.notifier)
        .recordVoiceActivity('voice_command_failed', text);
    if (!mounted) {
      return;
    }
    _setVoiceState('Sorry, I could not understand.');
    _snack(context, 'Sorry, I could not understand. Please try again.');
    await _speakVoice('Sorry, I could not understand. Please try again.');
  }

  Future<void> _applyVoiceDraft(VoicePurchaseDraft draft) async {
    if (draft.resetForm) {
      await _confirmResetUnsavedForm();
      return;
    }
    final state = ref.read(businessProvider);
    final seller = _bestPartyMatch(state.sellers, draft.sellerName);
    final material = _bestMaterialMatch(
      state.activeMaterials,
      draft.materialName,
    );
    final confirmations = <String>[];
    setState(() {
      if (seller != null) {
        _seller = seller;
        confirmations.add('Seller selected');
      }
      if (_lines.isEmpty) {
        _lines.add(LineDraft());
      }
      if (material != null) {
        _lines.first.setMaterial(material);
        confirmations.add('Material selected');
      }
      _lines.first.weight.text = _voiceNumberString(draft.weightKg);
      _lines.first.rate.text = _voiceNumberString(draft.rate);
      confirmations.addAll(['Weight added', 'Rate added']);
      if (draft.paidAmount > 0) {
        _paid.text = _voiceNumberString(draft.paidAmount);
        confirmations.add('Paid amount added');
      }
      if (draft.remarks.trim().isNotEmpty) {
        _remarks.text = draft.remarks.trim();
        confirmations.add('Remarks added');
      }
      if (draft.applyPreviousBalance && _editing) {
        _previousBalanceAction = _PreviousBalanceAction.apply;
        confirmations.add('Previous balance selected');
      }
      _voiceStatus = 'Recognized...';
      _voiceListening = false;
    });
    if (seller == null && draft.sellerName.trim().isNotEmpty) {
      _snack(context, 'Seller not found. Select seller manually.');
    }
    if (material == null) {
      _snack(context, 'Material not found. Select material manually.');
    }
    await _speakVoice(
      confirmations.isEmpty ? 'Recognized' : confirmations.join('. '),
    );
  }

  Future<bool> _applyDirectPurchaseVoiceCommand(String command) async {
    final text = normalizeSmartVoiceCommand(command);
    if (text.isEmpty) {
      return false;
    }
    if (text.contains('go back') || text == 'back') {
      _setVoiceState('Recognized...');
      await _speakVoice('Going back');
      if (!mounted) {
        return true;
      }
      Navigator.of(context).maybePop();
      return true;
    }
    if (text == 'clear' ||
        text == 'reset' ||
        text == 'clear purchase' ||
        text == 'reset purchase' ||
        text == 'reset form') {
      await _confirmResetUnsavedForm();
      return true;
    }
    if (text.contains('apply previous balance')) {
      if (!_editing) {
        _snack(
          context,
          'Previous bill settlement is not shown in New Purchase.',
        );
        _setVoiceState('Ready');
        await _speakVoice(
          'Previous bill settlement is not shown in new purchase',
        );
        return true;
      }
      setState(() {
        _previousBalanceAction = _PreviousBalanceAction.apply;
        _voiceStatus = 'Recognized...';
      });
      await _speakVoice('Previous balance selected');
      return true;
    }
    if (text.contains('add item')) {
      setState(() {
        _lines.add(LineDraft());
        _voiceStatus = 'Recognized...';
      });
      await _speakVoice('Item added');
      return true;
    }
    if (text.contains('remove item')) {
      if (_lines.length > 1) {
        setState(() {
          _lines.removeLast().dispose();
          _voiceStatus = 'Recognized...';
        });
        await _speakVoice('Item removed');
      } else {
        _setVoiceState('No removable item.');
        await _speakVoice('No removable item');
      }
      return true;
    }

    var handled = false;
    final confirmations = <String>[];
    final state = ref.read(businessProvider);

    final sellerName = _purchaseVoiceField(
      text,
      ['seller', 'supplier'],
      stopLabels: [
        'material',
        'maal',
        'item',
        'weight',
        'wajan',
        'rate',
        'paid',
        'payment',
        'remarks',
        'remark',
        'note',
        'save',
      ],
    );
    if (sellerName.isNotEmpty) {
      final seller = _bestPartyMatch(state.sellers, sellerName);
      if (seller != null) {
        setState(() => _seller = seller);
        confirmations.add('Seller selected');
      } else {
        _snack(context, 'Seller not found. Select seller manually.');
      }
      handled = true;
    }

    final materialName = _purchaseVoiceField(
      text,
      ['material', 'maal', 'item'],
      stopLabels: [
        'weight',
        'wajan',
        'rate',
        'paid',
        'payment',
        'seller',
        'supplier',
        'remarks',
        'remark',
        'note',
        'save',
      ],
    );
    if (materialName.isNotEmpty) {
      final material = _bestMaterialMatch(state.activeMaterials, materialName);
      setState(() {
        if (_lines.isEmpty) {
          _lines.add(LineDraft());
        }
        _lines.first.setMaterial(material);
      });
      confirmations.add('Material selected');
      handled = true;
    }

    final weight = _purchaseVoiceNumber(text, ['weight', 'wajan']);
    if (weight != null && weight > 0) {
      setState(() {
        if (_lines.isEmpty) {
          _lines.add(LineDraft());
        }
        _lines.first.weight.text = _voiceNumberString(weight);
      });
      confirmations.add('Weight added');
      handled = true;
    }
    final rate = _purchaseVoiceNumber(text, ['rate', 'dar', 'bhav']);
    if (rate != null && rate > 0) {
      setState(() {
        if (_lines.isEmpty) {
          _lines.add(LineDraft());
        }
        _lines.first.rate.text = _voiceNumberString(rate);
      });
      confirmations.add('Rate added');
      handled = true;
    }
    final paid = _purchaseVoiceNumber(text, ['paid amount', 'paid', 'payment']);
    if (paid != null && paid > 0) {
      setState(() => _paid.text = _voiceNumberString(paid));
      confirmations.add('Paid amount added');
      handled = true;
    }

    final remarks = _purchaseVoiceField(
      text,
      ['remarks', 'remark', 'note'],
      stopLabels: ['save'],
    );
    if (remarks.isNotEmpty) {
      setState(() => _remarks.text = remarks);
      confirmations.add('Remarks added');
      handled = true;
    }

    if (_isVoiceSaveCommand(text)) {
      await _save(fromVoice: true);
      return true;
    }

    if (handled) {
      _setVoiceState('Recognized...');
      await _speakVoice(confirmations.join('. '));
      return true;
    }

    if (text.contains('add seller')) {
      final created = await showPartyEditor(context, ref, PartyKind.seller);
      if (created != null && mounted) {
        setState(() => _seller = created);
      }
      _setVoiceState('Recognized...');
      await _speakVoice('Seller selected');
      return true;
    }
    if (text.contains('add material')) {
      final created = await showMaterialEditor(context, ref);
      if (created != null && mounted) {
        setState(() {
          if (_lines.isEmpty) {
            _lines.add(LineDraft());
          }
          _lines.first.setMaterial(created);
        });
      }
      _setVoiceState('Recognized...');
      await _speakVoice('Material selected');
      return true;
    }
    return false;
  }

  Future<void> _save({bool fromVoice = false}) async {
    if (_seller == null) {
      _snack(context, 'Select seller.');
      if (fromVoice) {
        await _speakVoice('Select seller');
      }
      return;
    }
    final items = _lines
        .map((line) => line.toItem())
        .whereType<LineItem>()
        .toList();
    final original = widget.purchase;
    final itemsForSave = original != null && !_itemsChanged
        ? original.items
        : items;
    if (itemsForSave.isEmpty) {
      _snack(context, 'Add at least one valid material line.');
      if (fromVoice) {
        await _speakVoice('Add at least one valid material line');
      }
      return;
    }
    final notifier = ref.read(businessProvider.notifier);
    if (original != null && !notifier.canEditPurchase(original)) {
      notifier.recordPurchaseEditBlocked(original);
      _snack(context, notifier.purchaseEditExpiredMessage(original));
      return;
    }
    final state = ref.read(businessProvider);
    var previousReferences = original == null
        ? <SellerBalanceReference>[]
        : state.previousBalanceReferencesForSeller(
            _seller!.id,
            excludingPurchaseId: original.id,
          );
    var availablePreviousBalance = original == null
        ? 0.0
        : roundMoneyValue(
            previousReferences.fold<double>(
              0,
              (runningTotal, item) => runningTotal + item.balanceAmount,
            ),
          );
    if (availablePreviousBalance.abs() <= 0.01 &&
        original != null &&
        original.previousBalanceAppliedAmount.abs() > 0.01 &&
        _seller!.id == original.seller.id) {
      availablePreviousBalance = original.previousBalanceAppliedAmount;
    }
    final previousBalanceAppliedAmount =
        original != null &&
            _previousBalanceAction == _PreviousBalanceAction.apply
        ? availablePreviousBalance
        : 0.0;
    final previousReferenceIds =
        original != null &&
            _previousBalanceAction == _PreviousBalanceAction.apply
        ? (previousReferences.isEmpty
              ? original.previousBalanceReferenceIds
              : previousReferences.map((item) => item.purchaseId).toList())
        : <String>[];
    final originalBillAmount = original != null && !_itemsChanged
        ? original.originalBillAmount
        : roundMoneyValue(
            itemsForSave.fold<double>(
              0,
              (runningTotal, item) =>
                  runningTotal + item.componentOriginalAmount,
            ),
          );
    final paidAmount = _read(_paid);
    final billBeforeSettlement = roundMoneyValue(
      originalBillAmount + previousBalanceAppliedAmount,
    );
    final currentBillDifference = roundMoneyValue(
      billBeforeSettlement - paidAmount,
    );
    final currentSettlementAdjustmentAmount =
        original != null &&
            _settlementAction == _CurrentBillSettlementAction.settleNow &&
            currentBillDifference.abs() > 0.01
        ? roundMoneyValue(paidAmount - billBeforeSettlement)
        : 0.0;
    final finalBillAmount = roundMoneyValue(
      billBeforeSettlement + currentSettlementAdjustmentAmount,
    );
    if (finalBillAmount < -0.01) {
      _snack(context, 'Final bill amount cannot be negative.');
      if (fromVoice) {
        await _speakVoice('Final bill amount cannot be negative');
      }
      return;
    }
    final settlementStatus = original == null
        ? 'carry_forward'
        : _settlementAction == _CurrentBillSettlementAction.settleNow
        ? 'settled_current_difference'
        : switch (_previousBalanceAction) {
            _PreviousBalanceAction.apply => 'previous_balance_applied',
            _PreviousBalanceAction.keepForLater => 'carry_forward',
            _PreviousBalanceAction.settleSeparately => 'settle_separately',
          };
    final purchase = original == null
        ? notifier.addPurchase(
            seller: _seller!,
            items: itemsForSave,
            paidAmount: paidAmount,
            purchaseDate: _purchaseDate,
            createdBy: state.user.role.isOwnerOrAdmin
                ? _createdBy
                : state.user.name,
            remarks: _remarks.text,
            previousBalanceAppliedAmount: previousBalanceAppliedAmount,
            previousBalanceReferenceIds: previousReferenceIds,
            currentSettlementAdjustmentAmount:
                currentSettlementAdjustmentAmount,
            settlementStatus: settlementStatus,
          )
        : notifier.editPurchase(
            original: original,
            seller: _seller!,
            items: itemsForSave,
            paidAmount: paidAmount,
            purchaseDate: _purchaseDate,
            createdBy: state.user.role.isOwnerOrAdmin
                ? _createdBy
                : state.user.name,
            remarks: _remarks.text,
            originalBillAmount: originalBillAmount,
            previousBalanceAppliedAmount: previousBalanceAppliedAmount,
            previousBalanceReferenceIds: previousReferenceIds,
            currentSettlementAdjustmentAmount:
                currentSettlementAdjustmentAmount,
            settlementStatus: settlementStatus,
          );
    if (fromVoice) {
      notifier.recordVoiceActivity(
        'voice_purchase_saved',
        '${purchase.invoiceNumber} ${purchase.seller.name}',
      );
      await _speakVoice('Purchase saved successfully');
    }
    if (!mounted) {
      return;
    }
    if (original == null) {
      await _showPurchaseSavedDialog(purchase);
    } else {
      _snack(context, '${purchase.invoiceNumber} saved');
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _showPurchaseSavedDialog(PurchaseRecord purchase) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Purchase Saved Successfully'),
        content: Text(
          '${purchase.invoiceNumber}\n${purchase.seller.name}\nDate: ${DateFormat('dd MMM yyyy').format(purchase.createdAt)}\n${kg(purchase.totalWeightKg)} | ${money(purchase.totalAmount)}',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await sharePurchaseInvoicePdf(
                context,
                ref,
                purchase,
                shareMethod: 'WhatsApp Seller',
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Send Invoice PDF'),
          ),
        ],
      ),
    );
  }

  void _setVoiceState(String status, {bool listening = false}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceStatus = status;
      _voiceListening = listening;
    });
  }

  Future<void> _speakVoice(String message) async {
    await _purchaseTts.stop();
    await _purchaseTts.speak(message);
  }

  Future<void> _speakPurchaseVoiceHelp() => _speakVoice(_purchaseVoiceHelpText);

  Future<void> _confirmResetUnsavedForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear unsaved purchase?'),
        content: const Text(
          'Only this unsaved form will be cleared. Saved bills are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      _setVoiceState('Ready');
      return;
    }
    setState(() {
      _seller = null;
      _paid.clear();
      _remarks.clear();
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..add(LineDraft());
      _itemsChanged = true;
      _previousBalanceAction = _PreviousBalanceAction.keepForLater;
      _settlementAction = _CurrentBillSettlementAction.carryForward;
      _voiceStatus = 'Ready';
      _voiceListening = false;
    });
    await _speakVoice('Form cleared');
  }
}

class _PreviousBalanceReferenceRow extends StatelessWidget {
  const _PreviousBalanceReferenceRow({required this.reference});

  final SellerBalanceReference reference;

  @override
  Widget build(BuildContext context) {
    final positive = reference.balanceAmount > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (positive ? EnterpriseTheme.warning : EnterpriseTheme.success)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (positive ? EnterpriseTheme.warning : EnterpriseTheme.success)
              .withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${reference.invoiceNumber} | ${DateFormat('dd MMM yyyy').format(reference.date)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                reference.actionLabel,
                style: TextStyle(
                  color: positive
                      ? EnterpriseTheme.warning
                      : EnterpriseTheme.success,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AmountLine(
            label: 'Previous bill amount',
            value: money(reference.originalBillAmount),
          ),
          AmountLine(label: 'Paid amount', value: money(reference.paidAmount)),
          AmountLine(
            label: 'Balance amount',
            value: positive
                ? money(reference.balanceAmount)
                : 'Advance ${money(reference.balanceAmount.abs())}',
            color: positive ? EnterpriseTheme.warning : EnterpriseTheme.success,
          ),
        ],
      ),
    );
  }
}

const _purchaseVoiceHelpText =
    'New Purchase screen. You can say seller name, material, weight, rate, paid amount, clear purchase, add item, save purchase.';

bool _isVoiceSaveCommand(String command) {
  final text = normalizeSmartVoiceCommand(command);
  return text == 'save' ||
      text.contains('save purchase') ||
      text.contains('purchase save');
}

double? _purchaseVoiceNumber(String command, List<String> labels) {
  final text = normalizeSmartVoiceCommand(command);
  for (final label in labels) {
    final match = RegExp(
      '\\b${RegExp.escape(label)}\\b\\s*(?:is|hai|rs|rupees|rupaye|inr)?\\s*(\\d+(?:\\.\\d+)?)',
    ).firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
  }
  return null;
}

String _purchaseVoiceField(
  String command,
  List<String> labels, {
  required List<String> stopLabels,
}) {
  final text = normalizeSmartVoiceCommand(command);
  for (final label in labels) {
    final match = RegExp(
      '\\b${RegExp.escape(label)}\\b\\s+(.+)',
    ).firstMatch(text);
    if (match == null) {
      continue;
    }
    var value = match.group(1)!.trim();
    for (final stop in stopLabels) {
      final stopMatch = RegExp(
        '\\b${RegExp.escape(stop)}\\b',
      ).firstMatch(value);
      if (stopMatch != null) {
        value = value.substring(0, stopMatch.start).trim();
      }
    }
    value = value
        .replaceAll(RegExp(r'\b(is|hai|ko|se|from|select|search)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _voiceNumberString(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

class SaleEditorScreen extends ConsumerStatefulWidget {
  const SaleEditorScreen({super.key, this.sale, this.initialCreatedBy});

  final SaleRecord? sale;
  final String? initialCreatedBy;

  @override
  ConsumerState<SaleEditorScreen> createState() => _SaleEditorScreenState();
}

class _SaleEditorScreenState extends ConsumerState<SaleEditorScreen> {
  final _received = TextEditingController();
  final _remarks = TextEditingController();
  final _lines = <SaleLineDraft>[];
  Party? _customer;
  DateTime _saleDate = DateTime.now();
  String _createdBy = '';

  bool get _editing => widget.sale != null;

  @override
  void initState() {
    super.initState();
    final initialCreator = widget.initialCreatedBy?.trim() ?? '';
    _createdBy = initialCreator.isNotEmpty
        ? initialCreator
        : ref.read(businessProvider).user.name;
    final sale = widget.sale;
    if (sale == null) {
      _lines.add(SaleLineDraft());
      return;
    }
    _customer = sale.customer;
    _saleDate = sale.createdAt;
    _createdBy = sale.createdBy.trim().isEmpty
        ? ref.read(businessProvider).user.name
        : sale.createdBy.trim();
    _received.text = sale.receivedAmount.toStringAsFixed(0);
    _remarks.text = sale.remarks;
    _lines.addAll(sale.items.map(SaleLineDraft.fromItem));
    if (_lines.isEmpty) {
      _lines.add(SaleLineDraft());
    }
  }

  @override
  void dispose() {
    _received.dispose();
    _remarks.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final staffNames = _cashStaffNameOptions(state, _createdBy);
    final selectedCreator = staffNames.contains(_createdBy.trim())
        ? _createdBy.trim()
        : staffNames.contains(state.user.name.trim())
        ? state.user.name.trim()
        : staffNames.first;
    _createdBy = selectedCreator;
    final amount = _lines.fold<double>(
      0,
      (runningTotal, line) => runningTotal + line.amount,
    );
    final balance = amount - _read(_received);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Sale' : 'New Sale')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PartyDropdown(
              label: 'Customer',
              value: _customer,
              items: state.customers,
              emptyLabel: 'Add customer',
              onAdd: () async {
                final created = await showPartyEditor(
                  context,
                  ref,
                  PartyKind.customer,
                );
                if (created != null) {
                  setState(() => _customer = created);
                }
              },
              onChanged: (value) => setState(() => _customer = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickSaleDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Sale Date: ${DateFormat('dd MMM yyyy').format(_saleDate)}',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select any sale date: 2 years back to 2 years future.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCreator,
              decoration: const InputDecoration(
                labelText: 'Sale Added By',
                helperText:
                    'Default is login user. Owner can correct staff name.',
              ),
              items: staffNames
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: isOwner
                  ? (value) =>
                        setState(() => _createdBy = value ?? selectedCreator)
                  : null,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _lines.length; index++) ...[
              SaleLineEditor(
                index: index,
                line: _lines[index],
                materials: state.activeMaterials,
                isOwner: isOwner,
                pricing: const SmartPricingService().suggestFor(
                  state,
                  _lines[index].material,
                ),
                onChanged: () => setState(() {}),
                onRemove: () => _removeLine(index),
                onAddMaterial: () async {
                  final created = await showMaterialEditor(context, ref);
                  if (created != null) {
                    setState(() => _lines[index].setMaterial(created));
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _lines.add(SaleLineDraft()));
                ref.read(businessProvider.notifier).recordSaleItemAdded();
              },
              icon: const Icon(Icons.add),
              label: const Text('+ Add Item'),
            ),
            if (isOwner) ...[
              const SizedBox(height: 12),
              NumberText(
                controller: _received,
                label: 'Paid Amount',
                onChanged: () => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            if (isOwner) ...[
              const SizedBox(height: 12),
              FeaturePanel(
                child: Column(
                  children: [
                    AmountLine(label: 'Invoice Amount', value: money(amount)),
                    AmountLine(
                      label: 'Pending',
                      value: money(balance.clamp(0, double.infinity)),
                      color: balance > 0
                          ? EnterpriseTheme.error
                          : EnterpriseTheme.success,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.receipt_long),
              label: Text(_editing ? 'Update Sale' : 'Save Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSaleDate() async {
    final now = DateTime.now();
    final firstAllowedDate = DateTime(now.year - 2, now.month, now.day);
    final lastAllowedDate = DateTime(now.year + 2, now.month, now.day);
    final initialAllowedDate = _saleDate.isBefore(firstAllowedDate)
        ? firstAllowedDate
        : _saleDate.isAfter(lastAllowedDate)
        ? lastAllowedDate
        : _saleDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialAllowedDate,
      firstDate: firstAllowedDate,
      lastDate: lastAllowedDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(
      () => _saleDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        now.hour,
        now.minute,
        now.second,
      ),
    );
  }

  void _removeLine(int index) {
    setState(() {
      final removed = _lines.removeAt(index);
      final materialName = removed.material?.name ?? 'Item ${index + 1}';
      removed.dispose();
      if (_lines.isEmpty) {
        _lines.add(SaleLineDraft());
      }
      ref
          .read(businessProvider.notifier)
          .recordSaleItemRemoved(materialName: materialName);
    });
  }

  Future<void> _save() async {
    final isOwner = ref.read(businessProvider).user.role.isOwnerOrAdmin;
    if (_customer == null) {
      _snack(context, 'Select customer.');
      return;
    }
    final items = _lines
        .map((line) => line.toItem())
        .whereType<LineItem>()
        .toList();
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final itemNumber = index + 1;
      if (line.material == null) {
        _snack(context, 'Select material for item $itemNumber.');
        return;
      }
      if (_read(line.weight) <= 0) {
        _snack(context, 'Weight must be greater than 0 for item $itemNumber.');
        return;
      }
      if (_read(line.rate) <= 0) {
        _snack(
          context,
          isOwner
              ? 'Rate must be greater than 0 for item $itemNumber.'
              : 'Sale rate is not configured for item $itemNumber. Contact owner.',
        );
        return;
      }
    }
    if (items.isEmpty) {
      _snack(context, 'Add at least one valid material line.');
      return;
    }
    if (_read(_received) < 0) {
      _snack(context, 'Paid amount cannot be negative.');
      return;
    }
    final notifier = ref.read(businessProvider.notifier);
    final original = widget.sale;
    if (original != null && !notifier.canModifySale(original)) {
      _snack(context, notifier.saleEditExpiredMessage(original));
      return;
    }
    final sale = original == null
        ? notifier.addSaleItems(
            customer: _customer!,
            items: items,
            receivedAmount: _read(_received),
            saleDate: _saleDate,
            createdBy: ref.read(businessProvider).user.role.isOwnerOrAdmin
                ? _createdBy
                : ref.read(businessProvider).user.name,
            remarks: _remarks.text,
          )
        : notifier.editSale(
            original: original,
            customer: _customer!,
            items: items,
            receivedAmount: _read(_received),
            saleDate: _saleDate,
            createdBy: ref.read(businessProvider).user.role.isOwnerOrAdmin
                ? _createdBy
                : ref.read(businessProvider).user.name,
            remarks: _remarks.text,
          );
    if (!mounted) {
      return;
    }
    _snack(context, '${sale.invoiceNumber} saved');
    await _showSaleSavedDialog(sale);
  }

  Future<void> _showSaleSavedDialog(SaleRecord sale) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${sale.invoiceNumber} saved'),
        content: Text(
          ref.read(businessProvider).user.role.isOwnerOrAdmin
              ? '${sale.customer.name}\nInvoice Amount: ${money(sale.totalAmount)}'
              : '${sale.customer.name}\n${kg(sale.totalWeightKg)} saved',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
          if (ref.read(businessProvider).user.role.isOwnerOrAdmin) ...[
            OutlinedButton.icon(
              onPressed: () => shareSalesInvoicePdf(context, ref, sale),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Invoice PDF'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await _sendSaleWhatsAppToRecipients(context, ref, sale);
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  navigator.pop();
                }
              },
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
          ],
        ],
      ),
    );
  }
}

class SaleLineEditor extends StatelessWidget {
  const SaleLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.materials,
    required this.isOwner,
    required this.pricing,
    required this.onChanged,
    required this.onAddMaterial,
    required this.onRemove,
  });

  final int index;
  final SaleLineDraft line;
  final List<MaterialStock> materials;
  final bool isOwner;
  final SmartPricingSuggestion? pricing;
  final VoidCallback onChanged;
  final Future<void> Function() onAddMaterial;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          MaterialDropdown(
            label: 'Material',
            value: line.material,
            materials: materials,
            onAdd: onAddMaterial,
            onChanged: (value) {
              line.setMaterial(value);
              onChanged();
            },
          ),
          if (line.material != null) ...[
            const SizedBox(height: 10),
            MaterialSnapshot(material: line.material!),
          ],
          const SizedBox(height: 10),
          if (isOwner)
            Row(
              children: [
                Expanded(
                  child: NumberText(
                    controller: line.weight,
                    label: 'Weight (KG)',
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumberText(
                    controller: line.rate,
                    label: 'Rate / KG',
                    onChanged: onChanged,
                  ),
                ),
              ],
            )
          else
            NumberText(
              controller: line.weight,
              label: 'Weight (KG)',
              onChanged: onChanged,
            ),
          if (isOwner) ...[
            const SizedBox(height: 8),
            AmountLine(label: 'Item Total', value: money(line.amount)),
            if (pricing != null) ...[
              AmountLine(
                label: 'Suggested Selling Rate',
                value: money(pricing!.suggestedSellingRate),
              ),
              AmountLine(
                label: 'Minimum Safe Rate',
                value: money(pricing!.safeMinimumSellingRate),
                color: pricing!.isBelowSafeRate(_read(line.rate))
                    ? EnterpriseTheme.error
                    : EnterpriseTheme.success,
              ),
              if (pricing!.isBelowSafeRate(_read(line.rate))) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: EnterpriseTheme.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: EnterpriseTheme.error.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    'Low profit warning: margin ${pricing!.marginPercentAt(_read(line.rate)).toStringAsFixed(1)}%. Review before saving.',
                    style: const TextStyle(
                      color: EnterpriseTheme.error,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class SaleLineDraft {
  SaleLineDraft();

  SaleLineDraft.fromItem(LineItem item) {
    material = MaterialStock(
      id: item.materialId,
      name: item.materialName,
      category: 'Selected',
      availableKg: 0,
      currentBuyingRate: item.rate,
      currentSellingRate: item.rate,
      photoPath: item.materialPhotoPath,
    );
    weight.text = item.weightKg.toStringAsFixed(0);
    rate.text = item.rate.toStringAsFixed(0);
  }

  MaterialStock? material;
  final weight = TextEditingController();
  final rate = TextEditingController();

  double get amount => _read(weight) * _read(rate);

  void setMaterial(MaterialStock? value) {
    material = value;
    if (value != null) {
      rate.text = _sellingRateFor(value).toStringAsFixed(0);
    }
  }

  LineItem? toItem() {
    final selected = material;
    final weightKg = _read(weight);
    final itemRate = _read(rate);
    if (selected == null || weightKg <= 0 || itemRate <= 0) {
      return null;
    }
    return LineItem(
      materialId: selected.id,
      materialName: selected.name,
      materialPhotoPath: selected.photoPath,
      weightKg: weightKg,
      effectiveWeight: weightKg,
      rate: itemRate,
    );
  }

  void dispose() {
    weight.dispose();
    rate.dispose();
  }
}

class DashboardDetailScreen extends ConsumerStatefulWidget {
  const DashboardDetailScreen({
    super.key,
    required this.metricKey,
    required this.title,
  });

  final String metricKey;
  final String title;

  @override
  ConsumerState<DashboardDetailScreen> createState() =>
      _DashboardDetailScreenState();
}

class _DashboardDetailScreenState extends ConsumerState<DashboardDetailScreen> {
  String _filter = 'Today';
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final table = _tableFor(state);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          FilterStrip(
            value: _filter,
            onChanged: (value) async {
              if (_isCustomFilter(value)) {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (range != null) {
                  _from = range.start;
                  _to = range.end;
                }
              }
              setState(() => _filter = value);
            },
          ),
          ExportBar(title: widget.title, table: table),
          Expanded(
            child: DataList(
              headers: table.headers,
              rows: table.rows,
              footerRows: table.footerRows,
            ),
          ),
        ],
      ),
    );
  }

  ReportTable _tableFor(BusinessState state) {
    switch (widget.metricKey) {
      case 'todayPurchase':
        return _purchaseReportTable(_filterPurchases(state.activePurchases));
      case 'todaySales':
        final sales = _filterSales(state.activeSales);
        final isOwner = state.user.role.isOwnerOrAdmin;
        if (!isOwner) {
          final rows = [
            for (final sale in sales)
              for (final item in sale.items)
                [
                  sale.invoiceNumber,
                  sale.customer.name,
                  item.materialName,
                  kg(item.weightKg),
                  kg(sale.totalWeightKg),
                  shortDate(sale.createdAt),
                ],
          ];
          final totalWeight = sales.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.totalWeightKg,
          );
          return ReportTable(
            headers: const [
              'Invoice No',
              'Customer',
              'Material',
              'Item Weight',
              'Total Invoice Weight',
              'Date',
            ],
            rows: rows,
            footerRows: rows.isEmpty
                ? const []
                : [
                    [
                      'Grand Total',
                      '',
                      '',
                      kg(totalWeight),
                      kg(totalWeight),
                      '',
                    ],
                  ],
            landscape: true,
            columnFlex: const [1.4, 1.7, 1.5, 1, 1, 1.1],
          );
        }
        final rows = [
          for (final sale in sales)
            for (final item in sale.items)
              [
                sale.invoiceNumber,
                sale.customer.name,
                item.materialName,
                kg(item.weightKg),
                money(item.rate),
                money(item.amount),
                kg(sale.totalWeightKg),
                money(sale.totalAmount),
                money(sale.receivedAmount),
                money(sale.balanceAmount),
                shortDate(sale.createdAt),
              ],
        ];
        final totalWeight = sales.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.totalWeightKg,
        );
        final totalAmount = sales.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.totalAmount,
        );
        final totalPaid = sales.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.receivedAmount,
        );
        final totalBalance = sales.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.balanceAmount,
        );
        return ReportTable(
          headers: const [
            'Invoice No',
            'Customer',
            'Material',
            'Item Weight',
            'Rate / KG',
            'Item Amount',
            'Total Invoice Weight',
            'Total Invoice Amount',
            'Paid Amount',
            'Balance',
            'Date',
          ],
          rows: rows,
          footerRows: rows.isEmpty
              ? const []
              : [
                  [
                    'Grand Total',
                    '',
                    '',
                    kg(totalWeight),
                    '',
                    money(totalAmount),
                    kg(totalWeight),
                    money(totalAmount),
                    money(totalPaid),
                    money(totalBalance),
                    '',
                  ],
                ],
          landscape: true,
          columnFlex: const [1.4, 1.7, 1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1.1],
        );
      case 'stockValue':
        return ReportTable(
          headers: const [
            'Material',
            'Quantity',
            'Current Buying Rate',
            'Selling Rate',
            'Stock Value',
          ],
          rows: [
            for (final item in state.activeMaterials)
              [
                item.name,
                kg(item.availableKg),
                money(item.currentBuyingRate),
                money(
                  item.currentSellingRate == 0
                      ? item.currentBuyingRate
                      : item.currentSellingRate,
                ),
                money(item.stockValue),
              ],
          ],
        );
      case 'profitLoss':
        return ReportTable(
          headers: const ['Metric', 'Value'],
          rows: [
            ['Purchase Cost', money(state.metrics.cashUsed)],
            ['Sales Collection', money(state.metrics.salesCollection)],
            ['Stock Profit Potential', money(state.metrics.profitLoss)],
            ['Profit / Loss', money(state.metrics.profitLoss)],
          ],
        );
      case 'pendingPayments':
        return ReportTable(
          headers: const ['Party', 'Type', 'Pending'],
          rows: [
            for (final item in state.sellers)
              [item.name, 'Seller', money(item.pendingAmount)],
            for (final item in state.customers)
              [item.name, 'Customer', money(item.pendingAmount)],
          ],
        );
      case 'cashWithSupervisor':
        return _supervisorCashLedgerTable(state);
      default:
        return _cashTable(state);
    }
  }

  ReportTable _cashTable(BusinessState state) {
    if (state.user.role.isOwnerOrAdmin) {
      final metrics = state.metrics;
      return ReportTable(
        headers: const [
          'Cash Given',
          'Cash Used',
          'Sales Collection',
          'Balance',
        ],
        rows: [
          [
            money(metrics.cashGiven),
            money(metrics.cashUsed),
            money(metrics.salesCollection),
            money(metrics.cashBalance),
          ],
        ],
      );
    }
    bool mine(String value) =>
        value.trim().toLowerCase() == state.user.name.trim().toLowerCase();
    final cashGiven = state.visibleCashAllocations.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.amount,
    );
    final purchaseUsed = state.activePurchases
        .where((item) => mine(item.createdBy))
        .fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.totalAmount,
        );
    final expensesUsed = state.activeExpenses
        .where((item) => mine(item.addedBy))
        .fold<double>(0, (runningTotal, item) => runningTotal + item.amount);
    final balance = cashGiven - purchaseUsed - expensesUsed;
    return ReportTable(
      headers: const ['Cash Given', 'Cash Used', 'Balance'],
      rows: [
        [money(cashGiven), money(purchaseUsed + expensesUsed), money(balance)],
      ],
    );
  }

  List<PurchaseRecord> _filterPurchases(List<PurchaseRecord> rows) {
    return rows.where((item) => _dateInFilter(item.createdAt)).toList();
  }

  List<SaleRecord> _filterSales(List<SaleRecord> rows) {
    return rows.where((item) => _dateInFilter(item.createdAt)).toList();
  }

  bool _dateInFilter(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    switch (_filter) {
      case 'Yesterday':
        return target == today.subtract(const Duration(days: 1));
      case 'Weekly':
        return !target.isBefore(today.subtract(const Duration(days: 6)));
      case 'Monthly':
        return date.year == now.year && date.month == now.month;
      case 'Custom':
      case 'Custom Date Range':
        final from = _from;
        final to = _to;
        if (from == null || to == null) {
          return true;
        }
        return !date.isBefore(from) &&
            !date.isAfter(to.add(const Duration(days: 1)));
      case 'Since Beginning':
        return true;
      default:
        return target == today;
    }
  }
}

class SupervisorCashLedgerScreen extends ConsumerStatefulWidget {
  const SupervisorCashLedgerScreen({super.key});

  @override
  ConsumerState<SupervisorCashLedgerScreen> createState() =>
      _SupervisorCashLedgerScreenState();
}

class _SupervisorCashLedgerScreenState
    extends ConsumerState<SupervisorCashLedgerScreen> {
  bool _loggedView = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_recordView);
  }

  void _recordView() {
    if (!mounted || _loggedView) {
      return;
    }
    _loggedView = true;
    ref.read(businessProvider.notifier).recordCashWithSupervisorViewed();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final summaries = state.visibleSupervisorCashSummaries;
    final ledgerEntries = state.visibleSupervisorCashLedgerEntries;
    final table = _supervisorCashLedgerTable(state);
    final totalOpening = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.openingBalance,
    );
    final totalCashGiven = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.cashGivenByOwner,
    );
    final totalScrapPurchase = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.scrapPurchaseUsed,
    );
    final totalOtherExpenses = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.otherExpenses,
    );
    final totalSalesCollection = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.salesCollection,
    );
    final totalCurrentCash = summaries.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.currentCashBalance,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Cash With Supervisor')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: FeaturePanel(
              child: Column(
                children: [
                  AmountLine(
                    label: state.user.role.isOwnerOrAdmin
                        ? 'Total Current Cash With Supervisors'
                        : 'Your Current Cash Balance',
                    value: money(totalCurrentCash),
                    color: totalCurrentCash >= 0
                        ? EnterpriseTheme.success
                        : EnterpriseTheme.error,
                  ),
                  AmountLine(
                    label: 'Opening Balance',
                    value: money(totalOpening),
                  ),
                  AmountLine(
                    label: 'Cash Given by Owner',
                    value: money(totalCashGiven),
                  ),
                  if (isOwner)
                    AmountLine(
                      label: 'Sales Collection',
                      value: money(totalSalesCollection),
                    ),
                  AmountLine(
                    label: 'Scrap Purchase Used',
                    value: money(totalScrapPurchase),
                  ),
                  AmountLine(
                    label: 'Other Expenses',
                    value: money(totalOtherExpenses),
                  ),
                ],
              ),
            ),
          ),
          ExportBar(title: 'Cash With Supervisor', table: table),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  state.user.role.isOwnerOrAdmin
                      ? 'Supervisor-wise cash available'
                      : 'Your cash available',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                if (summaries.isEmpty)
                  const FeaturePanel(
                    child: EmptyFeatureState(
                      icon: Icons.account_balance_wallet,
                      title: 'No supervisor cash records',
                      subtitle:
                          'Cash allocations, purchases, expenses, and sales collections will appear here.',
                    ),
                  )
                else
                  for (final item in summaries) ...[
                    _SupervisorCashSummaryCard(
                      summary: item,
                      showSalesCollection: isOwner,
                      onWhatsApp: () =>
                          _sendCashSummaryWhatsApp(context, ref, state, item),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 8),
                const Text(
                  'Date-wise ledger',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 10),
                if (ledgerEntries.isEmpty)
                  const FeaturePanel(
                    child: EmptyFeatureState(
                      icon: Icons.table_rows,
                      title: 'No ledger entries',
                      subtitle:
                          'Supervisor cash movement will be listed date-wise.',
                    ),
                  )
                else
                  for (final entry in ledgerEntries) ...[
                    _SupervisorCashLedgerEntryCard(
                      entry: entry,
                      showSalesCollection: isOwner,
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupervisorCashSummaryCard extends StatelessWidget {
  const _SupervisorCashSummaryCard({
    required this.summary,
    required this.showSalesCollection,
    this.onWhatsApp,
  });

  final SupervisorCashSummary summary;
  final bool showSalesCollection;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary.supervisorName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                money(summary.currentCashBalance),
                style: TextStyle(
                  color: summary.currentCashBalance >= 0
                      ? EnterpriseTheme.success
                      : EnterpriseTheme.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          AmountLine(
            label: 'Opening Balance',
            value: money(summary.openingBalance),
          ),
          AmountLine(
            label: 'Cash Given by Owner',
            value: money(summary.cashGivenByOwner),
          ),
          AmountLine(
            label: 'Scrap Purchase Used',
            value: money(summary.scrapPurchaseUsed),
          ),
          AmountLine(
            label: 'Other Expenses',
            value: money(summary.otherExpenses),
          ),
          if (showSalesCollection)
            AmountLine(
              label: 'Sales Collection',
              value: money(summary.salesCollection),
            ),
          AmountLine(
            label: 'Current Cash Balance',
            value: money(summary.currentCashBalance),
            color: summary.currentCashBalance >= 0
                ? EnterpriseTheme.success
                : EnterpriseTheme.error,
          ),
          if (onWhatsApp != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onWhatsApp,
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupervisorCashLedgerEntryCard extends StatelessWidget {
  const _SupervisorCashLedgerEntryCard({
    required this.entry,
    required this.showSalesCollection,
  });

  final SupervisorCashLedgerEntry entry;
  final bool showSalesCollection;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.activityType,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${shortDate(entry.date)} | ${entry.supervisorName}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                money(entry.currentCashBalance),
                style: TextStyle(
                  color: entry.currentCashBalance >= 0
                      ? EnterpriseTheme.success
                      : EnterpriseTheme.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          AmountLine(
            label: 'Opening Balance',
            value: money(entry.openingBalance),
          ),
          AmountLine(
            label: 'Cash Given by Owner',
            value: money(entry.cashGivenByOwner),
          ),
          AmountLine(
            label: 'Scrap Purchase Used',
            value: money(entry.scrapPurchaseUsed),
          ),
          AmountLine(
            label: 'Other Expenses',
            value: money(entry.otherExpenses),
          ),
          if (showSalesCollection)
            AmountLine(
              label: 'Sales Collection',
              value: money(entry.salesCollection),
            ),
          AmountLine(
            label: 'Current Cash Balance',
            value: money(entry.currentCashBalance),
            color: entry.currentCashBalance >= 0
                ? EnterpriseTheme.success
                : EnterpriseTheme.error,
          ),
          if (entry.details.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entry.details,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

ReportTable _supervisorCashLedgerTable(BusinessState state) {
  final showSalesCollection = state.user.role.isOwnerOrAdmin;
  final headers = [
    'Date',
    'Supervisor',
    'Activity',
    'Opening Balance',
    'Cash Given by Owner',
    'Scrap Purchase Used',
    'Other Expenses',
    if (showSalesCollection) 'Sales Collection',
    'Current Cash Balance',
    'Details',
  ];
  final summaries = state.visibleSupervisorCashSummaries;
  final rows = [
    for (final entry in state.visibleSupervisorCashLedgerEntries)
      [
        shortDate(entry.date),
        entry.supervisorName,
        entry.activityType,
        money(entry.openingBalance),
        money(entry.cashGivenByOwner),
        money(entry.scrapPurchaseUsed),
        money(entry.otherExpenses),
        if (showSalesCollection) money(entry.salesCollection),
        money(entry.currentCashBalance),
        entry.details,
      ],
  ];
  final footer = [
    'Grand Total',
    'All Supervisors',
    '',
    money(
      summaries.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.openingBalance,
      ),
    ),
    money(
      summaries.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.cashGivenByOwner,
      ),
    ),
    money(
      summaries.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.scrapPurchaseUsed,
      ),
    ),
    money(
      summaries.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.otherExpenses,
      ),
    ),
    if (showSalesCollection)
      money(
        summaries.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.salesCollection,
        ),
      ),
    money(
      summaries.fold<double>(
        0,
        (runningTotal, item) => runningTotal + item.currentCashBalance,
      ),
    ),
    '',
  ];

  return ReportTable(
    headers: headers,
    rows: rows,
    footerRows: summaries.isEmpty ? const [] : [footer],
    landscape: true,
    columnFlex: showSalesCollection
        ? const [1, 1.35, 1.35, 1, 1.1, 1.1, 1, 1, 1.15, 1.8]
        : const [1, 1.35, 1.35, 1, 1.1, 1.1, 1, 1.15, 1.8],
  );
}

class CashLedgerScreen extends ConsumerWidget {
  const CashLedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    bool mine(String value) =>
        value.trim().toLowerCase() == state.user.name.trim().toLowerCase();
    final cashAllocations = isOwner
        ? state.cashAllocations
        : state.visibleCashAllocations;
    final purchases = isOwner
        ? state.activePurchases
        : state.activePurchases.where((item) => mine(item.createdBy));
    final Iterable<SaleRecord> sales = isOwner
        ? state.activeSales
        : const <SaleRecord>[];
    final expenses = isOwner
        ? state.activeExpenses
        : state.activeExpenses.where((item) => mine(item.addedBy));
    final totalCashGiven = cashAllocations.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.amount,
    );
    final totalPurchaseAmount = purchases.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.totalAmount,
    );
    final totalExpenseAmount = expenses.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.amount,
    );
    final totalSalesCollection = sales.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.receivedAmount,
    );
    final netBalance =
        totalCashGiven - totalPurchaseAmount - totalExpenseAmount;
    final rows = <List<String>>[
      for (final item in cashAllocations)
        [
          shortDate(item.date),
          money(item.amount),
          money(0),
          money(0),
          item.supervisorName,
        ],
      for (final item in purchases)
        [
          shortDate(item.createdAt),
          money(0),
          money(item.totalAmount),
          money(0),
          item.seller.name,
        ],
      for (final item in expenses)
        [
          shortDate(item.date),
          money(0),
          money(item.amount),
          money(0),
          '${item.addedBy} - ${item.category}',
        ],
      for (final item in sales)
        [
          shortDate(item.createdAt),
          money(0),
          money(0),
          money(item.receivedAmount),
          item.customer.name,
        ],
    ];
    rows.sort((a, b) => b.first.compareTo(a.first));

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Ledger')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => showCashAllocationDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Cash Allocation'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FeaturePanel(
              child: Column(
                children: [
                  AmountLine(
                    label: 'Total Cash Given',
                    value: money(totalCashGiven),
                  ),
                  AmountLine(
                    label: 'Total Cash Used',
                    value: money(totalPurchaseAmount + totalExpenseAmount),
                  ),
                  if (isOwner)
                    AmountLine(
                      label: 'Total Sales',
                      value: money(totalSalesCollection),
                    ),
                  AmountLine(
                    label: 'Net Balance',
                    value: money(netBalance),
                    color: netBalance >= 0
                        ? EnterpriseTheme.success
                        : EnterpriseTheme.error,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: DataList(
              headers: isOwner
                  ? const [
                      'Date',
                      'Cash Given',
                      'Purchase Amount',
                      'Sales Collection',
                      'Balance/Party',
                    ]
                  : const [
                      'Date',
                      'Cash Given',
                      'Purchase Amount',
                      'Balance/Party',
                    ],
              rows: isOwner
                  ? rows
                  : [
                      for (final row in rows) [row[0], row[1], row[2], row[4]],
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

class CashAllocationScreen extends ConsumerStatefulWidget {
  const CashAllocationScreen({super.key});

  @override
  ConsumerState<CashAllocationScreen> createState() =>
      _CashAllocationScreenState();
}

class _CashAllocationScreenState extends ConsumerState<CashAllocationScreen> {
  String _query = '';
  String _mode = 'All';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final canManage = isOwner || state.user.role == UserRole.manager;
    final allocations = state.visibleCashAllocations.where((item) {
      final query = _query.toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          item.supervisorName.toLowerCase().contains(query) ||
          item.remarks.toLowerCase().contains(query);
      final matchesMode = _mode == 'All' || item.paymentMode == _mode;
      return matchesQuery && matchesMode;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Allocation')),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => showCashAllocationDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Entry'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search supervisor/manager or remarks',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(labelText: 'Mode'),
                        items: ['All', ..._paymentModes]
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _mode = value ?? _mode),
                      ),
                    ),
                  ],
                ),
                if (isOwner) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              showCashAllocationDialog(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('Allocate Cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              showStaffNameCorrectionDialog(context, ref),
                          icon: const Icon(Icons.manage_accounts),
                          label: const Text('Correct Name'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: allocations.isEmpty
                ? const EmptyFeatureState(
                    icon: Icons.payments,
                    title: 'No cash allocations',
                    subtitle: 'Add supervisor cash entries with date and mode.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: allocations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = allocations[index];
                      return FeaturePanel(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.payments),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.supervisorName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        '${shortDate(item.date)}  |  ${item.paymentMode}  |  Added by ${item.createdBy}',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  money(item.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            if (item.remarks.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(item.remarks),
                              ),
                            ],
                            if (canManage) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => showCashAllocationDialog(
                                        context,
                                        ref,
                                        existing: item,
                                      ),
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Edit'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _confirmAction(
                                        context,
                                        title: 'Delete Cash Allocation?',
                                        message:
                                            '${item.supervisorName} ${money(item.amount)} will be permanently removed.',
                                        confirmLabel: 'Delete',
                                        onConfirm: () => ref
                                            .read(businessProvider.notifier)
                                            .deleteCashAllocation(item),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SupervisorExpenseScreen extends ConsumerStatefulWidget {
  const SupervisorExpenseScreen({super.key});

  @override
  ConsumerState<SupervisorExpenseScreen> createState() =>
      _SupervisorExpenseScreenState();
}

class _SupervisorExpenseScreenState
    extends ConsumerState<SupervisorExpenseScreen> {
  String _query = '';
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final expenses = state.activeExpenses.where((item) {
      final query = _query.toLowerCase();
      final matchesQuery =
          query.isEmpty ||
          item.category.toLowerCase().contains(query) ||
          item.vendorName.toLowerCase().contains(query) ||
          item.addedBy.toLowerCase().contains(query) ||
          item.remarks.toLowerCase().contains(query);
      final matchesCategory = _category == 'All' || item.category == _category;
      return matchesQuery && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Supervisor Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search expenses',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: ['All', ..._expenseCategories]
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: expenses.isEmpty
                ? const EmptyFeatureState(
                    icon: Icons.receipt_long,
                    title: 'No expenses',
                    subtitle: 'Record supervisor purchases and expense bills.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: expenses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = expenses[index];
                      return FeaturePanel(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                EntityAvatar(
                                  path: item.photoPath,
                                  icon: Icons.receipt_long,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.category,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        '${shortDate(item.date)}  |  ${item.vendorName.isEmpty ? 'No vendor' : item.vendorName}  |  ${item.addedBy}',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  money(item.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => showRecordDetails(
                                      context,
                                      item.category,
                                      [
                                        ['Date', shortDate(item.date)],
                                        ['Amount', money(item.amount)],
                                        ['Vendor', item.vendorName],
                                        ['Remarks', item.remarks],
                                        ['Bill', item.billUploadPath],
                                        ['Photo', item.photoPath],
                                        ['Added By', item.addedBy],
                                        ['Created', shortDate(item.createdAt)],
                                        [
                                          'Updated',
                                          item.updatedAt == null
                                              ? '-'
                                              : shortDate(item.updatedAt!),
                                        ],
                                      ],
                                    ),
                                    icon: const Icon(Icons.history),
                                    label: const Text('History'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => showExpenseDialog(
                                      context,
                                      ref,
                                      existing: item,
                                    ),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Edit'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: 'Delete expense',
                                  onPressed: () => _confirmAction(
                                    context,
                                    title: 'Delete Expense?',
                                    message:
                                        '${item.category} ${money(item.amount)} will be removed from active reports.',
                                    confirmLabel: 'Delete',
                                    onConfirm: () => ref
                                        .read(businessProvider.notifier)
                                        .deleteExpense(item),
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SupervisorBalanceScreen extends ConsumerStatefulWidget {
  const SupervisorBalanceScreen({super.key});

  @override
  ConsumerState<SupervisorBalanceScreen> createState() =>
      _SupervisorBalanceScreenState();
}

class _SupervisorBalanceScreenState
    extends ConsumerState<SupervisorBalanceScreen> {
  String _filter = 'Since Beginning';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final rows = [
      for (final item in state.supervisorBalances)
        [
          item.supervisorName,
          money(item.cashAllocated),
          money(item.expenseTotal),
          money(item.scrapPurchaseTotal),
          money(item.otherPurchaseTotal),
          money(item.inventoryPurchaseTotal),
          money(item.remainingBalance),
        ],
    ];
    const headers = [
      'Supervisor',
      'Cash Given by Owner',
      'Total Expense',
      'Scrap Purchase',
      'Other Purchase',
      'Inventory Purchase',
      'Remaining Balance',
    ];
    final table = ReportTable(headers: headers, rows: rows);

    return Scaffold(
      appBar: AppBar(title: const Text('Supervisor Balance')),
      body: Column(
        children: [
          FilterStrip(
            value: _filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
          ExportBar(title: 'Supervisor Balance Report', table: table),
          Expanded(
            child: DataList(headers: headers, rows: rows),
          ),
        ],
      ),
    );
  }
}

class StockRegisterScreen extends ConsumerStatefulWidget {
  const StockRegisterScreen({super.key});

  @override
  ConsumerState<StockRegisterScreen> createState() =>
      _StockRegisterScreenState();
}

class _StockRegisterScreenState extends ConsumerState<StockRegisterScreen> {
  MaterialStock? _material;
  late DateTime _from;
  late DateTime _to;
  bool _reminderEnabled = false;
  List<TimeOfDay> _reminderTimes = const [TimeOfDay(hour: 9, minute: 0)];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month);
    _to = _stockDateOnly(now);
    Future.microtask(_loadReminderSettings);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    final materials = state.activeMaterials;
    final selected = _selectedMaterial(materials);
    final data = selected == null
        ? null
        : _buildStockRegisterData(state, selected, _from, _to);

    return Scaffold(
      appBar: AppBar(title: const Text('Analysis')),
      body: materials.isEmpty
          ? const EmptyFeatureState(
              icon: Icons.table_chart,
              title: 'No materials',
              subtitle: 'Add material to view analysis.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FeaturePanel(
                  child: Column(
                    children: [
                      MaterialDropdown(
                        label: 'Item',
                        value: selected,
                        materials: materials,
                        onAdd: () async {
                          final created = await showMaterialEditor(
                            context,
                            ref,
                          );
                          if (created != null && mounted) {
                            setState(() => _material = created);
                          }
                        },
                        onChanged: (value) => setState(() => _material = value),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickRangeDate(isFrom: true),
                              icon: const Icon(Icons.calendar_month),
                              label: Text('From ${_stockCompactDate(_from)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickRangeDate(isFrom: false),
                              icon: const Icon(Icons.event),
                              label: Text('To ${_stockCompactDate(_to)}'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (data != null) ...[
                  const SizedBox(height: 12),
                  _StockRegisterChart(data: data),
                  const SizedBox(height: 12),
                  _StockSummaryGrid(
                    data: data,
                    onPurchaseTap: () => _showPurchaseHistory(data),
                    onSaleTap: () => _showSaleHistory(data),
                  ),
                  const SizedBox(height: 12),
                  _StockRegisterTable(data: data),
                  if (isOwner) ...[
                    const SizedBox(height: 12),
                    _AutoReminderSettingsPanel(
                      enabled: _reminderEnabled,
                      times: _reminderTimes,
                      onEnabledChanged: _saveReminderEnabled,
                      onAddTime: _addReminderTime,
                      onRemoveTime: _removeReminderTime,
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  MaterialStock? _selectedMaterial(List<MaterialStock> materials) {
    if (materials.isEmpty) {
      return null;
    }
    final current = _material;
    if (current != null) {
      for (final item in materials) {
        if (item.id == current.id) {
          return item;
        }
      }
    }
    return materials.first;
  }

  Future<void> _pickRangeDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isFrom) {
        _from = _stockDateOnly(picked);
        if (_to.isBefore(_from)) {
          _to = _from;
        }
      } else {
        _to = _stockDateOnly(picked);
        if (_to.isBefore(_from)) {
          _from = _to;
        }
      }
    });
  }

  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _reminderEnabled =
          prefs.getBool(autoReminderEnabledPrefsKey) ?? _reminderEnabled;
      _reminderTimes = _reminderTimesFromPrefs(prefs);
    });
  }

  Future<void> _saveReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoReminderEnabledPrefsKey, value);
    if (!mounted) {
      return;
    }
    setState(() => _reminderEnabled = value);
    final label = _reminderTimes.map(_formatTimeOfDay).join(', ');
    if (value) {
      ref.read(businessProvider.notifier).recordAutoReminderScheduled(label);
      _snack(context, 'Local stock reminder notification enabled for $label.');
    } else {
      _snack(context, 'Local stock reminder notification disabled.');
    }
  }

  Future<void> _addReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTimes.isEmpty
          ? const TimeOfDay(hour: 9, minute: 0)
          : _reminderTimes.last,
    );
    if (picked == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final next = [..._reminderTimes, picked]..sort(_compareReminderTimes);
    await _saveReminderTimes(prefs, next);
    if (!mounted) {
      return;
    }
    setState(() => _reminderTimes = next);
    if (_reminderEnabled) {
      final label = next.map(_formatTimeOfDay).join(', ');
      ref.read(businessProvider.notifier).recordAutoReminderScheduled(label);
      _snack(context, 'Reminder times set to $label.');
    }
  }

  Future<void> _removeReminderTime(int index) async {
    if (index < 0 || index >= _reminderTimes.length) {
      return;
    }
    final next = [..._reminderTimes]..removeAt(index);
    if (next.isEmpty) {
      next.add(const TimeOfDay(hour: 9, minute: 0));
    }
    final prefs = await SharedPreferences.getInstance();
    await _saveReminderTimes(prefs, next);
    if (!mounted) {
      return;
    }
    setState(() => _reminderTimes = next);
    if (_reminderEnabled) {
      ref
          .read(businessProvider.notifier)
          .recordAutoReminderScheduled(next.map(_formatTimeOfDay).join(', '));
    }
  }

  void _showPurchaseHistory(_StockRegisterData data) {
    _showStockHistorySheet(
      context,
      title: '${data.material.name} Purchase History',
      headers: const [
        'Date',
        'Time',
        'Purchase Entry No',
        'Supplier / Given By',
        'Material Name',
        'Quantity KG',
        'Rate',
        'Amount',
        'Entered By',
        'Created Date-Time',
      ],
      rows: [
        for (final entry in data.purchaseHistory)
          [
            _stockTableDate(entry.createdAt),
            _stockTime(entry.createdAt),
            entry.referenceNo,
            entry.partyName,
            entry.materialName,
            kg(entry.quantityKg),
            money(entry.rate),
            money(entry.amount),
            entry.enteredBy,
            _stockDateTime(entry.createdAt),
          ],
      ],
    );
  }

  void _showSaleHistory(_StockRegisterData data) {
    final isOwner = ref.read(businessProvider).user.role.isOwnerOrAdmin;
    _showStockHistorySheet(
      context,
      title: '${data.material.name} Sale History',
      headers: isOwner
          ? const [
              'Date',
              'Time',
              'Invoice No',
              'Customer Name',
              'Material Name',
              'Quantity KG',
              'Rate',
              'Amount',
              'Entered By',
              'Created Date-Time',
            ]
          : const ['Date', 'Time', 'Customer', 'Material', 'Weight'],
      rows: [
        for (final entry in data.saleHistory)
          if (isOwner)
            [
              _stockTableDate(entry.createdAt),
              _stockTime(entry.createdAt),
              entry.referenceNo,
              entry.partyName,
              entry.materialName,
              kg(entry.quantityKg),
              money(entry.rate),
              money(entry.amount),
              entry.enteredBy,
              _stockDateTime(entry.createdAt),
            ]
          else
            [
              _stockTableDate(entry.createdAt),
              _stockTime(entry.createdAt),
              entry.partyName,
              entry.materialName,
              kg(entry.quantityKg),
            ],
      ],
    );
  }
}

class _AutoReminderSettingsPanel extends StatelessWidget {
  const _AutoReminderSettingsPanel({
    required this.enabled,
    required this.times,
    required this.onEnabledChanged,
    required this.onAddTime,
    required this.onRemoveTime,
  });

  final bool enabled;
  final List<TimeOfDay> times;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onAddTime;
  final ValueChanged<int> onRemoveTime;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manual Stock Reminder Mode',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_active),
            title: const Text('Local notification only'),
            subtitle: Text(
              enabled
                  ? 'Reminder notification is enabled. WhatsApp opens only when user taps manually.'
                  : 'Enable local alerts or use manual reminder settings.',
            ),
            trailing: Switch.adaptive(
              value: enabled,
              onChanged: onEnabledChanged,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StockReminderSettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Receiver Settings'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManualWhatsAppReminderScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Manual Send'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < times.length; index++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm),
              title: Text(_formatTimeOfDay(times[index])),
              subtitle: const Text(
                'At this time app shows local notification only.',
              ),
              trailing: times.length == 1
                  ? null
                  : IconButton(
                      onPressed: () => onRemoveTime(index),
                      icon: const Icon(Icons.delete_outline),
                    ),
            ),
          OutlinedButton.icon(
            onPressed: onAddTime,
            icon: const Icon(Icons.schedule),
            label: const Text('Add Local Notification Time'),
          ),
        ],
      ),
    );
  }
}

List<TimeOfDay> _reminderTimesFromPrefs(SharedPreferences prefs) {
  final saved = prefs.getStringList(autoReminderTimesPrefsKey) ?? const [];
  final parsed = saved.map(_parseReminderTime).whereType<TimeOfDay>().toList();
  if (parsed.isNotEmpty) {
    return parsed..sort(_compareReminderTimes);
  }
  return [
    TimeOfDay(
      hour: prefs.getInt(autoReminderHourPrefsKey) ?? 9,
      minute: prefs.getInt(autoReminderMinutePrefsKey) ?? 0,
    ),
  ];
}

Future<void> _saveReminderTimes(
  SharedPreferences prefs,
  List<TimeOfDay> times,
) async {
  final normalized = [...times]..sort(_compareReminderTimes);
  await prefs.setStringList(
    autoReminderTimesPrefsKey,
    normalized.map(_reminderTimeKey).toList(),
  );
  await prefs.setInt(autoReminderHourPrefsKey, normalized.first.hour);
  await prefs.setInt(autoReminderMinutePrefsKey, normalized.first.minute);
}

TimeOfDay? _parseReminderTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

int _compareReminderTimes(TimeOfDay left, TimeOfDay right) {
  final leftMinutes = left.hour * 60 + left.minute;
  final rightMinutes = right.hour * 60 + right.minute;
  return leftMinutes.compareTo(rightMinutes);
}

String _reminderTimeKey(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _formatTimeOfDay(TimeOfDay time) {
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  final hour = time.hour == 0
      ? 12
      : time.hour > 12
      ? time.hour - 12
      : time.hour;
  return '$hour:${time.minute.toString().padLeft(2, '0')} $suffix';
}

class _StockSummaryGrid extends StatelessWidget {
  const _StockSummaryGrid({
    required this.data,
    required this.onPurchaseTap,
    required this.onSaleTap,
  });

  final _StockRegisterData data;
  final VoidCallback onPurchaseTap;
  final VoidCallback onSaleTap;

  @override
  Widget build(BuildContext context) {
    final differenceCard = _StockSummaryCardData(
      data.differenceLabel,
      kg(data.stockDifference.abs()),
      data.stockDifference < 0
          ? Icons.trending_down
          : data.stockDifference > 0
          ? Icons.trending_up
          : Icons.balance,
      data.stockDifference < 0
          ? EnterpriseTheme.error
          : data.stockDifference > 0
          ? EnterpriseTheme.success
          : const Color(0xFF64748B),
    );
    final cards = [
      _StockSummaryCardData(
        'Selected Item Name',
        data.material.name,
        Icons.recycling,
        EnterpriseTheme.primary,
      ),
      _StockSummaryCardData(
        'Month Opening Qty',
        kg(data.monthOpeningQty),
        Icons.inventory,
        const Color(0xFF64748B),
      ),
      _StockSummaryCardData(
        'Total Purchase Qty',
        kg(data.totalPurchaseQty),
        Icons.add_shopping_cart,
        const Color(0xFF20A4C8),
        onTap: onPurchaseTap,
      ),
      _StockSummaryCardData(
        'Total Sale Qty',
        kg(data.totalSaleQty),
        Icons.point_of_sale,
        const Color(0xFF81A83A),
        onTap: onSaleTap,
      ),
      _StockSummaryCardData(
        'Expected Balance Stock',
        kg(data.expectedClosingStock),
        Icons.calculate,
        const Color(0xFF2563EB),
      ),
      _StockSummaryCardData(
        'Actual Physical Stock',
        kg(data.physicalClosingStock),
        Icons.inventory_2,
        EnterpriseTheme.success,
      ),
      differenceCard,
      _StockSummaryCardData(
        'Date Range',
        data.rangeLabel,
        Icons.date_range,
        EnterpriseTheme.warning,
      ),
      _StockSummaryCardData(
        'Last Purchase Date',
        data.lastPurchaseDate == null
            ? '-'
            : _stockTableDate(data.lastPurchaseDate!),
        Icons.event_available,
        const Color(0xFF2AA3BF),
      ),
      _StockSummaryCardData(
        'Last Sale Date',
        data.lastSaleDate == null ? '-' : _stockTableDate(data.lastSaleDate!),
        Icons.sell,
        const Color(0xFF81A83A),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 24) / 4
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                child: _StockSummaryCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _StockSummaryCard extends StatelessWidget {
  const _StockSummaryCard({required this.card});

  final _StockSummaryCardData card;

  @override
  Widget build(BuildContext context) {
    final content = Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: card.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(card.icon, color: card.color, size: 19),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    card.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (card.onTap == null) {
      return content;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: card.onTap,
      child: content,
    );
  }
}

class _StockRegisterTable extends StatelessWidget {
  const _StockRegisterTable({required this.data});

  final _StockRegisterData data;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _stockLedgerTableWidth,
          child: Column(
            children: [
              Container(
                width: _stockLedgerTableWidth,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                decoration: const BoxDecoration(
                  color: _stockHeaderBlue,
                  border: Border(
                    left: BorderSide(color: _stockBorderColor),
                    right: BorderSide(color: _stockBorderColor),
                    top: BorderSide(color: _stockBorderColor),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Item Name:- ${data.material.name}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Stock Ledger:- ${data.rangeLabel}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.all(color: _stockBorderColor, width: 0.7),
                columnWidths: const {
                  0: FixedColumnWidth(112),
                  1: FixedColumnWidth(82),
                  2: FixedColumnWidth(118),
                  3: FixedColumnWidth(144),
                  4: FixedColumnWidth(150),
                  5: FixedColumnWidth(104),
                  6: FixedColumnWidth(104),
                  7: FixedColumnWidth(126),
                  8: FixedColumnWidth(130),
                  9: FixedColumnWidth(150),
                },
                children: [
                  TableRow(
                    children: [
                      _stockCell('Date', _stockDateColor, header: true),
                      _stockCell('Time', _stockDateColor, header: true),
                      _stockCell('Type', _stockSerialColor, header: true),
                      _stockCell(
                        'Reference No',
                        _stockRemarkColor,
                        header: true,
                      ),
                      _stockCell('Party Name', _stockRemarkColor, header: true),
                      _stockCell('In Qty', _stockPurchaseColor, header: true),
                      _stockCell('Out Qty', _stockSaleColor, header: true),
                      _stockCell(
                        'Running Stock',
                        _stockClosingColor,
                        header: true,
                      ),
                      _stockCell('Entered By', _stockRemarkColor, header: true),
                      _stockCell('CreatedAt', _stockDateColor, header: true),
                    ],
                  ),
                  for (final row in data.ledgerEntries)
                    TableRow(
                      children: [
                        _stockCell(
                          _stockTableDate(row.createdAt),
                          _stockDateColor,
                        ),
                        _stockCell(_stockTime(row.createdAt), _stockDateColor),
                        _stockCell(row.type, _stockSerialColor),
                        _stockCell(row.referenceNo, _stockRemarkColor),
                        _stockCell(row.partyName, _stockRemarkColor),
                        _stockCell(_stockQty(row.inQty), _stockPurchaseColor),
                        _stockCell(_stockQty(row.outQty), _stockSaleColor),
                        _stockCell(
                          _stockQty(row.runningStock),
                          _stockClosingColor,
                        ),
                        _stockCell(row.enteredBy, _stockRemarkColor),
                        _stockCell(
                          _stockDateTime(row.createdAt),
                          _stockDateColor,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockRegisterChart extends StatelessWidget {
  const _StockRegisterChart({required this.data});

  final _StockRegisterData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.rows;
    var maxValue = 10.0;
    for (final row in rows) {
      if (row.cumPurchaseQty > maxValue) {
        maxValue = row.cumPurchaseQty;
      }
      if (row.cumSaleQty > maxValue) {
        maxValue = row.cumSaleQty;
      }
    }
    final labelStep = rows.length <= 6 ? 1 : (rows.length / 6).ceil();

    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Purchase Vs Sale Register:-Item Name-${data.material.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (rows.length - 1).toDouble().clamp(0, double.infinity),
                minY: 0,
                maxY: maxValue * 1.15,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xFF444444)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF0F172A),
                    getTooltipItems: (spots) => spots
                        .map(
                          (spot) => LineTooltipItem(
                            '${_stockTableDate(rows[spot.x.toInt()].date)}\n${_stockQty(spot.y)}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        )
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('Weight (Kg)'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) => Text(
                        _stockQty(value),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Date'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 72,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= rows.length ||
                            (index % labelStep != 0 &&
                                index != rows.length - 1)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Transform.rotate(
                            angle: -1.5708,
                            child: Text(
                              _stockTableDate(rows[index].date),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: false,
                    color: const Color(0xFF2DB5D7),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    spots: [
                      for (var i = 0; i < rows.length; i++)
                        FlSpot(i.toDouble(), rows[i].cumPurchaseQty),
                    ],
                  ),
                  LineChartBarData(
                    isCurved: false,
                    color: const Color(0xFF8AB542),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    spots: [
                      for (var i = 0; i < rows.length; i++)
                        FlSpot(i.toDouble(), rows[i].cumSaleQty),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _StockLegend(
                color: Color(0xFF2DB5D7),
                label: 'Cum. Purchase Qty',
              ),
              SizedBox(width: 22),
              _StockLegend(color: Color(0xFF8AB542), label: 'Cum. Sale Qty'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockLegend extends StatelessWidget {
  const _StockLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 30, height: 4, color: color),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _StockSummaryCardData {
  const _StockSummaryCardData(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class _StockRegisterData {
  const _StockRegisterData({
    required this.material,
    required this.from,
    required this.to,
    required this.rows,
    required this.ledgerEntries,
    required this.purchaseHistory,
    required this.saleHistory,
    required this.monthOpeningQty,
    required this.totalPurchaseQty,
    required this.totalSaleQty,
    required this.expectedClosingStock,
    required this.physicalClosingStock,
    required this.lastPurchaseDate,
    required this.lastSaleDate,
  });

  final MaterialStock material;
  final DateTime from;
  final DateTime to;
  final List<_StockRegisterRow> rows;
  final List<_StockLedgerEntry> ledgerEntries;
  final List<_StockHistoryEntry> purchaseHistory;
  final List<_StockHistoryEntry> saleHistory;
  final double monthOpeningQty;
  final double totalPurchaseQty;
  final double totalSaleQty;
  final double expectedClosingStock;
  final double physicalClosingStock;
  final DateTime? lastPurchaseDate;
  final DateTime? lastSaleDate;

  String get rangeLabel => '${_stockRangeDate(from)} to ${_stockRangeDate(to)}';
  double get stockDifference => physicalClosingStock - expectedClosingStock;
  String get differenceLabel {
    if (stockDifference < -0.01) {
      return 'Weight Loss';
    }
    if (stockDifference > 0.01) {
      return 'Weight Increase';
    }
    return 'No Difference';
  }
}

class _StockRegisterRow {
  const _StockRegisterRow({
    required this.serial,
    required this.date,
    required this.openingStock,
    required this.purchaseQty,
    required this.cumPurchaseQty,
    required this.saleQty,
    required this.cumSaleQty,
    required this.closingStock,
    required this.remarks,
  });

  final int serial;
  final DateTime date;
  final double openingStock;
  final double purchaseQty;
  final double cumPurchaseQty;
  final double saleQty;
  final double cumSaleQty;
  final double closingStock;
  final String remarks;
}

class _StockHistoryEntry {
  const _StockHistoryEntry({
    required this.createdAt,
    required this.referenceNo,
    required this.partyName,
    required this.materialName,
    required this.quantityKg,
    required this.rate,
    required this.amount,
    required this.enteredBy,
  });

  final DateTime createdAt;
  final String referenceNo;
  final String partyName;
  final String materialName;
  final double quantityKg;
  final double rate;
  final double amount;
  final String enteredBy;
}

class _StockLedgerEntry {
  const _StockLedgerEntry({
    required this.createdAt,
    required this.type,
    required this.referenceNo,
    required this.partyName,
    required this.inQty,
    required this.outQty,
    required this.runningStock,
    required this.enteredBy,
  });

  final DateTime createdAt;
  final String type;
  final String referenceNo;
  final String partyName;
  final double inQty;
  final double outQty;
  final double runningStock;
  final String enteredBy;
}

class _StockLedgerSeed {
  const _StockLedgerSeed({
    required this.createdAt,
    required this.type,
    required this.referenceNo,
    required this.partyName,
    required this.inQty,
    required this.outQty,
    required this.enteredBy,
  });

  final DateTime createdAt;
  final String type;
  final String referenceNo;
  final String partyName;
  final double inQty;
  final double outQty;
  final String enteredBy;
}

_StockRegisterData _buildStockRegisterData(
  BusinessState state,
  MaterialStock material,
  DateTime from,
  DateTime to,
) {
  var start = _stockDateOnly(from);
  var end = _stockDateOnly(to);
  if (end.isBefore(start)) {
    final swap = start;
    start = end;
    end = swap;
  }

  final analysis = buildStockAnalysis(state, material, from: start, to: end);
  final openingStock = analysis.monthOpeningQty;

  final rows = <_StockRegisterRow>[];
  var currentOpening = openingStock;
  var cumPurchase = openingStock;
  var totalPurchaseQty = 0.0;
  var cumSale = 0.0;
  DateTime? lastPurchaseDate;
  DateTime? lastSaleDate;

  for (
    var date = start, serial = 1;
    !date.isAfter(end);
    date = date.add(const Duration(days: 1)), serial++
  ) {
    final purchaseQty = state.activePurchases
        .where((purchase) => _sameStockDate(purchase.createdAt, date))
        .fold<double>(
          0,
          (total, purchase) =>
              total + _stockPurchaseQtyForDate(purchase, material),
        );
    final saleQty = state.activeSales
        .where((sale) => _sameStockDate(sale.createdAt, date))
        .fold<double>(
          0,
          (total, sale) => total + _stockSaleQtyForDate(sale, material),
        );
    totalPurchaseQty += purchaseQty;
    cumPurchase += purchaseQty;
    cumSale += saleQty;
    final closing = currentOpening + purchaseQty - saleQty;
    if (purchaseQty > 0) {
      lastPurchaseDate = date;
    }
    if (saleQty > 0) {
      lastSaleDate = date;
    }
    rows.add(
      _StockRegisterRow(
        serial: serial,
        date: date,
        openingStock: currentOpening,
        purchaseQty: purchaseQty,
        cumPurchaseQty: cumPurchase,
        saleQty: saleQty,
        cumSaleQty: cumSale,
        closingStock: closing,
        remarks: _stockRemarksForDate(state, material, date),
      ),
    );
    currentOpening = closing;
  }

  final purchaseHistory = <_StockHistoryEntry>[
    for (final purchase in state.activePurchases)
      if (!_stockDateOnly(purchase.createdAt).isBefore(start) &&
          !_stockDateOnly(purchase.createdAt).isAfter(end))
        for (final item in purchase.items)
          if (_stockMaterialMatches(
            item.materialId,
            item.materialName,
            material,
          ))
            _StockHistoryEntry(
              createdAt: purchase.createdAt,
              referenceNo: purchase.invoiceNumber,
              partyName: purchase.seller.name,
              materialName: item.materialName,
              quantityKg: item.weightKg,
              rate: item.rate,
              amount: item.amount,
              enteredBy: purchase.createdBy,
            ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final saleHistory = <_StockHistoryEntry>[
    for (final sale in state.activeSales)
      if (!_stockDateOnly(sale.createdAt).isBefore(start) &&
          !_stockDateOnly(sale.createdAt).isAfter(end))
        for (final item in sale.items)
          if (_stockMaterialMatches(
            item.materialId,
            item.materialName,
            material,
          ))
            _StockHistoryEntry(
              createdAt: sale.createdAt,
              referenceNo: sale.invoiceNumber,
              partyName: sale.customer.name,
              materialName: item.materialName,
              quantityKg: item.weightKg,
              rate: item.rate,
              amount: item.amount,
              enteredBy: sale.createdBy,
            ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final ledgerTransactions = [
    for (final entry in purchaseHistory)
      _StockLedgerSeed(
        createdAt: entry.createdAt,
        type: 'Purchase',
        referenceNo: entry.referenceNo,
        partyName: entry.partyName,
        inQty: entry.quantityKg,
        outQty: 0,
        enteredBy: entry.enteredBy,
      ),
    for (final entry in saleHistory)
      _StockLedgerSeed(
        createdAt: entry.createdAt,
        type: 'Sale',
        referenceNo: entry.referenceNo,
        partyName: entry.partyName,
        inQty: 0,
        outQty: entry.quantityKg,
        enteredBy: entry.enteredBy,
      ),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  var runningStock = openingStock;
  final ledgerEntries = <_StockLedgerEntry>[
    _StockLedgerEntry(
      createdAt: start,
      type: 'Month Opening',
      referenceNo: 'Month Opening',
      partyName: material.name,
      inQty: openingStock,
      outQty: 0,
      runningStock: openingStock,
      enteredBy: analysis.openingStock?.createdBy ?? 'Manual',
    ),
  ];
  for (final entry in ledgerTransactions) {
    runningStock += entry.inQty;
    runningStock -= entry.outQty;
    ledgerEntries.add(
      _StockLedgerEntry(
        createdAt: entry.createdAt,
        type: entry.type,
        referenceNo: entry.referenceNo,
        partyName: entry.partyName,
        inQty: entry.inQty,
        outQty: entry.outQty,
        runningStock: runningStock,
        enteredBy: entry.enteredBy,
      ),
    );
  }
  final expectedClosingStock = analysis.expectedStock;

  return _StockRegisterData(
    material: material,
    from: start,
    to: end,
    rows: rows,
    ledgerEntries: ledgerEntries,
    purchaseHistory: purchaseHistory,
    saleHistory: saleHistory,
    monthOpeningQty: analysis.monthOpeningQty,
    totalPurchaseQty: totalPurchaseQty,
    totalSaleQty: cumSale,
    expectedClosingStock: expectedClosingStock,
    physicalClosingStock: analysis.physicalStock,
    lastPurchaseDate: purchaseHistory.isEmpty
        ? lastPurchaseDate
        : purchaseHistory.first.createdAt,
    lastSaleDate: saleHistory.isEmpty
        ? lastSaleDate
        : saleHistory.first.createdAt,
  );
}

double _stockPurchaseQtyForDate(
  PurchaseRecord purchase,
  MaterialStock material,
) {
  return purchase.items
      .where(
        (item) =>
            _stockMaterialMatches(item.materialId, item.materialName, material),
      )
      .fold<double>(0, (total, item) => total + item.weightKg);
}

double _stockSaleQtyForDate(SaleRecord sale, MaterialStock material) {
  return sale.items
      .where(
        (item) =>
            _stockMaterialMatches(item.materialId, item.materialName, material),
      )
      .fold<double>(0, (total, item) => total + item.weightKg);
}

String _stockRemarksForDate(
  BusinessState state,
  MaterialStock material,
  DateTime date,
) {
  final remarks = <String>[];
  for (final opening in state.openingStocks) {
    if (_sameStockDate(opening.date, date) &&
        _stockMaterialMatches(
          opening.materialId,
          opening.materialName,
          material,
        ) &&
        opening.remarks.trim().isNotEmpty) {
      remarks.add(opening.remarks.trim());
    }
  }
  return remarks.join(', ');
}

bool _stockMaterialMatches(
  String materialId,
  String materialName,
  MaterialStock material,
) {
  if (materialId.trim().isNotEmpty && materialId == material.id) {
    return true;
  }
  return _stockTextKey(materialName) == _stockTextKey(material.name);
}

String _stockTextKey(String value) => value.trim().toLowerCase();

bool _sameStockDate(DateTime left, DateTime right) {
  final a = _stockDateOnly(left);
  final b = _stockDateOnly(right);
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

void _showStockHistorySheet(
  BuildContext context, {
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FeatureSheet(
      title: title,
      child: rows.isEmpty
          ? const EmptyFeatureState(
              icon: Icons.history,
              title: 'No entries',
              subtitle: 'No stock movement found for this material.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  EnterpriseTheme.primary.withValues(alpha: 0.1),
                ),
                columns: [
                  for (final header in headers) DataColumn(label: Text(header)),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [for (final value in row) DataCell(Text(value))],
                    ),
                ],
              ),
            ),
    ),
  );
}

DateTime _stockDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

Widget _stockCell(String value, Color color, {bool header = false}) {
  return Container(
    constraints: BoxConstraints(minHeight: header ? 48 : 34),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    color: color,
    child: Center(
      child: Text(
        value,
        textAlign: TextAlign.center,
        maxLines: header ? 2 : 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: header ? 13 : 12.5,
          fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          color: const Color(0xFF263238),
        ),
      ),
    ),
  );
}

String _stockQty(num value) =>
    NumberFormat.decimalPattern('en_IN').format(value);

String _stockTableDate(DateTime value) =>
    DateFormat('dd-MM-yyyy').format(value);

String _stockTime(DateTime value) => DateFormat('hh:mm a').format(value);

String _stockDateTime(DateTime value) =>
    DateFormat('dd-MM-yyyy hh:mm a').format(value);

String _stockCompactDate(DateTime value) =>
    DateFormat('dd MMM yyyy').format(value);

String _stockRangeDate(DateTime value) => DateFormat('d.M.yyyy').format(value);

const _stockLedgerTableWidth = 1220.0;
const _stockHeaderBlue = Color(0xFF2AA3BF);
const _stockBorderColor = Color(0xFF56646A);
const _stockSerialColor = Color(0xFFE6D7CB);
const _stockDateColor = Color(0xFFD8DFE2);
const _stockPurchaseColor = Color(0xFFEED1C3);
const _stockSaleColor = Color(0xFFA6C75B);
const _stockClosingColor = Color(0xFFC9D8DE);
const _stockRemarkColor = Color(0xFFD9DEE0);

class OpeningStockScreen extends ConsumerStatefulWidget {
  const OpeningStockScreen({super.key});

  @override
  ConsumerState<OpeningStockScreen> createState() => _OpeningStockScreenState();
}

class _OpeningStockScreenState extends ConsumerState<OpeningStockScreen> {
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _value = TextEditingController();
  final _remarks = TextEditingController();
  MaterialStock? _material;
  OpeningStockRecord? _editing;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    _value.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isOwner = state.user.role.isOwnerOrAdmin;
    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Opening Stock')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const FeaturePanel(
              child: EmptyFeatureState(
                icon: Icons.visibility,
                title: 'Operational stock view',
                subtitle:
                    'Supervisors can view material stock weight only. Values and rates are owner-only.',
              ),
            ),
            const SizedBox(height: 12),
            for (final material in state.activeMaterials) ...[
              FeaturePanel(
                child: Row(
                  children: [
                    EntityAvatar(
                      path: material.photoPath,
                      icon: Icons.recycling,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        material.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      kg(material.availableKg),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    }

    final computedValue = _read(_value) > 0
        ? _read(_value)
        : _read(_weight) * _read(_rate);

    return Scaffold(
      appBar: AppBar(title: const Text('Opening Stock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                MaterialDropdown(
                  label: 'Material',
                  value: _material,
                  materials: state.activeMaterials,
                  onAdd: () async {
                    final created = await showMaterialEditor(context, ref);
                    if (created != null) {
                      setState(() => _material = created);
                    }
                  },
                  onChanged: (value) {
                    setState(() {
                      _material = value;
                      if (value != null && _rate.text.trim().isEmpty) {
                        _rate.text = value.currentBuyingRate.toStringAsFixed(0);
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NumberText(
                        controller: _weight,
                        label: 'Month Opening Qty KG',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NumberText(
                        controller: _rate,
                        label: 'Month Opening Rate optional',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NumberText(
                  controller: _value,
                  label: 'Month Opening Value optional',
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(shortDate(_date)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _remarks,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
                const SizedBox(height: 12),
                AmountLine(
                  label: 'Month Opening Value',
                  value: money(computedValue),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_editing != null) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetForm,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: Text(
                          _editing == null
                              ? 'Save Month Opening'
                              : 'Update Month Opening',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Month opening stock records',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (state.openingStocks.isEmpty)
            const FeaturePanel(
              child: EmptyFeatureState(
                icon: Icons.inventory,
                title: 'No month opening stock',
                subtitle: 'Enter manual month opening quantity for each item.',
              ),
            )
          else
            for (final item in state.openingStocks) ...[
              FeaturePanel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.materialName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${shortDate(item.date)} | ${item.remarks.isEmpty ? 'No remarks' : item.remarks}',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          kg(item.openingWeightKg),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    AmountLine(
                      label: 'Month Opening Rate',
                      value: money(item.openingRate),
                    ),
                    AmountLine(
                      label: 'Month Opening Value',
                      value: money(item.openingValue),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _edit(item, state),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  void _save() {
    final material = _material;
    if (material == null) {
      _snack(context, 'Select material.');
      return;
    }
    final weight = _read(_weight);
    if (weight <= 0) {
      _snack(context, 'Enter month opening quantity.');
      return;
    }
    final rate = _read(_rate);
    final value = _read(_value) > 0 ? _read(_value) : weight * rate;
    final notifier = ref.read(businessProvider.notifier);
    final editing = _editing;
    if (editing == null) {
      notifier.addOpeningStock(
        material: material,
        openingWeightKg: weight,
        openingRate: rate,
        openingValue: value,
        date: _date,
        remarks: _remarks.text,
      );
      _snack(context, 'Month opening stock saved');
    } else {
      notifier.updateOpeningStock(
        editing.copyWith(
          materialId: material.id,
          materialName: material.name,
          openingWeightKg: weight,
          openingRate: rate,
          openingValue: value,
          date: _date,
          remarks: _remarks.text.trim(),
        ),
      );
      _snack(context, 'Month opening stock updated');
    }
    _resetForm();
  }

  void _edit(OpeningStockRecord record, BusinessState state) {
    final material = state.activeMaterials.firstWhere(
      (item) => item.id == record.materialId,
      orElse: () => MaterialStock(
        id: record.materialId,
        name: record.materialName,
        category: 'Opening Stock',
        availableKg: record.openingWeightKg,
        currentBuyingRate: record.openingRate,
      ),
    );
    setState(() {
      _editing = record;
      _material = material;
      _weight.text = record.openingWeightKg.toStringAsFixed(2);
      _rate.text = record.openingRate.toStringAsFixed(2);
      _value.text = record.openingValue.toStringAsFixed(2);
      _date = record.date;
      _remarks.text = record.remarks;
    });
  }

  void _resetForm() {
    setState(() {
      _editing = null;
      _material = null;
      _weight.clear();
      _rate.clear();
      _value.clear();
      _remarks.clear();
      _date = DateTime.now();
    });
  }
}

class OwnerSupervisorAdminScreen extends ConsumerStatefulWidget {
  const OwnerSupervisorAdminScreen({super.key});

  @override
  ConsumerState<OwnerSupervisorAdminScreen> createState() =>
      _OwnerSupervisorAdminScreenState();
}

class _OwnerSupervisorAdminScreenState
    extends ConsumerState<OwnerSupervisorAdminScreen> {
  final _service = FirebaseLoginService();

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProfileProvider);
    if (profile == null || !profile.role.isOwnerOrAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Owner Dashboard')),
        body: const EmptyFeatureState(
          icon: Icons.lock,
          title: 'Owner access required',
          subtitle: 'Only Owner/Admin can view users, logs, and notifications.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Owner Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _UserListPanel(service: _service, owner: profile),
          const SizedBox(height: 12),
          _LoginLogsPanel(service: _service),
          const SizedBox(height: 12),
          _ActivityLogsPanel(service: _service),
          const SizedBox(height: 12),
          _OwnerNotificationsPanel(service: _service),
        ],
      ),
    );
  }
}

class _UserListPanel extends StatelessWidget {
  const _UserListPanel({required this.service, required this.owner});

  final FirebaseLoginService service;
  final AuthenticatedProfile owner;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registered Users',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.watchUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'No users registered.',
                  style: TextStyle(color: Color(0xFF64748B)),
                );
              }
              return Column(
                children: [
                  for (final doc in docs)
                    _UserRow(
                      doc: doc,
                      onStatusChanged: (active) => service.setUserActive(
                        userId: doc.id,
                        active: active,
                        owner: owner,
                      ),
                      onEditProfile: () => _showEditRegisteredUserDialog(
                        context,
                        service,
                        owner,
                        doc,
                      ),
                      onViewActivity: () => _showUserActivity(
                        context,
                        service,
                        doc.id,
                        (doc.data()['name'] ?? 'User').toString(),
                      ),
                      onResetPassword: () async {
                        final email = (doc.data()['email'] ?? '').toString();
                        if (email.trim().isEmpty) {
                          _snack(context, 'No login email available.');
                          return;
                        }
                        try {
                          await service.sendPasswordReset(email);
                          if (context.mounted) {
                            _snack(
                              context,
                              'Password reset link sent to $email',
                            );
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            _snack(context, error.toString());
                          }
                        }
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.doc,
    required this.onStatusChanged,
    required this.onEditProfile,
    required this.onViewActivity,
    required this.onResetPassword,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ValueChanged<bool> onStatusChanged;
  final VoidCallback onEditProfile;
  final VoidCallback onViewActivity;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final active = data['active'] != false;
    final role = (data['role'] ?? 'user').toString();
    final email = (data['email'] ?? '').toString().trim().toLowerCase();
    final isOfficialOwner = email == ownerEmail;
    final canToggle = !isOfficialOwner;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(child: Icon(active ? Icons.person : Icons.person_off)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data['name'] ?? 'User').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${data['email'] ?? ''}  |  $role\nMobile: ${(data['mobile'] ?? '').toString().isEmpty ? '-' : data['mobile']}\nLast login: ${_firestoreDate(data['lastLoginAt'])}\nLast active: ${_firestoreDate(data['lastActiveAt'])}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Send password reset',
            onPressed: onResetPassword,
            icon: const Icon(Icons.password),
          ),
          IconButton(
            tooltip: 'Edit user name/role',
            onPressed: isOfficialOwner ? null : onEditProfile,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'View user activity',
            onPressed: onViewActivity,
            icon: const Icon(Icons.manage_search),
          ),
          Switch.adaptive(
            value: active,
            onChanged: canToggle ? onStatusChanged : null,
          ),
        ],
      ),
    );
  }
}

Future<void> _showEditRegisteredUserDialog(
  BuildContext context,
  FirebaseLoginService service,
  AuthenticatedProfile owner,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final data = doc.data();
  final name = TextEditingController(text: (data['name'] ?? '').toString());
  final mobile = TextEditingController(text: (data['mobile'] ?? '').toString());
  var role = _roleFromUserDoc(data['role']);
  var active = data['active'] != false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Edit User Profile',
        child: Column(
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Correct Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: mobile,
              decoration: const InputDecoration(labelText: 'Mobile'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<UserRole>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items:
                  const [
                        UserRole.supervisor,
                        UserRole.manager,
                        UserRole.accountant,
                        UserRole.user,
                      ]
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => role = value ?? role),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active Account'),
              value: active,
              onChanged: (value) => setState(() => active = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  _snack(context, 'Name is required.');
                  return;
                }
                try {
                  await service.updateUserProfile(
                    userId: doc.id,
                    name: name.text,
                    mobile: mobile.text,
                    role: role,
                    active: active,
                    owner: owner,
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _snack(context, 'User profile updated');
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    _snack(context, error.toString());
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save User'),
            ),
          ],
        ),
      ),
    ),
  );
  name.dispose();
  mobile.dispose();
}

UserRole _roleFromUserDoc(Object? value) {
  return switch ((value ?? 'user').toString()) {
    'owner' => UserRole.manager,
    'admin' => UserRole.manager,
    'supervisor' => UserRole.supervisor,
    'manager' => UserRole.manager,
    'accountant' => UserRole.accountant,
    _ => UserRole.user,
  };
}

class _LoginLogsPanel extends StatelessWidget {
  const _LoginLogsPanel({required this.service});

  final FirebaseLoginService service;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: _LogStream(
        title: 'Login Logs',
        stream: service.watchLoginLogs(),
        timeField: 'loginAt',
        lineBuilder: (data) =>
            '${data['name'] ?? ''}  |  ${data['email'] ?? ''}\n${data['role'] ?? ''}  |  ${data['appVersion'] ?? ''}',
      ),
    );
  }
}

class _ActivityLogsPanel extends StatelessWidget {
  const _ActivityLogsPanel({required this.service});

  final FirebaseLoginService service;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: _LogStream(
        title: 'Activity Logs',
        stream: service.watchActivityLogs(),
        timeField: 'createdAt',
        lineBuilder: (data) =>
            '${data['action'] ?? ''}  |  ${data['screen'] ?? ''}\n${data['details'] ?? ''}',
      ),
    );
  }
}

class _OwnerNotificationsPanel extends StatelessWidget {
  const _OwnerNotificationsPanel({required this.service});

  final FirebaseLoginService service;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: _LogStream(
        title: 'Owner Notifications',
        stream: service.watchOwnerNotifications(),
        timeField: 'createdAt',
        lineBuilder: (data) => '${data['title'] ?? ''}\n${data['body'] ?? ''}',
      ),
    );
  }
}

void _showUserActivity(
  BuildContext context,
  FirebaseLoginService service,
  String userId,
  String name,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: _LogStream(
            title: '$name Activity',
            stream: service.watchActivityLogs(userId: userId),
            timeField: 'createdAt',
            lineBuilder: (data) =>
                '${data['action'] ?? ''}  |  ${data['screen'] ?? ''}\n${data['details'] ?? ''}',
          ),
        ),
      ),
    ),
  );
}

class _LogStream extends StatelessWidget {
  const _LogStream({
    required this.title,
    required this.stream,
    required this.timeField,
    required this.lineBuilder,
  });

  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String timeField;
  final String Function(Map<String, dynamic> data) lineBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Text(
                'No logs yet.',
                style: TextStyle(color: Color(0xFF64748B)),
              );
            }
            return Column(
              children: [
                for (final doc in docs.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.history, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${lineBuilder(doc.data())}\n${_firestoreDate(doc.data()[timeField])}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _firestoreDate(Object? value) {
  if (value is Timestamp) {
    return shortDate(value.toDate());
  }
  if (value is DateTime) {
    return shortDate(value);
  }
  return '-';
}

class AuditTrailScreen extends ConsumerWidget {
  const AuditTrailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audits = ref.watch(businessProvider).auditTrail;
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: audits.isEmpty
          ? const EmptyFeatureState(
              icon: Icons.fact_check,
              title: 'No audit entries',
              subtitle: 'Create, edit or delete records to build history.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: audits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = audits[index];
                return FeaturePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.action,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.field}: ${item.oldValue.isEmpty ? '-' : item.oldValue} -> ${item.newValue.isEmpty ? '-' : item.newValue}',
                        style: const TextStyle(color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.user}  |  ${shortDate(item.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class ActivityFeedScreen extends ConsumerStatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  ConsumerState<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends ConsumerState<ActivityFeedScreen> {
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !_logged) {
        _logged = true;
        ref.read(businessProvider.notifier).recordActivityFeedOpened();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final activities = state.user.role.isOwnerOrAdmin
        ? state.activities
        : state.activities
              .where(
                (item) =>
                    item.userName.trim().toLowerCase() ==
                    state.user.name.trim().toLowerCase(),
              )
              .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Live Recent Activity')),
      body: activities.isEmpty
          ? const EmptyFeatureState(
              icon: Icons.timeline,
              title: 'No recent activity',
              subtitle:
                  'Purchases, sales, logins, exports and voice actions will appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: activities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = activities[index];
                return FeaturePanel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _activityColor(
                            item.title,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _activityIcon(item.title),
                          color: _activityColor(item.title),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _timeOnly(item.createdAt),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _activityTitle(item.title),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _activitySubtitle(item),
                              style: const TextStyle(color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class ReportCenterScreen extends ConsumerStatefulWidget {
  const ReportCenterScreen({
    super.key,
    this.initialReport = 'Purchase Report',
    this.initialFilter = 'Today',
  });

  final String initialReport;
  final String initialFilter;

  @override
  ConsumerState<ReportCenterScreen> createState() => _ReportCenterScreenState();
}

class _ReportCenterScreenState extends ConsumerState<ReportCenterScreen> {
  late String _filter;
  late String _report;
  String _purchaseExportType = 'Normal Report';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _report = widget.initialReport;
    Future.microtask(() => _recordReportAction('report_opened'));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final isInternalPurchase =
        _report == 'Purchase Report' &&
        state.user.role.isOwnerOrAdmin &&
        _purchaseExportType == 'Internal Report';
    final bundle = _buildReportBundle(
      state,
      report: _report,
      filter: _filter,
      from: _from,
      to: _to,
      internalPurchase: isInternalPurchase,
    );
    final summary = _reportShareText(bundle);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: const Text('Scrap Report')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _report,
                decoration: const InputDecoration(labelText: 'Report'),
                items: _reportNames
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  final selected = value ?? _report;
                  setState(() => _report = selected);
                  _recordReportAction('report_opened', reportName: selected);
                },
              ),
            ),
            if (_report == 'Purchase Report' && state.user.role.isOwnerOrAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'Normal Report',
                      label: Text('Normal Report'),
                    ),
                    ButtonSegment(
                      value: 'Internal Report',
                      label: Text('Internal Report'),
                    ),
                  ],
                  selected: {_purchaseExportType},
                  onSelectionChanged: (value) {
                    setState(() => _purchaseExportType = value.first);
                  },
                ),
              ),
            FilterStrip(
              value: _filter,
              compact: true,
              onChanged: _changeFilter,
            ),
            ExportBar(
              title: bundle.title,
              table: bundle.detailTable,
              bundle: bundle,
              onPdfExport: () => _recordReportAction('report_pdf_exported'),
              onExcelExport: () => _recordReportAction('report_excel_exported'),
              onPrint: () => _recordReportAction('report_printed'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareWhatsApp(summary),
                      icon: const Icon(Icons.chat),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _sharePdf(bundle),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              onTap: (index) {
                if (index == 1) {
                  _recordReportAction('report_graph_viewed');
                }
              },
              tabs: const [
                Tab(text: 'Summary'),
                Tab(text: 'Graphs'),
                Tab(text: 'Details'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ReportSummaryTab(bundle: bundle),
                  ReportGraphList(charts: bundle.charts),
                  DataList(
                    headers: bundle.detailTable.headers,
                    rows: bundle.detailTable.rows,
                    footerRows: bundle.detailTable.footerRows,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFilter(String value) async {
    if (_isCustomFilter(value)) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (range != null) {
        _from = range.start;
        _to = range.end;
      }
    }
    setState(() => _filter = value);
    _recordReportAction('report_opened');
  }

  void _recordReportAction(String action, {String? reportName}) {
    ref
        .read(businessProvider.notifier)
        .recordReportAction(
          action: action,
          reportName: reportName ?? _report,
          filterType: _filter,
          dateRange: _dateRangeLabel(_filter, _from, _to),
        );
  }

  Future<void> _shareWhatsApp(String text) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      if (mounted) {
        _snack(context, 'WhatsApp is not installed.');
      }
      return;
    }
    ref
        .read(businessProvider.notifier)
        .recordWhatsAppShared(
          action: 'whatsapp_report_shared',
          screen: 'Scrap Report',
          details: _report,
        );
  }

  Future<void> _sharePdf(ReportBundle bundle) async {
    final bytes = await _buildReportPdf(bundle);
    final fileName = '${_safeName(bundle.title)}.pdf';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
        ],
        fileNameOverrides: [fileName],
        subject: bundle.title,
        text: _reportShareText(bundle),
      ),
    );
    _recordReportAction('report_pdf_exported');
  }
}

class _ReportSummaryTab extends StatelessWidget {
  const _ReportSummaryTab({required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ReportSummaryCards(cards: bundle.summaryCards),
        const SizedBox(height: 12),
        if (bundle.charts.isNotEmpty)
          ReportChartPanel(chart: bundle.charts.first)
        else
          const FeaturePanel(
            child: EmptyFeatureState(
              icon: Icons.query_stats,
              title: 'No graph data',
              subtitle: 'Graphs will appear when data is available.',
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Date-wise total',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        _CompactTable(table: bundle.dateWiseTable),
      ],
    );
  }
}

class _CompactTable extends StatelessWidget {
  const _CompactTable({required this.table});

  final ReportTable table;

  @override
  Widget build(BuildContext context) {
    if (table.rows.isEmpty) {
      return const FeaturePanel(
        child: EmptyFeatureState(
          icon: Icons.table_rows,
          title: 'No date-wise data',
          subtitle: 'Try another report filter.',
        ),
      );
    }
    return Column(
      children: [
        for (final row in [...table.rows.take(6), ...table.footerRows])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FeaturePanel(
              child: Column(
                children: [
                  for (
                    var i = 0;
                    i < table.headers.length && i < row.length;
                    i++
                  )
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              table.headers[i],
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row[i],
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

const _reportNames = [
  'Purchase Report',
  'Sales Report',
  'Inventory Report',
  'Cash Ledger',
  'Seller Ledger',
  'Customer Ledger',
  'Audit Report',
  'Deleted Transaction Report',
  'Profit/Loss Report',
  'Material-wise Report',
  'Supervisor Performance Report',
  'Supervisor Balance Report',
  'Expense Report',
];

String _reportShareText(ReportBundle bundle) {
  return [
    appDisplayName,
    bundle.title,
    'Date Range: ${bundle.dateRange}',
    for (final item in bundle.summaryCards) '${item.label}: ${item.value}',
  ].join('\n');
}

ReportBundle _buildReportBundle(
  BusinessState state, {
  required String report,
  required String filter,
  required DateTime? from,
  required DateTime? to,
  bool internalPurchase = false,
}) {
  switch (report) {
    case 'Sales Report':
      return _salesReportBundle(state, filter, from, to);
    case 'Inventory Report':
      return _inventoryReportBundle(state, filter, from, to);
    case 'Cash Report':
    case 'Cash Ledger':
      return _cashReportBundle(state, filter, from, to);
    case 'Seller Ledger':
      return _sellerLedgerBundle(state, filter, from, to);
    case 'Customer Ledger':
      return _customerLedgerBundle(state, filter, from, to);
    case 'Audit Report':
      return _auditReportBundle(state, filter, from, to);
    case 'Deleted Transaction Report':
      return _deletedReportBundle(state, filter, from, to);
    case 'Profit/Loss Report':
      return _profitLossBundle(state, filter, from, to);
    case 'Material-wise Report':
      return _materialWiseBundle(state, filter, from, to);
    case 'Supervisor Performance Report':
      return _supervisorPerformanceBundle(state, filter, from, to);
    case 'Supervisor Balance Report':
      return _supervisorBalanceBundle(state, filter, from, to);
    case 'Expense Report':
      return _expenseReportBundle(state, filter, from, to);
    default:
      return _purchaseReportBundle(state, filter, from, to, internalPurchase);
  }
}

ReportBundle _purchaseReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
  bool internal,
) {
  final purchases = state.activePurchases
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final dateTotals = <String, List<double>>{};
  final materialTotals = <String, double>{};
  final sellerTotals = <String, double>{};
  for (final purchase in purchases) {
    final key = _dateKey(purchase.createdAt);
    final totals = dateTotals.putIfAbsent(key, () => [0, 0, 0, 0, 0]);
    totals[0] += 1;
    totals[1] += purchase.totalWeightKg;
    totals[2] += purchase.totalAmount;
    totals[3] += purchase.paidAmount;
    totals[4] += purchase.balanceAmount;
    _addToMap(sellerTotals, purchase.seller.name, purchase.totalAmount);
    for (final item in purchase.items) {
      _addToMap(materialTotals, item.materialName, item.amount);
    }
  }
  final totalWeight = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalWeightKg,
  );
  final totalAmount = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalPaid = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.paidAmount,
  );
  final totalBalance = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.balanceAmount,
  );
  final dateRows = [
    for (final entry in _dateEntries({
      for (final e in dateTotals.entries) e.key: e.value[2],
    }))
      [
        entry.key,
        (dateTotals[entry.key]![0]).toStringAsFixed(0),
        kg(dateTotals[entry.key]![1]),
        money(dateTotals[entry.key]![2]),
        money(dateTotals[entry.key]![3]),
        money(dateTotals[entry.key]![4]),
      ],
  ];
  final dateWiseTable = ReportTable(
    headers: const [
      'Date',
      'Total Invoices',
      'Total Weight',
      'Total Purchase Amount',
      'Paid Amount',
      'Balance',
    ],
    rows: dateRows,
    footerRows: purchases.isEmpty
        ? const []
        : [
            [
              'Grand Total',
              purchases.length.toString(),
              kg(totalWeight),
              money(totalAmount),
              money(totalPaid),
              money(totalBalance),
            ],
          ],
    landscape: true,
  );
  final materialTable = ReportTable(
    headers: const ['Material', 'Purchase Amount'],
    rows: [
      for (final entry in _sortedEntries(materialTotals))
        [entry.key, money(entry.value)],
    ],
  );
  final sellerTable = ReportTable(
    headers: const ['Seller', 'Purchase Amount'],
    rows: [
      for (final entry in _sortedEntries(sellerTotals))
        [entry.key, money(entry.value)],
    ],
  );

  return ReportBundle(
    title: internal ? 'Purchase Report - Internal Report' : 'Purchase Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Today Purchase',
        value: money(state.metrics.todayPurchase),
        icon: Icons.shopping_cart,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Total Weight',
        value: kg(totalWeight),
        icon: Icons.scale,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Total Invoices',
        value: purchases.length.toString(),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Paid Amount',
        value: money(totalPaid),
        icon: Icons.payments,
        color: const Color(0xFF0891B2),
      ),
      ReportSummaryMetric(
        label: 'Balance',
        value: money(totalBalance),
        icon: Icons.pending_actions,
        color: EnterpriseTheme.error,
      ),
    ],
    dateWiseTable: dateWiseTable,
    detailTable: _purchaseReportTable(purchases, internal: internal),
    extraSections: [
      ReportTableSection(title: 'Material-wise', table: materialTable),
      ReportTableSection(title: 'Seller-wise', table: sellerTable),
    ],
    charts: [
      ReportChartSpec(
        title: 'Date-wise purchase amount',
        type: ReportChartType.bar,
        entries: _dateEntries({
          for (final e in dateTotals.entries) e.key: e.value[2],
        }),
      ),
      ReportChartSpec(
        title: 'Date-wise purchase trend',
        type: ReportChartType.line,
        entries: _dateEntries({
          for (final e in dateTotals.entries) e.key: e.value[2],
        }),
      ),
      ReportChartSpec(
        title: 'Material-wise purchase amount',
        type: ReportChartType.pie,
        entries: _sortedEntries(materialTotals),
      ),
      ReportChartSpec(
        title: 'Seller-wise purchase amount',
        type: ReportChartType.bar,
        entries: _sortedEntries(sellerTotals),
      ),
    ],
  );
}

bool _salesReportVisibleToUser(BusinessState state, SaleRecord sale) {
  if (state.user.role.isOwnerOrAdmin || state.user.role == UserRole.manager) {
    return true;
  }
  final left = sale.createdBy.trim().toLowerCase();
  final right = state.user.name.trim().toLowerCase();
  return left.isNotEmpty &&
      right.isNotEmpty &&
      (left == right || left.contains(right) || right.contains(left));
}

ReportBundle _restrictedSalesReportBundle(
  BusinessState state,
  List<SaleRecord> sales,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final dateTotals = <String, List<double>>{};
  for (final sale in sales) {
    final key = _dateKey(sale.createdAt);
    final totals = dateTotals.putIfAbsent(key, () => [0, 0]);
    totals[0] += 1;
    totals[1] += sale.totalWeightKg;
  }
  final totalWeight = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalWeightKg,
  );
  final pendingCount = sales.where((item) => item.isPaymentPending).length;
  final dateWiseTable = ReportTable(
    headers: const ['Date', 'Invoices', 'Weight'],
    rows: [
      for (final entry in _dateEntries({
        for (final e in dateTotals.entries) e.key: e.value[1],
      }))
        [
          entry.key,
          (dateTotals[entry.key]![0]).toStringAsFixed(0),
          kg(dateTotals[entry.key]![1]),
        ],
    ],
    footerRows: sales.isEmpty
        ? const []
        : [
            ['Grand Total', sales.length.toString(), kg(totalWeight)],
          ],
    landscape: true,
  );
  final detailTable = ReportTable(
    headers: const [
      'Invoice No',
      'Customer',
      'Material',
      'Weight',
      'Payment Status',
      'Reminder',
      'Added By',
      'Date',
    ],
    rows: [
      for (final sale in sales)
        for (final item in sale.items)
          [
            sale.invoiceNumber,
            sale.customer.name,
            item.materialName,
            kg(item.weightKg),
            sale.isPaymentPending ? 'Payment Pending' : 'Payment Received',
            sale.reminderSent ? 'Sent' : 'Not Sent',
            sale.createdBy,
            shortDate(sale.createdAt),
          ],
    ],
    footerRows: sales.isEmpty
        ? const []
        : [
            ['Grand Total', '', '', kg(totalWeight), '', '', '', ''],
          ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Sales Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Sale Weight',
        value: kg(totalWeight),
        icon: Icons.scale,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Invoices',
        value: sales.length.toString(),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Pending Bills',
        value: pendingCount.toString(),
        icon: Icons.pending_actions,
        color: pendingCount > 0
            ? EnterpriseTheme.error
            : EnterpriseTheme.success,
      ),
    ],
    dateWiseTable: dateWiseTable,
    detailTable: detailTable,
    extraSections: const [],
    charts: [
      ReportChartSpec(
        title: 'Date-wise sale weight',
        type: ReportChartType.bar,
        entries: _dateEntries({
          for (final e in dateTotals.entries) e.key: e.value[1],
        }),
      ),
    ],
  );
}

ReportBundle _salesReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final sales = state.activeSales
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .where((item) => _salesReportVisibleToUser(state, item))
      .toList();
  if (!state.user.role.isOwnerOrAdmin) {
    return _restrictedSalesReportBundle(state, sales, filter, from, to);
  }
  final dateTotals = <String, List<double>>{};
  final customerTotals = <String, double>{};
  final materialTotals = <String, double>{};
  for (final sale in sales) {
    final key = _dateKey(sale.createdAt);
    final totals = dateTotals.putIfAbsent(key, () => [0, 0, 0, 0]);
    totals[0] += sale.totalAmount;
    totals[1] += sale.receivedAmount;
    totals[2] += sale.balanceAmount;
    totals[3] += sale.totalWeightKg;
    _addToMap(customerTotals, sale.customer.name, sale.totalAmount);
    for (final item in sale.items) {
      _addToMap(materialTotals, item.materialName, item.amount);
    }
  }
  final totalSales = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalReceived = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.receivedAmount,
  );
  final totalWeight = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalWeightKg,
  );
  final pending = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.balanceAmount,
  );
  final dateWiseTable = ReportTable(
    headers: const ['Date', 'Sales Amount', 'Paid Amount', 'Pending', 'Weight'],
    rows: [
      for (final entry in _dateEntries({
        for (final e in dateTotals.entries) e.key: e.value[0],
      }))
        [
          entry.key,
          money(dateTotals[entry.key]![0]),
          money(dateTotals[entry.key]![1]),
          money(dateTotals[entry.key]![2]),
          kg(dateTotals[entry.key]![3]),
        ],
    ],
    footerRows: sales.isEmpty
        ? const []
        : [
            [
              'Grand Total',
              money(totalSales),
              money(totalReceived),
              money(pending),
              kg(totalWeight),
            ],
          ],
    landscape: true,
  );
  final detailTable = ReportTable(
    headers: const [
      'Invoice No',
      'Customer',
      'Material',
      'Item Weight',
      'Rate / KG',
      'Item Amount',
      'Total Invoice Weight',
      'Total Invoice Amount',
      'Paid Amount',
      'Balance',
      'Added By',
      'Date',
    ],
    rows: [
      for (final sale in sales)
        for (final item in sale.items)
          [
            sale.invoiceNumber,
            sale.customer.name,
            item.materialName,
            kg(item.weightKg),
            money(item.rate),
            money(item.amount),
            kg(sale.totalWeightKg),
            money(sale.totalAmount),
            money(sale.receivedAmount),
            money(sale.balanceAmount),
            sale.createdBy,
            shortDate(sale.createdAt),
          ],
    ],
    footerRows: sales.isEmpty
        ? const []
        : [
            [
              'Grand Total',
              '',
              '',
              kg(totalWeight),
              '',
              money(totalSales),
              kg(totalWeight),
              money(totalSales),
              money(totalReceived),
              money(pending),
              '',
              '',
            ],
          ],
    landscape: true,
    columnFlex: const [1.4, 1.7, 1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1.1],
  );
  return ReportBundle(
    title: 'Sales Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Total Sales',
        value: money(totalSales),
        icon: Icons.point_of_sale,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Received',
        value: money(totalReceived),
        icon: Icons.payments,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Payment Pending',
        value: money(pending),
        icon: Icons.pending_actions,
        color: EnterpriseTheme.error,
      ),
      ReportSummaryMetric(
        label: 'Invoices',
        value: sales.length.toString(),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.warning,
      ),
    ],
    dateWiseTable: dateWiseTable,
    detailTable: detailTable,
    extraSections: [
      ReportTableSection(
        title: 'Customer-wise',
        table: ReportTable(
          headers: const ['Customer', 'Sales Amount'],
          rows: [
            for (final e in _sortedEntries(customerTotals))
              [e.key, money(e.value)],
          ],
        ),
      ),
      ReportTableSection(
        title: 'Material-wise',
        table: ReportTable(
          headers: const ['Material', 'Sales Amount'],
          rows: [
            for (final e in _sortedEntries(materialTotals))
              [e.key, money(e.value)],
          ],
        ),
      ),
    ],
    charts: [
      ReportChartSpec(
        title: 'Date-wise sales amount',
        type: ReportChartType.bar,
        entries: _dateEntries({
          for (final e in dateTotals.entries) e.key: e.value[0],
        }),
      ),
      ReportChartSpec(
        title: 'Sales trend',
        type: ReportChartType.line,
        entries: _dateEntries({
          for (final e in dateTotals.entries) e.key: e.value[0],
        }),
      ),
      ReportChartSpec(
        title: 'Customer-wise sales',
        type: ReportChartType.pie,
        entries: _sortedEntries(customerTotals),
      ),
      ReportChartSpec(
        title: 'Material-wise sales',
        type: ReportChartType.pie,
        entries: _sortedEntries(materialTotals),
      ),
    ],
  );
}

ReportBundle _inventoryReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final materials = state.materials;
  final isOwner = state.user.role.isOwnerOrAdmin;
  final stockMap = {for (final item in materials) item.name: item.availableKg};
  final valueMap = {for (final item in materials) item.name: item.stockValue};
  final lowStock = {
    for (final item in materials.where((item) => item.availableKg <= 0))
      item.name: item.availableKg,
  };
  final totalStock = materials.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.availableKg,
  );
  final totalValue = materials.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.stockValue,
  );
  double openingWeightFor(MaterialStock material) => state.openingStocks
      .where((item) => item.materialId == material.id)
      .fold<double>(0, (total, item) => total + item.openingWeightKg);
  double purchaseWeightFor(MaterialStock material) => state.activePurchases
      .expand((purchase) => purchase.items)
      .where((item) => item.materialId == material.id)
      .fold<double>(0, (total, item) => total + item.weightKg);
  double saleWeightFor(MaterialStock material) => state.activeSales
      .expand((sale) => sale.items)
      .where((item) => item.materialId == material.id)
      .fold<double>(0, (total, item) => total + item.weightKg);
  final detailTable = ReportTable(
    headers: isOwner
        ? const [
            'Material',
            'Opening Stock',
            'Purchase Weight',
            'Sale Weight',
            'Closing Stock',
            'Shortage/Excess',
            'Buying Rate',
            'Selling Rate',
            'Stock Value',
            'Status',
          ]
        : const [
            'Material',
            'Opening Stock',
            'Purchase Weight',
            'Sale Weight',
            'Closing Stock',
            'Shortage/Excess',
            'Status',
          ],
    rows: [
      for (final item in materials)
        if (isOwner)
          [
            item.name,
            kg(openingWeightFor(item)),
            kg(purchaseWeightFor(item)),
            kg(saleWeightFor(item)),
            kg(item.availableKg),
            kg(
              item.availableKg -
                  (openingWeightFor(item) +
                      purchaseWeightFor(item) -
                      saleWeightFor(item)),
            ),
            money(item.currentBuyingRate),
            money(
              item.currentSellingRate == 0
                  ? item.currentBuyingRate
                  : item.currentSellingRate,
            ),
            money(item.stockValue),
            item.isActive ? 'Active' : 'Inactive',
          ]
        else
          [
            item.name,
            kg(openingWeightFor(item)),
            kg(purchaseWeightFor(item)),
            kg(saleWeightFor(item)),
            kg(item.availableKg),
            kg(
              item.availableKg -
                  (openingWeightFor(item) +
                      purchaseWeightFor(item) -
                      saleWeightFor(item)),
            ),
            item.isActive ? 'Active' : 'Inactive',
          ],
    ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Inventory Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Materials',
        value: materials.length.toString(),
        icon: Icons.inventory_2,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Total Stock',
        value: kg(totalStock),
        icon: Icons.scale,
        color: EnterpriseTheme.success,
      ),
      if (isOwner)
        ReportSummaryMetric(
          label: 'Stock Value',
          value: money(totalValue),
          icon: Icons.account_balance_wallet,
          color: EnterpriseTheme.warning,
        ),
      ReportSummaryMetric(
        label: 'Low Stock',
        value: lowStock.length.toString(),
        icon: Icons.warning_amber,
        color: EnterpriseTheme.error,
      ),
    ],
    dateWiseTable: detailTable,
    detailTable: detailTable,
    extraSections: [
      ReportTableSection(
        title: 'Low Stock Alert',
        table: ReportTable(
          headers: const ['Material', 'Current Stock'],
          rows: [
            for (final e in lowStock.entries) [e.key, kg(e.value)],
          ],
        ),
      ),
    ],
    charts: [
      ReportChartSpec(
        title: 'Material-wise stock',
        type: ReportChartType.bar,
        entries: _sortedEntries(stockMap),
        valueKind: ReportColumnKind.weight,
      ),
      if (isOwner)
        ReportChartSpec(
          title: 'Stock value share',
          type: ReportChartType.pie,
          entries: _sortedEntries(valueMap),
        ),
      ReportChartSpec(
        title: 'Low stock alert',
        type: ReportChartType.bar,
        entries: _sortedEntries(lowStock),
        valueKind: ReportColumnKind.weight,
      ),
    ],
  );
}

ReportBundle _cashReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final showSalesCollection = state.user.role.isOwnerOrAdmin;
  final entries = state.visibleSupervisorCashLedgerEntries
      .where((item) => _dateInReportFilter(item.date, filter, from, to))
      .toList();
  final dayValues = <String, List<double>>{};
  final expenseTotals = <String, double>{};
  for (final entry in entries) {
    final key = _dateKey(entry.date);
    final totals = dayValues.putIfAbsent(key, () => [0, 0, 0, 0]);
    totals[0] += entry.cashGivenByOwner;
    totals[1] += entry.scrapPurchaseUsed;
    totals[2] += entry.otherExpenses;
    totals[3] += entry.salesCollection;
  }
  final sortedDays = dayValues.keys.toList()..sort();
  var runningBalance = 0.0;
  final dateRows = <List<String>>[];
  final closingMap = <String, double>{};
  final usedMap = <String, double>{};
  for (final day in sortedDays) {
    final totals = dayValues[day]!;
    final opening = runningBalance;
    runningBalance += totals[0] - totals[1] - totals[2];
    closingMap[day] = runningBalance;
    usedMap[day] = totals[1] + totals[2];
    dateRows.add([
      day,
      money(opening),
      money(totals[0]),
      money(totals[1]),
      money(totals[2]),
      if (showSalesCollection) money(totals[3]),
      money(runningBalance),
    ]);
  }
  final visibleNames = {
    for (final item in state.visibleSupervisorCashSummaries)
      item.supervisorName,
  };
  bool visibleStaff(String value) =>
      state.user.role.isOwnerOrAdmin ||
      visibleNames.any(
        (name) => name.trim().toLowerCase() == value.trim().toLowerCase(),
      );
  for (final expense in state.activeExpenses.where(
    (item) =>
        _dateInReportFilter(item.date, filter, from, to) &&
        visibleStaff(item.addedBy),
  )) {
    _addToMap(expenseTotals, expense.category, expense.amount);
  }
  final supervisorBalance = {
    for (final item in state.visibleSupervisorCashSummaries)
      item.supervisorName: item.currentCashBalance,
  };
  final dateWiseTable = ReportTable(
    headers: [
      'Date',
      'Opening Balance',
      'Cash Given',
      'Scrap Purchase',
      'Other Expenses',
      if (showSalesCollection) 'Sales Collection',
      'Closing Balance',
    ],
    rows: dateRows,
    landscape: true,
  );
  return ReportBundle(
    title: 'Cash Ledger',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Cash Given',
        value: money(
          entries.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.cashGivenByOwner,
          ),
        ),
        icon: Icons.payments,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Scrap Purchase',
        value: money(
          entries.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.scrapPurchaseUsed,
          ),
        ),
        icon: Icons.shopping_cart,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Other Expenses',
        value: money(
          entries.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.otherExpenses,
          ),
        ),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.error,
      ),
      if (showSalesCollection)
        ReportSummaryMetric(
          label: 'Sales Collection',
          value: money(
            entries.fold<double>(
              0,
              (runningTotal, item) => runningTotal + item.salesCollection,
            ),
          ),
          icon: Icons.point_of_sale,
          color: EnterpriseTheme.success,
        ),
      ReportSummaryMetric(
        label: 'Closing Balance',
        value: money(runningBalance),
        icon: Icons.account_balance_wallet,
        color: runningBalance >= 0
            ? EnterpriseTheme.success
            : EnterpriseTheme.error,
      ),
    ],
    dateWiseTable: dateWiseTable,
    detailTable: ReportTable(
      headers: [
        'Date',
        'Supervisor',
        'Activity',
        'Opening Balance',
        'Cash Given by Owner',
        'Scrap Purchase Used',
        'Other Expenses',
        if (showSalesCollection) 'Sales Collection',
        'Current Cash Balance',
        'Details',
      ],
      rows: [
        for (final entry in entries)
          [
            shortDate(entry.date),
            entry.supervisorName,
            entry.activityType,
            money(entry.openingBalance),
            money(entry.cashGivenByOwner),
            money(entry.scrapPurchaseUsed),
            money(entry.otherExpenses),
            if (showSalesCollection) money(entry.salesCollection),
            money(entry.currentCashBalance),
            entry.details,
          ],
      ],
      landscape: true,
    ),
    extraSections: [
      ReportTableSection(
        title: 'Expense Details',
        table: ReportTable(
          headers: const [
            'Date',
            'Supervisor',
            'Description',
            'Amount',
            'Remarks',
          ],
          rows: [
            for (final item in state.activeExpenses.where(
              (item) => _dateInReportFilter(item.date, filter, from, to),
            ))
              [
                shortDate(item.date),
                item.addedBy,
                item.category,
                money(item.amount),
                item.remarks,
              ],
          ],
        ),
      ),
      ReportTableSection(
        title: 'Purchase Cash Usage',
        table: ReportTable(
          headers: const ['Date', 'Invoice', 'Supervisor', 'Seller', 'Amount'],
          rows: [
            for (final item in state.activePurchases.where(
              (item) => _dateInReportFilter(item.createdAt, filter, from, to),
            ))
              [
                shortDate(item.createdAt),
                item.invoiceNumber,
                item.createdBy,
                item.seller.name,
                money(item.totalAmount),
              ],
          ],
        ),
      ),
    ],
    charts: [
      ReportChartSpec(
        title: 'Date-wise closing balance',
        type: ReportChartType.line,
        entries: _dateEntries(closingMap),
      ),
      ReportChartSpec(
        title: 'Cash given by date',
        type: ReportChartType.bar,
        entries: _dateEntries({
          for (final e in dayValues.entries) e.key: e.value[0],
        }),
      ),
      ReportChartSpec(
        title: 'Cash used by date',
        type: ReportChartType.bar,
        entries: _dateEntries(usedMap),
      ),
      ReportChartSpec(
        title: 'Expense-wise split',
        type: ReportChartType.pie,
        entries: _sortedEntries(expenseTotals),
      ),
      ReportChartSpec(
        title: 'Supervisor-wise cash balance',
        type: ReportChartType.bar,
        entries: _sortedEntries(supervisorBalance),
      ),
    ],
  );
}

ReportBundle _sellerLedgerBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final purchases = state.activePurchases
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final purchaseBySeller = <String, double>{};
  final paidBySeller = <String, double>{};
  final trend = <String, double>{};
  for (final purchase in purchases) {
    _addToMap(purchaseBySeller, purchase.seller.name, purchase.totalAmount);
    _addToMap(paidBySeller, purchase.seller.name, purchase.paidAmount);
    _addToMap(trend, _dateKey(purchase.createdAt), purchase.totalAmount);
  }
  final rows = [
    for (final seller in state.sellers)
      [
        seller.name,
        money(0),
        money(purchaseBySeller[seller.name] ?? 0),
        money(paidBySeller[seller.name] ?? 0),
        money(
          (purchaseBySeller[seller.name] ?? 0) -
              (paidBySeller[seller.name] ?? 0),
        ),
      ],
  ];
  final detail = ReportTable(
    headers: const [
      'Seller',
      'Opening Balance',
      'Purchases',
      'Paid Amount',
      'Closing Balance',
    ],
    rows: rows,
  );
  final totalPurchase = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalPaid = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.paidAmount,
  );
  return ReportBundle(
    title: 'Seller Ledger',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Sellers',
        value: state.sellers.length.toString(),
        icon: Icons.storefront,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Purchases',
        value: money(totalPurchase),
        icon: Icons.shopping_cart,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Paid Amount',
        value: money(totalPaid),
        icon: Icons.payments,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Closing Balance',
        value: money(totalPurchase - totalPaid),
        icon: Icons.pending_actions,
        color: EnterpriseTheme.error,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Purchase Amount'],
      rows: [
        for (final e in _dateEntries(trend)) [e.key, money(e.value)],
      ],
    ),
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Seller-wise purchase amount',
        type: ReportChartType.bar,
        entries: _sortedEntries(purchaseBySeller),
      ),
      ReportChartSpec(
        title: 'Seller-wise pending balance',
        type: ReportChartType.bar,
        entries: _sortedEntries({
          for (final seller in state.sellers)
            seller.name:
                (purchaseBySeller[seller.name] ?? 0) -
                (paidBySeller[seller.name] ?? 0),
        }),
      ),
      ReportChartSpec(
        title: 'Date-wise seller transaction trend',
        type: ReportChartType.line,
        entries: _dateEntries(trend),
      ),
    ],
  );
}

ReportBundle _customerLedgerBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final sales = state.activeSales
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final salesByCustomer = <String, double>{};
  final receivedByCustomer = <String, double>{};
  final receivedTrend = <String, double>{};
  for (final sale in sales) {
    _addToMap(salesByCustomer, sale.customer.name, sale.totalAmount);
    _addToMap(receivedByCustomer, sale.customer.name, sale.receivedAmount);
    _addToMap(receivedTrend, _dateKey(sale.createdAt), sale.receivedAmount);
  }
  final totalSales = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalReceived = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.receivedAmount,
  );
  final detail = ReportTable(
    headers: const [
      'Customer',
      'Opening Balance',
      'Sales',
      'Received Amount',
      'Closing Balance',
    ],
    rows: [
      for (final customer in state.customers)
        [
          customer.name,
          money(0),
          money(salesByCustomer[customer.name] ?? 0),
          money(receivedByCustomer[customer.name] ?? 0),
          money(
            (salesByCustomer[customer.name] ?? 0) -
                (receivedByCustomer[customer.name] ?? 0),
          ),
        ],
    ],
  );
  return ReportBundle(
    title: 'Customer Ledger',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Customers',
        value: state.customers.length.toString(),
        icon: Icons.people,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Sales',
        value: money(totalSales),
        icon: Icons.point_of_sale,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Received',
        value: money(totalReceived),
        icon: Icons.payments,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Closing Balance',
        value: money(totalSales - totalReceived),
        icon: Icons.pending_actions,
        color: EnterpriseTheme.error,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Payment Received'],
      rows: [
        for (final e in _dateEntries(receivedTrend)) [e.key, money(e.value)],
      ],
    ),
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Customer-wise sales',
        type: ReportChartType.bar,
        entries: _sortedEntries(salesByCustomer),
      ),
      ReportChartSpec(
        title: 'Customer-wise pending balance',
        type: ReportChartType.bar,
        entries: _sortedEntries({
          for (final customer in state.customers)
            customer.name:
                (salesByCustomer[customer.name] ?? 0) -
                (receivedByCustomer[customer.name] ?? 0),
        }),
      ),
      ReportChartSpec(
        title: 'Date-wise payment received',
        type: ReportChartType.line,
        entries: _dateEntries(receivedTrend),
      ),
    ],
  );
}

ReportBundle _profitLossBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final purchases = state.activePurchases
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final sales = state.activeSales
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final expenses = state.activeExpenses
      .where((item) => _dateInReportFilter(item.date, filter, from, to))
      .toList();
  final purchaseByDate = <String, double>{};
  final salesByDate = <String, double>{};
  final expenseByDate = <String, double>{};
  final expenseByCategory = <String, double>{};
  final materialPurchase = <String, double>{};
  final materialSales = <String, double>{};
  for (final purchase in purchases) {
    _addToMap(
      purchaseByDate,
      _dateKey(purchase.createdAt),
      purchase.totalAmount,
    );
    for (final item in purchase.items) {
      _addToMap(materialPurchase, item.materialName, item.amount);
    }
  }
  for (final sale in sales) {
    _addToMap(salesByDate, _dateKey(sale.createdAt), sale.totalAmount);
    for (final item in sale.items) {
      _addToMap(materialSales, item.materialName, item.amount);
    }
  }
  for (final expense in expenses) {
    _addToMap(expenseByDate, _dateKey(expense.date), expense.amount);
    _addToMap(expenseByCategory, expense.category, expense.amount);
  }
  final totalSales = sales.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalPurchase = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalExpense = expenses.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.amount,
  );
  final grossProfit = totalSales - totalPurchase;
  final netProfit = grossProfit - totalExpense;
  final margin = totalSales == 0 ? 0.0 : (netProfit / totalSales) * 100;
  final allDates = <String>{
    ...purchaseByDate.keys,
    ...salesByDate.keys,
    ...expenseByDate.keys,
  }.toList()..sort();
  final profitByDate = {
    for (final day in allDates)
      day:
          (salesByDate[day] ?? 0) -
          (purchaseByDate[day] ?? 0) -
          (expenseByDate[day] ?? 0),
  };
  final materialProfit = {
    for (final material in <String>{
      ...materialPurchase.keys,
      ...materialSales.keys,
    })
      material:
          (materialSales[material] ?? 0) - (materialPurchase[material] ?? 0),
  };
  final detail = ReportTable(
    headers: const ['Metric', 'Value'],
    rows: [
      ['Total Sales', money(totalSales)],
      ['Total Purchase', money(totalPurchase)],
      ['Other Expenses', money(totalExpense)],
      ['Gross Profit', money(grossProfit)],
      ['Net Profit', money(netProfit)],
      ['Profit Margin %', '${margin.toStringAsFixed(2)}%'],
    ],
  );
  return ReportBundle(
    title: 'Profit/Loss Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Total Sales',
        value: money(totalSales),
        icon: Icons.point_of_sale,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Total Purchase',
        value: money(totalPurchase),
        icon: Icons.shopping_cart,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Other Expenses',
        value: money(totalExpense),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.error,
      ),
      ReportSummaryMetric(
        label: 'Net Profit',
        value: money(netProfit),
        icon: Icons.trending_up,
        color: netProfit >= 0 ? EnterpriseTheme.success : EnterpriseTheme.error,
      ),
      ReportSummaryMetric(
        label: 'Margin',
        value: '${margin.toStringAsFixed(2)}%',
        icon: Icons.percent,
        color: EnterpriseTheme.primary,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Sales', 'Purchase', 'Expenses', 'Profit'],
      rows: [
        for (final day in allDates)
          [
            day,
            money(salesByDate[day] ?? 0),
            money(purchaseByDate[day] ?? 0),
            money(expenseByDate[day] ?? 0),
            money(profitByDate[day] ?? 0),
          ],
      ],
    ),
    detailTable: detail,
    extraSections: [
      ReportTableSection(
        title: 'Expense Impact',
        table: ReportTable(
          headers: const ['Expense', 'Amount'],
          rows: [
            for (final e in _sortedEntries(expenseByCategory))
              [e.key, money(e.value)],
          ],
        ),
      ),
      ReportTableSection(
        title: 'Material-wise Profit',
        table: ReportTable(
          headers: const ['Material', 'Profit/Loss'],
          rows: [
            for (final e in _sortedEntries(materialProfit))
              [e.key, money(e.value)],
          ],
        ),
      ),
    ],
    charts: [
      ReportChartSpec(
        title: 'Date-wise profit',
        type: ReportChartType.line,
        entries: _dateEntries(profitByDate),
      ),
      ReportChartSpec(
        title: 'Sales vs Purchase',
        type: ReportChartType.bar,
        entries: [
          MapEntry('Sales', totalSales),
          MapEntry('Purchase', totalPurchase),
        ],
      ),
      ReportChartSpec(
        title: 'Expense impact',
        type: ReportChartType.pie,
        entries: _sortedEntries(expenseByCategory),
      ),
      ReportChartSpec(
        title: 'Material-wise profit',
        type: ReportChartType.bar,
        entries: _sortedEntries(materialProfit),
      ),
    ],
  );
}

ReportBundle _materialWiseBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final purchases = state.activePurchases
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final sales = state.activeSales
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final purchasedWeight = <String, double>{};
  final soldWeight = <String, double>{};
  final purchaseValue = <String, double>{};
  final salesValue = <String, double>{};
  for (final purchase in purchases) {
    for (final item in purchase.items) {
      _addToMap(purchasedWeight, item.materialName, item.weightKg);
      _addToMap(purchaseValue, item.materialName, item.amount);
    }
  }
  for (final sale in sales) {
    for (final item in sale.items) {
      _addToMap(soldWeight, item.materialName, item.weightKg);
      _addToMap(salesValue, item.materialName, item.amount);
    }
  }
  final names = <String>{
    for (final item in state.activeMaterials) item.name,
    ...purchasedWeight.keys,
    ...soldWeight.keys,
  }.toList()..sort();
  final profit = {
    for (final name in names)
      name: (salesValue[name] ?? 0) - (purchaseValue[name] ?? 0),
  };
  final stock = {
    for (final item in state.activeMaterials) item.name: item.availableKg,
  };
  final detail = ReportTable(
    headers: const [
      'Material',
      'Purchased Weight',
      'Sold Weight',
      'Current Stock',
      'Purchase Value',
      'Sales Value',
      'Profit/Loss',
    ],
    rows: [
      for (final name in names)
        [
          name,
          kg(purchasedWeight[name] ?? 0),
          kg(soldWeight[name] ?? 0),
          kg(stock[name] ?? 0),
          money(purchaseValue[name] ?? 0),
          money(salesValue[name] ?? 0),
          money(profit[name] ?? 0),
        ],
    ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Material-wise Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Materials',
        value: names.length.toString(),
        icon: Icons.inventory_2,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Purchased Weight',
        value: kg(
          purchasedWeight.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.scale,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Sold Weight',
        value: kg(
          soldWeight.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.local_shipping,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Profit/Loss',
        value: money(
          profit.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.trending_up,
        color: EnterpriseTheme.primary,
      ),
    ],
    dateWiseTable: detail,
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Material-wise purchase weight',
        type: ReportChartType.bar,
        entries: _sortedEntries(purchasedWeight),
        valueKind: ReportColumnKind.weight,
      ),
      ReportChartSpec(
        title: 'Material-wise sales weight',
        type: ReportChartType.bar,
        entries: _sortedEntries(soldWeight),
        valueKind: ReportColumnKind.weight,
      ),
      ReportChartSpec(
        title: 'Material-wise profit',
        type: ReportChartType.bar,
        entries: _sortedEntries(profit),
      ),
      ReportChartSpec(
        title: 'Material-wise stock balance',
        type: ReportChartType.bar,
        entries: _sortedEntries(stock),
        valueKind: ReportColumnKind.weight,
      ),
    ],
  );
}

ReportBundle _supervisorPerformanceBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final isOwner = state.user.role.isOwnerOrAdmin;
  bool mine(String value) =>
      value.trim().toLowerCase() == state.user.name.trim().toLowerCase();
  final names = <String>{
    for (final item in state.visibleSupervisorCashSummaries)
      item.supervisorName,
    for (final item in state.activePurchases)
      if (isOwner || mine(item.createdBy)) item.createdBy,
    for (final item in state.activeSales)
      if (isOwner || mine(item.createdBy)) item.createdBy,
    for (final item in state.activeExpenses)
      if (isOwner || mine(item.addedBy)) item.addedBy,
  }..removeWhere((item) => item.trim().isEmpty);
  final purchaseBySupervisor = <String, double>{};
  final salesBySupervisor = <String, double>{};
  final expenseBySupervisor = <String, double>{};
  final cashBySupervisor = <String, double>{};
  final activityBySupervisor = <String, double>{};
  for (final purchase in state.activePurchases.where(
    (item) =>
        _dateInReportFilter(item.createdAt, filter, from, to) &&
        (isOwner || mine(item.createdBy)),
  )) {
    _addToMap(purchaseBySupervisor, purchase.createdBy, purchase.totalAmount);
  }
  for (final sale in state.activeSales.where(
    (item) =>
        _dateInReportFilter(item.createdAt, filter, from, to) &&
        (isOwner || mine(item.createdBy)),
  )) {
    _addToMap(salesBySupervisor, sale.createdBy, sale.totalAmount);
  }
  for (final expense in state.activeExpenses.where(
    (item) =>
        _dateInReportFilter(item.date, filter, from, to) &&
        (isOwner || mine(item.addedBy)),
  )) {
    _addToMap(expenseBySupervisor, expense.addedBy, expense.amount);
  }
  for (final item in state.visibleSupervisorCashSummaries) {
    cashBySupervisor[item.supervisorName] = item.currentCashBalance;
  }
  for (final activity in state.activities) {
    _addToMap(activityBySupervisor, activity.userName, 1);
  }
  String lastActive(String name) {
    final matches =
        state.activities.where((item) => item.userName == name).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.isEmpty ? '-' : shortDate(matches.first.createdAt);
  }

  final detail = ReportTable(
    headers: const [
      'Supervisor',
      'Purchase Handled',
      'Sales Handled',
      'Cash Handled',
      'Expenses Entered',
      'Activity Count',
      'Last Active Time',
    ],
    rows: [
      for (final name in names.toList()..sort())
        [
          name,
          money(purchaseBySupervisor[name] ?? 0),
          money(salesBySupervisor[name] ?? 0),
          money(cashBySupervisor[name] ?? 0),
          money(expenseBySupervisor[name] ?? 0),
          (activityBySupervisor[name] ?? 0).toStringAsFixed(0),
          lastActive(name),
        ],
    ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Supervisor Performance Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Supervisors',
        value: names.length.toString(),
        icon: Icons.supervisor_account,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Purchase Handled',
        value: money(
          purchaseBySupervisor.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.shopping_cart,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Sales Handled',
        value: money(
          salesBySupervisor.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.point_of_sale,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Cash Handled',
        value: money(
          cashBySupervisor.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.account_balance_wallet,
        color: EnterpriseTheme.primary,
      ),
    ],
    dateWiseTable: detail,
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Supervisor-wise purchase',
        type: ReportChartType.bar,
        entries: _sortedEntries(purchaseBySupervisor),
      ),
      ReportChartSpec(
        title: 'Supervisor-wise cash handled',
        type: ReportChartType.bar,
        entries: _sortedEntries(cashBySupervisor),
      ),
      ReportChartSpec(
        title: 'Supervisor activity',
        type: ReportChartType.bar,
        entries: _sortedEntries(activityBySupervisor),
        valueKind: ReportColumnKind.text,
      ),
    ],
  );
}

ReportBundle _supervisorBalanceBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final table = ReportTable(
    headers: const [
      'Supervisor',
      'Cash Given by Owner',
      'Expense',
      'Scrap Purchase',
      'Other Purchase',
      'Inventory Purchase',
      'Remaining Balance',
    ],
    rows: [
      for (final item in state.supervisorBalances)
        [
          item.supervisorName,
          money(item.cashAllocated),
          money(item.expenseTotal),
          money(item.scrapPurchaseTotal),
          money(item.otherPurchaseTotal),
          money(item.inventoryPurchaseTotal),
          money(item.remainingBalance),
        ],
    ],
    landscape: true,
  );
  final balanceMap = {
    for (final item in state.supervisorBalances)
      item.supervisorName: item.remainingBalance,
  };
  return ReportBundle(
    title: 'Supervisor Balance Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Supervisors',
        value: state.supervisorBalances.length.toString(),
        icon: Icons.supervisor_account,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Cash Given',
        value: money(
          state.supervisorBalances.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.cashAllocated,
          ),
        ),
        icon: Icons.payments,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Expenses',
        value: money(
          state.supervisorBalances.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.expenseTotal,
          ),
        ),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.warning,
      ),
      ReportSummaryMetric(
        label: 'Remaining Balance',
        value: money(
          balanceMap.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.account_balance_wallet,
        color: EnterpriseTheme.primary,
      ),
    ],
    dateWiseTable: table,
    detailTable: table,
    charts: [
      ReportChartSpec(
        title: 'Supervisor remaining balance',
        type: ReportChartType.bar,
        entries: _sortedEntries(balanceMap),
      ),
      ReportChartSpec(
        title: 'Supervisor cash given',
        type: ReportChartType.bar,
        entries: _sortedEntries({
          for (final item in state.supervisorBalances)
            item.supervisorName: item.cashAllocated,
        }),
      ),
      ReportChartSpec(
        title: 'Supervisor expense',
        type: ReportChartType.pie,
        entries: _sortedEntries({
          for (final item in state.supervisorBalances)
            item.supervisorName: item.expenseTotal,
        }),
      ),
    ],
  );
}

ReportBundle _expenseReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final expenses = state.activeExpenses
      .where((item) => _dateInReportFilter(item.date, filter, from, to))
      .toList();
  final dateTotals = <String, double>{};
  final categoryTotals = <String, double>{};
  final supervisorTotals = <String, double>{};
  for (final expense in expenses) {
    _addToMap(dateTotals, _dateKey(expense.date), expense.amount);
    _addToMap(categoryTotals, expense.category, expense.amount);
    _addToMap(supervisorTotals, expense.addedBy, expense.amount);
  }
  final total = expenses.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.amount,
  );
  final detail = ReportTable(
    headers: const ['Date', 'Supervisor', 'Description', 'Amount', 'Remarks'],
    rows: [
      for (final expense in expenses)
        [
          shortDate(expense.date),
          expense.addedBy,
          expense.category,
          money(expense.amount),
          expense.remarks,
        ],
    ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Expense Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Total Expense',
        value: money(total),
        icon: Icons.receipt_long,
        color: EnterpriseTheme.error,
      ),
      ReportSummaryMetric(
        label: 'Entries',
        value: expenses.length.toString(),
        icon: Icons.list_alt,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Supervisors',
        value: supervisorTotals.length.toString(),
        icon: Icons.supervisor_account,
        color: EnterpriseTheme.success,
      ),
      ReportSummaryMetric(
        label: 'Categories',
        value: categoryTotals.length.toString(),
        icon: Icons.category,
        color: EnterpriseTheme.warning,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Expense Amount'],
      rows: [
        for (final e in _dateEntries(dateTotals)) [e.key, money(e.value)],
      ],
    ),
    detailTable: detail,
    extraSections: [
      ReportTableSection(
        title: 'Category-wise',
        table: ReportTable(
          headers: const ['Description', 'Amount'],
          rows: [
            for (final e in _sortedEntries(categoryTotals))
              [e.key, money(e.value)],
          ],
        ),
      ),
      ReportTableSection(
        title: 'Supervisor-wise',
        table: ReportTable(
          headers: const ['Supervisor', 'Amount'],
          rows: [
            for (final e in _sortedEntries(supervisorTotals))
              [e.key, money(e.value)],
          ],
        ),
      ),
    ],
    charts: [
      ReportChartSpec(
        title: 'Date-wise expense',
        type: ReportChartType.bar,
        entries: _dateEntries(dateTotals),
      ),
      ReportChartSpec(
        title: 'Expense category split',
        type: ReportChartType.pie,
        entries: _sortedEntries(categoryTotals),
      ),
      ReportChartSpec(
        title: 'Supervisor-wise expense',
        type: ReportChartType.bar,
        entries: _sortedEntries(supervisorTotals),
      ),
    ],
  );
}

ReportBundle _auditReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final audits = state.auditTrail
      .where((item) => _dateInReportFilter(item.createdAt, filter, from, to))
      .toList();
  final actionTotals = <String, double>{};
  final dateTotals = <String, double>{};
  for (final audit in audits) {
    _addToMap(actionTotals, audit.action, 1);
    _addToMap(dateTotals, _dateKey(audit.createdAt), 1);
  }
  final detail = ReportTable(
    headers: const ['Action', 'Field', 'Old', 'New', 'User', 'Date'],
    rows: [
      for (final item in audits)
        [
          item.action,
          item.field,
          item.oldValue,
          item.newValue,
          item.user,
          shortDate(item.createdAt),
        ],
    ],
    landscape: true,
  );
  return ReportBundle(
    title: 'Audit Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Audit Entries',
        value: audits.length.toString(),
        icon: Icons.fact_check,
        color: EnterpriseTheme.primary,
      ),
      ReportSummaryMetric(
        label: 'Action Types',
        value: actionTotals.length.toString(),
        icon: Icons.category,
        color: EnterpriseTheme.warning,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Audit Count'],
      rows: [
        for (final e in _dateEntries(dateTotals))
          [e.key, e.value.toStringAsFixed(0)],
      ],
    ),
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Date-wise audit count',
        type: ReportChartType.bar,
        entries: _dateEntries(dateTotals),
        valueKind: ReportColumnKind.text,
      ),
      ReportChartSpec(
        title: 'Action-wise audit count',
        type: ReportChartType.pie,
        entries: _sortedEntries(actionTotals),
        valueKind: ReportColumnKind.text,
      ),
    ],
  );
}

ReportBundle _deletedReportBundle(
  BusinessState state,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final deletedPurchases = state.deletedPurchases
      .where(
        (item) =>
            item.deletedAt == null ||
            _dateInReportFilter(item.deletedAt!, filter, from, to),
      )
      .toList();
  final deletedSales = state.deletedSales
      .where(
        (item) =>
            item.deletedAt == null ||
            _dateInReportFilter(item.deletedAt!, filter, from, to),
      )
      .toList();
  final dateTotals = <String, double>{};
  for (final item in deletedPurchases) {
    _addToMap(
      dateTotals,
      _dateKey(item.deletedAt ?? item.createdAt),
      item.totalAmount,
    );
  }
  for (final item in deletedSales) {
    _addToMap(
      dateTotals,
      _dateKey(item.deletedAt ?? item.createdAt),
      item.totalAmount,
    );
  }
  final rows = [
    for (final item in deletedPurchases)
      [
        'Purchase',
        item.invoiceNumber,
        item.seller.name,
        money(item.totalAmount),
        item.deletedBy,
        shortDate(item.deletedAt ?? item.createdAt),
      ],
    for (final item in deletedSales)
      [
        'Sale',
        item.invoiceNumber,
        item.customer.name,
        money(item.totalAmount),
        item.deletedBy,
        shortDate(item.deletedAt ?? item.createdAt),
      ],
  ];
  final detail = ReportTable(
    headers: const ['Type', 'Invoice', 'Party', 'Amount', 'Deleted By', 'Date'],
    rows: rows,
    landscape: true,
  );
  return ReportBundle(
    title: 'Deleted Transaction Report',
    filterType: filter,
    dateRange: _dateRangeLabel(filter, from, to),
    summaryCards: [
      ReportSummaryMetric(
        label: 'Deleted Rows',
        value: rows.length.toString(),
        icon: Icons.delete_outline,
        color: EnterpriseTheme.error,
      ),
      ReportSummaryMetric(
        label: 'Deleted Amount',
        value: money(
          dateTotals.values.fold<double>(
            0,
            (runningTotal, value) => runningTotal + value,
          ),
        ),
        icon: Icons.payments,
        color: EnterpriseTheme.warning,
      ),
    ],
    dateWiseTable: ReportTable(
      headers: const ['Date', 'Deleted Amount'],
      rows: [
        for (final e in _dateEntries(dateTotals)) [e.key, money(e.value)],
      ],
    ),
    detailTable: detail,
    charts: [
      ReportChartSpec(
        title: 'Date-wise deleted amount',
        type: ReportChartType.bar,
        entries: _dateEntries(dateTotals),
      ),
      ReportChartSpec(
        title: 'Deleted type count',
        type: ReportChartType.pie,
        entries: [
          MapEntry('Purchase', deletedPurchases.length.toDouble()),
          MapEntry('Sale', deletedSales.length.toDouble()),
        ],
        valueKind: ReportColumnKind.text,
      ),
    ],
  );
}

class OwnerAnalyticsScreen extends ConsumerWidget {
  const OwnerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final metrics = state.metrics;
    return Scaffold(
      appBar: AppBar(title: const Text('Owner Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              StatPanel(
                label: "Today's Purchase",
                value: money(metrics.todayPurchase),
                icon: Icons.shopping_cart,
              ),
              StatPanel(
                label: "Today's Sale",
                value: money(metrics.todaySales),
                icon: Icons.point_of_sale,
              ),
              StatPanel(
                label: "Today's Profit",
                value: money(metrics.todaySales - metrics.todayPurchase),
                icon: Icons.trending_up,
              ),
              StatPanel(
                label: 'Cash Position',
                value: money(metrics.cashBalance),
                icon: Icons.account_balance_wallet,
              ),
              StatPanel(
                label: 'Stock Value',
                value: money(metrics.stockValue),
                icon: Icons.inventory_2,
              ),
              StatPanel(
                label: 'Audit Logs',
                value: state.auditTrail.length.toString(),
                icon: Icons.fact_check,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnalyticsBars(title: 'Top Sellers', rows: _topParties(state.sellers)),
          const SizedBox(height: 12),
          AnalyticsBars(
            title: 'Top Customers',
            rows: _topParties(state.customers),
          ),
          const SizedBox(height: 12),
          AnalyticsBars(
            title: 'Top Materials',
            rows: _topMaterials(state.activeMaterials),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, double>> _topParties(List<Party> rows) {
    return rows
        .map((item) => MapEntry(item.name, item.pendingAmount.abs()))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  List<MapEntry<String, double>> _topMaterials(List<MaterialStock> rows) {
    return rows.map((item) => MapEntry(item.name, item.stockValue)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }
}

class ConfidentialProfitScreen extends ConsumerStatefulWidget {
  const ConfidentialProfitScreen({super.key});

  @override
  ConsumerState<ConfidentialProfitScreen> createState() =>
      _ConfidentialProfitScreenState();
}

class _ConfidentialProfitScreenState
    extends ConsumerState<ConfidentialProfitScreen> {
  final _selling = TextEditingController();
  final _transport = TextEditingController();
  final _labour = TextEditingController();
  final _other = TextEditingController();
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_recordAccess);
  }

  @override
  void dispose() {
    _selling.dispose();
    _transport.dispose();
    _labour.dispose();
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final profile = ref.watch(authProfileProvider);
    final isOwner =
        profile?.role.isOwnerOrAdmin == true || state.user.role.isOwnerOrAdmin;
    if (!isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confidential Profit Analytics')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FeaturePanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 42),
                  const SizedBox(height: 12),
                  const Text(
                    'You do not have permission to view this information.',
                    style: TextStyle(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Login with the owner account to view confidential profit analytics.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final purchaseCost = state.activePurchases.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.totalAmount,
    );
    final sellingAmount = _read(_selling) == 0
        ? state.activeSales.fold<double>(
            0,
            (runningTotal, item) => runningTotal + item.totalAmount,
          )
        : _read(_selling);
    final expense = _read(_transport) + _read(_labour) + _read(_other);
    final profit = sellingAmount - purchaseCost - expense;
    final margin = sellingAmount <= 0 ? 0 : (profit / sellingAmount) * 100;

    return Scaffold(
      appBar: AppBar(title: const Text('Confidential Profit Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                NumberText(
                  controller: _selling,
                  label: 'Actual Selling Amount',
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NumberText(
                        controller: _transport,
                        label: 'Transport',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NumberText(
                        controller: _labour,
                        label: 'Labour',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NumberText(
                  controller: _other,
                  label: 'Other Expenses',
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              children: [
                AmountLine(label: 'Purchase Cost', value: money(purchaseCost)),
                AmountLine(
                  label: 'Selling Amount',
                  value: money(sellingAmount),
                ),
                AmountLine(label: 'Expenses', value: money(expense)),
                AmountLine(
                  label: 'Profit / Loss',
                  value: money(profit),
                  color: profit >= 0
                      ? EnterpriseTheme.success
                      : EnterpriseTheme.error,
                ),
                AmountLine(
                  label: 'Margin %',
                  value: '${margin.toStringAsFixed(1)}%',
                ),
                AmountLine(
                  label: 'Stock Valuation Difference',
                  value: money(state.metrics.profitLoss),
                ),
                AmountLine(
                  label: 'Supervisor Cash Gap',
                  value: money(state.metrics.cashBalance),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnalyticsBars(
            title: 'Material-wise Gap',
            rows: [
              for (final item in state.activeMaterials)
                MapEntry(
                  item.name,
                  item.availableKg *
                      ((item.currentSellingRate == 0
                              ? item.currentBuyingRate
                              : item.currentSellingRate) -
                          item.currentBuyingRate),
                ),
            ]..sort((a, b) => b.value.compareTo(a.value)),
          ),
          const SizedBox(height: 12),
          AnalyticsBars(
            title: 'Seller Profit Gap',
            rows: [
              for (final item in state.sellers)
                MapEntry(item.name, item.pendingAmount.abs()),
            ]..sort((a, b) => b.value.compareTo(a.value)),
          ),
          const SizedBox(height: 12),
          AnalyticsBars(
            title: 'Cash Movement',
            rows: [
              MapEntry('Cash Given', state.metrics.cashGiven),
              MapEntry('Purchase', state.metrics.cashUsed),
              MapEntry('Sales Collection', state.metrics.salesCollection),
              MapEntry('Balance', state.metrics.cashBalance.abs()),
            ],
          ),
        ],
      ),
    );
  }

  void _recordAccess() {
    if (!mounted || _logged) {
      return;
    }
    _logged = true;
    final state = ref.read(businessProvider);
    final profile = ref.read(authProfileProvider);
    final isOwner =
        profile?.role.isOwnerOrAdmin == true || state.user.role.isOwnerOrAdmin;
    final notifier = ref.read(businessProvider.notifier);
    if (isOwner) {
      notifier.recordConfidentialProfitViewed();
    } else {
      notifier.recordUnauthorizedConfidentialAccess();
    }
  }
}

class FastScrapEntryScreen extends ConsumerStatefulWidget {
  const FastScrapEntryScreen({super.key});

  @override
  ConsumerState<FastScrapEntryScreen> createState() =>
      _FastScrapEntryScreenState();
}

class _FastScrapEntryScreenState extends ConsumerState<FastScrapEntryScreen> {
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  Party? _seller;
  MaterialStock? _material;
  bool _repeatSeller = true;
  bool _repeatMaterial = false;
  bool _continuous = false;

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final amount = _read(_weight) * _read(_rate);
    return Scaffold(
      appBar: AppBar(title: const Text('Fast Scrap Entry')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('BIG SAVE'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PartyDropdown(
            label: 'Seller',
            value: _seller,
            items: state.sellers,
            emptyLabel: 'Add seller',
            onAdd: () async {
              final created = await showPartyEditor(
                context,
                ref,
                PartyKind.seller,
              );
              if (created != null) setState(() => _seller = created);
            },
            onChanged: (value) => setState(() => _seller = value),
          ),
          if (_seller != null) ...[
            const SizedBox(height: 10),
            SellerSnapshot(seller: _seller!),
          ],
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              for (final material in state.activeMaterials.where(
                (item) => item.isActive,
              ))
                InkWell(
                  onTap: () => setState(() {
                    _material = material;
                    _rate.text = material.currentBuyingRate.toStringAsFixed(0);
                  }),
                  child: FeaturePanel(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EntityAvatar(
                          path: material.photoPath,
                          icon: Icons.recycling,
                          size: 54,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          material.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_material != null) MaterialSnapshot(material: _material!),
          const SizedBox(height: 12),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(
              labelText: 'BIG Weight (KG)',
              prefixIcon: Icon(Icons.scale),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(labelText: 'Rate'),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              children: [
                AmountLine(
                  label: 'Preview Material',
                  value: _material?.name ?? '-',
                ),
                AmountLine(label: 'Weight', value: kg(_read(_weight))),
                AmountLine(label: 'Rate', value: money(_read(_rate))),
                AmountLine(
                  label: 'Total',
                  value: money(amount),
                  color: EnterpriseTheme.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SwitchListTile.adaptive(
                  title: const Text('Repeat seller'),
                  value: _repeatSeller,
                  onChanged: (value) => setState(() => _repeatSeller = value),
                ),
              ),
              Expanded(
                child: SwitchListTile.adaptive(
                  title: const Text('Repeat material'),
                  value: _repeatMaterial,
                  onChanged: (value) => setState(() => _repeatMaterial = value),
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            title: const Text('Speak continuously'),
            value: _continuous,
            onChanged: (value) => setState(() => _continuous = value),
          ),
          FilledButton.icon(
            onPressed: _voice,
            icon: const Icon(Icons.mic),
            label: Text(
              _continuous ? 'Listen Continuous Entry' : 'Voice Entry',
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _voice() async {
    final command = await showVoiceCommandDialog(
      context,
      ref: ref,
      title: 'Fast Purchase Voice Entry',
      helpText: _purchaseVoiceHelpText,
    );
    if (command == null) return;
    final draft = parseSmartPurchaseCommand(command);
    if (draft == null) {
      ref
          .read(businessProvider.notifier)
          .recordVoiceActivity('voice_command_failed', command);
      if (mounted) _snack(context, 'Weight or rate missing');
      return;
    }
    final state = ref.read(businessProvider);
    setState(() {
      _seller = _bestPartyMatch(state.sellers, draft.sellerName) ?? _seller;
      _material = _bestMaterialMatch(state.activeMaterials, draft.materialName);
      _weight.text = _voiceNumberString(draft.weightKg);
      _rate.text = _voiceNumberString(draft.rate);
    });
    if (_continuous && _isVoiceSaveCommand(command)) {
      _save();
      ref
          .read(businessProvider.notifier)
          .recordVoiceActivity(
            'voice_purchase_saved',
            _seller?.name ?? draft.materialName,
          );
    }
  }

  void _save() {
    if (_seller == null) {
      _snack(context, 'Seller missing');
      return;
    }
    if (_material == null) {
      _snack(context, 'Material missing');
      return;
    }
    if (_read(_weight) <= 0) {
      _snack(context, 'Weight missing');
      return;
    }
    if (_read(_rate) <= 0) {
      _snack(context, 'Rate missing');
      return;
    }
    ref
        .read(businessProvider.notifier)
        .addPurchase(
          seller: _seller!,
          items: [
            LineItem(
              materialId: _material!.id,
              materialName: _material!.name,
              materialPhotoPath: _material!.photoPath,
              weightKg: _read(_weight),
              wastageDeductionPercent:
                  _material!.normalizedWastageDeductionPercent,
              effectiveWeight: _effectiveWeightFor(_read(_weight), _material!),
              rate: _read(_rate),
            ),
          ],
          paidAmount: 0,
        );
    _snack(context, 'Saved');
    setState(() {
      _weight.clear();
      if (!_repeatSeller) _seller = null;
      if (!_repeatMaterial) {
        _material = null;
        _rate.clear();
      }
    });
  }
}

class DeletedTransactionsScreen extends ConsumerWidget {
  const DeletedTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessProvider);
    final rows = <Widget>[
      for (final item in state.deletedPurchases)
        _DeletedTile(
          title: 'Purchase ${item.invoiceNumber}',
          subtitle:
              '${item.seller.name}  |  ${money(item.totalAmount)}  |  ${_recycleBinStatus(item.deletedAt)}',
          onRestore: () =>
              ref.read(businessProvider.notifier).restorePurchase(item),
        ),
      for (final item in state.deletedSales)
        _DeletedTile(
          title: 'Sale ${item.invoiceNumber}',
          subtitle:
              '${item.customer.name}  |  ${money(item.totalAmount)}  |  ${_recycleBinStatus(item.deletedAt)}',
          onRestore: () =>
              ref.read(businessProvider.notifier).restoreSale(item),
        ),
    ];
    final content = <Widget>[
      const _RecycleBinInfoPanel(),
      if (rows.isEmpty)
        const EmptyFeatureState(
          icon: Icons.restore,
          title: 'Recycle Bin empty',
          subtitle: 'Deleted purchases and sales stay here for 30 days.',
        )
      else
        ...rows,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle Bin')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: content.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => content[index],
      ),
    );
  }
}

class _RecycleBinInfoPanel extends StatelessWidget {
  const _RecycleBinInfoPanel();

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.delete_sweep),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Owner can restore deleted records for ${BusinessController.recycleBinRetention.inDays} days. Expired records are permanently removed automatically.',
              style: const TextStyle(color: Color(0xFF334155), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

String _recycleBinStatus(DateTime? deletedAt) {
  final daysLeft = _recycleBinDaysLeft(deletedAt);
  if (daysLeft == 0) {
    return 'Expires today';
  }
  if (daysLeft == 1) {
    return '1 day left';
  }
  return '$daysLeft days left';
}

int _recycleBinDaysLeft(DateTime? deletedAt) {
  if (deletedAt == null) {
    return BusinessController.recycleBinRetention.inDays;
  }
  final elapsedDays = DateTime.now().difference(deletedAt).inDays;
  final remainingDays =
      BusinessController.recycleBinRetention.inDays - elapsedDays;
  return remainingDays
      .clamp(0, BusinessController.recycleBinRetention.inDays)
      .toInt();
}

class _DeletedTile extends StatelessWidget {
  const _DeletedTile({
    required this.title,
    required this.subtitle,
    required this.onRestore,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Row(
        children: [
          const Icon(Icons.restore_from_trash),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          FilledButton(onPressed: onRestore, child: const Text('Restore')),
        ],
      ),
    );
  }
}

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  String _fontSize = 'Medium';
  bool _simpleMode = true;
  bool _advancedMode = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getString('theme_font_size') ?? _fontSize;
      _simpleMode = prefs.getBool('simple_supervisor_mode') ?? _simpleMode;
      _advancedMode = prefs.getBool('owner_advanced_mode') ?? _advancedMode;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_font_size', _fontSize);
    await prefs.setBool('simple_supervisor_mode', _simpleMode);
    await prefs.setBool('owner_advanced_mode', _advancedMode);
    if (mounted) _snack(context, 'Settings saved locally');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final selectedTheme = ref
        .watch(enterpriseThemeModeProvider)
        .maybeWhen(
          data: (mode) => mode,
          orElse: () => EnterpriseThemeMode.midnightBlue,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              children: [
                DropdownButtonFormField<EnterpriseThemeMode>(
                  initialValue: selectedTheme,
                  decoration: const InputDecoration(
                    labelText: 'Theme Settings',
                  ),
                  items: EnterpriseThemeMode.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) {
                      return;
                    }
                    await ref
                        .read(enterpriseThemeModeProvider.notifier)
                        .setMode(value);
                    ref
                        .read(businessProvider.notifier)
                        .recordThemeChanged(value.label);
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThemeSettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.palette),
                  label: const Text('Open Premium Theme Settings'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _fontSize,
                  decoration: const InputDecoration(labelText: 'Font size'),
                  items: const ['Small', 'Medium', 'Large']
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _fontSize = value ?? _fontSize),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Simple Supervisor Mode'),
                  value: _simpleMode,
                  onChanged: (value) => setState(() => _simpleMode = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Owner Advanced Mode'),
                  value: _advancedMode,
                  onChanged: (value) => setState(() => _advancedMode = value),
                ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              children: [
                FilledButton.icon(
                  onPressed: () => _exportBackup(state),
                  icon: const Icon(Icons.backup),
                  label: const Text('Export Local Backup'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _snack(
                    context,
                    'Restore backup: import the exported JSON into Firestore or use the migration script.',
                  ),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Backup'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BusinessState state) async {
    final backup = jsonEncode({
      'owner': state.user.name,
      'generatedAt': DateTime.now().toIso8601String(),
      'purchases': state.purchases.length,
      'sales': state.sales.length,
      'materials': state.activeMaterials.length,
      'sellers': state.sellers.length,
      'customers': state.customers.length,
      'summary': state.reportSummary,
    });
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        _snack(context, 'Backup JSON copied to clipboard. Save it manually.');
      }
      return;
    }
    final path = await saveTextFile('scrap_backup.json', backup);
    if (mounted) _snack(context, 'Backup exported: $path');
  }
}

Future<Party?> showPartyEditor(
  BuildContext context,
  WidgetRef ref,
  PartyKind kind, {
  Party? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final mobile = TextEditingController(text: existing?.mobile ?? '');
  final area = TextEditingController(text: existing?.area ?? '');
  final address = TextEditingController(text: existing?.address ?? '');
  final remarks = TextEditingController(text: existing?.remarks ?? '');
  var photoPath = existing?.photoPath ?? '';
  final result = await showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: existing == null
            ? (kind == PartyKind.seller ? 'Add Seller' : 'Add Customer')
            : (kind == PartyKind.seller ? 'Edit Seller' : 'Edit Customer'),
        child: Column(
          children: [
            EntityAvatar(
              path: photoPath,
              icon: kind == PartyKind.seller ? Icons.storefront : Icons.person,
              size: 62,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => photoPath = ''),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.camera);
                      if (path != null) setState(() => photoPath = path);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.gallery);
                      if (path != null) setState(() => photoPath = path);
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: area,
              decoration: const InputDecoration(labelText: 'Area'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty || mobile.text.trim().isEmpty) {
                  _snack(context, 'Name and mobile are required.');
                  return;
                }
                final current = existing;
                final party = current == null
                    ? ref
                          .read(businessProvider.notifier)
                          .addParty(
                            name: name.text,
                            mobile: mobile.text,
                            area: area.text,
                            address: address.text,
                            remarks: remarks.text,
                            photoPath: photoPath,
                            kind: kind,
                          )
                    : current.copyWith(
                        name: name.text.trim(),
                        mobile: mobile.text.trim(),
                        area: area.text.trim(),
                        address: address.text.trim(),
                        remarks: remarks.text.trim(),
                        photoPath: photoPath,
                      );
                if (current != null) {
                  ref.read(businessProvider.notifier).updateParty(party);
                }
                Navigator.of(context).pop(party);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
  name.dispose();
  mobile.dispose();
  area.dispose();
  address.dispose();
  remarks.dispose();
  return result;
}

Future<MaterialStock?> showMaterialEditor(
  BuildContext context,
  WidgetRef ref, {
  MaterialStock? existing,
}) async {
  final isOwner = ref.read(businessProvider).user.role.isOwnerOrAdmin;
  if (!isOwner) {
    _snack(context, 'Only owner can create or edit materials.');
    return null;
  }
  final name = TextEditingController(text: existing?.name ?? '');
  final category = TextEditingController(text: existing?.category ?? '');
  final rate = TextEditingController(
    text: existing?.currentBuyingRate.toStringAsFixed(0) ?? '',
  );
  final sellingRate = TextEditingController(
    text: existing?.currentSellingRate.toStringAsFixed(0) ?? '',
  );
  final wastageDeduction = TextEditingController(
    text: existing?.normalizedWastageDeductionPercent.toStringAsFixed(0) ?? '',
  );
  var photoPath = existing?.photoPath ?? '';
  var isActive = existing?.isActive ?? true;
  final result = await showModalBottomSheet<MaterialStock>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: existing == null ? 'Add Material' : 'Edit Material',
        child: Column(
          children: [
            EntityAvatar(path: photoPath, icon: Icons.recycling, size: 62),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.camera);
                      if (path != null) setState(() => photoPath = path);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.gallery);
                      if (path != null) setState(() => photoPath = path);
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => photoPath = ''),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete Photo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Material Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: category,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 10),
            NumberText(
              controller: rate,
              label: 'Current Buying Rate',
              onChanged: () {},
            ),
            const SizedBox(height: 10),
            NumberText(
              controller: sellingRate,
              label: 'Current Selling Rate',
              onChanged: () {},
            ),
            const SizedBox(height: 10),
            NumberText(
              controller: wastageDeduction,
              label: 'Wastage Deduction %',
              onChanged: () {},
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active material'),
              value: isActive,
              onChanged: (value) => setState(() => isActive = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  _snack(context, 'Material name is required.');
                  return;
                }
                final current = existing;
                final material = current == null
                    ? ref
                          .read(businessProvider.notifier)
                          .addMaterial(
                            name: name.text,
                            category: category.text,
                            rate: _read(rate),
                            photoPath: photoPath,
                            currentSellingRate: _read(sellingRate),
                            wastageDeductionPercent: _read(
                              wastageDeduction,
                            ).clamp(0, 100).toDouble(),
                            isActive: isActive,
                          )
                    : current.copyWith(
                        name: name.text.trim(),
                        category: category.text.trim().isEmpty
                            ? 'General'
                            : category.text.trim(),
                        currentBuyingRate: _read(rate),
                        photoPath: photoPath,
                        currentSellingRate: _read(sellingRate),
                        wastageDeductionPercent: _read(
                          wastageDeduction,
                        ).clamp(0, 100).toDouble(),
                        isActive: isActive,
                      );
                if (current != null) {
                  ref.read(businessProvider.notifier).updateMaterial(material);
                }
                Navigator.of(context).pop(material);
              },
              child: const Text('Save Material'),
            ),
          ],
        ),
      ),
    ),
  );
  name.dispose();
  category.dispose();
  rate.dispose();
  sellingRate.dispose();
  wastageDeduction.dispose();
  return result;
}

Future<void> showCashAllocationDialog(
  BuildContext context,
  WidgetRef ref, {
  CashAllocation? existing,
}) async {
  final state = ref.read(businessProvider);
  final isOwner = state.user.role.isOwnerOrAdmin;
  final isManager = state.user.role == UserRole.manager;
  if (existing == null && !isOwner) {
    _snack(context, 'Only Owner/Admin can allocate cash.');
    return;
  }
  if (existing != null && !isOwner && !isManager) {
    _snack(context, 'Supervisors cannot edit cash allocation.');
    return;
  }

  final staffNames = _cashStaffNameOptions(state, existing?.supervisorName);
  var selectedSupervisor = existing?.supervisorName.trim().isNotEmpty == true
      ? existing!.supervisorName.trim()
      : staffNames.first;
  if (!staffNames.any((item) => item == selectedSupervisor)) {
    selectedSupervisor = staffNames.first;
  }
  final amount = TextEditingController(
    text: existing?.amount.toStringAsFixed(0) ?? '',
  );
  final remarks = TextEditingController(text: existing?.remarks ?? '');
  var allocationDate = existing?.date ?? DateTime.now();
  var paymentMode = existing?.paymentMode ?? 'Cash';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: existing == null ? 'Cash Allocation' : 'Edit Cash Allocation',
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedSupervisor,
              decoration: const InputDecoration(
                labelText: 'Supervisor / Manager',
              ),
              items: staffNames
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: isOwner
                  ? (value) => setState(
                      () => selectedSupervisor = value ?? selectedSupervisor,
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: allocationDate,
                        firstDate: DateTime(now.year - 2, now.month, now.day),
                        lastDate: DateTime(now.year + 2, now.month, now.day),
                      );
                      if (picked != null) {
                        setState(
                          () => allocationDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            allocationDate.hour,
                            allocationDate.minute,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_stockCompactDate(allocationDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(allocationDate),
                      );
                      if (picked != null) {
                        setState(
                          () => allocationDate = DateTime(
                            allocationDate.year,
                            allocationDate.month,
                            allocationDate.day,
                            picked.hour,
                            picked.minute,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      _formatTimeOfDay(TimeOfDay.fromDateTime(allocationDate)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NumberText(controller: amount, label: 'Amount', onChanged: () {}),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: _paymentModes
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => paymentMode = value ?? paymentMode),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (selectedSupervisor.trim().isEmpty) {
                  _snack(context, 'Supervisor/Manager is required.');
                  return;
                }
                if (_read(amount) <= 0) {
                  _snack(context, 'Enter a positive cash amount.');
                  return;
                }
                final notifier = ref.read(businessProvider.notifier);
                final current = existing;
                if (current == null) {
                  notifier.addCashAllocation(
                    supervisorName: selectedSupervisor,
                    amount: _read(amount),
                    allocationDate: allocationDate,
                    paymentMode: paymentMode,
                    remarks: remarks.text,
                  );
                } else {
                  notifier.updateCashAllocation(
                    current.copyWith(
                      supervisorName: selectedSupervisor.trim(),
                      amount: _read(amount),
                      allocationDate: allocationDate,
                      paymentMode: paymentMode,
                      remarks: remarks.text.trim(),
                    ),
                  );
                }
                Navigator.of(context).pop();
                _snack(context, 'Cash allocation saved');
              },
              icon: const Icon(Icons.save),
              label: Text(existing == null ? 'Save Entry' : 'Update Entry'),
            ),
          ],
        ),
      ),
    ),
  );
  amount.dispose();
  remarks.dispose();
}

Future<void> showStaffNameCorrectionDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(businessProvider);
  if (!state.user.role.isOwnerOrAdmin) {
    _snack(context, 'Only Owner/Admin can correct supervisor/manager names.');
    return;
  }
  final names = _cashStaffNameOptions(state, null);
  var oldName = names.first;
  final newName = TextEditingController(text: oldName);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Correct Supervisor/Manager Name',
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: oldName,
              decoration: const InputDecoration(labelText: 'Wrong / Old Name'),
              items: names
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) {
                final selected = value ?? oldName;
                setState(() {
                  oldName = selected;
                  newName.text = selected;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newName,
              decoration: const InputDecoration(
                labelText: 'Correct Name',
                helperText:
                    'This updates cash allocation, purchase, sale and expense records that used the old name.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (newName.text.trim().isEmpty) {
                  _snack(context, 'Correct name is required.');
                  return;
                }
                ref
                    .read(businessProvider.notifier)
                    .correctStaffNameAcrossCashRecords(
                      oldName: oldName,
                      newName: newName.text,
                    );
                Navigator.of(context).pop();
                _snack(context, 'Supervisor/manager name corrected');
              },
              icon: const Icon(Icons.save),
              label: const Text('Correct Name'),
            ),
          ],
        ),
      ),
    ),
  );
  newName.dispose();
}

List<String> _cashStaffNameOptions(BusinessState state, String? existingName) {
  final names = <String>{
    ...state.cashAllocationStaffNames,
    state.user.name.trim(),
    if (existingName != null && existingName.trim().isNotEmpty)
      existingName.trim(),
  };
  names.removeWhere((item) => item.trim().isEmpty);
  if (names.isEmpty) {
    names.add('Mohit Kumar');
  }
  return names.toList()..sort((a, b) => a.compareTo(b));
}

Future<void> showExpenseDialog(
  BuildContext context,
  WidgetRef ref, {
  ExpenseRecord? existing,
}) async {
  var expenseDate = existing?.date ?? DateTime.now();
  var category = existing?.category ?? _expenseCategories.first;
  final amount = TextEditingController(
    text: existing?.amount.toStringAsFixed(0) ?? '',
  );
  final vendor = TextEditingController(text: existing?.vendorName ?? '');
  final supervisor = TextEditingController(
    text: existing?.addedBy ?? ref.read(businessProvider).user.name,
  );
  final remarks = TextEditingController(text: existing?.remarks ?? '');
  var billUploadPath = existing?.billUploadPath ?? '';
  var photoPath = existing?.photoPath ?? '';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: existing == null ? 'Add Expense' : 'Edit Expense',
        child: Column(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: expenseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => expenseDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(shortDate(expenseDate)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _expenseCategories
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => category = value ?? category),
            ),
            const SizedBox(height: 10),
            NumberText(controller: amount, label: 'Amount', onChanged: () {}),
            const SizedBox(height: 10),
            TextField(
              controller: supervisor,
              decoration: const InputDecoration(labelText: 'Added By'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: vendor,
              decoration: const InputDecoration(labelText: 'Vendor Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.gallery);
                      if (path != null) {
                        setState(() => billUploadPath = path);
                      }
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Bill'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickImage(ImageSource.camera);
                      if (path != null) {
                        setState(() => photoPath = path);
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Photo'),
                  ),
                ),
              ],
            ),
            if (billUploadPath.isNotEmpty || photoPath.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (billUploadPath.isNotEmpty) 'Bill attached',
                  if (photoPath.isNotEmpty) 'Photo attached',
                ].join('  |  '),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (_read(amount) <= 0) {
                  _snack(context, 'Enter a positive amount.');
                  return;
                }
                if (supervisor.text.trim().isEmpty) {
                  _snack(context, 'Added By is required.');
                  return;
                }
                final notifier = ref.read(businessProvider.notifier);
                final current = existing;
                if (current == null) {
                  notifier.addExpense(
                    category: category,
                    amount: _read(amount),
                    expenseDate: expenseDate,
                    vendorName: vendor.text,
                    remarks: remarks.text,
                    billUploadPath: billUploadPath,
                    photoPath: photoPath,
                    addedBy: supervisor.text,
                  );
                } else {
                  notifier.updateExpense(
                    current.copyWith(
                      category: category,
                      amount: _read(amount),
                      expenseDate: expenseDate,
                      vendorName: vendor.text.trim(),
                      remarks: remarks.text.trim(),
                      billUploadPath: billUploadPath,
                      photoPath: photoPath,
                      addedBy: supervisor.text.trim(),
                    ),
                  );
                }
                Navigator.of(context).pop();
                _snack(context, 'Expense saved');
              },
              icon: const Icon(Icons.save),
              label: Text(existing == null ? 'Save Expense' : 'Update Expense'),
            ),
          ],
        ),
      ),
    ),
  );

  amount.dispose();
  vendor.dispose();
  supervisor.dispose();
  remarks.dispose();
}

Future<void> showInventoryAdjustmentDialog(
  BuildContext context,
  WidgetRef ref,
  MaterialStock material,
) async {
  final quantity = TextEditingController(
    text: material.availableKg.toStringAsFixed(0),
  );
  final reason = TextEditingController(text: 'Physical stock verified');
  var entryDate = DateTime.now();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Physical Stock Entry',
        child: Column(
          children: [
            MaterialSnapshot(material: material),
            const SizedBox(height: 10),
            NumberText(
              controller: quantity,
              label: 'Physical Stock (KG)',
              onChanged: () {},
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: entryDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => entryDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(shortDate(entryDate)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (_read(quantity) < 0) {
                  _snack(context, 'Stock cannot be negative.');
                  return;
                }
                if (reason.text.trim().isEmpty) {
                  _snack(context, 'Reason is required.');
                  return;
                }
                ref
                    .read(businessProvider.notifier)
                    .adjustMaterialStock(
                      material: material,
                      availableKg: _read(quantity),
                      reason: reason.text,
                      entryDate: entryDate,
                    );
                Navigator.of(context).pop();
                _snack(context, 'Physical stock saved');
              },
              icon: const Icon(Icons.scale),
              label: const Text('Save Physical Stock'),
            ),
          ],
        ),
      ),
    ),
  );
  quantity.dispose();
  reason.dispose();
}

Future<void> showBusinessVoiceCommand(
  BuildContext context,
  WidgetRef ref, {
  String? initialCommand,
}) async {
  final command =
      initialCommand ??
      await showVoiceCommandDialog(
        context,
        ref: ref,
        title: 'Business Voice Command',
        helpText:
            'Say cash allocation, supervisor name, amount, payment mode, expense category, or go back.',
      );
  if (command == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final draft = parseBusinessVoiceCommand(command);
  if (draft == null) {
    ref
        .read(businessProvider.notifier)
        .recordVoiceActivity('voice_command_failed', command);
    if (context.mounted) {
      _snack(context, 'Sorry, I could not understand. Please try again.');
    }
    return;
  }
  if (draft is VoiceCashAllocationDraft) {
    await _confirmVoiceCash(context, ref, draft);
    return;
  }
  if (draft is VoiceSupervisorExpenseDraft) {
    await _confirmVoiceExpense(context, ref, draft);
  }
}

Future<void> _confirmVoiceCash(
  BuildContext context,
  WidgetRef ref,
  VoiceCashAllocationDraft draft,
) async {
  final supervisor = TextEditingController(text: draft.supervisorName);
  final amount = TextEditingController(text: draft.amount.toStringAsFixed(0));
  var paymentMode = draft.paymentMode;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Confirm Cash Allocation',
        child: Column(
          children: [
            TextField(
              controller: supervisor,
              decoration: const InputDecoration(labelText: 'Supervisor'),
            ),
            const SizedBox(height: 10),
            NumberText(controller: amount, label: 'Amount', onChanged: () {}),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: _paymentModes
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => paymentMode = value ?? paymentMode),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_read(amount) <= 0 ||
                          supervisor.text.trim().isEmpty) {
                        _snack(context, 'Supervisor and amount are required.');
                        return;
                      }
                      ref
                          .read(businessProvider.notifier)
                          .addCashAllocation(
                            supervisorName: supervisor.text,
                            amount: _read(amount),
                            paymentMode: paymentMode,
                            remarks: 'Voice entry',
                          );
                      Navigator.of(context).pop();
                      _snack(context, 'Voice cash allocation saved');
                    },
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  supervisor.dispose();
  amount.dispose();
}

Future<void> _confirmVoiceExpense(
  BuildContext context,
  WidgetRef ref,
  VoiceSupervisorExpenseDraft draft,
) async {
  final supervisor = TextEditingController(text: draft.supervisorName);
  final amount = TextEditingController(text: draft.amount.toStringAsFixed(0));
  final remarks = TextEditingController(text: draft.remarks);
  var category = draft.category;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: 'Confirm Expense',
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _expenseCategories
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => category = value ?? category),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: supervisor,
              decoration: const InputDecoration(labelText: 'Added By'),
            ),
            const SizedBox(height: 10),
            NumberText(controller: amount, label: 'Amount', onChanged: () {}),
            const SizedBox(height: 10),
            TextField(
              controller: remarks,
              decoration: const InputDecoration(labelText: 'Remarks'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_read(amount) <= 0 ||
                          supervisor.text.trim().isEmpty) {
                        _snack(context, 'Added By and amount are required.');
                        return;
                      }
                      ref
                          .read(businessProvider.notifier)
                          .addExpense(
                            category: category,
                            amount: _read(amount),
                            addedBy: supervisor.text,
                            remarks: remarks.text,
                          );
                      Navigator.of(context).pop();
                      _snack(context, 'Voice expense saved');
                    },
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  supervisor.dispose();
  amount.dispose();
  remarks.dispose();
}

Future<void> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    onConfirm();
    if (context.mounted) {
      _snack(context, '$confirmLabel complete');
    }
  }
}

void showRecordDetails(
  BuildContext context,
  String title,
  List<List<String>> rows, {
  List<Widget> actions = const [],
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FeatureSheet(
      title: title,
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AmountLine(
                label: row.first,
                value: row.length > 1 ? row[1] : '',
              ),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    ),
  );
}

class DocumentAiReviewScreen extends ConsumerStatefulWidget {
  const DocumentAiReviewScreen({super.key});

  @override
  ConsumerState<DocumentAiReviewScreen> createState() =>
      _DocumentAiReviewScreenState();
}

class _DocumentAiReviewScreenState
    extends ConsumerState<DocumentAiReviewScreen> {
  final _invoiceNumber = TextEditingController();
  final _partyName = TextEditingController();
  final _materialName = TextEditingController();
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _amount = TextEditingController();
  var _type = DocumentAiType.purchase;
  var _invoiceDate = DateTime.now();
  var _proofPath = '';

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _partyName.dispose();
    _materialName.dispose();
    _weight.dispose();
    _rate.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessProvider);
    final service = const DocumentAiService();
    final draft = _draft;
    final duplicates = service.findDuplicates(state, draft);
    final proofName = _proofPath.trim().isEmpty
        ? 'No proof attached'
        : fileNameFromPath(_proofPath);

    return Scaffold(
      appBar: AppBar(title: const Text('Document AI Review')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FeaturePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bill Review',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  service.ocrConfigured
                      ? 'OCR is configured.'
                      : 'OCR is not configured. Attach proof and review the draft manually before saving.',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                SegmentedButton<DocumentAiType>(
                  segments: const [
                    ButtonSegment(
                      value: DocumentAiType.purchase,
                      label: Text('Purchase'),
                      icon: Icon(Icons.shopping_cart),
                    ),
                    ButtonSegment(
                      value: DocumentAiType.sale,
                      label: Text('Sale'),
                      icon: Icon(Icons.receipt_long),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickProof(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickProof(ImageSource.gallery),
                        icon: const Icon(Icons.image),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  proofName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              children: [
                TextField(
                  controller: _invoiceNumber,
                  decoration: const InputDecoration(labelText: 'Invoice No'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _partyName,
                  decoration: InputDecoration(
                    labelText: _type == DocumentAiType.purchase
                        ? 'Seller / Supplier'
                        : 'Customer',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _materialName,
                  decoration: const InputDecoration(labelText: 'Item'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NumberText(
                        controller: _weight,
                        label: 'Weight KG',
                        onChanged: () {
                          _syncAmountFromRate();
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NumberText(
                        controller: _rate,
                        label: 'Rate',
                        onChanged: () {
                          _syncAmountFromRate();
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NumberText(
                  controller: _amount,
                  label: 'Amount',
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(shortDate(_invoiceDate)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FeaturePanel(
            child: Column(
              children: [
                AmountLine(
                  label: 'Draft Type',
                  value: _type == DocumentAiType.purchase
                      ? 'Purchase Bill'
                      : 'Sales Bill',
                ),
                AmountLine(label: 'Invoice', value: draft.invoiceNumber),
                AmountLine(label: 'Party', value: draft.partyName),
                AmountLine(label: 'Item', value: draft.materialName),
                AmountLine(label: 'Weight', value: kg(draft.weightKg)),
                AmountLine(label: 'Amount', value: money(draft.amount)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (duplicates.isEmpty)
            const FeaturePanel(
              child: EmptyFeatureState(
                icon: Icons.verified,
                title: 'No duplicate found',
                subtitle: 'Invoice number, date, party, and amount look clear.',
              ),
            )
          else
            FeaturePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Duplicate Review',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  for (final duplicate in duplicates.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AmountLine(
                        label: duplicate.invoiceNumber,
                        value:
                            '${duplicate.reason} | ${duplicate.partyName} | ${money(duplicate.amount)}',
                        color: EnterpriseTheme.warning,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _openEntry,
            icon: Icon(
              _type == DocumentAiType.purchase
                  ? Icons.shopping_cart
                  : Icons.receipt_long,
            ),
            label: Text(
              _type == DocumentAiType.purchase
                  ? 'Open Purchase Entry'
                  : 'Open Sale Entry',
            ),
          ),
        ],
      ),
    );
  }

  DocumentAiDraft get _draft => DocumentAiDraft(
    type: _type,
    invoiceNumber: _invoiceNumber.text.trim(),
    partyName: _partyName.text.trim(),
    materialName: _materialName.text.trim(),
    weightKg: _read(_weight),
    rate: _read(_rate),
    amount: _read(_amount),
    invoiceDate: _invoiceDate,
    proofPath: _proofPath,
  );

  Future<void> _pickProof(ImageSource source) async {
    final path = await _pickImage(source);
    if (path == null || !mounted) {
      return;
    }
    setState(() => _proofPath = path);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _invoiceDate = picked);
  }

  void _syncAmountFromRate() {
    final weight = _read(_weight);
    final rate = _read(_rate);
    if (weight > 0 && rate > 0 && _amount.text.trim().isEmpty) {
      _amount.text = (weight * rate).toStringAsFixed(0);
    }
  }

  void _openEntry() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _type == DocumentAiType.purchase
            ? const PurchaseEditorScreen()
            : const SaleEditorScreen(),
      ),
    );
  }
}

class PurchaseLineEditor extends StatelessWidget {
  const PurchaseLineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.materials,
    required this.onChanged,
    required this.onAddMaterial,
    this.onRemove,
  });

  final int index;
  final LineDraft line;
  final List<MaterialStock> materials;
  final VoidCallback onChanged;
  final Future<void> Function() onAddMaterial;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (onRemove != null)
                IconButton(onPressed: onRemove, icon: const Icon(Icons.close)),
            ],
          ),
          MaterialDropdown(
            label: 'Material',
            value: line.material,
            materials: materials,
            onAdd: onAddMaterial,
            onChanged: (value) {
              line.setMaterial(value);
              onChanged();
            },
          ),
          if (line.material != null) ...[
            const SizedBox(height: 10),
            MaterialSnapshot(material: line.material!),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NumberText(
                  controller: line.weight,
                  label: 'Weight (KG)',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NumberText(
                  controller: line.rate,
                  label: 'Rate / KG',
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AmountLine(label: 'Line Amount', value: money(line.amount)),
        ],
      ),
    );
  }
}

class LineDraft {
  LineDraft();

  LineDraft.fromItem(LineItem item) {
    material = MaterialStock(
      id: item.materialId,
      name: item.materialName,
      category: 'Selected',
      availableKg: 0,
      currentBuyingRate: item.rate,
      photoPath: item.materialPhotoPath,
      wastageDeductionPercent: item.wastageDeductionPercent,
    );
    weight.text = item.weightKg.toStringAsFixed(0);
    rate.text = item.rate.toStringAsFixed(0);
  }

  MaterialStock? material;
  final weight = TextEditingController();
  final rate = TextEditingController();

  double get effectiveWeight {
    final actualWeight = _read(weight);
    final deduction = material?.normalizedWastageDeductionPercent ?? 0;
    return (actualWeight - (actualWeight * deduction / 100)).clamp(
      0,
      double.infinity,
    );
  }

  double get amount => effectiveWeight * _read(rate);

  void setMaterial(MaterialStock? value) {
    material = value;
    if (value != null) {
      rate.text = value.currentBuyingRate.toStringAsFixed(0);
    }
  }

  LineItem? toItem() {
    final selected = material;
    final weightKg = _read(weight);
    final itemRate = _read(rate);
    if (selected == null || weightKg <= 0 || itemRate <= 0) {
      return null;
    }
    return LineItem(
      materialId: selected.id,
      materialName: selected.name,
      materialPhotoPath: selected.photoPath,
      weightKg: weightKg,
      wastageDeductionPercent: selected.normalizedWastageDeductionPercent,
      effectiveWeight: effectiveWeight,
      rate: itemRate,
    );
  }

  void dispose() {
    weight.dispose();
    rate.dispose();
  }
}

class PartyDropdown extends StatelessWidget {
  const PartyDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.emptyLabel,
    required this.onAdd,
    required this.onChanged,
  });

  final String label;
  final Party? value;
  final List<Party> items;
  final String emptyLabel;
  final Future<void> Function() onAdd;
  final ValueChanged<Party?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: Text(emptyLabel),
      );
    }
    final selected = _matchingParty(items, value);
    return DropdownButtonFormField<Party>(
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in items)
          DropdownMenuItem(
            value: item,
            child: Row(
              children: [
                EntityAvatar(
                  path: item.photoPath,
                  icon: item.kind == PartyKind.seller
                      ? Icons.storefront
                      : Icons.person,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(item.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class MaterialDropdown extends StatelessWidget {
  const MaterialDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.materials,
    required this.onAdd,
    required this.onChanged,
  });

  final String label;
  final MaterialStock? value;
  final List<MaterialStock> materials;
  final Future<void> Function() onAdd;
  final ValueChanged<MaterialStock?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dropdownMaterials = [...materials];
    final selectedValue = value;
    if (selectedValue != null &&
        !dropdownMaterials.any((material) => material.id == selectedValue.id)) {
      dropdownMaterials.add(selectedValue);
    }
    if (dropdownMaterials.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add material'),
      );
    }
    final selected = _matchingMaterial(dropdownMaterials, value);
    return DropdownButtonFormField<MaterialStock>(
      initialValue: selected,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in dropdownMaterials)
          DropdownMenuItem(
            value: item,
            child: Row(
              children: [
                EntityAvatar(
                  path: item.photoPath,
                  icon: Icons.recycling,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(item.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class SellerSnapshot extends StatelessWidget {
  const SellerSnapshot({super.key, required this.seller});

  final Party seller;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Row(
        children: [
          EntityAvatar(path: seller.photoPath, icon: Icons.storefront),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${seller.mobile}  |  ${seller.area}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            money(seller.pendingAmount),
            style: const TextStyle(
              color: EnterpriseTheme.warning,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class MaterialSnapshot extends ConsumerWidget {
  const MaterialSnapshot({super.key, required this.material});

  final MaterialStock material;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(businessProvider).user.role.isOwnerOrAdmin;
    return FeaturePanel(
      child: Row(
        children: [
          EntityAvatar(path: material.photoPath, icon: Icons.recycling),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${material.name}\n${material.category}  |  ${material.isActive ? 'Active' : 'Inactive'}',
              style: const TextStyle(color: Color(0xFF334155)),
            ),
          ),
          Text(
            isOwner
                ? '${kg(material.availableKg)}\nBuy ${money(material.currentBuyingRate)} | Sell ${money(material.currentSellingRate == 0 ? material.currentBuyingRate : material.currentSellingRate)}'
                : kg(material.availableKg),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class StatPanel extends StatelessWidget {
  const StatPanel({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FeaturePanel(
      child: Row(
        children: [
          Icon(icon, color: EnterpriseTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnalyticsBars extends StatelessWidget {
  const AnalyticsBars({super.key, required this.title, required this.rows});

  final String title;
  final List<MapEntry<String, double>> rows;

  @override
  Widget build(BuildContext context) {
    final maxValue = rows.isEmpty
        ? 1.0
        : rows.first.value.clamp(1, double.infinity).toDouble();
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('No data', style: TextStyle(color: Color(0xFF94A3B8)))
          else
            for (final row in rows.take(5)) ...[
              Text(row.key, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (row.value / maxValue).clamp(0, 1),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class FilterStrip extends StatelessWidget {
  const FilterStrip({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final filters = compact
        ? const ['Today', 'Yesterday', 'Weekly', 'Monthly', 'Custom Date Range']
        : const [
            'Today',
            'Yesterday',
            'Weekly',
            'Monthly',
            'Custom Date Range',
            'Since Beginning',
          ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final item in filters) ...[
            ChoiceChip(
              label: Text(item),
              selected: value == item,
              onSelected: (_) => onChanged(item),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class ExportBar extends StatelessWidget {
  const ExportBar({
    super.key,
    required this.title,
    required this.table,
    this.bundle,
    this.onPdfExport,
    this.onExcelExport,
    this.onPrint,
  });

  final String title;
  final ReportTable table;
  final ReportBundle? bundle;
  final VoidCallback? onPdfExport;
  final VoidCallback? onExcelExport;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _exportPdf(context),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _exportExcel(context),
              icon: const Icon(Icons.table_view),
              label: const Text('Excel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _print(context),
              icon: const Icon(Icons.print),
              label: const Text('Print'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    onPdfExport?.call();
    final reportBundle = bundle;
    final bytes = reportBundle == null
        ? await _buildPdf(title, table)
        : await _buildReportPdf(reportBundle);
    await Printing.sharePdf(bytes: bytes, filename: '${_safeName(title)}.pdf');
  }

  Future<void> _print(BuildContext context) async {
    onPrint?.call();
    final reportBundle = bundle;
    final bytes = reportBundle == null
        ? await _buildPdf(title, table)
        : await _buildReportPdf(reportBundle);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _exportExcel(BuildContext context) async {
    onExcelExport?.call();
    final reportBundle = bundle;
    final bytes = reportBundle == null
        ? _buildXlsx(title, table)
        : _buildReportXlsx(reportBundle);
    final fileName = '${_safeName(title)}.xlsx';
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: fileName,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          fileNameOverrides: [fileName],
          subject: title,
        ),
      );
      return;
    }
    final path = await saveBytesFile(fileName, bytes);
    if (context.mounted) {
      _snack(context, 'Excel saved: $path');
    }
  }
}

class DataList extends StatelessWidget {
  const DataList({
    super.key,
    required this.headers,
    required this.rows,
    this.footerRows = const [],
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<List<String>> footerRows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = [...rows, ...footerRows];
    if (visibleRows.isEmpty) {
      return const EmptyFeatureState(
        icon: Icons.table_rows,
        title: 'No records',
        subtitle: 'Try another filter or add transactions.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visibleRows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = visibleRows[index];
        final isFooter = index >= rows.length;
        return FeaturePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < headers.length && i < row.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          headers[i],
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row[i],
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: isFooter
                                ? FontWeight.w900
                                : FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class FeaturePanel extends StatelessWidget {
  const FeaturePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class FeatureSheet extends StatelessWidget {
  const FeatureSheet({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyFeatureState extends StatelessWidget {
  const EmptyFeatureState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class EntityAvatar extends StatelessWidget {
  const EntityAvatar({
    super.key,
    required this.path,
    required this.icon,
    this.size = 38,
  });

  final String path;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final exists = path.isNotEmpty && localFileExists(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Container(
        width: size,
        height: size,
        color: EnterpriseTheme.primary.withValues(alpha: 0.18),
        child: exists
            ? localImageFromPath(path, fit: BoxFit.cover)
            : Icon(icon, color: EnterpriseTheme.primary, size: size * 0.48),
      ),
    );
  }
}

class NumberText extends StatelessWidget {
  const NumberText({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class AmountLine extends StatelessWidget {
  const AmountLine({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class ReportTable {
  const ReportTable({
    required this.headers,
    required this.rows,
    this.footerRows = const [],
    this.landscape = false,
    this.columnFlex,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final List<List<String>> footerRows;
  final bool landscape;
  final List<double>? columnFlex;

  List<List<String>> get exportRows => [...rows, ...footerRows];
}

class ReportSummaryMetric {
  const ReportSummaryMetric({
    required this.label,
    required this.value,
    this.icon = Icons.insights,
    this.color = EnterpriseTheme.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class ReportTableSection {
  const ReportTableSection({required this.title, required this.table});

  final String title;
  final ReportTable table;
}

enum ReportChartType { bar, line, pie }

class ReportChartSpec {
  const ReportChartSpec({
    required this.title,
    required this.type,
    required this.entries,
    this.valueKind = ReportColumnKind.currency,
  });

  final String title;
  final ReportChartType type;
  final List<MapEntry<String, double>> entries;
  final ReportColumnKind valueKind;
}

class ReportBundle {
  const ReportBundle({
    required this.title,
    required this.filterType,
    required this.dateRange,
    required this.summaryCards,
    required this.dateWiseTable,
    required this.detailTable,
    this.extraSections = const [],
    this.charts = const [],
  });

  final String title;
  final String filterType;
  final String dateRange;
  final List<ReportSummaryMetric> summaryCards;
  final ReportTable dateWiseTable;
  final ReportTable detailTable;
  final List<ReportTableSection> extraSections;
  final List<ReportChartSpec> charts;

  ReportTable get summaryTable => ReportTable(
    headers: const ['Metric', 'Value'],
    rows: [
      ['Report', title],
      ['Filter', filterType],
      ['Date Range', dateRange],
      ['Generated At', shortDate(DateTime.now())],
      for (final item in summaryCards) [item.label, item.value],
    ],
  );

  List<ReportTableSection> get excelSections => [
    ReportTableSection(title: 'Summary', table: summaryTable),
    ReportTableSection(title: 'Date-wise', table: dateWiseTable),
    ReportTableSection(title: 'Details', table: detailTable),
    ...extraSections,
  ];
}

class ReportSummaryCards extends StatelessWidget {
  const ReportSummaryCards({super.key, required this.cards});

  final List<ReportSummaryMetric> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const EmptyFeatureState(
        icon: Icons.insights,
        title: 'No summary',
        subtitle: 'Add transactions to see decision cards.',
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.15,
      children: [
        for (final card in cards)
          FeaturePanel(
            child: Row(
              children: [
                Icon(card.icon, color: card.color, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        card.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          card.value,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ReportGraphList extends StatelessWidget {
  const ReportGraphList({super.key, required this.charts});

  final List<ReportChartSpec> charts;

  @override
  Widget build(BuildContext context) {
    if (charts.isEmpty) {
      return const EmptyFeatureState(
        icon: Icons.query_stats,
        title: 'No graph data',
        subtitle: 'Graphs will appear when transactions are available.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: charts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => ReportChartPanel(chart: charts[index]),
    );
  }
}

class ReportChartPanel extends StatelessWidget {
  const ReportChartPanel({super.key, required this.chart});

  final ReportChartSpec chart;

  @override
  Widget build(BuildContext context) {
    final entries = chart.entries
        .where((entry) => entry.value.abs() > 0.0001)
        .take(8)
        .toList();
    return FeaturePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const SizedBox(
              height: 170,
              child: EmptyFeatureState(
                icon: Icons.query_stats,
                title: 'No chart values',
                subtitle: 'There is no data in this filter.',
              ),
            )
          else ...[
            SizedBox(height: 210, child: _chartWidget(entries)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (var i = 0; i < entries.length; i++)
                  _ChartLegend(
                    color: _chartColors[i % _chartColors.length],
                    label: entries[i].key,
                    value: _formatChartValue(entries[i].value, chart.valueKind),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chartWidget(List<MapEntry<String, double>> entries) {
    switch (chart.type) {
      case ReportChartType.line:
        return _ReportLineChart(entries: entries, valueKind: chart.valueKind);
      case ReportChartType.pie:
        return _ReportPieChart(entries: entries, valueKind: chart.valueKind);
      case ReportChartType.bar:
        return _ReportBarChart(entries: entries, valueKind: chart.valueKind);
    }
  }
}

class _ReportBarChart extends StatelessWidget {
  const _ReportBarChart({required this.entries, required this.valueKind});

  final List<MapEntry<String, double>> entries;
  final ReportColumnKind valueKind;

  @override
  Widget build(BuildContext context) {
    final maxValue = entries
        .map((entry) => entry.value.abs())
        .fold<double>(1, (largest, value) => value > largest ? value : largest);
    return BarChart(
      BarChartData(
        maxY: maxValue * 1.18,
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${entries[group.x.toInt()].key}\n${_formatChartValue(rod.toY, valueKind)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                _compactChartValue(value, valueKind),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _shortChartLabel(entries[index].key),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.abs(),
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                  color: _chartColors[i % _chartColors.length],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReportLineChart extends StatelessWidget {
  const _ReportLineChart({required this.entries, required this.valueKind});

  final List<MapEntry<String, double>> entries;
  final ReportColumnKind valueKind;

  @override
  Widget build(BuildContext context) {
    final values = entries.map((entry) => entry.value).toList();
    final minValue = values.fold<double>(
      0,
      (smallest, value) => value < smallest ? value : smallest,
    );
    final maxValue = values.fold<double>(
      1,
      (largest, value) => value > largest ? value : largest,
    );
    final padding = ((maxValue - minValue).abs() * 0.15).clamp(1, 1000000);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (entries.length - 1).toDouble().clamp(0, double.infinity),
        minY: minValue - padding,
        maxY: maxValue + padding,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${entries[spot.x.toInt()].key}\n${_formatChartValue(spot.y, valueKind)}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                )
                .toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                _compactChartValue(value, valueKind),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _shortChartLabel(entries[index].key),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: EnterpriseTheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: EnterpriseTheme.primary.withValues(alpha: 0.12),
            ),
            spots: [
              for (var i = 0; i < entries.length; i++)
                FlSpot(i.toDouble(), entries[i].value),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportPieChart extends StatelessWidget {
  const _ReportPieChart({required this.entries, required this.valueKind});

  final List<MapEntry<String, double>> entries;
  final ReportColumnKind valueKind;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(
      0,
      (runningTotal, entry) => runningTotal + entry.value.abs(),
    );
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 34,
        sections: [
          for (var i = 0; i < entries.length; i++)
            PieChartSectionData(
              value: entries[i].value.abs(),
              color: _chartColors[i % _chartColors.length],
              radius: 72,
              title: total == 0
                  ? ''
                  : '${((entries[i].value.abs() / total) * 100).toStringAsFixed(0)}%',
              titleStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$label: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

const _chartColors = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFDC2626),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF475569),
];

ReportTable _purchaseReportTable(
  List<PurchaseRecord> purchases, {
  bool internal = false,
}) {
  final headers = internal
      ? const [
          'Invoice No',
          'Seller',
          'Material',
          'Actual Weight',
          'Effective Weight',
          'Wastage Deduction %',
          'Rate / KG',
          'Item Amount',
          'Total Invoice Weight',
          'Total Invoice Amount',
          'Paid Amount',
          'Balance',
          'Added By',
          'Date',
        ]
      : const [
          'Invoice No',
          'Seller',
          'Material',
          'Item Weight',
          'Rate / KG',
          'Item Amount',
          'Total Invoice Weight',
          'Total Invoice Amount',
          'Paid Amount',
          'Balance',
          'Added By',
          'Date',
        ];
  final rows = <List<String>>[];
  for (final purchase in purchases) {
    for (final item in purchase.items) {
      if (internal) {
        rows.add([
          purchase.invoiceNumber,
          purchase.seller.name,
          item.materialName,
          kg(item.actualWeight),
          kg(item.effectiveWeight),
          '${item.wastageDeductionPercent.toStringAsFixed(2)}%',
          money(item.rate),
          money(item.amount),
          kg(purchase.totalWeightKg),
          money(purchase.totalAmount),
          money(purchase.paidAmount),
          money(purchase.balanceAmount),
          purchase.createdBy,
          shortDate(purchase.createdAt),
        ]);
      } else {
        rows.add([
          purchase.invoiceNumber,
          purchase.seller.name,
          item.materialName,
          kg(item.actualWeight),
          money(item.rate),
          money(item.amount),
          kg(purchase.totalWeightKg),
          money(purchase.totalAmount),
          money(purchase.paidAmount),
          money(purchase.balanceAmount),
          purchase.createdBy,
          shortDate(purchase.createdAt),
        ]);
      }
    }
  }

  final totalWeight = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalWeightKg,
  );
  final totalAmount = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.totalAmount,
  );
  final totalPaid = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.paidAmount,
  );
  final totalBalance = purchases.fold<double>(
    0,
    (runningTotal, item) => runningTotal + item.balanceAmount,
  );
  final footer = internal
      ? [
          'Grand Total',
          '',
          '',
          kg(totalWeight),
          '',
          '',
          '',
          money(totalAmount),
          kg(totalWeight),
          money(totalAmount),
          money(totalPaid),
          money(totalBalance),
          '',
          '',
        ]
      : [
          'Grand Total',
          '',
          '',
          kg(totalWeight),
          '',
          money(totalAmount),
          kg(totalWeight),
          money(totalAmount),
          money(totalPaid),
          money(totalBalance),
          '',
          '',
        ];

  return ReportTable(
    headers: headers,
    rows: rows,
    footerRows: rows.isEmpty ? const [] : [footer],
    landscape: true,
    columnFlex: internal
        ? const [1.4, 1.5, 1.4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.1]
        : const [1.4, 1.7, 1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1.1],
  );
}

Future<String?> showVoiceCommandDialog(
  BuildContext context, {
  WidgetRef? ref,
  String title = 'Voice Command',
  String initialText = '',
  String helpText =
      'Say seller name, material, weight, rate, paid amount, add item, save purchase, or go back.',
}) async {
  final command = TextEditingController(text: initialText);
  final speech = SpeechToText();
  final tts = FlutterTts();
  var listening = false;
  var locale = 'en_IN';
  var status = 'Ready';
  var error = '';
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => FeatureSheet(
        title: title,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: locale,
              decoration: const InputDecoration(labelText: 'Language'),
              items: const [
                DropdownMenuItem(value: 'en_IN', child: Text('English')),
                DropdownMenuItem(value: 'hi_IN', child: Text('Hindi')),
                DropdownMenuItem(value: 'hinglish', child: Text('Hinglish')),
              ],
              onChanged: (value) => setState(() => locale = value ?? locale),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  listening ? Icons.hearing : Icons.mic_none,
                  color: listening
                      ? EnterpriseTheme.primary
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (status == 'Listening...' || status == 'Processing...')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 4),
              ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(
                  color: EnterpriseTheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: command,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.mic),
                labelText: 'Command text',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      ref
                          ?.read(businessProvider.notifier)
                          .recordVoiceActivity('voice_started', title);
                      setState(() {
                        status = 'Processing...';
                        error = '';
                      });
                      final hasPermission = await _ensureMicPermission();
                      if (!hasPermission) {
                        setState(() {
                          listening = false;
                          status = 'Permission Denied...';
                          error = 'Microphone permission denied.';
                        });
                        ref
                            ?.read(businessProvider.notifier)
                            .recordVoiceActivity(
                              'voice_command_failed',
                              'Microphone permission denied',
                            );
                        await tts.speak('Permission denied');
                        return;
                      }
                      bool available;
                      try {
                        available = await speech.initialize(
                          onStatus: (value) {
                            setState(() {
                              if (value == 'listening') {
                                listening = true;
                                status = 'Listening...';
                              } else if (value == 'done' ||
                                  value == 'notListening') {
                                listening = false;
                                status = command.text.trim().isEmpty
                                    ? 'No Speech Detected...'
                                    : 'Recognized...';
                              }
                            });
                          },
                          onError: (value) {
                            setState(() {
                              listening = false;
                              status = value.errorMsg.contains('permission')
                                  ? 'Permission Denied...'
                                  : 'No Speech Detected...';
                              error = value.errorMsg.contains('permission')
                                  ? 'Microphone permission denied.'
                                  : 'Sorry, I could not understand. Please try again.';
                            });
                            ref
                                ?.read(businessProvider.notifier)
                                .recordVoiceActivity(
                                  'voice_command_failed',
                                  value.errorMsg,
                                );
                          },
                        );
                      } catch (_) {
                        available = false;
                      }
                      if (!available) {
                        final hasPermission = await speech.hasPermission;
                        setState(() {
                          listening = false;
                          status = hasPermission
                              ? 'No Speech Detected...'
                              : 'Permission Denied...';
                          error = hasPermission
                              ? 'Voice recognition is not available on this device.'
                              : 'Microphone permission denied.';
                        });
                        ref
                            ?.read(businessProvider.notifier)
                            .recordVoiceActivity('voice_command_failed', error);
                        await tts.speak(
                          hasPermission
                              ? 'Voice recognition is not available'
                              : 'Permission denied',
                        );
                        return;
                      }
                      setState(() => listening = true);
                      await tts.speak('Listening');
                      await speech.listen(
                        listenOptions: SpeechListenOptions(
                          localeId: locale == 'hinglish' ? 'en_IN' : locale,
                          listenMode: ListenMode.dictation,
                          listenFor: const Duration(seconds: 20),
                          pauseFor: const Duration(seconds: 3),
                          cancelOnError: true,
                          partialResults: true,
                        ),
                        onResult: (result) {
                          command.text = result.recognizedWords;
                          command.selection = TextSelection.fromPosition(
                            TextPosition(offset: command.text.length),
                          );
                          if (result.finalResult) {
                            setState(() {
                              listening = false;
                              status = command.text.trim().isEmpty
                                  ? 'No Speech Detected...'
                                  : 'Recognized...';
                            });
                            if (command.text.trim().isNotEmpty) {
                              ref
                                  ?.read(businessProvider.notifier)
                                  .recordVoiceActivity(
                                    'voice_command_recognized',
                                    command.text,
                                  );
                              tts.speak('Recognized');
                            }
                          }
                        },
                      );
                    },
                    icon: Icon(listening ? Icons.hearing : Icons.mic),
                    label: const Text('Listen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await speech.stop();
                      setState(() {
                        listening = false;
                        status = command.text.trim().isEmpty
                            ? 'No Speech Detected...'
                            : 'Processing...';
                      });
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => tts.speak(helpText),
              icon: const Icon(Icons.help_outline),
              label: const Text('Voice Help'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(command.text),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Parse Command'),
            ),
          ],
        ),
      ),
    ),
  );
  await speech.stop();
  await tts.stop();
  command.dispose();
  return result;
}

Future<bool> _ensureMicPermission() async {
  final status = await Permission.microphone.status;
  if (status.isGranted) {
    return true;
  }
  final requested = await Permission.microphone.request();
  return requested.isGranted;
}

Party? _bestPartyMatch(List<Party> parties, String name) {
  if (name.trim().isEmpty) {
    return null;
  }
  final needle = name.toLowerCase();
  for (final party in parties) {
    final haystack = party.name.toLowerCase();
    if (haystack == needle ||
        haystack.contains(needle) ||
        needle.contains(haystack)) {
      return party;
    }
  }
  return null;
}

MaterialStock? _bestMaterialMatch(List<MaterialStock> materials, String name) {
  final needle = name.toLowerCase();
  for (final material in materials) {
    final haystack = material.name.toLowerCase();
    if (haystack == needle ||
        haystack.contains(needle) ||
        needle.contains(haystack)) {
      return material;
    }
  }
  return materials.isEmpty ? null : materials.first;
}

Party? _matchingParty(List<Party> parties, Party? value) {
  if (value == null) {
    return null;
  }
  for (final party in parties) {
    if (party.id == value.id) {
      return party;
    }
  }
  return null;
}

MaterialStock? _matchingMaterial(
  List<MaterialStock> materials,
  MaterialStock? value,
) {
  if (value == null) {
    return null;
  }
  for (final material in materials) {
    if (material.id == value.id) {
      return material;
    }
  }
  return null;
}

Future<String?> _pickImage(ImageSource source) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(source: source, imageQuality: 72);
  return file?.path;
}

Future<Uint8List> _buildReportPdf(ReportBundle bundle) async {
  final doc = pw.Document();
  final generatedAt = DateTime.now();
  final graphRows = <List<String>>[
    for (final chart in bundle.charts)
      [
        chart.title,
        chart.entries
            .take(6)
            .map(
              (entry) =>
                  '${entry.key}: ${_formatChartValue(entry.value, chart.valueKind)}',
            )
            .join('\n'),
      ],
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => [
        pw.Text(
          appDisplayName,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          bundle.title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('Date range: ${bundle.dateRange}'),
        pw.Text('Generated: ${shortDate(generatedAt)}'),
        pw.SizedBox(height: 12),
        pw.Text(
          'Executive Summary',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _pdfTable(
          ReportTable(
            headers: const ['Metric', 'Value'],
            rows: [
              for (final card in bundle.summaryCards) [card.label, card.value],
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Date-wise Summary',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _pdfTable(bundle.dateWiseTable, maxRows: 12),
        if (graphRows.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'Graph Summary',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfTable(
            ReportTable(
              headers: const ['Graph', 'Top Values'],
              rows: graphRows,
              columnFlex: const [1.1, 2.4],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Interactive charts are available in the app. PDF includes equivalent chart data.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: bundle.detailTable.landscape
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => [
        pw.Text(
          '${bundle.title} Details',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        _pdfTable(bundle.detailTable),
        for (final section in bundle.extraSections.take(3)) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            section.title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          _pdfTable(section.table, maxRows: 30),
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _pdfTable(ReportTable table, {int? maxRows}) {
  final rows = maxRows == null ? table.rows : table.rows.take(maxRows).toList();
  if (rows.isEmpty) {
    return pw.Text('No records');
  }
  return pw.TableHelper.fromTextArray(
    headers: table.headers,
    data: rows,
    columnWidths: _pdfColumnWidths(table),
    cellAlignments: _pdfCellAlignments(table),
    headerAlignments: _pdfCellAlignments(table),
    cellAlignment: pw.Alignment.topLeft,
    headerAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    headerStyle: pw.TextStyle(
      fontSize: table.landscape ? 7.2 : 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    cellStyle: pw.TextStyle(fontSize: table.landscape ? 6.8 : 8.5),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
    oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
  );
}

Future<Uint8List> _buildPdf(String title, ReportTable table) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: table.landscape
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        if (table.rows.isEmpty)
          pw.Text('No records')
        else ...[
          pw.TableHelper.fromTextArray(
            headers: table.headers,
            data: table.rows,
            columnWidths: _pdfColumnWidths(table),
            cellAlignments: _pdfCellAlignments(table),
            headerAlignments: _pdfCellAlignments(table),
            cellAlignment: pw.Alignment.topLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 5,
            ),
            headerPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 6,
            ),
            headerStyle: pw.TextStyle(
              fontSize: table.landscape ? 7.2 : 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            cellStyle: pw.TextStyle(fontSize: table.landscape ? 6.8 : 8.5),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          ),
          if (table.footerRows.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              data: table.footerRows,
              headerCount: 0,
              columnWidths: _pdfColumnWidths(table),
              cellAlignments: _pdfCellAlignments(table),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              cellStyle: pw.TextStyle(
                fontSize: table.landscape ? 7 : 9,
                fontWeight: pw.FontWeight.bold,
              ),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
            ),
          ],
        ],
      ],
    ),
  );
  return doc.save();
}

List<int> _buildXlsx(String title, ReportTable table) {
  final workbook = xls.Excel.createExcel();
  const sheetName = 'Report';
  final sheet = workbook[sheetName];
  workbook.delete('Sheet1');

  final headerStyle = xls.CellStyle(
    bold: true,
    fontColorHex: xls.ExcelColor.white,
    backgroundColorHex: xls.ExcelColor.fromHexString('FF1E3A5F'),
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Center,
  );
  final textStyle = xls.CellStyle(
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final currencyStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '"Rs " #,##0'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final weightStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '#,##0.## "KG"'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final percentStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '0.00%'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final footerStyle = xls.CellStyle(
    bold: true,
    backgroundColorHex: xls.ExcelColor.fromHexString('FFFFF3CD'),
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Top,
  );

  for (var i = 0; i < table.headers.length; i++) {
    _setExcelCell(
      sheet,
      row: 0,
      column: i,
      value: xls.TextCellValue(table.headers[i]),
      style: headerStyle,
    );
    sheet.setColumnWidth(i, _excelColumnWidth(table, i));
  }

  var rowIndex = 1;
  for (final row in table.rows) {
    _writeExcelRow(
      sheet,
      table,
      row,
      rowIndex,
      textStyle,
      currencyStyle,
      weightStyle,
      percentStyle,
    );
    rowIndex++;
  }
  for (final row in table.footerRows) {
    _writeExcelRow(
      sheet,
      table,
      row,
      rowIndex,
      footerStyle,
      currencyStyle.copyWith(boldVal: true),
      weightStyle.copyWith(boldVal: true),
      percentStyle.copyWith(boldVal: true),
    );
    rowIndex++;
  }

  return workbook.encode() ?? <int>[];
}

List<int> _buildReportXlsx(ReportBundle bundle) {
  final workbook = xls.Excel.createExcel();
  workbook.delete('Sheet1');
  final usedSheetNames = <String>{};

  final headerStyle = xls.CellStyle(
    bold: true,
    fontColorHex: xls.ExcelColor.white,
    backgroundColorHex: xls.ExcelColor.fromHexString('FF1E3A5F'),
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Center,
  );
  final textStyle = xls.CellStyle(
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final currencyStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '"Rs " #,##0'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final weightStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '#,##0.## "KG"'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final percentStyle = xls.CellStyle(
    numberFormat: xls.NumFormat.custom(formatCode: '0.00%'),
    horizontalAlign: xls.HorizontalAlign.Right,
    verticalAlign: xls.VerticalAlign.Top,
  );
  final footerStyle = xls.CellStyle(
    bold: true,
    backgroundColorHex: xls.ExcelColor.fromHexString('FFFFF3CD'),
    textWrapping: xls.TextWrapping.WrapText,
    verticalAlign: xls.VerticalAlign.Top,
  );

  for (final section in bundle.excelSections) {
    final sheetName = _safeSheetName(section.title, usedSheetNames);
    final sheet = workbook[sheetName];
    final table = section.table;
    for (var i = 0; i < table.headers.length; i++) {
      _setExcelCell(
        sheet,
        row: 0,
        column: i,
        value: xls.TextCellValue(table.headers[i]),
        style: headerStyle,
      );
      sheet.setColumnWidth(i, _excelColumnWidth(table, i));
    }
    var rowIndex = 1;
    for (final row in table.rows) {
      _writeExcelRow(
        sheet,
        table,
        row,
        rowIndex,
        textStyle,
        currencyStyle,
        weightStyle,
        percentStyle,
      );
      rowIndex++;
    }
    for (final row in table.footerRows) {
      _writeExcelRow(
        sheet,
        table,
        row,
        rowIndex,
        footerStyle,
        currencyStyle.copyWith(boldVal: true),
        weightStyle.copyWith(boldVal: true),
        percentStyle.copyWith(boldVal: true),
      );
      rowIndex++;
    }
  }

  return workbook.encode() ?? <int>[];
}

void _writeExcelRow(
  xls.Sheet sheet,
  ReportTable table,
  List<String> row,
  int rowIndex,
  xls.CellStyle textStyle,
  xls.CellStyle currencyStyle,
  xls.CellStyle weightStyle,
  xls.CellStyle percentStyle,
) {
  for (var column = 0; column < table.headers.length; column++) {
    final value = column < row.length ? row[column] : '';
    final kind = _reportColumnKind(table.headers[column]);
    final parsed = _numberFromReportValue(value);
    final xls.CellValue cellValue;
    final xls.CellStyle style;
    if (value.trim().isEmpty ||
        parsed == null ||
        kind == ReportColumnKind.text) {
      cellValue = xls.TextCellValue(value);
      style = textStyle;
    } else if (kind == ReportColumnKind.currency) {
      cellValue = xls.DoubleCellValue(parsed);
      style = currencyStyle;
    } else if (kind == ReportColumnKind.weight) {
      cellValue = xls.DoubleCellValue(parsed);
      style = weightStyle;
    } else {
      cellValue = xls.DoubleCellValue(parsed / 100);
      style = percentStyle;
    }
    _setExcelCell(
      sheet,
      row: rowIndex,
      column: column,
      value: cellValue,
      style: style,
    );
  }
}

void _setExcelCell(
  xls.Sheet sheet, {
  required int row,
  required int column,
  required xls.CellValue value,
  required xls.CellStyle style,
}) {
  sheet.updateCell(
    xls.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    value,
    cellStyle: style,
  );
}

Map<int, pw.TableColumnWidth> _pdfColumnWidths(ReportTable table) {
  final flex = table.columnFlex;
  if (flex == null) {
    return const {};
  }
  return {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])};
}

Map<int, pw.AlignmentGeometry> _pdfCellAlignments(ReportTable table) {
  return {
    for (var i = 0; i < table.headers.length; i++)
      i: _reportColumnKind(table.headers[i]) == ReportColumnKind.text
          ? pw.Alignment.topLeft
          : pw.Alignment.topRight,
  };
}

double _excelColumnWidth(ReportTable table, int column) {
  if (column >= table.headers.length) {
    return 14;
  }
  final header = table.headers[column].toLowerCase();
  if (header.contains('seller') || header.contains('material')) {
    return 22;
  }
  if (header.contains('invoice')) {
    return 18;
  }
  if (header.contains('date')) {
    return 18;
  }
  if (header.contains('deduction')) {
    return 16;
  }
  return 14;
}

enum ReportColumnKind { text, currency, weight, percent }

ReportColumnKind _reportColumnKind(String header) {
  final value = header.toLowerCase();
  if (value.contains('%') || value.contains('deduction')) {
    return ReportColumnKind.percent;
  }
  if (value.contains('amount') ||
      value.contains('paid') ||
      value.contains('balance') ||
      value.contains('rate') ||
      value.contains('cash') ||
      value.contains('purchase') ||
      value.contains('expense') ||
      value.contains('sales') ||
      value.contains('outstanding') ||
      value.contains('pending') ||
      value.contains('value') ||
      value.contains('gap')) {
    return ReportColumnKind.currency;
  }
  if (value.contains('weight') ||
      value.contains('quantity') ||
      value.contains('stock')) {
    return ReportColumnKind.weight;
  }
  return ReportColumnKind.text;
}

double? _numberFromReportValue(String value) {
  final cleaned = value
      .replaceAll('Rs', '')
      .replaceAll('KG', '')
      .replaceAll('%', '')
      .replaceAll(',', '')
      .trim();
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}

String _safeName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'_+$'), '');

Future<void> showPurchaseInvoicePdfActions(
  BuildContext context,
  WidgetRef ref,
  PurchaseRecord purchase,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchase Invoice PDF',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${purchase.invoiceNumber}  |  ${purchase.seller.name}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await sharePurchaseInvoicePdf(
                  context,
                  ref,
                  purchase,
                  shareMethod: 'WhatsApp Seller',
                );
              },
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp Seller'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await downloadPurchaseInvoicePdf(context, ref, purchase);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await sharePurchaseInvoicePdf(
                  context,
                  ref,
                  purchase,
                  shareMethod: 'Share PDF',
                );
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Share PDF'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> sharePurchaseInvoicePdf(
  BuildContext context,
  WidgetRef ref,
  PurchaseRecord purchase, {
  String shareMethod = 'Share PDF',
}) async {
  try {
    final state = ref.read(businessProvider);
    final bytes = await _buildPurchaseInvoicePdf(state, purchase);
    final fileName =
        'purchase_invoice_${_safeName(purchase.invoiceNumber)}.pdf';
    ref
        .read(businessProvider.notifier)
        .recordPurchaseInvoiceGenerated(purchase);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
        ],
        fileNameOverrides: [fileName],
        subject: 'Purchase Invoice ${purchase.invoiceNumber}',
        text: purchaseInvoiceWhatsAppMessage(purchase),
      ),
    );
    ref
        .read(businessProvider.notifier)
        .recordPurchaseInvoiceShared(
          purchase: purchase,
          shareMethod: shareMethod,
        );
  } catch (error) {
    if (context.mounted) {
      _snack(context, 'Could not share purchase invoice PDF: $error');
    }
  }
}

Future<void> downloadPurchaseInvoicePdf(
  BuildContext context,
  WidgetRef ref,
  PurchaseRecord purchase,
) async {
  try {
    final state = ref.read(businessProvider);
    final bytes = await _buildPurchaseInvoicePdf(state, purchase);
    final fileName =
        'purchase_invoice_${_safeName(purchase.invoiceNumber)}.pdf';
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
          ],
          fileNameOverrides: [fileName],
          subject: 'Purchase Invoice ${purchase.invoiceNumber}',
          text: purchaseInvoiceWhatsAppMessage(purchase),
        ),
      );
      ref
          .read(businessProvider.notifier)
          .recordPurchaseInvoiceGenerated(purchase);
      return;
    }

    final path = await saveBytesFile(
      fileName,
      bytes,
      documents: true,
      subdirectory: 'purchase_invoices',
    );
    ref
        .read(businessProvider.notifier)
        .recordPurchaseInvoiceGenerated(purchase);
    if (context.mounted) {
      _snack(context, 'Purchase invoice saved: $path');
    }
  } catch (error) {
    if (context.mounted) {
      _snack(context, 'Could not download purchase invoice PDF: $error');
    }
  }
}

Future<Uint8List> _buildPurchaseInvoicePdf(
  BusinessState state,
  PurchaseRecord purchase,
) async {
  final doc = pw.Document();
  final isOwner = state.user.role.isOwnerOrAdmin;
  final address = [
    purchase.seller.address.trim(),
    purchase.seller.area.trim(),
  ].where((item) => item.isNotEmpty).join(', ');
  final hasInternalDetails =
      isOwner &&
      purchase.items.any(
        (item) =>
            item.wastageDeductionPercent > 0 ||
            item.effectiveWeight != item.actualWeight,
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blueGrey700, width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                companyInvoiceName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(companyAddress, textAlign: pw.TextAlign.center),
              pw.Text('Mobile : $companyMobile'),
              pw.Text('Email : $companyEmail'),
              pw.Text('GSTIN : $companyGstin'),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            'PURCHASE INVOICE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 10),
        _invoiceInfoTable([
          ['Purchase Number', purchase.invoiceNumber],
          ['Date', DateFormat('dd MMM yyyy').format(purchase.createdAt)],
          ['Time', DateFormat('hh:mm a').format(purchase.createdAt)],
        ]),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('SELLER DETAILS'),
        _invoiceInfoTable([
          ['Seller Name', purchase.seller.name],
          ['Mobile Number', purchase.seller.mobile],
          if (address.isNotEmpty) ['Address', address],
        ]),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('MATERIAL DETAILS'),
        _salesInvoiceTable(
          headers: const ['Material Name', 'Weight (KG)', 'Rate', 'Amount'],
          rows: [
            for (final item in purchase.items)
              [
                item.materialName,
                _plainKg(item.actualWeight),
                money(item.rate),
                money(item.amount),
              ],
          ],
          columnWidths: {
            0: const pw.FlexColumnWidth(2.6),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.2),
          },
        ),
        pw.SizedBox(height: 12),
        _salesInvoiceSectionTitle('SUMMARY'),
        _invoiceInfoTable(
          [
            ['Total Weight', kg(purchase.totalWeightKg)],
            ['Total Amount', money(purchase.totalAmount)],
          ],
          emphasizeRows: const {0, 1},
        ),
        if (purchase.remarks.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _salesInvoiceSectionTitle('REMARKS'),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Text(purchase.remarks.trim()),
          ),
        ],
        if (hasInternalDetails) ...[
          pw.SizedBox(height: 14),
          _salesInvoiceSectionTitle('INTERNAL DETAILS - OWNER ONLY'),
          _salesInvoiceTable(
            headers: const [
              'Material',
              'Actual KG',
              'Effective KG',
              'Wastage %',
              'Line Amount',
            ],
            rows: [
              for (final item in purchase.items)
                [
                  item.materialName,
                  _plainKg(item.actualWeight),
                  _plainKg(item.effectiveWeight),
                  '${item.wastageDeductionPercent.toStringAsFixed(2)}%',
                  money(item.amount),
                ],
            ],
            columnWidths: {
              0: const pw.FlexColumnWidth(2.1),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.2),
            },
          ),
        ],
        pw.SizedBox(height: 14),
        pw.UrlLink(
          destination: purchaseInvoiceWhatsAppUrl(purchase),
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.green700,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              'Send to Seller WhatsApp',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Regards,'),
        pw.Text(
          companyInvoiceName,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('Mobile : $companyMobile'),
        pw.Text('Email  : $companyEmail'),
      ],
    ),
  );
  return doc.save();
}

Future<void> shareSalesInvoicePdf(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
) async {
  try {
    final state = ref.read(businessProvider);
    final bytes = await _buildSalesInvoicePdf(state, sale);
    final fileName = 'sales_invoice_${_safeName(sale.invoiceNumber)}.pdf';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
        ],
        fileNameOverrides: [fileName],
        subject: 'Sales Invoice ${sale.invoiceNumber}',
        text: salesInvoiceWhatsAppMessage(state, sale),
      ),
    );
    ref
        .read(businessProvider.notifier)
        .recordWhatsAppShared(
          action: 'sales_invoice_pdf_shared',
          screen: 'Sales',
          details: sale.invoiceNumber,
        );
  } catch (error) {
    if (context.mounted) {
      _snack(context, 'Could not share invoice PDF: $error');
    }
  }
}

Future<Uint8List> _buildSalesInvoicePdf(
  BusinessState state,
  SaleRecord sale,
) async {
  final previousSales = _previousPendingSalesForCustomer(state, sale);
  final previousPending = previousSales.fold<double>(
    0,
    (total, item) => total + item.balanceAmount,
  );
  final totalPayable = sale.totalAmount + previousPending;
  final outstanding = (totalPayable - sale.receivedAmount).clamp(
    0,
    double.infinity,
  );
  final status = outstanding > 0 ? 'PENDING' : 'PAID';
  final qrImage = await _loadPaymentQrImage();
  final whatsappUrl = salesInvoiceWhatsAppUrl(state, sale);
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blueGrey700, width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                companyInvoiceName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(companyAddress, textAlign: pw.TextAlign.center),
              pw.Text('Mobile : $companyMobile'),
              pw.Text('Email : $companyEmail'),
              pw.Text('GSTIN : $companyGstin'),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            'SALES INVOICE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 10),
        _invoiceInfoTable([
          ['Invoice No', sale.invoiceNumber],
          ['Date', _invoiceDateTime(sale.createdAt)],
          ['Customer Name', sale.customer.name],
        ]),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle("TODAY'S MATERIAL SALE BILL"),
        _salesInvoiceTable(
          headers: const ['Item Name', 'Qty(KG)', 'Rate', 'Amount'],
          rows: [
            for (final item in sale.items)
              [
                item.materialName,
                _plainKg(item.weightKg),
                money(item.rate),
                money(item.amount),
              ],
          ],
          columnWidths: {
            0: const pw.FlexColumnWidth(2.5),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.2),
          },
        ),
        pw.SizedBox(height: 8),
        _invoiceAmountRow(
          "Today's Material Bill Amount",
          money(sale.totalAmount),
        ),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('PREVIOUS PENDING MATERIAL BILLS'),
        if (previousSales.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Text('No previous pending material bills.'),
          )
        else
          _salesInvoiceTable(
            headers: const ['Date', 'Material Details', 'Pending Amount'],
            rows: [
              for (final previous in previousSales)
                [
                  _invoiceShortDate(previous.createdAt),
                  _invoiceMaterialDetails(previous.items),
                  money(previous.balanceAmount),
                ],
            ],
            columnWidths: {
              0: const pw.FlexColumnWidth(1.1),
              1: const pw.FlexColumnWidth(2.8),
              2: const pw.FlexColumnWidth(1.2),
            },
          ),
        pw.SizedBox(height: 8),
        _invoiceAmountRow('Previous Pending Balance', money(previousPending)),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('TOTAL PAYMENT SUMMARY'),
        _invoiceInfoTable(
          [
            ["Today's Material Bill", money(sale.totalAmount)],
            ['Previous Pending Balance', money(previousPending)],
            ['TOTAL AMOUNT TO PAY', money(totalPayable)],
            ['Paid Amount', money(sale.receivedAmount)],
            ['Balance Outstanding', money(outstanding)],
            ['PAYMENT STATUS', status],
          ],
          emphasizeRows: const {2, 5},
        ),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('PAYMENT DETAILS'),
        _invoicePaymentDetails(qrImage),
        pw.SizedBox(height: 10),
        pw.UrlLink(
          destination: whatsappUrl,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.green700,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              'Send to Customer WhatsApp',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 14),
        _salesInvoiceSectionTitle('CUSTOMER PAYMENT NOTE'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Today's Material Bill: ${money(sale.totalAmount)}"),
              pw.Text(
                'Previous Pending Material Bills: ${money(previousPending)}',
              ),
              pw.Text('Total Amount Payable: ${money(totalPayable)}'),
              pw.SizedBox(height: 8),
              pw.Text('Kindly clear the outstanding balance.'),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Regards,'),
        pw.Text(
          companyInvoiceName,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Text('Mobile : $companyMobile'),
        pw.Text('Email  : $companyEmail'),
      ],
    ),
  );
  return doc.save();
}

List<SaleRecord> _previousPendingSalesForCustomer(
  BusinessState state,
  SaleRecord sale,
) {
  final customerId = sale.customer.id.trim();
  final customerName = sale.customer.name.trim().toLowerCase();
  final matches = state.activeSales.where((item) {
    if (item.id == sale.id || item.balanceAmount <= 0) {
      return false;
    }
    final sameId = customerId.isNotEmpty && item.customer.id == customerId;
    final sameName =
        customerName.isNotEmpty &&
        item.customer.name.trim().toLowerCase() == customerName;
    return (sameId || sameName) && item.createdAt.isBefore(sale.createdAt);
  }).toList();
  matches.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return matches;
}

pw.Widget _salesInvoiceSectionTitle(String title) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: PdfColors.blueGrey800,
    child: pw.Text(
      title,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}

pw.Widget _salesInvoiceTable({
  required List<String> headers,
  required List<List<String>> rows,
  Map<int, pw.TableColumnWidth>? columnWidths,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    columnWidths: columnWidths,
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
      fontSize: 9,
    ),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignment: pw.Alignment.topLeft,
    headerAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.45),
  );
}

Future<pw.MemoryImage?> _loadPaymentQrImage() async {
  try {
    final data = await rootBundle.load(paymentQrAssetPath);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

pw.Widget _invoicePaymentDetails(pw.MemoryImage? qrImage) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey500, width: 0.45),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _invoiceInfoTable([
            ['Bank Name', paymentBankName],
            ['Account Name', paymentAccountName],
            ['Account Number', paymentAccountNumber],
            ['GPay / UPI No', paymentUpiMobile],
            ['G-Pay Number', paymentGPayNumber],
          ]),
        ),
        pw.SizedBox(width: 16),
        pw.Container(
          width: 124,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (qrImage == null)
                pw.Container(
                  width: 110,
                  height: 110,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500),
                  ),
                  child: pw.Text(
                    paymentUpiMobile,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                )
              else
                pw.Image(
                  qrImage,
                  width: 110,
                  height: 110,
                  fit: pw.BoxFit.contain,
                ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Scan to Pay with any UPI App',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _invoiceInfoTable(
  List<List<String>> rows, {
  Set<int> emphasizeRows = const {},
}) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.45),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(2.5),
    },
    children: [
      for (var index = 0; index < rows.length; index++)
        pw.TableRow(
          decoration: index.isEven
              ? const pw.BoxDecoration(color: PdfColors.grey100)
              : null,
          children: [
            _invoiceInfoCell(rows[index][0], bold: true),
            _invoiceInfoCell(
              rows[index][1],
              bold: emphasizeRows.contains(index),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _invoiceInfoCell(String value, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _invoiceAmountRow(String label, String value) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      width: 260,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ),
  );
}

String _invoiceMaterialDetails(List<LineItem> items) {
  if (items.isEmpty) {
    return 'Mixed Material Balance';
  }
  return items
      .map((item) => '${item.materialName} - ${_plainKg(item.weightKg)} KG')
      .join('\n');
}

String _plainKg(num value) =>
    NumberFormat.decimalPattern('en_IN').format(value);

String _invoiceShortDate(DateTime value) =>
    DateFormat('dd-MMM-yy').format(value);

String _invoiceDateTime(DateTime value) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(value);

Future<void> _sendCashSummaryWhatsApp(
  BuildContext context,
  WidgetRef ref,
  BusinessState state,
  SupervisorCashSummary summary,
) {
  return _openWhatsAppToMobile(
    context,
    ref,
    mobile: _supervisorMobile(state, summary.supervisorName),
    message: _cashWhatsAppMessage(
      summary,
      showSalesCollection: state.user.role.isOwnerOrAdmin,
    ),
    action: 'whatsapp_cash_report_sent',
    screen: 'Cash With Supervisor',
    details: summary.supervisorName,
  );
}

Future<void> _sendSaleWhatsAppToRecipients(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
) async {
  final state = ref.read(businessProvider);
  final recipients = _saleWhatsAppRecipients(sale);
  if (recipients.isEmpty) {
    _snack(context, 'No WhatsApp mobile number available.');
    return;
  }

  final message = salesInvoiceWhatsAppMessage(state, sale);
  var opened = 0;
  for (final recipient in recipients) {
    final launched = await _launchWhatsAppNumber(
      context,
      number: recipient.number,
      message: message,
    );
    if (launched) {
      opened++;
    }
  }
  if (opened == 0) {
    return;
  }
  ref
      .read(businessProvider.notifier)
      .recordWhatsAppShared(
        action: 'whatsapp_sales_sent',
        screen: 'Sales',
        details:
            '${sale.invoiceNumber} ${recipients.map((item) => item.label).join(', ')}',
      );
  if (context.mounted) {
    _snack(context, 'WhatsApp opened for $opened recipient(s).');
  }
}

List<_WhatsAppRecipient> _saleWhatsAppRecipients(SaleRecord sale) {
  final recipients = <_WhatsAppRecipient>[];

  void add(String label, String mobile) {
    final number = _indiaWhatsAppNumber(mobile);
    if (number == null) {
      return;
    }
    recipients.add(_WhatsAppRecipient(label: label, number: number));
  }

  add('Customer', sale.customer.mobile);
  return recipients;
}

Future<bool> _launchWhatsAppNumber(
  BuildContext context, {
  required String number,
  required String message,
}) async {
  final uri = Uri.parse(
    'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
  );
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    _snack(context, 'WhatsApp is not installed.');
  }
  return launched;
}

Future<void> _openWhatsAppToMobile(
  BuildContext context,
  WidgetRef ref, {
  required String mobile,
  required String message,
  required String action,
  required String screen,
  required String details,
}) async {
  final number = _indiaWhatsAppNumber(mobile);
  if (number == null) {
    _snack(context, 'Mobile number not available.');
    return;
  }
  final launched = await _launchWhatsAppNumber(
    context,
    number: number,
    message: message,
  );
  if (!launched) {
    return;
  }
  ref
      .read(businessProvider.notifier)
      .recordWhatsAppShared(action: action, screen: screen, details: details);
}

String? _indiaWhatsAppNumber(String mobile) {
  var digits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length == 10) {
    return '91$digits';
  }
  if (digits.length == 12 && digits.startsWith('91')) {
    return digits;
  }
  return null;
}

class _WhatsAppRecipient {
  const _WhatsAppRecipient({required this.label, required this.number});

  final String label;
  final String number;
}

String _supervisorMobile(BusinessState state, String supervisorName) {
  final needle = supervisorName.trim().toLowerCase();
  if (needle == state.user.name.trim().toLowerCase()) {
    return state.user.mobile;
  }
  for (final party in [...state.sellers, ...state.customers]) {
    if (party.name.trim().toLowerCase() == needle) {
      return party.mobile;
    }
  }
  return '';
}

String salesInvoiceWhatsAppMessage(BusinessState state, SaleRecord sale) {
  final previousPending = _previousPendingSalesForCustomer(
    state,
    sale,
  ).fold<double>(0, (total, item) => total + item.balanceAmount);
  final totalPayable = sale.totalAmount + previousPending;
  return [
    'Dear ${sale.customer.name},',
    '',
    'Your invoice ${sale.invoiceNumber} has been generated.',
    '',
    "Today's Material Bill: ${money(sale.totalAmount)}",
    'Previous Pending Balance: ${money(previousPending)}',
    'Total Amount Payable: ${money(totalPayable)}',
    '',
    'Payment Details:',
    'GPay / UPI: $paymentUpiMobile',
    '',
    'Please find the attached invoice PDF.',
    '',
    'Regards,',
    companyInvoiceName,
  ].join('\n');
}

String salesInvoiceWhatsAppUrl(BusinessState state, SaleRecord sale) {
  final number = _indiaWhatsAppNumber(sale.customer.mobile);
  final message = Uri.encodeComponent(salesInvoiceWhatsAppMessage(state, sale));
  if (number == null) {
    return 'https://wa.me/?text=$message';
  }
  return 'https://wa.me/$number?text=$message';
}

String purchaseInvoiceWhatsAppMessage(PurchaseRecord purchase) {
  return [
    'Dear ${purchase.seller.name},',
    '',
    'Thank you.',
    '',
    'Please find attached Purchase Invoice.',
    '',
    'Invoice No:',
    purchase.invoiceNumber,
    '',
    'Date:',
    DateFormat('dd MMM yyyy').format(purchase.createdAt),
    '',
    'Total Weight:',
    kg(purchase.totalWeightKg),
    '',
    'Total Amount:',
    money(purchase.totalAmount),
    '',
    'Regards,',
    companyInvoiceName,
  ].join('\n');
}

String purchaseInvoiceWhatsAppUrl(PurchaseRecord purchase) {
  final number = _indiaWhatsAppNumber(purchase.seller.mobile);
  final message = Uri.encodeComponent(purchaseInvoiceWhatsAppMessage(purchase));
  if (number == null) {
    return 'https://wa.me/?text=$message';
  }
  return 'https://wa.me/$number?text=$message';
}

class CustomerPaymentReminder {
  const CustomerPaymentReminder({
    required this.customer,
    required this.todayMaterialBill,
    required this.previousPendingBalance,
    required this.totalPending,
  });

  final Party customer;
  final double todayMaterialBill;
  final double previousPendingBalance;
  final double totalPending;
}

List<CustomerPaymentReminder> pendingCustomerPaymentReminders(
  BusinessState state,
) {
  final today = DateTime.now();
  final reminders = <CustomerPaymentReminder>[];
  for (final customer in state.customers) {
    final customerSales = state.activeSales.where((sale) {
      final sameId =
          customer.id.trim().isNotEmpty && sale.customer.id == customer.id;
      final sameName =
          sale.customer.name.trim().toLowerCase() ==
          customer.name.trim().toLowerCase();
      return sameId || sameName;
    }).toList();
    final pendingSales = customerSales
        .where((sale) => sale.balanceAmount > 0)
        .toList();
    final totalPending = pendingSales.fold<double>(
      0,
      (total, sale) => total + sale.balanceAmount,
    );
    if (totalPending <= 0) {
      continue;
    }
    final todayBill = customerSales
        .where((sale) => _invoiceSameDate(sale.createdAt, today))
        .fold<double>(0, (total, sale) => total + sale.totalAmount);
    final previousPending = pendingSales
        .where((sale) => !_invoiceSameDate(sale.createdAt, today))
        .fold<double>(0, (total, sale) => total + sale.balanceAmount);
    reminders.add(
      CustomerPaymentReminder(
        customer: customer,
        todayMaterialBill: todayBill,
        previousPendingBalance: previousPending,
        totalPending: totalPending,
      ),
    );
  }
  return reminders..sort((a, b) => b.totalPending.compareTo(a.totalPending));
}

String autoInvoiceReminderWhatsAppMessage(CustomerPaymentReminder reminder) {
  return [
    'Dear ${reminder.customer.name},',
    '',
    'Your invoice/payment reminder has been generated.',
    '',
    "Today's Material Bill: ${money(reminder.todayMaterialBill)}",
    'Previous Pending Balance: ${money(reminder.previousPendingBalance)}',
    'Total Amount Payable: ${money(reminder.totalPending)}',
    '',
    'Payment Details:',
    'GPay / UPI: $paymentUpiMobile',
    '',
    'Please find the attached invoice PDF if available.',
    '',
    'Regards,',
    companyInvoiceName,
  ].join('\n');
}

bool _invoiceSameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _cashWhatsAppMessage(
  SupervisorCashSummary summary, {
  required bool showSalesCollection,
}) {
  return [
    appDisplayName,
    'Supervisor Cash Summary',
    '',
    'Supervisor: ${summary.supervisorName}',
    'Opening Balance: ${money(summary.openingBalance)}',
    'Cash Given: ${money(summary.cashGivenByOwner)}',
    'Scrap Purchase: ${money(summary.scrapPurchaseUsed)}',
    'Other Expenses: ${money(summary.otherExpenses)}',
    if (showSalesCollection)
      'Sales Collection: ${money(summary.salesCollection)}',
    'Closing Balance: ${money(summary.currentCashBalance)}',
  ].join('\n');
}

String _timeOnly(DateTime value) {
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String _activityTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('purchase')) {
    return lower.contains('voice')
        ? 'Voice Purchase Created'
        : 'Purchase Added';
  }
  if (lower.contains('sale')) {
    return 'Sale Added';
  }
  if (lower.contains('seller')) {
    return 'Seller Added';
  }
  if (lower.contains('expense')) {
    return 'Expense Added';
  }
  if (lower.contains('cash')) {
    return 'Cash With Supervisor';
  }
  if (lower.contains('login')) {
    return 'User Login';
  }
  if (lower.contains('report') &&
      (lower.contains('export') || lower.contains('printed'))) {
    return 'Report Exported';
  }
  return title;
}

String _activitySubtitle(ActivityRecord item) {
  final text = item.subtitle.replaceAll(' | ', '\n');
  return text.isEmpty ? item.userName : text;
}

IconData _activityIcon(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('purchase')) {
    return Icons.add_shopping_cart;
  }
  if (lower.contains('sale')) {
    return Icons.point_of_sale;
  }
  if (lower.contains('seller')) {
    return Icons.storefront;
  }
  if (lower.contains('expense')) {
    return Icons.receipt_long;
  }
  if (lower.contains('cash')) {
    return Icons.account_balance_wallet;
  }
  if (lower.contains('login')) {
    return Icons.login;
  }
  if (lower.contains('voice')) {
    return Icons.mic;
  }
  if (lower.contains('report')) {
    return Icons.summarize;
  }
  return Icons.timeline;
}

Color _activityColor(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('purchase')) {
    return EnterpriseTheme.primary;
  }
  if (lower.contains('sale')) {
    return EnterpriseTheme.success;
  }
  if (lower.contains('expense')) {
    return EnterpriseTheme.error;
  }
  if (lower.contains('cash')) {
    return EnterpriseTheme.warning;
  }
  if (lower.contains('voice')) {
    return const Color(0xFF7C3AED);
  }
  return const Color(0xFF0F766E);
}

String _safeSheetName(String value, Set<String> used) {
  final base = value
      .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final fallback = base.isEmpty ? 'Sheet' : base;
  var candidate = fallback.length > 31 ? fallback.substring(0, 31) : fallback;
  var suffix = 1;
  while (used.contains(candidate)) {
    final suffixText = ' $suffix';
    final maxBaseLength = 31 - suffixText.length;
    final baseLength = fallback.length < maxBaseLength
        ? fallback.length
        : maxBaseLength;
    candidate = '${fallback.substring(0, baseLength)}$suffixText';
    suffix++;
  }
  used.add(candidate);
  return candidate;
}

String _formatChartValue(double value, ReportColumnKind kind) {
  switch (kind) {
    case ReportColumnKind.currency:
      return money(value);
    case ReportColumnKind.weight:
      return kg(value);
    case ReportColumnKind.percent:
      return '${value.toStringAsFixed(2)}%';
    case ReportColumnKind.text:
      return value.toStringAsFixed(0);
  }
}

String _compactChartValue(double value, ReportColumnKind kind) {
  final prefix = kind == ReportColumnKind.currency ? 'Rs ' : '';
  final suffix = kind == ReportColumnKind.weight
      ? 'kg'
      : kind == ReportColumnKind.percent
      ? '%'
      : '';
  final absValue = value.abs();
  if (absValue >= 10000000) {
    return '$prefix${(value / 10000000).toStringAsFixed(1)}Cr$suffix';
  }
  if (absValue >= 100000) {
    return '$prefix${(value / 100000).toStringAsFixed(1)}L$suffix';
  }
  if (absValue >= 1000) {
    return '$prefix${(value / 1000).toStringAsFixed(1)}K$suffix';
  }
  return '$prefix${value.toStringAsFixed(0)}$suffix';
}

String _shortChartLabel(String value) {
  final cleaned = value.trim();
  if (cleaned.length <= 10) {
    return cleaned;
  }
  return cleaned.substring(0, 10);
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateRangeLabel(String filter, DateTime? from, DateTime? to) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (_isCustomFilter(filter) && from != null && to != null) {
    return '${shortDate(from)} to ${shortDate(to)}';
  }
  switch (filter) {
    case 'Yesterday':
      return shortDate(today.subtract(const Duration(days: 1)));
    case 'Weekly':
      return '${shortDate(today.subtract(const Duration(days: 6)))} to ${shortDate(today)}';
    case 'Monthly':
      return '${now.month.toString().padLeft(2, '0')}/${now.year}';
    case 'Since Beginning':
      return 'Since Beginning';
    default:
      return shortDate(today);
  }
}

bool _isCustomFilter(String filter) =>
    filter == 'Custom' || filter == 'Custom Date Range';

bool _dateInReportFilter(
  DateTime date,
  String filter,
  DateTime? from,
  DateTime? to,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  switch (filter) {
    case 'Yesterday':
      return target == today.subtract(const Duration(days: 1));
    case 'Weekly':
      return !target.isBefore(today.subtract(const Duration(days: 6)));
    case 'Monthly':
      return date.year == now.year && date.month == now.month;
    case 'Since Beginning':
      return true;
    default:
      if (_isCustomFilter(filter)) {
        if (from == null || to == null) {
          return true;
        }
        return !date.isBefore(from) &&
            !date.isAfter(to.add(const Duration(days: 1)));
      }
      return target == today;
  }
}

List<MapEntry<String, double>> _sortedEntries(Map<String, double> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

List<MapEntry<String, double>> _dateEntries(Map<String, double> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries;
}

void _addToMap(Map<String, double> target, String key, double value) {
  final cleaned = key.trim().isEmpty ? 'Unknown' : key.trim();
  target[cleaned] = (target[cleaned] ?? 0) + value;
}

double _read(TextEditingController controller) {
  return double.tryParse(controller.text.trim()) ?? 0;
}

String _normalizedEmail(String value) => value.trim().toLowerCase();

double _effectiveWeightFor(double actualWeight, MaterialStock material) {
  final deduction = material.normalizedWastageDeductionPercent;
  return (actualWeight - (actualWeight * deduction / 100)).clamp(
    0,
    double.infinity,
  );
}

double _sellingRateFor(MaterialStock material) {
  return material.currentSellingRate == 0
      ? material.currentBuyingRate
      : material.currentSellingRate;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
