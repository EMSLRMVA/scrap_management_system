import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs ',
    decimalDigits: 0,
  );
  static final _compactCurrency = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: 'Rs ',
    decimalDigits: 1,
  );
  static final _weight = NumberFormat('#,##0.##', 'en_IN');
  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final _time = DateFormat('hh:mm a');

  static String money(num value) => _currency.format(value);
  static String compactMoney(num value) => _compactCurrency.format(value);
  static String kg(num value) => '${_weight.format(value)} KG';
  static String date(DateTime value) => _date.format(value);
  static String dateTime(DateTime value) => _dateTime.format(value);
  static String time(DateTime value) => _time.format(value);
}
