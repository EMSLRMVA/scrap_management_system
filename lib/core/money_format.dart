import 'package:intl/intl.dart';

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: 'Rs ',
  decimalDigits: 0,
);
final _number = NumberFormat.decimalPattern('en_IN');

String money(num value) => _money.format(value);
String kg(num value) => '${_number.format(value)} KG';
String shortDate(DateTime value) => DateFormat('dd MMM, hh:mm a').format(value);
String invoiceDate(DateTime value) => DateFormat('yyyyMMdd').format(value);
