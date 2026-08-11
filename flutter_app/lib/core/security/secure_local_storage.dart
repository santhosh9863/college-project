import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform keychain instead of the
/// default plaintext storage. Sessions (access/refresh tokens) therefore never
/// touch unencrypted storage on the device.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'college_project_sb_session';
  static const String _accessTokenKey = 'college_project_sb_access_token';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _accessTokenKey);

  @override
  Future<String?> accessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    final session = jsonDecode(persistSessionString) as Map<String, dynamic>;
    final accessToken = session['access_token'] as String?;
    if (accessToken != null) {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    }
    await _storage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _accessTokenKey);
  }
}
