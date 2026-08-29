import 'dart:io';

import 'package:flutter/services.dart';

import 'settings.dart';
import 'src/rust/api/user.dart';

const _channel = MethodChannel('gramma/bookmarks');

/// Security-scoped bookmarks (ADR 0027): under the Mac App Store
/// sandbox, access to a picker-chosen sync folder survives relaunches
/// only through a bookmark — created when the folder is chosen,
/// resolved at startup. The iCloud container needs none (its
/// entitlement grants access), so choosing it clears the bookmark.
Future<void> rememberMacSyncFolder(
    SettingsController settings, String path) async {
  if (!Platform.isMacOS) return;
  try {
    settings.setMacSyncBookmark(
        await _channel.invokeMethod<String>('create', path));
  } catch (_) {
    settings.setMacSyncBookmark(null);
  }
}

void forgetMacSyncFolder(SettingsController settings) {
  if (!Platform.isMacOS) return;
  settings.setMacSyncBookmark(null);
}

/// Resolve the stored bookmark at startup: re-grants folder access,
/// follows a moved folder (reconfiguring sync), and refreshes a stale
/// bookmark. A no-op without a bookmark or off the Mac.
Future<void> restoreMacSyncAccess(SettingsController settings) async {
  if (!Platform.isMacOS) return;
  final stored = settings.macSyncBookmark;
  if (stored == null) return;
  try {
    final reply =
        await _channel.invokeMethod<Map<Object?, Object?>>('resolve', stored);
    final path = reply?['path'] as String?;
    if (path == null) return;
    final fresh = reply?['bookmark'] as String?;
    if (fresh != null) settings.setMacSyncBookmark(fresh);
    if (path != syncDir()) configureSync(dir: path);
  } catch (_) {
    // Sync stays configured; a folder that truly went away surfaces
    // as the usual polite error on the next sync attempt.
  }
}
