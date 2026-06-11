import '../constants/app_constants.dart';
import '../models/expense.dart';
import '../models/transaction_item.dart';

sealed class VoiceCommandResult {
  const VoiceCommandResult();
}

class VoicePurchaseDraft extends VoiceCommandResult {
  const VoicePurchaseDraft(this.item);

  final TransactionItem item;
}

class VoiceExpenseDraft extends VoiceCommandResult {
  const VoiceExpenseDraft(this.expense);

  final Expense expense;
}

class VoiceParserService {
  VoiceCommandResult? parse(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll('\u20b9', ' ')
        .replaceAll('rs.', 'rs')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.contains('expense') ||
        normalized.contains('kharcha') ||
        normalized.contains('spent')) {
      return _parseExpense(normalized);
    }
    return _parsePurchase(normalized);
  }

  VoiceCommandResult? _parsePurchase(String input) {
    final material = _materialFromInput(input);
    if (material.isEmpty) {
      return null;
    }

    final weight = _extractNumberBefore(input, [
      'kg',
      'kgs',
      'kilo',
      'kilos',
      'kilogram',
      'kilograms',
    ]);
    final rate =
        _extractNumberAfter(input, ['at', 'rate', 'dar', 'bhav']) ??
        _fallbackRate(input);
    if (weight == null || rate == null) {
      return null;
    }

    return VoicePurchaseDraft(
      TransactionItem(
        materialId: material.toLowerCase().replaceAll(' ', '-'),
        materialName: material,
        weightKg: weight,
        rate: rate,
      ),
    );
  }

  VoiceCommandResult? _parseExpense(String input) {
    final category = AppConstants.expenseCategories.firstWhere(
      (item) => input.contains(item.toLowerCase()),
      orElse: () => 'Miscellaneous',
    );
    final amount = _extractLastNumber(input);
    if (amount == null) {
      return null;
    }
    return VoiceExpenseDraft(
      Expense(
        id: 'voice-${DateTime.now().microsecondsSinceEpoch}',
        category: category,
        amount: amount,
        createdAt: DateTime.now(),
        createdBy: 'Voice Assistant',
        note: input,
      ),
    );
  }

  double? _extractNumberBefore(String input, List<String> terms) {
    for (final term in terms) {
      final match = RegExp(
        r'(\d+(?:\.\d+)?)\s*' + term + r'\b',
      ).firstMatch(input);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  double? _extractNumberAfter(String input, List<String> terms) {
    for (final term in terms) {
      final match = RegExp(
        term + r'\s*(?:rs|rupees|rupaye|inr)?\s*(\d+(?:\.\d+)?)',
      ).firstMatch(input);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  double? _extractLastNumber(String input) {
    final matches = RegExp(r'\d+(?:\.\d+)?').allMatches(input).toList();
    if (matches.isEmpty) {
      return null;
    }
    return double.tryParse(matches.last.group(0)!);
  }

  double? _fallbackRate(String input) {
    final matches = RegExp(r'\d+(?:\.\d+)?').allMatches(input).toList();
    if (matches.length < 2) {
      return null;
    }
    return double.tryParse(matches.last.group(0)!);
  }

  String _materialFromInput(String input) {
    final material = AppConstants.materials.firstWhere(
      (item) => input.contains(item.toLowerCase()),
      orElse: () => '',
    );
    if (material.isNotEmpty) {
      return material;
    }
    const aliases = {
      'narial shell': 'Coconut Shell',
      'nariyal shell': 'Coconut Shell',
      'coconut': 'Coconut Shell',
      'pet botal': 'PET Bottle',
      'pet bottle': 'PET Bottle',
      'e waste': 'E-Waste',
      'tyre': 'Tyres',
      'tire': 'Tyres',
    };
    for (final entry in aliases.entries) {
      if (input.contains(entry.key)) {
        return entry.value;
      }
    }
    return '';
  }
}
