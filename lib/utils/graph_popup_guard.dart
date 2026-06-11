import 'package:flutter/material.dart';

class GraphPopupGuard {
  GraphPopupGuard._();

  static bool _isOpen = false;
  static DateTime? _lastOpenAt;

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
  }) {
    final now = DateTime.now();
    final openedRecently =
        _lastOpenAt != null &&
        now.difference(_lastOpenAt!) < const Duration(milliseconds: 450);
    if (_isOpen || openedRecently) {
      return Future<T?>.value();
    }
    _isOpen = true;
    _lastOpenAt = now;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      builder: builder,
    ).whenComplete(() {
      _isOpen = false;
    });
  }
}
