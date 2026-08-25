import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Direct Dropbox transport (ADR 0014): mirrors the local op-log folder
/// to Dropbox over HTTPS — no desktop client, no sync agent. The user
/// brings their own Dropbox app key (a scoped "App folder" app), so no
/// gramma-operated service is involved; the Rust engine keeps reading
/// and writing plain local files and this class only ferries them.
///
/// One writer per file carries over unchanged: this device uploads only
/// its own log and downloads everyone else's, keyed by Dropbox revs.

const _remoteRoot = '/gramma-sync/oplog';

/// The currently connected transport, or null; configured at startup and
/// from the settings screen.
DropboxSync? activeDropbox;

/// PKCE material for the OAuth flow (no client secret involved).
class DropboxAuth {
  DropboxAuth() : verifier = _randomVerifier();

  final String verifier;

  static String _randomVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  String get challenge => base64UrlEncode(
        sha256.convert(ascii.encode(verifier)).bytes,
      ).replaceAll('=', '');

  /// The URL the user opens; Dropbox shows a code to paste back.
  Uri authorizeUrl(String appKey) =>
      Uri.parse('https://www.dropbox.com/oauth2/authorize').replace(
        queryParameters: {
          'client_id': appKey,
          'response_type': 'code',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'token_access_type': 'offline',
        },
      );

  /// Exchanges the pasted code for a long-lived refresh token.
  Future<String> exchangeCode(
    String appKey,
    String code, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    final res = await c.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      body: {
        'code': code.trim(),
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
        'client_id': appKey,
      },
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Dropbox rejected the code (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final refresh = data['refresh_token'] as String?;
    if (refresh == null) {
      throw Exception('Dropbox returned no refresh token');
    }
    return refresh;
  }
}

class DropboxSync {
  DropboxSync({
    required this.appKey,
    required this.refreshToken,
    required this.localRoot,
    required this.ownLog,
    required SharedPreferences prefs,
    http.Client? client,
  })  : _prefs = prefs, // ignore: prefer_initializing_formals
        _client = client ?? http.Client();

  final String appKey;
  final String refreshToken;

  /// The local sync folder the Rust engine works in.
  final String localRoot;

  /// This device's own log file name (`<device>.jsonl`) — the only file
  /// ever uploaded.
  final String ownLog;

  final SharedPreferences _prefs;
  final http.Client _client;

  String? _accessToken;
  DateTime _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, String> get _revs {
    final raw = _prefs.getString('dropboxRevs');
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveRevs(Map<String, String> revs) =>
      _prefs.setString('dropboxRevs', jsonEncode(revs));

  Future<String> _access() async {
    final token = _accessToken;
    if (token != null && DateTime.now().isBefore(_accessExpiry)) {
      return token;
    }
    final res = await _client.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': appKey,
      },
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Dropbox token refresh failed (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _accessExpiry =
        DateTime.now().add(Duration(seconds: expiresIn - 120));
    return _accessToken!;
  }

  /// Remote log names and their revs; an absent folder is simply empty.
  Future<Map<String, String>> _listRemote() async {
    final token = await _access();
    final entries = <String, String>{};
    var body = jsonEncode({'path': _remoteRoot, 'recursive': false});
    var url = Uri.parse('https://api.dropboxapi.com/2/files/list_folder');
    while (true) {
      final res = await _client
          .post(url,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: body)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 409) return {}; // folder not created yet
      if (res.statusCode != 200) {
        throw Exception('Dropbox list failed (${res.statusCode})');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      for (final entry in data['entries'] as List) {
        final map = entry as Map<String, dynamic>;
        if (map['.tag'] == 'file' && map['name'] is String) {
          entries[map['name'] as String] = (map['rev'] as String?) ?? '';
        }
      }
      if (data['has_more'] != true) return entries;
      url = Uri.parse(
          'https://api.dropboxapi.com/2/files/list_folder/continue');
      body = jsonEncode({'cursor': data['cursor']});
    }
  }

  Future<List<int>> _download(String name) async {
    final token = await _access();
    final res = await _client.post(
      Uri.parse('https://content.dropboxapi.com/2/files/download'),
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({'path': '$_remoteRoot/$name'}),
      },
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('Dropbox download failed (${res.statusCode})');
    }
    return res.bodyBytes;
  }

  Future<void> _upload(String name, List<int> bytes) async {
    final token = await _access();
    final res = await _client.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({
          'path': '$_remoteRoot/$name',
          'mode': 'overwrite',
          'mute': true,
        }),
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('Dropbox upload failed (${res.statusCode})');
    }
  }

  /// Downloads every foreign log whose rev changed into the local folder.
  Future<void> pullForeign() async {
    final remote = await _listRemote();
    final revs = _revs;
    var dirty = false;
    for (final entry in remote.entries) {
      final name = entry.key;
      if (!name.endsWith('.jsonl') || name == ownLog) continue;
      if (revs[name] == entry.value) continue;
      final bytes = await _download(name);
      final file = File('$localRoot/gramma-sync/oplog/$name');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      revs[name] = entry.value;
      dirty = true;
    }
    if (dirty) await _saveRevs(revs);
  }

  /// Uploads the own log when its content changed since the last upload.
  Future<void> pushOwn() async {
    final file = File('$localRoot/gramma-sync/oplog/$ownLog');
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return;
    final hash = sha256.convert(bytes).toString();
    if (_prefs.getString('dropboxOwnHash') == hash) return;
    await _upload(ownLog, bytes);
    await _prefs.setString('dropboxOwnHash', hash);
  }
}
