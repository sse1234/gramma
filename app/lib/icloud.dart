import 'dart:io';

import 'package:flutter/services.dart';

/// The Apple transport of ADR 0014: the app's own iCloud Drive container,
/// a plain folder to the sync engine. On iOS and macOS alike the path
/// comes from the platform (ADR 0027: under the sandbox the container
/// must be resolved through FileManager, not composed from $HOME).
///
/// Requires the paid Apple Developer Program (the iCloud capability is
/// closed to personal teams) plus `CODE_SIGN_ENTITLEMENTS =
/// Runner/Runner.entitlements;` in the Runner build configurations.
const icloudTransportEnabled = true;

const _channel = MethodChannel('gramma/icloud');

/// The container's Documents folder, or null when iCloud is unavailable
/// (signed out, iCloud Drive off, container not yet created).
Future<String?> icloudContainerPath() async {
  if (!Platform.isIOS && !Platform.isMacOS) return null;
  try {
    return await _channel.invokeMethod<String>('containerPath');
  } catch (_) {
    return null;
  }
}

/// Foreign op-logs may sit as undownloaded placeholders; ask the system
/// to materialize them before the engine reads. No-op elsewhere.
Future<void> icloudPrepare(String dir) async {
  if (!Platform.isIOS && !Platform.isMacOS) return;
  try {
    await _channel.invokeMethod('prepare', dir);
  } catch (_) {}
}
