import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/dropbox_sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted Dropbox: records requests, serves a canned remote state.
class _FakeDropbox {
  final Map<String, String> remoteFiles = {}; // name -> content
  final Map<String, String> revs = {}; // name -> rev
  final List<String> calls = [];
  int tokenRequests = 0;

  MockClient client() => MockClient((request) async {
        calls.add(request.url.path);
        switch (request.url.path) {
          case '/oauth2/token':
            tokenRequests++;
            if (request.body.contains('authorization_code')) {
              return http.Response(
                  jsonEncode({
                    'access_token': 'at',
                    'refresh_token': 'rt',
                    'expires_in': 14400,
                  }),
                  200);
            }
            return http.Response(
                jsonEncode({'access_token': 'at', 'expires_in': 14400}),
                200);
          case '/2/files/list_folder':
            if (remoteFiles.isEmpty) {
              return http.Response('{"error": "not_found"}', 409);
            }
            return http.Response(
                jsonEncode({
                  'entries': [
                    for (final name in remoteFiles.keys)
                      {'.tag': 'file', 'name': name, 'rev': revs[name]},
                  ],
                  'has_more': false,
                }),
                200);
          case '/2/files/download':
            final arg = jsonDecode(
                request.headers['Dropbox-API-Arg']!) as Map<String, dynamic>;
            final name = (arg['path'] as String).split('/').last;
            return http.Response(remoteFiles[name] ?? '', 200);
          case '/2/files/upload':
            final arg = jsonDecode(
                request.headers['Dropbox-API-Arg']!) as Map<String, dynamic>;
            final name = (arg['path'] as String).split('/').last;
            remoteFiles[name] = request.body;
            revs[name] = 'rev${remoteFiles[name].hashCode}';
            return http.Response('{}', 200);
          default:
            return http.Response('unexpected', 404);
        }
      });
}

Future<DropboxSync> _sync(_FakeDropbox fake, Directory root) async {
  SharedPreferences.setMockInitialValues({});
  return DropboxSync(
    appKey: 'key',
    refreshToken: 'rt',
    localRoot: root.path,
    ownLog: 'aaaa.jsonl',
    prefs: await SharedPreferences.getInstance(),
    client: fake.client(),
  );
}

void main() {
  test('foreign logs land locally; unchanged revs are not re-fetched',
      () async {
    final root = Directory.systemTemp.createTempSync('dbx');
    final fake = _FakeDropbox()
      ..remoteFiles['bbbb.jsonl'] = '{"k":"desks","v":"r","t":[1,0],"d":"bbbb"}\n'
      ..revs['bbbb.jsonl'] = 'r1';
    final sync = await _sync(fake, root);

    await sync.pullForeign();
    final local = File('${root.path}/gramma-sync/oplog/bbbb.jsonl');
    expect(local.existsSync(), isTrue);
    expect(local.readAsStringSync(), contains('"k":"desks"'));

    fake.calls.clear();
    await sync.pullForeign();
    expect(fake.calls.where((c) => c.contains('download')), isEmpty,
        reason: 'same rev means no second download');
  });

  test('the own log uploads once per content change and never downloads',
      () async {
    final root = Directory.systemTemp.createTempSync('dbx');
    final fake = _FakeDropbox();
    final sync = await _sync(fake, root);
    final own = File('${root.path}/gramma-sync/oplog/aaaa.jsonl')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"k":"desk/1","v":"x","t":[1,0],"d":"aaaa"}\n');

    await sync.pushOwn();
    expect(fake.remoteFiles['aaaa.jsonl'], own.readAsStringSync());

    fake.calls.clear();
    await sync.pushOwn();
    expect(fake.calls.where((c) => c.contains('upload')), isEmpty,
        reason: 'unchanged content is not re-uploaded');

    own.writeAsStringSync('${own.readAsStringSync()}'
        '{"k":"desk/1","v":"y","t":[2,0],"d":"aaaa"}\n');
    await sync.pushOwn();
    expect(fake.remoteFiles['aaaa.jsonl'], contains('"v":"y"'));

    // The own log is never treated as foreign.
    await sync.pullForeign();
    expect(fake.calls.where((c) => c.contains('download')), isEmpty);
  });

  test('an empty remote (409) is just an empty state', () async {
    final root = Directory.systemTemp.createTempSync('dbx');
    final sync = await _sync(_FakeDropbox(), root);
    await sync.pullForeign(); // must not throw
  });

  test('the PKCE exchange returns the refresh token', () async {
    final fake = _FakeDropbox();
    final auth = DropboxAuth();
    expect(auth.verifier.length, 64);
    expect(auth.challenge, isNot(contains('=')));
    expect(
      auth.authorizeUrl('mykey').queryParameters['code_challenge_method'],
      'S256',
    );
    final refresh =
        await auth.exchangeCode('mykey', ' code ', client: fake.client());
    expect(refresh, 'rt');
  });
}
