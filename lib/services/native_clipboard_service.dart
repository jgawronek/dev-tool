
import 'package:flutter/services.dart';

class NativeClipboardService {
  NativeClipboardService._();
  static const _channel = MethodChannel('devutils/clipboard');

  static Future<void> copyImage(Uint8List bytes) async {
    final copied = await _channel.invokeMethod<bool>('copyImage', bytes);
    if (copied != true) {
      throw PlatformException(
        code: 'image_copy',
        message: 'Could not copy the image.',
      );
    }
  }
}
