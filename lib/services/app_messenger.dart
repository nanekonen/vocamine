import 'package:flutter/material.dart';

class AppMessenger {
  AppMessenger._();

  static final key = GlobalKey<ScaffoldMessengerState>();

  static void show(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = key.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }
}
