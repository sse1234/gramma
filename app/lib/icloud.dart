import 'dart:io';

import 'package:flutter/services.dart';

/// The Apple transport of ADR 0014: the app's own iCloud Drive container,
/// a plain folder to the sync engine. On iOS the path comes from the
/// platform; on the Mac the container appears under Mobile Documents.
///
/// Dormant: the iCloud capability requires a paid Apple Developer
/// Program membership, which the current personal team lacks. To enable,
/// flip this flag and re-add `CODE_SIGN_ENTITLEMENTS =
/// Runner/Runner.entitlements;` to the three Runner build
/// configurations — everything else (entitlements file, container
/// declaration, platform channel) is already in place.
const icloudTransportEnabled = false;

const _channel = MethodChannel('gramma/icloud');

/// The container's Documents folder on iOS, or null when iCloud is
/// unavailable (signed out, iCloud Drive off).
Future<String?> icloudContainerPath() async {
  if (!Platform.isIOS) return null;
  try {
    return await _channel.invokeMethod<String>('containerPath');
  } catch (_) {
    return null;
  }
}

/// Where the container surfaces on the Mac once any device has created
/// it; null when it does not exist yet (open gramma on an iPhone or iPad
/// first).
String? macIcloudContainerPath() {
  if (!Platform.isMacOS) return null;
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final container =
      '$home/Library/Mobile Documents/iCloud~io~sse~gramma';
  if (!Directory(container).existsSync()) return null;
  final documents = Directory('$container/Documents');
  documents.createSync(recursive: true);
  return documents.path;
}

/// On iOS, foreign op-logs may sit as undownloaded placeholders; ask the
/// system to materialize them before the engine reads. No-op elsewhere.
Future<void> icloudPrepare(String dir) async {
  if (!Platform.isIOS) return;
  try {
    await _channel.invokeMethod('prepare', dir);
  } catch (_) {}
}
