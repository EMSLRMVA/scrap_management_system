class InvoiceNumberGenerator {
  const InvoiceNumberGenerator._();

  static String next({
    required String prefix,
    required int count,
    DateTime? date,
  }) {
    final value = date ?? DateTime.now();
    return '$prefix-${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}-${(count + 1).toString().padLeft(3, '0')}';
  }
}
