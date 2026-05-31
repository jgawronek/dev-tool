import 'package:flutter/services.dart';

/// Controls native macOS appearance: the menu-bar (status bar) icon and the
/// Dock icon. Backed by an `NSStatusItem` and the app's activation policy.
class AppAppearanceService {
  AppAppearanceService._();

  static const MethodChannel _channel = MethodChannel('devutils/app_appearance');

  /// Applies the appearance preferences natively.
  ///
  /// If the Dock icon is hidden the app becomes menu-bar-only, so the status
  /// bar icon is forced on to keep the app reachable.
  static Future<void> apply({
    required bool showStatusBar,
    required bool showDock,
  }) async {
    final effectiveStatusBar = showDock ? showStatusBar : true;
    try {
      await _channel.invokeMethod('apply', {
        'showStatusBar': effectiveStatusBar,
        'showDock': showDock,
      });
    } on MissingPluginException {
      // Non-macOS platform or the channel isn't ready yet.
    }
  }
}
