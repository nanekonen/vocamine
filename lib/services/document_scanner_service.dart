import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DocumentScannerService {
  static const _channel = MethodChannel('glossalyze/document_scanner');

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<List<Uint8List>> scan() async {
    if (!isSupported) {
      throw UnsupportedError('書類スキャンはiOS・Androidアプリで利用できます');
    }
    final result = await _channel.invokeMethod<List<dynamic>>('scanDocument');
    return (result ?? const <dynamic>[]).whereType<Uint8List>().toList();
  }
}
