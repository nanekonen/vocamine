import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BrowserContextMenuLease {
  static int _count = 0;

  static void acquire() {
    if (!kIsWeb) return;
    if (_count++ == 0) BrowserContextMenu.disableContextMenu();
  }

  static void release() {
    if (!kIsWeb || _count == 0) return;
    if (--_count == 0) BrowserContextMenu.enableContextMenu();
  }
}
