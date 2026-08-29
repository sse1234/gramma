import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/mac_bookmarks.dart';
import 'package:gramma/settings.dart';
import 'package:gramma/src/rust/api/user.dart';
import 'package:gramma/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bookmark orchestration of ADR 0027, with the platform channel
/// mocked. These tests run on the macOS host, where Platform.isMacOS
/// keeps the guarded paths live.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  final calls = <MethodCall>[];
  Object? reply;

  setUpAll(() async {
    const base = '../target/debug/';
    final library = Platform.isMacOS
        ? '${base}librust_lib_gramma.dylib'
        : Platform.isWindows
            ? '${base}rust_lib_gramma.dll'
            : '${base}librust_lib_gramma.so';
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls.clear();
    reply = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('gramma/bookmarks'), (call) async {
      calls.add(call);
      return reply;
    });
  });

  test('choosing a folder stores the bookmark; forgetting clears it',
      () async {
    final settings = SettingsController(prefs);
    reply = base64Encode(utf8.encode('grant'));
    await rememberMacSyncFolder(settings, '/Users/x/Sync');
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, '/Users/x/Sync');
    expect(settings.macSyncBookmark, reply);

    forgetMacSyncFolder(settings);
    expect(settings.macSyncBookmark, isNull);
  }, skip: !Platform.isMacOS ? 'exercises the macOS platform channel' : null);

  test('startup resolve follows a moved folder and refreshes staleness',
      () async {
    final dir = Directory.systemTemp.createTempSync('gramma-bm');
    addTearDown(() => dir.deleteSync(recursive: true));
    final oldDir = Directory('${dir.path}/old')..createSync();
    final newDir = Directory('${dir.path}/new')..createSync();
    openUserStore(path: '${dir.path}/user.db');
    configureSync(dir: oldDir.path);

    final settings = SettingsController(prefs);
    settings.setMacSyncBookmark('stored');
    reply = {'path': newDir.path, 'bookmark': 'fresh'};
    await restoreMacSyncAccess(settings);
    expect(calls.single.method, 'resolve');
    expect(syncDir(), newDir.path, reason: 'sync follows the moved folder');
    expect(settings.macSyncBookmark, 'fresh');
  }, skip: !Platform.isMacOS ? 'exercises the macOS platform channel' : null);

  test('a failing resolve leaves the configuration untouched', () async {
    final dir = Directory.systemTemp.createTempSync('gramma-bm');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sync = Directory('${dir.path}/sync')..createSync();
    openUserStore(path: '${dir.path}/user.db');
    configureSync(dir: sync.path);

    final settings = SettingsController(prefs);
    settings.setMacSyncBookmark('stored');
    reply = null;
    await restoreMacSyncAccess(settings);
    expect(syncDir(), sync.path);
    expect(settings.macSyncBookmark, 'stored');
  }, skip: !Platform.isMacOS ? 'exercises the macOS platform channel' : null);

  test('without a bookmark the startup restore is a no-op', () async {
    final settings = SettingsController(prefs);
    await restoreMacSyncAccess(settings);
    expect(calls, isEmpty);
  });
}
