enum LedgerDirection { credit, debit }

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.partyId,
    required this.partyName,
    required this.date,
    required this.description,
    required this.direction,
    required this.amount,
    required this.balanceAfter,
  });

  final String id;
  final String partyId;
  final String partyName;
  final DateTime date;
  final String description;
  final LedgerDirection direction;
  final double amount;
  final double balanceAfter;
}
