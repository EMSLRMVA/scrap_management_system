import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/transaction_item.dart';
import '../providers/scrap_data_provider.dart';
import '../services/voice_parser_service.dart';

class VoiceCommandProvider extends ChangeNotifier {
  final VoiceParserService _parser = VoiceParserService();
  final SpeechToText _speech = SpeechToText();

  ScrapDataProvider? _dataProvider;
  bool _listening = false;
  String _status = 'Ready';
  String _errorMessage = '';
  String _lastTranscript = '';
  VoiceCommandResult? _lastResult;

  bool get listening => _listening;
  String get status => _status;
  String get errorMessage => _errorMessage;
  String get lastTranscript => _lastTranscript;
  VoiceCommandResult? get lastResult => _lastResult;

  void attachDataProvider(ScrapDataProvider provider) {
    _dataProvider = provider;
  }

  Future<void> startListening() async {
    _status = 'Processing';
    _errorMessage = '';
    notifyListeners();
    bool available;
    try {
      available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) {
          _listening = false;
          _status = 'Not available';
          _errorMessage = error.errorMsg.contains('permission')
              ? 'Permission denied'
              : 'Sorry, I could not understand. Please try again.';
          notifyListeners();
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available) {
      final hasPermission = await _speech.hasPermission;
      _listening = false;
      _status = hasPermission ? 'Not available' : 'Permission denied';
      _errorMessage = hasPermission
          ? 'Voice recognition is not available on this device.'
          : 'Microphone permission denied.';
      notifyListeners();
      return;
    }
    _listening = true;
    _status = 'Listening';
    notifyListeners();
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'en_IN',
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        partialResults: true,
      ),
      onResult: (result) {
        _lastTranscript = result.recognizedWords;
        _lastResult = _parser.parse(_lastTranscript);
        if (result.finalResult) {
          _listening = false;
          _status = 'Processing';
          if (_lastResult == null) {
            _errorMessage = 'Sorry, I could not understand. Please try again.';
          }
        }
        notifyListeners();
      },
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _listening = false;
    _status = 'Processing';
    notifyListeners();
  }

  VoiceCommandResult? parseManual(String command) {
    _lastTranscript = command;
    _lastResult = _parser.parse(command);
    _errorMessage = _lastResult == null
        ? 'Sorry, I could not understand. Please try again.'
        : '';
    _status = 'Ready';
    notifyListeners();
    return _lastResult;
  }

  void _handleSpeechStatus(String status) {
    if (status == 'listening') {
      _listening = true;
      _status = 'Listening';
    } else if (status == 'notListening' || status == 'done') {
      _listening = false;
      _status = 'Ready';
    }
    notifyListeners();
  }

  void saveVoiceExpense(String createdBy) {
    final result = _lastResult;
    final dataProvider = _dataProvider;
    if (result is VoiceExpenseDraft && dataProvider != null) {
      dataProvider.addExpense(
        category: result.expense.category,
        amount: result.expense.amount,
        createdBy: createdBy,
        note: result.expense.note,
      );
    }
  }

  TransactionItem? currentPurchaseItem() {
    final result = _lastResult;
    return result is VoicePurchaseDraft ? result.item : null;
  }
}
