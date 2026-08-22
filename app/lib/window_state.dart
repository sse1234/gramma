import 'dart:async';
import 'dart:io';

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Restores and tracks the desktop window's bounds.
///
/// Window geometry is per-device state, so it lives in local preferences
/// and is deliberately not part of the synced layout object (ADR 0008).
class WindowStatePersistence with WindowListener {
  WindowStatePersistence(this._prefs);

  final SharedPreferences _prefs;
  Timer? _debounce;

  static bool get supported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<void> restoreAndTrack() async {
    await windowManager.ensureInitialized();
    final x = _prefs.getDouble('window.x');
    final y = _prefs.getDouble('window.y');
    final width = _prefs.getDouble('window.width');
    final height = _prefs.getDouble('window.height');
    if (x != null && y != null && width != null && height != null) {
      await windowManager.setBounds(Rect.fromLTWH(x, y, width, height));
    }
    windowManager.addListener(this);
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final bounds = await windowManager.getBounds();
      await _prefs.setDouble('window.x', bounds.left);
      await _prefs.setDouble('window.y', bounds.top);
      await _prefs.setDouble('window.width', bounds.width);
      await _prefs.setDouble('window.height', bounds.height);
    });
  }
}
