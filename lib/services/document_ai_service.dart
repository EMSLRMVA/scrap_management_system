import '../domain/business_models.dart';

enum DocumentAiType { purchase, sale }

class DocumentAiDraft {
  const DocumentAiDraft({
    required this.type,
    required this.invoiceNumber,
    required this.partyName,
    required this.materialName,
    required this.weightKg,
    required this.rate,
    required this.amount,
    required this.invoiceDate,
    required this.proofPath,
  });

  final DocumentAiType type;
  final String invoiceNumber;
  final String partyName;
  final String materialName;
  final double weightKg;
  final double rate;
  final double amount;
  final DateTime invoiceDate;
  final String proofPath;
}

class DocumentAiDuplicate {
  const DocumentAiDuplicate({
    required this.type,
    required this.invoiceNumber,
    required this.partyName,
    required this.amount,
    required this.reason,
  });

  final DocumentAiType type;
  final String invoiceNumber;
  final String partyName;
  final double amount;
  final String reason;
}

class DocumentAiService {
  const DocumentAiService();

  bool get ocrConfigured => false;

  List<DocumentAiDuplicate> findDuplicates(
    BusinessState state,
    DocumentAiDraft draft,
  ) {
    return switch (draft.type) {
      DocumentAiType.purchase => _purchaseDuplicates(state, draft),
      DocumentAiType.sale => _saleDuplicates(state, draft),
    };
  }

  List<DocumentAiDuplicate> _purchaseDuplicates(
    BusinessState state,
    DocumentAiDraft draft,
  ) {
    final duplicates = <DocumentAiDuplicate>[];
    for (final purchase in state.activePurchases) {
      final reason = _duplicateReason(
        draft,
        invoiceNumber: purchase.invoiceNumber,
        partyName: purchase.seller.name,
        amount: purchase.totalAmount,
        date: purchase.createdAt,
      );
      if (reason == null) {
        continue;
      }
      duplicates.add(
        DocumentAiDuplicate(
          type: DocumentAiType.purchase,
          invoiceNumber: purchase.invoiceNumber,
          partyName: purchase.seller.name,
          amount: purchase.totalAmount,
          reason: reason,
        ),
      );
    }
    return duplicates;
  }

  List<DocumentAiDuplicate> _saleDuplicates(
    BusinessState state,
    DocumentAiDraft draft,
  ) {
    final duplicates = <DocumentAiDuplicate>[];
    for (final sale in state.activeSales) {
      final reason = _duplicateReason(
        draft,
        invoiceNumber: sale.invoiceNumber,
        partyName: sale.customer.name,
        amount: sale.totalAmount,
        date: sale.createdAt,
      );
      if (reason == null) {
        continue;
      }
      duplicates.add(
        DocumentAiDuplicate(
          type: DocumentAiType.sale,
          invoiceNumber: sale.invoiceNumber,
          partyName: sale.customer.name,
          amount: sale.totalAmount,
          reason: reason,
        ),
      );
    }
    return duplicates;
  }

  String? _duplicateReason(
    DocumentAiDraft draft, {
    required String invoiceNumber,
    required String partyName,
    required double amount,
    required DateTime date,
  }) {
    final invoiceMatches =
        draft.invoiceNumber.trim().isNotEmpty &&
        invoiceNumber.trim().toLowerCase() ==
            draft.invoiceNumber.trim().toLowerCase();
    if (invoiceMatches) {
      return 'Same invoice number';
    }
    final amountMatches = draft.amount > 0 && (amount - draft.amount).abs() < 1;
    final sameDate = _sameDay(date, draft.invoiceDate);
    final sameParty =
        draft.partyName.trim().isNotEmpty &&
        partyName.trim().toLowerCase().contains(
          draft.partyName.trim().toLowerCase(),
        );
    if (amountMatches && sameDate && sameParty) {
      return 'Same party, date, and amount';
    }
    if (amountMatches && sameDate) {
      return 'Same date and amount';
    }
    return null;
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
